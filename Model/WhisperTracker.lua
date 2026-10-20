local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")

-- Spec §7.1 and §7.2: whispers between the player and a lead's customer. Our own greeting
-- or a prefill the player sent marks the lead greeted; the customer's answer marks it
-- replied. The two whisper events stay registered only while an unexpired lead exists,
-- scanning or not (§4.3 rule 4). Chat lockdown makes both events' arguments secret; those
-- whispers are skipped.
local WhisperTracker = {}

local WHISPER = "CHAT_MSG_WHISPER"
local WHISPER_INFORM = "CHAT_MSG_WHISPER_INFORM"

-- The customer's newest lead for a whisper partner; nil for a secret or unknown name.
local function leadFor(name)
  if FlavorCompat.issecretvalue(name) then
    return nil
  end
  local key = PlayerName.Normalize(name)
  return key and Leads.FindActiveByCustomer(key)
end

-- The player whispered somebody: (text, target).
local function onInform(_, target)
  local lead = leadFor(target)
  if lead then
    Leads.MarkGreeted(lead.id)
  end
end

-- Somebody whispered the player: (text, sender).
local function onWhisper(_, sender)
  local lead = leadFor(sender)
  if lead then
    Leads.MarkReplied(lead.id)
  end
end

-- Registers the whisper events while a lead exists, else drops them.
function WhisperTracker.Refresh()
  local register = Leads.HasActive() and EventRouter.On or EventRouter.Off
  register(WHISPER_INFORM, onInform)
  register(WHISPER, onWhisper)
end

-- Bootstrap, after Leads.Restore: leads restored from the last session need the events too.
function WhisperTracker.Install()
  Leads.On("change", WhisperTracker.Refresh)
  WhisperTracker.Refresh()
end

ns.WhisperTracker = WhisperTracker
return WhisperTracker
