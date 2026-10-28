local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local AwaySummary = ns.AwaySummary or require("CraftAlert.Model.AwaySummary")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local AlertToast = ns.AlertToast or require("CraftAlert.UI.AlertToast")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local Launcher = ns.Launcher or require("CraftAlert.UI.Launcher")
local LeadRow = ns.LeadRow or require("CraftAlert.UI.LeadRow")
local BridgePanel = ns.BridgePanel or require("CraftAlert.UI.BridgePanel")
local BridgeInfo = ns.BridgeInfo or require("CraftAlert.UI.BridgeInfo")

-- Spec C.2, C.3: when WhisperMessenger's addon API (_G.WhisperMessengerAPI, version 1) is there at
-- login, the toast becomes WM's widget preview, the leads window becomes a WM panel
-- (UI/BridgePanel.lua), /ca config opens its settings, whisper boxes open as WM conversations and
-- each customer's conversation gets an info line (UI/BridgeInfo.lua). The earlier modules never
-- call this one: Activate plugs it in through their setters (Launcher.SetSuppressed,
-- LeadsWindow.SetRouter and SetSettingsRouter, GreetAction.SetOpener, LeadRow.SetUnreadSource).
-- Without the API nothing here runs.
local WhisperBridge = {}

local ipairs = ipairs
local pcall = pcall
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
---@type table|nil
local summary = nil -- the away summary's token while it is WM's preview (never with `shown`)

local function now()
  return _G["GetTime"]()
end

local function isUsable(candidate)
  if type(candidate) ~= "table" or candidate.version ~= 1 then
    return false
  end
  for _, name in ipairs(REQUIRED) do
    if type(candidate[name]) ~= "function" then
      return false
    end
  end
  return true
end

-- Every call into WM's API after Activate: a raise counts as a refusal (false), so a broken WM
-- never costs the player the Blizzard fallback or the rest of a handler.
local function ask(name, ...)
  local ok, result = pcall(api[name], ...)
  return ok and result
end

-- /ca config: the panel on settings. Shown in settings → closes it (as the own window does); shown
-- on the leads → settings; hidden → opens it, then settings (WM runs onShow inside ShowPanel).
-- → whether WM answered; false leaves /ca config to the own window.
local function toggleSettings()
  if BridgePanel.IsShown() then
    if BridgePanel.InSettings() then
      return ask("TogglePanel", KEY)
    end
    BridgePanel.ShowSettings()
    return true
  end
  if not ask("ShowPanel", KEY) then
    return false
  end
  BridgePanel.ShowSettings()
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
  if not ask("OpenConversation", target, text) then
    defaultOpen(target, text)
  end
end

local function hidePreview()
  shown, summary = nil, nil
  ask("HidePreview", KEY)
end

-- After the toast duration, hides the preview while `isCurrent()`: C_Timer.After cannot be
-- cancelled, so a timer acts only while its own preview is the shown one.
local function hideLater(isCurrent)
  _G["C_Timer"].After(_G["CraftAlertDB"].settings.toastDuration or 20, function()
    if isCurrent() then
      hidePreview()
    end
  end)
end

-- The info lines go out through SetContactInfo (UI/BridgeInfo.lua), a refusal or raise as false.
local function sendInfo(customer, text, lines)
  return ask("SetContactInfo", KEY, customer, text, lines)
end

local function syncInfo()
  BridgeInfo.Sync(sendInfo)
end

-- Bootstrap's step after Leads.Restore: the leads of the last session are back without a "change",
-- so their customers' lines go out now. Not activated: nothing.
function WhisperBridge.SyncInfo()
  if active then
    syncInfo()
  end
end

local function onChange()
  if shown and not Leads.IsActive(shown.lead.id) then
    hidePreview()
  end
  BridgePanel.Refresh()
  ask("RefreshPanelBadge", KEY)
  syncInfo()
end

-- How many whispers of the lead's customer the player has not read in WM; a raise answers false,
-- which LeadRow (like any non-number) counts as 0.
local function unreadOf(lead)
  return ask("GetUnreadCount", lead.customer)
end

-- WM's unread counts changed: repaint every view whose rows can be pink. CraftAlert's own window
-- shows them too when WM refuses the panel (combat, M+ lockdown). Both are no-ops while hidden.
local function onUnreadChanged()
  BridgePanel.Refresh()
  LeadsWindow.Refresh()
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
  local panel = BridgePanel.Build()
  -- An older WM has no GetUnreadCount: no unread callback, no pink dots. The callback goes on the
  -- panel before RegisterPanel: WM copies the panel once and never reads it again.
  local countsUnread = type(candidate.GetUnreadCount) == "function"
  if countsUnread then
    panel.onUnreadChanged = onUnreadChanged
  end
  if candidate.RegisterPanel(KEY, panel) ~= true then
    active = false
    return false
  end
  api, active = candidate, true
  if countsUnread then
    LeadRow.SetUnreadSource(unreadOf)
  end
  Launcher.SetSuppressed(true)
  LeadsWindow.SetRouter(function()
    return ask("TogglePanel", KEY)
  end)
  LeadsWindow.SetSettingsRouter(toggleSettings)
  -- ShowPanel on a shown panel runs no onShow, so the panel leaves the settings itself.
  LeadsWindow.SetOpenRouter(function()
    local opened = ask("ShowPanel", KEY)
    if opened and BridgePanel.InSettings() then
      BridgePanel.ToggleSettings()
    end
    return opened
  end)
  GreetAction.SetOpener(open)
  -- "greeted" and "replied" are always followed by a "change", which syncs the info lines.
  Leads.On("change", onChange)
  Leads.On("seen", function()
    ask("RefreshPanelBadge", KEY)
  end)
  -- A greeting sent while the panel shows (its Greet, a keybind, the preview, or a whisper the
  -- player typed) opens that chat; WM shows it in the panel's place. A test lead has no customer.
  Leads.On("greeted", function(lead)
    if BridgePanel.IsShown() and not lead.test then
      ask("OpenConversation", GreetAction.Target(lead))
    end
  end)
  return true
end

-- Three rows on WM's widget: the customer, their chat line (the item when the line is empty), and
-- who of yours can craft it (`detail`, an alt's name class-coloured; a WM without the field ignores it).
local function previewFor(lead, entry)
  local message = LeadText.Message(lead)
  return {
    sender = lead.customer,
    text = message ~= "" and message or LeadText.What(lead),
    detail = LeadText.CrafterLine(lead),
    classTag = FlavorCompat.ClassOf(lead.guid),
    pulse = true,
    onClick = function()
      local wasGreeted = lead.greeted
      local action = ClickRouter.Handle("LeftButton", lead, entry.shownAt)
      -- Only a greeting this click sent: otherwise Greet opened the draft already, and a test
      -- lead (dry run) has no customer to open.
      if action == "greet" and lead.greeted and not wasGreeted and not lead.test then
        ask("OpenConversation", GreetAction.Target(lead))
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
  if not ask("ShowPreview", KEY, previewFor(lead, entry)) then
    AlertToast.Show(lead)
    return
  end
  AlertToast.Alert(lead)
  shown, summary = entry, nil
  hideLater(function()
    return shown == entry
  end)
end

-- The away summary (Model/AwaySummary.lua, wired by Bootstrap when Activate returned true): WM's
-- preview, a click opens the panel on the list (LeadsWindow.Open, never a toggle), hidden after the
-- toast duration. WM refusing falls back to CraftAlert's own toast. It and a lead's preview replace
-- each other (WM keeps one per key). Nothing in an instance.
function WhisperBridge.ShowSummary(count, expired)
  if FlavorCompat.InInstance() then
    return
  end
  -- A click or dismissal keeps the token: its timer then hides an already hidden preview of this key.
  local entry = {}
  local preview = { sender = Localization.Text("Craft Alert"), text = AwaySummary.Text(count, expired), onClick = LeadsWindow.Open }
  if not ask("ShowPreview", KEY, preview) then
    AlertToast.ShowSummary(count, expired)
    return
  end
  shown, summary = nil, entry
  hideLater(function()
    return summary == entry
  end)
end

-- ScanGate.OnChange (wired by Bootstrap, also standalone): entering an instance takes the preview
-- down; an open panel and the badge follow the gate both ways (empty inside, full again outside).
-- Arguments are ignored.
function WhisperBridge.OnGate()
  if not active then
    return
  end
  if (shown or summary) and FlavorCompat.InInstance() then
    hidePreview()
  end
  BridgePanel.Refresh()
  ask("RefreshPanelBadge", KEY)
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
  if shown and ask("IsPreviewShown", KEY) then
    consider(shown.lead, shown.shownAt)
  else
    consider(AlertToast.VisibleLead())
  end
  if ask("IsPanelShown", KEY) then
    consider(BridgePanel.TopRow())
  end
  return found, foundAt
end

ns.WhisperBridge = WhisperBridge
return WhisperBridge
