local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local SendGuard = ns.SendGuard or require("CraftAlert.Model.SendGuard")
local WhisperBridge = ns.WhisperBridge or require("CraftAlert.UI.WhisperBridge")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local SavedState = ns.SavedState or require("CraftAlert.Persistence.SavedState")

-- Spec §7.1 keybinds, called from Bindings.xml: greet or dismiss the latest lead, toggle the
-- leads window. Defines, at load, the binding labels and the CraftAlert_* functions (§4.3 rule
-- 3 own globals). In an instance every key does nothing, silently (see SlashCommands).
local Bindings = {}

-- GetTime() since when the lead has been on screen: the earlier of its toast (WhisperMessenger's
-- preview when bridged) and its top row in the leads window (or WM's panel); nil when neither
-- shows it.
local function shownAt(lead)
  local since
  local toastLead, toastShownAt = WhisperBridge.VisibleLead()
  if toastLead and toastLead.id == lead.id then
    since = toastShownAt
  end
  local rowLead, rowShownAt = LeadsWindow.VisibleLatest()
  if rowLead and rowLead.id == lead.id and (since == nil or rowShownAt < since) then
    since = rowShownAt
  end
  return since
end

-- §7.5 rule 3: with the latest lead on neither the toast nor the window, the keybind prefills.
function Bindings.GreetLatest()
  if FlavorCompat.InInstance() then
    return
  end
  local lead = Leads.Latest()
  if lead == nil then
    return
  end
  local since = shownAt(lead)
  if since == nil then
    GreetAction.Prefill(lead)
    return
  end
  GreetAction.Greet(lead, since)
end

-- §7.5 rule 3: a latest lead the toast or the window has shown for under 0.5 s stays, so a key
-- pressed as a new lead pops up never drops it unseen; one on neither is dismissed.
function Bindings.DismissLatest()
  if FlavorCompat.InInstance() then
    return
  end
  local lead = Leads.Latest()
  if lead == nil then
    return
  end
  local since = shownAt(lead)
  if since ~= nil and not SendGuard.Looked(since) then
    return
  end
  Leads.Dismiss(lead.id)
end

-- The window reads its settings from CraftAlertDB, missing or unchecked when the saved data
-- failed to load (already reported at ADDON_LOADED).
function Bindings.ToggleLeads()
  if FlavorCompat.InInstance() then
    return
  end
  if SavedState.Ready() then
    LeadsWindow.Toggle()
  end
end

_G.BINDING_HEADER_CRAFTALERT = Localization.Text("Craft Alert")
_G.BINDING_NAME_CRAFTALERT_GREET = Localization.Text("Greet the latest lead")
_G.BINDING_NAME_CRAFTALERT_DISMISS = Localization.Text("Dismiss the latest lead")
_G.BINDING_NAME_CRAFTALERT_TOGGLE = Localization.Text("Show or hide the leads window")
_G.CraftAlert_GreetLatest = Bindings.GreetLatest
_G.CraftAlert_DismissLatest = Bindings.DismissLatest
_G.CraftAlert_ToggleLeads = Bindings.ToggleLeads

ns.Bindings = Bindings
return Bindings
