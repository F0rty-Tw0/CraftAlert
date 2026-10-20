local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local Perf = ns.Perf or require("CraftAlert.Core.Perf")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local AlertToast = ns.AlertToast or require("CraftAlert.UI.AlertToast")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local SettingsWindow = ns.SettingsWindow or require("CraftAlert.UI.Settings.SettingsWindow")

-- Spec §7.3 and §4.4: /craftalert and /ca. No argument toggles the leads window; `config` the
-- settings window; `test <line>` runs a trade line through the matcher; `perf` toggles timing.
local SlashCommands = {}

local lower = string.lower
local match = string.match
local tostring = tostring

local COMMAND_1, COMMAND_2 = "/craftalert", "/ca"

local function kindLine(lead)
  if lead.kind == "item" then
    return Localization.Text("Item: %s", LeadText.What(lead))
  end
  return Localization.Text("Profession: %s", LeadText.What(lead))
end

-- `/ca test` (§7.3): steps 2-5 on `text` as if "Test" on the player's realm had sent it in
-- Trade. It prints what matched, why, who answers and the greeting that would be sent, and
-- shows a toast marked "Test". No lead, no ledger count, nothing sent.
local function runTest(text)
  if text == "" then
    ChatPrint.Line(Localization.Text("Usage: /ca test <a trade chat line>"))
    return
  end
  local result = Matcher.MatchUngated(text)
  if result == nil then
    ChatPrint.Line(Localization.Text("No match (stopped at: %s)", tostring(Matcher.lastStop)))
    return
  end
  local lead = Leads.Preview(result, text)
  if lead == nil then
    ChatPrint.Line(Localization.Text("Matched, but none of your enabled characters can answer it"))
    return
  end
  local greeting = Greeting.Build(lead, _G["CraftAlertDB"].settings)
  ChatPrint.Line(kindLine(lead))
  ChatPrint.Line(Localization.Text("Why: %s", lead.why))
  ChatPrint.Line(Localization.Text("Crafter: %s", lead.crafter))
  ChatPrint.Line(Localization.Text("Greeting: %s", greeting))
  AlertToast.ShowTest(lead, greeting)
end

local function togglePerf()
  if Perf.IsRunning() then
    Perf.Stop()
  else
    Perf.Start()
  end
end

local COMMANDS = {
  config = function()
    SettingsWindow.Toggle()
  end,
  test = runTest,
  perf = togglePerf,
}

local function onSlash(message)
  local name, rest = match(message or "", "^%s*(%S*)%s*(.-)%s*$")
  name = lower(name)
  if name == "" then
    LeadsWindow.Toggle()
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
