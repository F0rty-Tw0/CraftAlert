local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local CardBody = ns.CardBody or require("CraftAlert.UI.CardBody")
local AlertToast = ns.AlertToast or require("CraftAlert.UI.AlertToast")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local Launcher = ns.Launcher or require("CraftAlert.UI.Launcher")
local BridgePanel = ns.BridgePanel or require("CraftAlert.UI.BridgePanel")

-- Spec C.2, C.3: when WhisperMessenger's addon API (_G.WhisperMessengerAPI, version 1) is there at
-- login, the toast becomes WM's widget preview, the leads window becomes a WM panel, whisper boxes
-- open as WM conversations and each customer's conversation gets an info line. The earlier modules
-- never call this one: Activate plugs it in through their setters (Launcher.SetSuppressed,
-- LeadsWindow.SetRouter, GreetAction.SetOpener). Without the API nothing here runs.
local WhisperBridge = {}

local concat = table.concat
local ipairs = ipairs
local pairs = pairs
local type = type

local KEY = "CraftAlert"
local REQUIRED = {
  "OpenConversation",
  "ShowPreview",
  "HidePreview",
  "IsPreviewShown",
  "RegisterPanel",
  "ShowPanel",
  "TogglePanel",
  "IsPanelShown",
  "RefreshPanelBadge",
  "SetContactInfo",
}

---@type table
local api = nil -- _G.WhisperMessengerAPI once Activate accepted it
local active = nil -- nil until Activate ran, then whether it activated
---@type table|nil
local shown = nil -- { lead, shownAt } of the preview on WM's widget, nil when none
local sentInfo = {} -- customer -> the info line last sent

local function now()
  return _G["GetTime"]()
end

local function isUsable(candidate)
  if type(candidate) ~= "table" or type(candidate.version) ~= "number" or candidate.version < 1 then
    return false
  end
  for _, name in ipairs(REQUIRED) do
    if type(candidate[name]) ~= "function" then
      return false
    end
  end
  return true
end

-- Today's two calls (Blizzard's whisper box), for when WM refuses (combat, lockdown).
local function defaultOpen(target, text)
  if text then
    FlavorCompat.SendTellWithMessage(target, text)
  else
    FlavorCompat.SendTell(target)
  end
end

local function open(target, text)
  if not api.OpenConversation(target, text) then
    defaultOpen(target, text)
  end
end

local function hidePreview()
  shown = nil
  api.HidePreview(KEY)
end

local function add(parts, text)
  if text and text ~= "" then
    parts[#parts + 1] = text
  end
end

-- "Craft Alert: <what> · <profession> · <crafter>", the profession dropped when it is the what.
local function infoText(lead)
  local what, parts = LeadText.What(lead), {}
  add(parts, what)
  if lead.profName ~= what then
    add(parts, lead.profName)
  end
  local crafter = CardBody.Crafters(lead)[1]
  add(parts, crafter and crafter.name)
  return "|cffffd100" .. Localization.Text("Craft Alert") .. ":|r " .. concat(parts, " · ")
end

-- Each customer's info line follows their newest active lead (Leads.List is newest first); a line
-- goes out only when its text changed, a customer without an active lead loses theirs.
local function syncInfo()
  local newest = {}
  for _, lead in ipairs(Leads.List()) do
    if newest[lead.customer] == nil then
      newest[lead.customer] = lead
    end
  end
  for customer, lead in pairs(newest) do
    local text = infoText(lead)
    if sentInfo[customer] ~= text then
      sentInfo[customer] = text
      api.SetContactInfo(KEY, customer, text)
    end
  end
  for customer in pairs(sentInfo) do
    if newest[customer] == nil then
      sentInfo[customer] = nil
      api.SetContactInfo(KEY, customer, nil)
    end
  end
end

local function onChange()
  if shown and not Leads.IsActive(shown.lead.id) then
    hidePreview()
  end
  BridgePanel.Refresh()
  api.RefreshPanelBadge(KEY)
  syncInfo()
end

-- Activates once per session (spec C.2): → whether the bridge is on. A second call returns the
-- first answer and wires nothing again. RegisterPanel, the one call out, comes before the wiring:
-- a raise or a false answer (WM refuses, e.g. the key is taken) leaves CraftAlert standalone.
function WhisperBridge.Activate()
  if active ~= nil then
    return active
  end
  local candidate = _G["WhisperMessengerAPI"]
  if not isUsable(candidate) then
    active = false
    return false
  end
  if candidate.RegisterPanel(KEY, BridgePanel.Build()) ~= true then
    active = false
    return false
  end
  api, active = candidate, true
  Launcher.SetSuppressed(true)
  LeadsWindow.SetRouter(function()
    return api.TogglePanel(KEY)
  end)
  GreetAction.SetOpener(open)
  Leads.On("change", onChange)
  Leads.On("greeted", syncInfo)
  Leads.On("replied", syncInfo)
  return true
end

local function previewFor(lead, entry)
  return {
    sender = lead.customer,
    text = LeadText.What(lead),
    onClick = function()
      local wasGreeted = lead.greeted
      local action = ClickRouter.Handle("LeftButton", lead, entry.shownAt)
      -- Only a greeting this click sent: otherwise Greet opened the draft already, and a test
      -- lead (dry run) has no customer to open.
      if action == "greet" and lead.greeted and not wasGreeted and not lead.test then
        api.OpenConversation(GreetAction.Target(lead))
      end
      if shown == entry then
        shown = nil
      end
    end,
    onDismiss = function()
      if shown == entry then
        shown = nil
      end
    end,
    onShown = function()
      entry.shownAt = now()
    end,
  }
end

-- A new lead (Leads.On("new"), wired by Bootstrap when Activate returned true): WM's preview, with
-- the sound and flash from CraftAlert's settings, hidden after the toast duration or when the lead
-- leaves the list. WM refusing the preview falls back to CraftAlert's own toast, which alerts for
-- itself. Nothing in an instance.
function WhisperBridge.ShowLead(lead)
  if FlavorCompat.InInstance() then
    return
  end
  local entry = { lead = lead, shownAt = now() }
  if not api.ShowPreview(KEY, previewFor(lead, entry)) then
    AlertToast.Show(lead)
    return
  end
  AlertToast.Alert(lead)
  shown = entry
  -- C_Timer.After cannot be cancelled: a timer acts only while its own preview is the shown one.
  _G["C_Timer"].After(_G["CraftAlertDB"].settings.toastDuration or 20, function()
    if shown == entry then
      hidePreview()
    end
  end)
end

-- ScanGate.OnChange (wired by Bootstrap, also standalone): entering an instance takes the preview
-- down; an open panel and the badge follow the gate both ways (empty inside, full again outside).
-- Arguments are ignored.
function WhisperBridge.OnGate()
  if not active then
    return
  end
  if shown and FlavorCompat.InInstance() then
    hidePreview()
  end
  BridgePanel.Refresh()
  api.RefreshPanelBadge(KEY)
end

-- The latest lead and GetTime() when it appeared, from whichever of the WM preview (else the
-- fallback toast) and the panel's top row shows it, the earliest of the two; nil when none does.
-- Not activated: the toast's.
function WhisperBridge.VisibleLead()
  if not active then
    return AlertToast.VisibleLead()
  end
  local latest = Leads.Latest()
  local found, foundAt
  local function consider(lead, shownAt)
    if lead ~= nil and lead == latest and (foundAt == nil or shownAt < foundAt) then
      found, foundAt = lead, shownAt
    end
  end
  if shown and api.IsPreviewShown(KEY) then
    consider(shown.lead, shown.shownAt)
  else
    consider(AlertToast.VisibleLead())
  end
  if api.IsPanelShown(KEY) then
    consider(BridgePanel.TopRow())
  end
  return found, foundAt
end

ns.WhisperBridge = WhisperBridge
return WhisperBridge
