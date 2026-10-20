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

-- The normalized key of a whisper partner; nil for a secret or unknown name.
local function keyOf(name)
  if FlavorCompat.issecretvalue(name) then
    return nil
  end
  return PlayerName.Normalize(name)
end

-- The player whispered somebody: (text, target). Their newest lead counts as greeted.
local function onInform(_, target)
  local key = keyOf(target)
  local lead = key and Leads.FindActiveByCustomer(key)
  if lead then
    Leads.MarkGreeted(lead.id)
  end
end

-- Somebody whispered the player: (text, sender). Every greeted lead of theirs still waiting for
-- an answer gets it, so a newer, ungreeted lead of the same customer cannot hide the greeting.
local function onWhisper(_, sender)
  local key = keyOf(sender)
  if key == nil then
    return
  end
  for _, lead in ipairs(Leads.List()) do
    if lead.customer == key then
      Leads.MarkReplied(lead.id)
    end
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
