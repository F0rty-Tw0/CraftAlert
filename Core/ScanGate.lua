local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local Status = ns.Status or require("CraftAlert.Core.Status")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")

-- Spec §6.1: the public chat events are registered only while scanning is active (not in an
-- instance, enabled, the index has entries, a Trade channel exists here unless "Only where Trade
-- chat exists" is off), and this module is the only owner of that rule and of the
-- event-to-channel mapping. Chat lines enter the hot path (§6.3 steps 1-4) here and, on a match,
-- go on to Leads.
local ScanGate = {}

local type = type

local CHANNEL_EVENT = "CHAT_MSG_CHANNEL"
local GUILD_EVENT = "CHAT_MSG_GUILD"
local COMMUNITIES_EVENT = "CHAT_MSG_COMMUNITIES_CHANNEL"

-- Settings keys in the order they are listed, each with its name (the one table behind the
-- status line, the General page's toggles and a lead's channel word), and below, the event each
-- one arrives on. Retail Services (42) and LookingForGroup (26) were not seen in Phase 0
-- (flavor-choices.md); 26 is the client's own ID for LookingForGroup.
ScanGate.CHANNELS = {
  { key = "trade", label = "Trade" },
  { key = "services", label = "Services" },
  { key = "general", label = "General" },
  { key = "lfg", label = "LookingForGroup" },
  { key = "guild", label = "Guild" },
  { key = "communities", label = "Communities" },
}
local CHANNEL_EVENTS = {
  trade = CHANNEL_EVENT,
  services = CHANNEL_EVENT,
  general = CHANNEL_EVENT,
  lfg = CHANNEL_EVENT,
  guild = GUILD_EVENT,
  communities = COMMUNITIES_EVENT,
}
local CHANNEL_NAMES = {}

for _, channel in ipairs(ScanGate.CHANNELS) do
  CHANNEL_NAMES[channel.key] = channel.label
end

-- CHAT_MSG_CHANNEL: the zone channel ID, never secret and the same on every client language.
local TRADE_ZONE_CHANNEL = 2
local ZONE_CHANNELS = { [1] = "general", [TRADE_ZONE_CHANNEL] = "trade", [42] = "services", [26] = "lfg" }
local EVENT_CHANNELS = { [GUILD_EVENT] = "guild", [COMMUNITIES_EVENT] = "communities" }

local available = Constants.flavors[FlavorCompat.flavorKey].channels
local Normalize = PlayerName.Normalize

---@type table
local db = nil
local active = nil -- nil until the first evaluation, so that one is reported too
local lastReason = nil -- why the last evaluation paused, nil while active
local lastUnread = nil -- the profession the last "empty" pause named, nil otherwise
local announced = false -- whether the status line was printed this session
local registered = {} -- event -> true while the shim below is registered for it
local shims = {} -- event -> the function registered with EventRouter, created once
local listeners = {}
local handler -- what the shims call; HandleChat unless SetHandler replaced it

-- → "trade", "services", "general", "lfg", "guild", "communities" or nil. Hot path: table
-- lookups only. The base name is never compared (§6.1); a channel the flavor lacks is nil.
function ScanGate.ChannelKey(event, _, zoneChannelID)
  local key
  if event == CHANNEL_EVENT then
    -- Chat lockdown (an open-world boss, rated PvP) can hand over secret payloads; a secret is
    -- never used as a table key, the line is skipped.
    if FlavorCompat.issecretvalue(zoneChannelID) then
      return nil
    end
    key = ZONE_CHANNELS[zoneChannelID]
  else
    key = EVENT_CHANNELS[event]
  end
  return key and available[key] and key or nil
end

-- The default chat handler. The arguments follow Blizzard's chat event order: text, sender,
-- language, channel name, sender again, flags, zone channel ID, channel index, base name,
-- language ID, line ID, guid. Steps 1-4 run in the Matcher, steps 5-7 for a match.
function ScanGate.HandleChat(event, text, sender, _, _, _, _, zoneChannelID, _, channelBaseName, _, _, guid)
  local key = ScanGate.ChannelKey(event, channelBaseName, zoneChannelID)
  if key == nil then
    return
  end
  local result = Matcher.Match(key, text, sender, guid)
  if result == nil then
    return
  end
  Leads.OnMatch(result, Normalize(sender), text, key, guid)
end

handler = ScanGate.HandleChat

-- Replaces what the chat event frame calls (`/ca perf` times it); nil restores HandleChat.
function ScanGate.SetHandler(fn)
  handler = fn or ScanGate.HandleChat
end

-- Hands one event to the current handler, as the chat event frame does.
function ScanGate.Deliver(event, ...)
  return handler(event, ...)
end

local function shimFor(event)
  local shim = shims[event]
  if shim == nil then
    shim = function(...)
      return handler(event, ...)
    end
    shims[event] = shim
  end
  return shim
end

local function isResting()
  local resting = _G["IsResting"]
  return type(resting) == "function" and resting() == true
end

-- Whether a Trade channel exists here: a joined channel, not disabled, whose zone channel ID is 2
-- (the slot it sits on and its localized name do not matter). Without GetChannelList or the
-- channel info API, the old resting test decides. Both are read on each call, so tests that stub
-- them after load still reach this code. Never called in an instance (pauseReason stops first).
-- A secret name, disabled flag or zone channel ID (chat lockdown) skips that channel: a secret is
-- never tested or compared.
local function hasTrade()
  local getChannelList = _G["GetChannelList"]
  local chatInfo = _G["C_ChatInfo"]
  local getInfo = type(chatInfo) == "table" and chatInfo.GetChannelInfoFromIdentifier or nil
  if type(getChannelList) ~= "function" or type(getInfo) ~= "function" then
    return isResting()
  end
  local isSecret = FlavorCompat.issecretvalue
  local list = { getChannelList() }
  for i = 1, #list, 3 do
    local name, disabled = list[i + 1], list[i + 2]
    local info = not isSecret(name) and not isSecret(disabled) and not disabled and getInfo(name) or nil
    local zoneID = type(info) == "table" and info.zoneChannelID or nil
    if not isSecret(zoneID) and zoneID == TRADE_ZONE_CHANNEL then
      return true
    end
  end
  return false
end

-- Why scanning is paused, or nil while it runs. A login step that raised leaves the gate or
-- Leads without the db: then a match would make no lead, so nothing is scanned. "building":
-- the first index of the session is still being built by the Slicer job (the login build).
local function pauseReason()
  if db == nil or not Leads.IsBound() then
    return "notStarted"
  end
  if FlavorCompat.InInstance() then
    return "instance"
  end
  if not db.settings.enable then
    return "disabled"
  end
  local index = Index.Current()
  if index == nil and Slicer.IsRunning("index") then
    return "building"
  end
  if index == nil or index.size == 0 then
    return "empty"
  end
  if db.settings.onlyResting and not hasTrade() then
    return "noTrade"
  end
  return nil
end

-- The channel keys switched on in the settings that exist on this flavor, in list order.
local function enabledChannels()
  local keys = {}
  local switches = db and db.settings.channels or {}
  for _, channel in ipairs(ScanGate.CHANNELS) do
    local key = channel.key
    if available[key] and switches[key] == true then
      keys[#keys + 1] = key
    end
  end
  return keys
end

-- { active, reason, channels = { "Trade", ... }, recipeCount, crafterCount, unreadProfession }:
-- a new table, for the status line and the launcher (not a hot path).
function ScanGate.State()
  local reason = pauseReason()
  local index = Index.Current()
  local names = {}
  for i, key in ipairs(enabledChannels()) do
    names[i] = CHANNEL_NAMES[key]
  end
  local state = {
    active = reason == nil,
    reason = reason,
    channels = names,
    recipeCount = index and index.size or 0,
    crafterCount = index and index.crafterCount or 0,
  }
  if reason == "empty" then
    state.unreadProfession = ProfessionList.UnreadNames(db, PlayerName.Own())[1]
  end
  return state
end

function ScanGate.IsActive()
  return active == true
end

-- Registers the events in `wanted` (event -> true) and drops every other one.
local function applyEvents(wanted)
  for event in pairs(registered) do
    if not wanted[event] then
      EventRouter.Off(event, shims[event])
      registered[event] = nil
    end
  end
  for event in pairs(wanted) do
    if not registered[event] then
      EventRouter.On(event, shimFor(event))
      registered[event] = true
    end
  end
end

local function notify(state)
  EventRouter.CallAll(listeners, state.active, state)
  if state.active and not announced then
    announced = true
    ChatPrint.Line(Status.Text(state))
  end
end

-- §6.1: sets the registered chat events from the current settings, index, instance and resting
-- state. Called on each index rebuild, on the resting, zone and world events, and by the settings
-- pages.
function ScanGate.Evaluate()
  if db == nil then
    return
  end
  local state = ScanGate.State()
  local wanted = {}
  for _, key in ipairs(state.active and enabledChannels() or {}) do
    wanted[CHANNEL_EVENTS[key]] = true
  end
  local changed = state.active ~= active or state.reason ~= lastReason or state.unreadProfession ~= lastUnread
  -- Set first: the events are registered while the gate already reports active.
  active = state.active
  lastReason = state.reason
  lastUnread = state.unreadProfession
  applyEvents(wanted)
  if changed then
    notify(state)
  end
end

-- Called with (active, state) whenever the gate turns active or paused or pauses for another
-- reason (entering an instance while already paused counts), or an "empty" pause names another
-- unread profession; the first evaluation counts.
function ScanGate.OnChange(fn)
  listeners[#listeners + 1] = fn
end

-- Bootstrap, after the settings are loaded: re-evaluate when the player enters or leaves a
-- city or inn, changes zone, joins or leaves a channel (CHANNEL_UI_UPDATE, every flavor), or
-- enters or leaves an instance (PLAYER_ENTERING_WORLD). The db is bound last: while a
-- registration raises, Evaluate keeps returning early and no chat event is registered without
-- the Trade and instance gates.
function ScanGate.Install(accountDb)
  EventRouter.On("PLAYER_UPDATE_RESTING", ScanGate.Evaluate)
  EventRouter.On("ZONE_CHANGED_NEW_AREA", ScanGate.Evaluate)
  EventRouter.On("CHANNEL_UI_UPDATE", ScanGate.Evaluate)
  EventRouter.On("PLAYER_ENTERING_WORLD", ScanGate.Evaluate)
  db = accountDb
end

ns.ScanGate = ScanGate
return ScanGate
