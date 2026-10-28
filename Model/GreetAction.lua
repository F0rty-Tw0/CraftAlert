local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local SendGuard = ns.SendGuard or require("CraftAlert.Model.SendGuard")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")

-- Spec §7.1 and §7.5: what a greet click or keybind does with a lead. Called only from click
-- and keybind handlers, so every whisper starts with the player (§4.3 rule 6). The one place
-- in the addon that sends an addon message, and it never listens for one.
local GreetAction = {}

local find = string.find
local pcall = pcall
local type = type

local NOTICE_PREFIX = "robots.txt"
local NOTICE = "Q:CraftAlert"

-- Who the whisper goes to. Forever names are region-unique, so its whispers carry no realm
-- (spec §10); elsewhere the stored Name-Realm key is the target.
local function targetOf(lead)
  if FlavorCompat.isForever then
    return PlayerName.NameOf(lead.customer)
  end
  return lead.customer
end

-- Opens a whisper box to `target`, with `text` as the draft when given. Blizzard's edit box
-- unless SetOpener swaps it (WhisperMessenger's conversation).
local function defaultOpener(target, text)
  if text then
    FlavorCompat.SendTellWithMessage(target, text)
  else
    FlavorCompat.SendTell(target)
  end
end

local opener = defaultOpener

-- A test lead (`/ca test`) never reaches a send API: the send it would make prints in chat
-- instead. → whether it did.
local function dryRun(lead, text, ...)
  if not lead.test then
    return false
  end
  ChatPrint.Line(Localization.Text(text, ...))
  return true
end

-- The greeting for `lead` from the saved settings; the details pane and `/ca test` show it too.
function GreetAction.GreetingFor(lead)
  return Greeting.Build(lead, _G["CraftAlertDB"].settings)
end

-- Lets customer-side filters recognise the whisper that follows (§7.5 rule 4). Whatever it
-- returns or raises (throttled, locked down, target offline), the greeting is still sent.
local function sendNotice(lead, customer)
  if dryRun(lead, 'Test, would send addon message %s "%s" to %s', NOTICE_PREFIX, NOTICE, customer) then
    return
  end
  local chatInfo = _G["C_ChatInfo"]
  local send = type(chatInfo) == "table" and chatInfo.SendAddonMessage or _G["SendAddonMessage"]
  if type(send) == "function" then
    pcall(send, NOTICE_PREFIX, NOTICE, "WHISPER", customer)
  end
end

-- Sends the greeting when the anti-bot rules allow it, else opens the edit box with it. A
-- lead that is no longer listed (dismissed, expired, evicted) can never be marked greeted, so
-- it would be sent to again on every click: it only prefills.
-- A greeting with nothing to say (a hand-edited empty template, tags that all expand to "")
-- is never sent: an empty whisper opens for the player to type into.
-- shownAt: GetTime() when the toast or row showing the lead appeared, nil when none is visible.
function GreetAction.Greet(lead, shownAt)
  local greeting = GreetAction.GreetingFor(lead)
  local target = targetOf(lead)
  if not find(greeting, "%S") then
    if not dryRun(lead, "Test, would open an empty whisper to %s", target) then
      opener(target)
    end
    return
  end
  if not Leads.IsActive(lead.id) or not SendGuard.Check(lead, shownAt) then
    if not dryRun(lead, "Test, would open a whisper to %s with: %s", target, greeting) then
      opener(target, greeting)
    end
    return
  end
  sendNotice(lead, target)
  if not dryRun(lead, "Test, would whisper %s: %s", target, greeting) then
    FlavorCompat.SendChatMessage(greeting, "WHISPER", nil, target)
  end
  SendGuard.RecordSend()
  Leads.MarkGreeted(lead.id)
end

-- Opens the edit box with the greeting; the player sends it (§7.1 shift-click).
function GreetAction.Prefill(lead)
  local target, greeting = targetOf(lead), GreetAction.GreetingFor(lead)
  if not dryRun(lead, "Test, would open a whisper to %s with: %s", target, greeting) then
    opener(target, greeting)
  end
end

-- Opens an empty whisper to the customer (§7.1 ctrl-click).
function GreetAction.Empty(lead)
  local target = targetOf(lead)
  if not dryRun(lead, "Test, would open an empty whisper to %s", target) then
    opener(target)
  end
end

-- `fn(target, text|nil)` opens the whisper box in place of Blizzard's; nil restores it.
function GreetAction.SetOpener(fn)
  opener = fn or defaultOpener
end

-- The name the whisper goes to (the Forever form drops the realm).
GreetAction.Target = targetOf

ns.GreetAction = GreetAction
return GreetAction
