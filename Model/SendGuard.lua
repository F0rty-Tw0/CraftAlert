local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")

-- Spec §7.5 rules 1-3: whether a greeting may be sent now or must open the edit box instead.
-- Every time is GetTime(). Rule 4 (the disclosure notice) belongs to GreetAction.
local SendGuard = {}

local remove = table.remove
local type = type

local MAX_SENDS = 6
local WINDOW_SECONDS = 60
local LOOK_SECONDS = 0.5

local sends = {} -- GetTime() of each greeting GreetAction sent, oldest first

local function now()
  return _G["GetTime"]()
end

-- A secret flag or a missing API is unknown, and unknown counts as AFK (the flag is secret
-- during chat lockdown). The secret test comes first: a secret value cannot be compared.
local function playerIsAway()
  local isAfk = _G["UnitIsAFK"]
  if type(isAfk) ~= "function" then
    return true
  end
  local afk = isAfk("player")
  return FlavorCompat.issecretvalue(afk) or afk ~= false
end

local function sendsInWindow()
  local current = now()
  while #sends > 0 and current - sends[1] >= WINDOW_SECONDS do
    remove(sends, 1)
  end
  return #sends
end

-- Rule 3, the look: whether the toast or row that appeared at `shownAt` (GetTime(), nil when none
-- is visible) has been up 0.5 s. A dismiss by click obeys it too (ClickRouter).
function SendGuard.Looked(shownAt)
  return shownAt ~= nil and now() - shownAt >= LOOK_SECONDS
end

-- lead: the lead to greet; shownAt: GetTime() when the toast or row showing it appeared, nil
-- when none is visible. → true, or false and the first rule that blocks: "afk", "rate"
-- (6 greetings in 60 s), "greeted" (once per lead, by any route) or "look" (shown under 0.5 s).
function SendGuard.Check(lead, shownAt)
  if playerIsAway() then
    return false, "afk"
  end
  if sendsInWindow() >= MAX_SENDS then
    return false, "rate"
  end
  if lead.greeted then
    return false, "greeted"
  end
  if not SendGuard.Looked(shownAt) then
    return false, "look"
  end
  return true
end

-- Counts one greeting Craft Alert sent itself; prefills and manual whispers do not count.
function SendGuard.RecordSend()
  sends[#sends + 1] = now()
end

ns.SendGuard = SendGuard
return SendGuard
