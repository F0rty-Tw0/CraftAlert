local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local CrafterRank = ns.CrafterRank or require("CraftAlert.Model.CrafterRank")

-- Spec §7.2: the leads (matched requests) the player can answer. Steps 5-7 of §6.3 run here
-- on matched lines only. Leads live in `db.leads`, oldest first (an updated lead moves to the
-- end); a lead is plain data (no table fields), because the Matcher's result it is copied
-- from is reused by the next line. One expiry timer (§4.3 rule 1) waits for the oldest lead.
local Leads = {}

local concat = table.concat
local remove = table.remove
local sort = table.sort
local max = math.max
local pcall = pcall
local tostring = tostring
local type = type

local MAX_LEADS = 100
local EVENTS = { new = true, change = true, greeted = true, replied = true }

---@type table
local db = nil
---@type table
local leads = nil -- db.leads, edited in place
local nextId = 1
local timerArmed = false
local timerGeneration = 0 -- only the timer started last acts when it fires
local timerDeadline = 0 -- time() when the pending timer fires
local listeners = { new = {}, change = {}, greeted = {}, replied = {} }

local function now()
  return _G["time"]()
end

local function timeoutSeconds()
  return db.settings.leadTimeoutMin * 60
end

local function reportError(err)
  local getHandler = _G["geterrorhandler"]
  if type(getHandler) == "function" then
    getHandler()(err)
  end
end

-- "change" listeners get no argument; the others get the lead.
local function fire(name, lead)
  local list = listeners[name]
  for i = 1, #list do
    local ok, err
    if lead then
      ok, err = pcall(list[i], lead)
    else
      ok, err = pcall(list[i])
    end
    if not ok then
      reportError(err)
    end
  end
end

-- "new" (lead: the first alert), "change" (no arguments: any add, update, dismiss, expiry),
-- "greeted" and "replied" (lead).
function Leads.On(name, fn)
  if not EVENTS[name] then
    error("Leads.On: unknown event " .. tostring(name), 2)
  end
  local list = listeners[name]
  list[#list + 1] = fn
end

local function sweep()
  local limit = timeoutSeconds()
  local current = now()
  local removed = false
  for i = #leads, 1, -1 do
    if current - leads[i].time > limit then
      remove(leads, i)
      removed = true
    end
  end
  return removed
end

local armExpiry

local function onExpiry(generation)
  if generation ~= timerGeneration then
    return
  end
  timerArmed = false
  if sweep() then
    fire("change")
  end
  armExpiry()
end

local function startTimer(delay)
  timerArmed = true
  timerGeneration = timerGeneration + 1
  timerDeadline = now() + delay
  local generation = timerGeneration
  _G["C_Timer"].After(delay, function()
    onExpiry(generation)
  end)
end

local function delayForOldest()
  return max(1, leads[1].time + timeoutSeconds() - now() + 1)
end

-- Waits for the oldest lead to pass the timeout (strictly, as the sweep counts it). A timer
-- that is already pending is kept: if its lead was dismissed or refreshed, it fires early,
-- sweeps nothing and re-arms.
armExpiry = function()
  if timerArmed or leads[1] == nil then
    return
  end
  startTimer(delayForOldest())
end

-- After a leadTimeoutMin change (settings page): sweeps what the new timeout already expired,
-- and when the oldest lead's new deadline comes before the pending timer, arms one for it. The
-- timer it replaces cannot be cancelled; it fires later and does nothing. A later deadline
-- keeps the pending timer, which fires early and re-arms.
function Leads.Rearm()
  if db == nil then
    return
  end
  if sweep() then
    fire("change")
  end
  if leads[1] == nil then
    return
  end
  local delay = delayForOldest()
  if not timerArmed or now() + delay < timerDeadline then
    startTimer(delay)
  end
end

-- Oldest first; leads of the same second keep their id order (ids are unique by now).
local function isOlder(a, b)
  if a.time ~= b.time then
    return a.time < b.time
  end
  return a.id < b.id
end

-- A hand-edited db may repeat or lack ids; find(id) must see each lead once. The first holder
-- of an id keeps it, the rest get fresh ones above every id in the db.
local function fixIds()
  local seen, broken = {}, {}
  nextId = 1
  for i = 1, #leads do
    local id = leads[i].id
    -- NaN can't be a table key and inf + 1 == inf, so only finite numbers count as ids.
    if type(id) == "number" and id == id and id > -math.huge and id < math.huge and not seen[id] then
      seen[id] = true
      nextId = max(nextId, id + 1)
    else
      broken[#broken + 1] = leads[i]
    end
  end
  for i = 1, #broken do
    broken[i].id = nextId
    nextId = nextId + 1
  end
end

-- Keeps the newest MAX_LEADS of a list that is sorted oldest first.
local function trim()
  local count = #leads
  local excess = count - MAX_LEADS
  if excess <= 0 then
    return
  end
  for i = 1, count do
    leads[i] = leads[i + excess]
  end
end

-- A lead dated after now (hand-edited, or the clock was set back) would never pass the timeout:
-- it counts as arrived now.
local function clampTimes()
  local current = now()
  for i = 1, #leads do
    if leads[i].time > current then
      leads[i].time = current
    end
  end
end

-- Binds db.leads (Bootstrap, at PLAYER_LOGIN): repairs a hand-edited list (ids, times, order,
-- size), drops expired leads and starts the timer.
function Leads.Restore(accountDb)
  db = accountDb
  leads = db.leads
  fixIds()
  clampTimes()
  sort(leads, isOlder)
  trim()
  if sweep() then
    fire("change")
  end
  armExpiry()
end

local function find(id)
  for i = 1, #leads do
    if leads[i].id == id then
      return leads[i], i
    end
  end
  return nil
end

local function sameMatch(lead, result)
  if lead.kind ~= result.kind then
    return false
  end
  if result.kind == "profession" then
    return lead.prof == result.prof
  end
  return lead.group == result.group
end

-- The same sender asking for the same thing again inside the timeout. → lead, position.
local function findDuplicate(customerKey, result)
  local limit, current = timeoutSeconds(), now()
  for i = #leads, 1, -1 do
    local lead = leads[i]
    if lead.customer == customerKey and current - lead.time <= limit and sameMatch(lead, result) then
      return lead, i
    end
  end
  return nil
end

-- Joins the Matcher's why tokens (the intent word, then what matched; item IDs are numbers).
local function joinWhy(result)
  local parts = {}
  for i = 1, result.whyCount do
    parts[i] = tostring(result.why[i])
  end
  return concat(parts, " + ")
end

-- What the chosen crafter's own record says about the match: its recipe (item results) and
-- the name of the profession.
local function describeCrafter(lead, result, crafter)
  local character = db.characters[crafter]
  local profession = character and character.professions and character.professions[result.prof]
  lead.profName = profession and profession.name or (type(result.prof) == "string" and result.prof or nil)
  if result.kind ~= "item" then
    return
  end
  for i = 1, result.entryCount do
    local entry = result.entries[i]
    if entry.character == crafter then
      local recipe = character and character.recipes and character.recipes[entry.recipeKey]
      lead.recipeName = recipe and recipe.name or (type(entry.recipeKey) == "string" and entry.recipeKey or nil)
      lead.itemID = recipe and recipe.item or nil
      if lead.itemID then
        lead.itemLink = select(2, FlavorCompat.GetItemInfo(lead.itemID))
      end
      return
    end
  end
end

-- The lead for a matched line from `crafter`, copied out of the Matcher's reused result;
-- numbered and stored by the caller.
local function buildLead(result, customerKey, text, channelKey, crafter, cannotOrder)
  local lead = {
    customer = customerKey,
    message = text,
    channel = channelKey,
    kind = result.kind,
    prof = result.prof,
    group = result.group,
    why = joinWhy(result),
    crafter = crafter,
    cannotOrder = cannotOrder,
    time = now(),
    greeted = false,
    replied = false,
  }
  describeCrafter(lead, result, crafter)
  return lead
end

-- nil when the player is not AFK-flagged or the flag is secret (§7.6).
local function afkNow()
  local isAfk = _G["UnitIsAFK"]
  if type(isAfk) ~= "function" then
    return nil
  end
  local afk = isAfk("player")
  if FlavorCompat.issecretvalue(afk) then
    return nil
  end
  return afk == true
end

-- Steps 5-7 on a matched line. result: the Matcher's (reused) result; customerKey: the
-- normalized sender. → lead, isNew; nil when no crafter qualifies (customer ignored, or none
-- of the matched crafters is left).
function Leads.OnMatch(result, customerKey, text, channelKey, guid)
  if db == nil or customerKey == nil then
    return nil
  end
  local lead, position = findDuplicate(customerKey, result)
  if lead then
    lead.message, lead.channel, lead.time = text, channelKey, now()
    lead.why = joinWhy(result)
    remove(leads, position)
    leads[#leads + 1] = lead
    fire("change")
    return lead, false
  end
  local crafter, cannotOrder = CrafterRank.Pick(result, customerKey, db)
  if crafter == nil then
    return nil
  end
  lead = buildLead(result, customerKey, text, channelKey, crafter, cannotOrder)
  lead.id = nextId
  lead.guid = type(guid) == "string" and not FlavorCompat.issecretvalue(guid) and guid or nil
  lead.arrivedWhileAfk = afkNow()
  nextId = nextId + 1
  leads[#leads + 1] = lead
  if #leads > MAX_LEADS then
    remove(leads, 1)
  end
  armExpiry()
  fire("new", lead)
  fire("change")
  return lead, true
end

-- `/ca test` (§7.3): the lead `text` would make if "Test" on the player's realm had sent it in
-- Trade, with the ignore list skipped. Not numbered, stored, counted or announced.
-- → lead or nil when no enabled crafter qualifies.
function Leads.Preview(result, text)
  if db == nil then
    return nil
  end
  local customerKey = PlayerName.TestCustomer()
  local crafter, cannotOrder = CrafterRank.Pick(result, customerKey, db, { skipIgnore = true })
  if crafter == nil then
    return nil
  end
  return buildLead(result, customerKey, text, "trade", crafter, cannotOrder)
end

-- The first time a lead is greeted, however it was sent (§7.1). → whether this was the first.
function Leads.MarkGreeted(id)
  local lead = find(id)
  if lead == nil or lead.greeted then
    return false
  end
  lead.greeted = true
  db.recentGreeted[lead.customer] = now()
  fire("greeted", lead)
  fire("change")
  return true
end

-- The first customer whisper after the greeting. → whether this was the first.
function Leads.MarkReplied(id)
  local lead = find(id)
  if lead == nil or not lead.greeted or lead.replied then
    return false
  end
  lead.replied = true
  fire("replied", lead)
  fire("change")
  return true
end

-- The customer's newest lead.
function Leads.FindActiveByCustomer(key)
  for i = #leads, 1, -1 do
    if leads[i].customer == key then
      return leads[i]
    end
  end
  return nil
end

-- Whether the lead is still listed; a dismissed, expired or evicted one is not.
function Leads.IsActive(id)
  return find(id) ~= nil
end

function Leads.Dismiss(id)
  local lead, position = find(id)
  if lead then
    remove(leads, position)
    fire("change")
  end
end

function Leads.DismissCustomer(key)
  local removed = false
  for i = #leads, 1, -1 do
    if leads[i].customer == key then
      remove(leads, i)
      removed = true
    end
  end
  if removed then
    fire("change")
  end
end

-- The row "Block" button (§7.3): hot-path block set rebuilt, customer's leads dismissed.
function Leads.Block(key)
  key = PlayerName.Normalize(key)
  if key == nil then
    return
  end
  db.ignored[key] = true
  Leads.DismissCustomer(key)
  Index.RequestRebuild("block")
end

function Leads.Latest()
  return leads[#leads]
end

-- Newest first, as a new array.
function Leads.List()
  local list = {}
  for i = #leads, 1, -1 do
    list[#list + 1] = leads[i]
  end
  return list
end

function Leads.HasActive()
  return #leads > 0
end

ns.Leads = Leads
return Leads
