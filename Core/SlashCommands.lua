local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Perf = ns.Perf or require("CraftAlert.Core.Perf")
local SavedState = ns.SavedState or require("CraftAlert.Persistence.SavedState")
local TestLine = ns.TestLine or require("CraftAlert.Core.TestLine")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")

-- Spec §7.3 and §4.4: /craftalert and /ca. No argument toggles the leads window; `config` its
-- settings pane; `test` runs a trade line through the real path (TestLine); `perf` toggles timing.
-- In an instance every form only prints the off line (spec 2026-10-25-instance-chat-line; the
-- user accepted the chat-frame taint risk).
local SlashCommands = {}

local lower = string.lower
local match = string.match

local COMMAND_1, COMMAND_2 = "/craftalert", "/ca"

local function offLine()
  ChatPrint.Line(Localization.Text("Off in instances; it works again when you leave."))
end

local function togglePerf()
  if Perf.IsRunning() then
    Perf.Stop()
  else
    Perf.Start()
  end
end

-- The windows read their settings from CraftAlertDB, which is missing or unchecked when the
-- saved data failed to load (reported at ADDON_LOADED). → whether they may open.
local function hasDb()
  if SavedState.Ready() then
    return true
  end
  ChatPrint.Line(Localization.Text("Craft Alert's saved data did not load; /reload to try again"))
  return false
end

local COMMANDS = {
  config = function()
    if hasDb() then
      LeadsWindow.ToggleSettings()
    end
  end,
  test = TestLine.Run,
  perf = togglePerf,
}

local function onSlash(message)
  if FlavorCompat.InInstance() then
    offLine()
    return
  end
  local name, rest = match(message or "", "^%s*(%S*)%s*(.-)%s*$")
  name = lower(name)
  if name == "" then
    if hasDb() then
      LeadsWindow.Toggle()
    end
    return
  end
  local command = COMMANDS[name]
  if command == nil then
    ChatPrint.Line(Localization.Text("Commands: /ca (leads window), /ca config, /ca test <line>, /ca perf"))
    return
  end
  command(rest)
end

-- Bootstrap, at PLAYER_LOGIN. The only global writes: the two SLASH_ names and our own field
-- of SlashCmdList (spec §4.3 rule 3).
function SlashCommands.Register()
  _G["SLASH_CRAFTALERT1"] = COMMAND_1
  _G["SLASH_CRAFTALERT2"] = COMMAND_2
  _G["SlashCmdList"].CRAFTALERT = onSlash
end

ns.SlashCommands = SlashCommands
return SlashCommands
