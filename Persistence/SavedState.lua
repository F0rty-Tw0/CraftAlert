local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Defaults = ns.Defaults or require("CraftAlert.Persistence.Defaults")
local Schema = ns.Schema or require("CraftAlert.Persistence.Schema")

-- Loads CraftAlertDB (spec §10): creates it when absent, repairs it with Schema, drops
-- what has expired. Runs at ADDON_LOADED, before PlayerName.Init, so it never touches
-- player names: keys are kept exactly as stored.
local SavedState = {}

SavedState.isFirstRun = false

local MAX_LEADS = 100
local LEDGER_DAYS = 30
local RECENT_GREETED_SECONDS = 24 * 60 * 60
local SECONDS_PER_DAY = 24 * 60 * 60

local function byTime(a, b)
  if a.lead.time ~= b.lead.time then
    return a.lead.time < b.lead.time
  end
  return a.index < b.index
end

-- Keeps the `max` newest leads, oldest first. Schema guarantees every lead has a time.
local function newest(leads, max)
  local ranked = {}
  for index, lead in ipairs(leads) do
    ranked[index] = { lead = lead, index = index }
  end
  table.sort(ranked, byTime)
  local kept = {}
  for i = #ranked - max + 1, #ranked do
    kept[#kept + 1] = ranked[i].lead
  end
  return kept
end

local function pruneLeads(db, now)
  local limit = db.settings.leadTimeoutMin * 60
  local alive = {}
  for _, lead in ipairs(db.leads) do
    if now - lead.time <= limit then
      alive[#alive + 1] = lead
    end
  end
  db.leads = #alive > MAX_LEADS and newest(alive, MAX_LEADS) or alive
end

-- Ledger days are local-date strings, so the cutoff is one too; they compare as text.
local function pruneLedger(db, now)
  local cutoff = _G["date"]("%Y-%m-%d", now - LEDGER_DAYS * SECONDS_PER_DAY)
  if type(cutoff) ~= "string" then
    return
  end
  for day in pairs(db.ledger) do
    if day < cutoff then
      db.ledger[day] = nil
    end
  end
end

local function pruneRecentGreeted(db, now)
  for customer, greetedAt in pairs(db.recentGreeted) do
    if now - greetedAt > RECENT_GREETED_SECONDS then
      db.recentGreeted[customer] = nil
    end
  end
end

-- Binds the global CraftAlertDB and returns it. `isFirstRun` says whether it was absent
-- or unusable (not a table), i.e. whether the player starts from a fresh db.
function SavedState.Load()
  local stored = _G.CraftAlertDB
  SavedState.isFirstRun = type(stored) ~= "table"
  local db = Schema.Validate(stored == nil and Defaults.Db() or stored)
  local now = _G["time"]()
  pruneLeads(db, now)
  pruneLedger(db, now)
  pruneRecentGreeted(db, now)
  _G.CraftAlertDB = db
  return db
end

ns.SavedState = SavedState
return SavedState
