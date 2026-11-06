local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")

-- Spec §9, Forever and Classic: a quiet /who for the asker of a clicked lead, so the card can say
-- where they stand. SendWho is protected: it works only inside a hardware event, so TryFor runs
-- from the lead row's left click, never from a timer. FriendsFrame (and Forever's Group Finder Who
-- tab) pop the Who list on WHO_LIST_UPDATE, so their event stays unregistered while our query is
-- in flight. The shapes follow WhisperMessenger's Transport/WhoLookup.lua; WINDOW and MIN_GAP keep
-- the two addons from flying at once (§9.4).
local WhoCity = {}

WhoCity.WINDOW = 4 -- seconds a query waits for its answer (WM waits 5 after our send)
WhoCity.MIN_GAP = 6 -- seconds since anyone's last SendWho (WM's window is 5)

local WHO_EVENT = "WHO_LIST_UPDATE"
local WHO_LISTENERS = { "FriendsFrame", "LFGWhoListFrame" }
local WHO_PANELS = { "WhoFrame", "LFGWhoListFrame" }
-- The states a click may ask again from; nil (never asked) also asks.
local RETRY = { none = true, failed = true }

local lower, match = string.lower, string.match

local hooked = false
local inFlight = false
local sendingOurs = false
local flightId = nil
local flightName = nil
local timer = nil
local lastSentAt = nil
local previousWhoToUi = false

-- GetTime, not whole-second time(): time() can read a 5.5 s gap as 6 s.
local function now()
  return _G["GetTime"]()
end

local function setWhoListeners(method)
  for _, name in ipairs(WHO_LISTENERS) do
    local frame = _G[name]
    if frame and frame[method] then
      frame[method](frame, WHO_EVENT)
    end
  end
end

-- IsVisible, not IsShown: a closed parent leaves its Who tab shown.
local function whoPanelVisible()
  for _, name in ipairs(WHO_PANELS) do
    local frame = _G[name]
    if frame and frame.IsVisible and frame:IsVisible() == true then
      return true
    end
  end
  return false
end

-- B6: the listeners hear WHO_LIST_UPDATE again; the flag stays on while a Who panel is on screen.
local function cleanup()
  setWhoListeners("RegisterEvent")
  _G["C_FriendList"].SetWhoToUi(whoPanelVisible() or previousWhoToUi)
end

local function endFlight(state, zone)
  inFlight = false
  if timer then
    timer:Cancel()
  end
  timer = nil
  local id = flightId
  flightId, flightName = nil, nil
  Leads.SetWho(id, state, zone)
end

-- B7: no answer within WINDOW.
local function onTimeout()
  if not inFlight then
    return
  end
  endFlight("failed", nil)
  cleanup()
end

-- Runs after every SendWho, ours included: the server throttles them all. A foreign one ends
-- ours at once (B7), so the player's own /who behaves normally.
local function onSendWho()
  lastSentAt = now()
  if inFlight and not sendingOurs then
    endFlight("failed", nil)
    cleanup()
  end
end

-- B5: the first entry whose name before "-" is the asker's, any case. → its zone, or nil.
local function findZone(shortName)
  local api = _G["C_FriendList"]
  local wanted = lower(shortName)
  for i = 1, api.GetNumWhoResults() do
    local info = api.GetWhoInfo(i)
    local fullName = info and info.fullName
    if type(fullName) == "string" and lower(match(fullName, "^[^-]+") or "") == wanted then
      return info.area
    end
  end
  return nil
end

-- B5: cleanup waits a frame, so FriendsFrame does not hear this same event.
local function onWhoListUpdate()
  if not inFlight then
    return
  end
  local zone = findZone(flightName)
  if type(zone) == "string" then
    endFlight("done", zone)
  else
    endFlight("none", nil)
  end
  _G["C_Timer"].After(0, cleanup)
end

-- B1: Forever and Classic only (Bootstrap, at login). Without the hook a foreign send would go
-- unseen, so TryFor sends nothing until it is installed.
function WhoCity.Init()
  if hooked or FlavorCompat.isRetail then
    return
  end
  local api = _G["C_FriendList"]
  local hook = _G["hooksecurefunc"]
  if type(api) ~= "table" or type(api.SendWho) ~= "function" or type(hook) ~= "function" then
    return
  end
  hook(api, "SendWho", onSendWho)
  EventRouter.On(WHO_EVENT, onWhoListUpdate)
  hooked = true
end

-- B3: as WM's isBlocked. Without NewTimer the flight would never end.
local function isBlocked()
  if _G["InCombatLockdown"]() then
    return true
  end
  local chatInfo = _G["C_ChatInfo"]
  if chatInfo and chatInfo.InChatMessagingLockdown and chatInfo.InChatMessagingLockdown() then
    return true
  end
  local timers = _G["C_Timer"]
  return not (timers and timers.NewTimer)
end

local function isThrottled()
  return inFlight or (lastSentAt ~= nil and now() - lastSentAt < WhoCity.MIN_GAP)
end

-- B4, in the spec's order.
local function sendQuery(shortName)
  setWhoListeners("UnregisterEvent")
  local api = _G["C_FriendList"]
  previousWhoToUi = api.GetWhoToUi and api.GetWhoToUi() or false
  api.SetWhoToUi(true)
  Leads.SetWho(flightId, "pending", nil)
  timer = _G["C_Timer"].NewTimer(WhoCity.WINDOW, onTimeout)
  sendingOurs = true
  api.SendWho('n-"' .. shortName .. '"')
end

-- The lead row's left click (UI/LeadRow.lua). → whether a query was sent; when not, the click
-- just selects. A send that raises marks the lead "failed" and cleans up at once.
function WhoCity.TryFor(lead)
  if not hooked or lead == nil then
    return false
  end
  local state = lead.whoState
  if state ~= nil and not RETRY[state] then
    return false
  end
  if isBlocked() or isThrottled() then
    return false
  end
  inFlight, flightId = true, lead.id
  flightName = match(lead.customer, "^[^-]+") or lead.customer
  lastSentAt = now()
  local ok = pcall(sendQuery, flightName)
  sendingOurs = false
  if not ok then
    endFlight("failed", nil)
    cleanup()
  end
  return ok
end

ns.WhoCity = WhoCity
return WhoCity
