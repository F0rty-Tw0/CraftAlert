local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local SendGuard = ns.SendGuard or require("CraftAlert.Model.SendGuard")

-- Spec §7.1 and §7.5: what a greet click or keybind does with a lead. Called only from click
-- and keybind handlers, so every whisper starts with the player (§4.3 rule 6). The one place
-- in the addon that sends an addon message, and it never listens for one.
local GreetAction = {}

local pcall = pcall
local type = type

local NOTICE_PREFIX = "robots.txt"
local NOTICE = "Q:CraftAlert"

local function greetingFor(lead)
  return Greeting.Build(lead, _G["CraftAlertDB"].settings)
end

-- Lets customer-side filters recognise the whisper that follows (§7.5 rule 4). Whatever it
-- returns or raises (throttled, locked down, target offline), the greeting is still sent.
local function sendNotice(customer)
  local chatInfo = _G["C_ChatInfo"]
  local send = type(chatInfo) == "table" and chatInfo.SendAddonMessage or _G["SendAddonMessage"]
  if type(send) == "function" then
    pcall(send, NOTICE_PREFIX, NOTICE, "WHISPER", customer)
  end
end

-- Sends the greeting when the anti-bot rules allow it, else opens the edit box with it. A
-- lead that is no longer listed (dismissed, expired, evicted) can never be marked greeted, so
-- it would be sent to again on every click: it only prefills.
-- shownAt: GetTime() when the toast or row showing the lead appeared, nil when none is visible.
function GreetAction.Greet(lead, shownAt)
  local greeting = greetingFor(lead)
  if not Leads.IsActive(lead.id) or not SendGuard.Check(lead, shownAt) then
    FlavorCompat.SendTellWithMessage(lead.customer, greeting)
    return
  end
  sendNotice(lead.customer)
  FlavorCompat.SendChatMessage(greeting, "WHISPER", nil, lead.customer)
  SendGuard.RecordSend()
  Leads.MarkGreeted(lead.id)
end

-- Opens the edit box with the greeting; the player sends it (§7.1 shift-click).
function GreetAction.Prefill(lead)
  FlavorCompat.SendTellWithMessage(lead.customer, greetingFor(lead))
end

-- Opens an empty whisper to the customer (§7.1 ctrl-click).
function GreetAction.Empty(lead)
  FlavorCompat.SendTell(lead.customer)
end

ns.GreetAction = GreetAction
return GreetAction
