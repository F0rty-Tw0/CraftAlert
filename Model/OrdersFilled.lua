local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Ledger = ns.Ledger or require("CraftAlert.Model.Ledger")
local SavedState = ns.SavedState or require("CraftAlert.Persistence.SavedState")

-- Spec §8, Retail only (Bootstrap installs it there): a crafting order filled for a customer the
-- player greeted in the last 24 hours (`db.recentGreeted`, §7.2) counts one "filled". The event's
-- playerName carries no realm (Phase 0, docs/knowledge/in-game-facts.md row 18), so a bare name
-- matches the name part of a greeted key; a name with a realm matches the whole key. NPC orders
-- fire the event too; NPC names are never greeted.
local OrdersFilled = {}

local find = string.find
local pairs = pairs

local EVENT = "CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG"
local GREETED_SECONDS = SavedState.RECENT_GREETED_SECONDS

---@type table
local db = nil

-- recentGreeted is pruned only at login (Persistence/SavedState.lua), so a session longer than a
-- day still holds older greetings: each one is checked against the clock.
local function isRecent(greetedAt, now)
  return greetedAt ~= nil and now - greetedAt <= GREETED_SECONDS
end

local function wasGreeted(playerName)
  local now = _G["time"]()
  if find(playerName, "-", 1, true) then
    return isRecent(db.recentGreeted[PlayerName.Normalize(playerName)], now)
  end
  for key, greetedAt in pairs(db.recentGreeted) do
    if PlayerName.NameOf(key) == playerName and isRecent(greetedAt, now) then
      return true
    end
  end
  return false
end

-- (orderType, itemName, playerName, tip, quantity). At most one "filled" per event.
local function onFulfilled(_, _, playerName)
  if FlavorCompat.issecretvalue(playerName) or type(playerName) ~= "string" or playerName == "" then
    return
  end
  if wasGreeted(playerName) then
    Ledger.Add("filled")
  end
end

function OrdersFilled.Install(accountDb)
  db = accountDb
  EventRouter.On(EVENT, onFulfilled)
end

ns.OrdersFilled = OrdersFilled
return OrdersFilled
