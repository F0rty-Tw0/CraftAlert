local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LeadsView = ns.LeadsView or require("CraftAlert.UI.LeadsView")
local SettingsGear = ns.SettingsGear or require("CraftAlert.UI.SettingsGear")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")

-- Spec C.2, C.4: the leads in WhisperMessenger's panel. The RegisterPanel table the bridge hands
-- over (UI/WhisperBridge.lua) and the split view WM's host frame shows: built once per host, sent
-- back to the top with the newest lead selected on every show, refreshed on lead changes while
-- shown. A gear at the details header's top right opens CraftAlert's own window on Settings.
local BridgePanel = {}

local max = math.max
local min = math.min

-- WM's CONTENT_MIN_WIDTH and CONTACTS_MIN_WIDTH (UI/Theme/Layout.lua:12-13, WM): the details keep
-- at least 340 px of the host, the list takes the rest between 180 and the standalone 260.
local DETAILS_MIN_WIDTH = 340
local LIST_MIN_WIDTH = 180
local GEAR_INSET = 6
local GEAR_LEVEL = 10 -- above the details frame's header, zones and buttons

---@type table
local view = nil -- the LeadsView in the current host, nil until the first show
local panelShown = false

-- Leads keeps its leads in an instance, where the addon shows none (spec C.3).
local function visibleLeads()
  if FlavorCompat.InInstance() then
    return {}
  end
  return Leads.List()
end

local function refresh()
  LeadsView.Layout(view)
  LeadsView.Refresh(view, visibleLeads())
end

-- The gear sits on the details pane, not the details frame, so it stays when no lead is selected.
local function addGear()
  local gear = SettingsGear.Build(view.detailsPane, LeadsWindow.ToggleSettings)
  gear:SetPoint("TOPRIGHT", view.details.header, "TOPRIGHT", -GEAR_INSET, -GEAR_INSET)
  gear:SetFrameLevel(view.details.frame:GetFrameLevel() + GEAR_LEVEL)
end

local function build(host)
  view = LeadsView.New(host, {
    getHeight = function()
      return host:GetHeight()
    end,
    getListWidth = function()
      return min(Theme.LAYOUT.LIST_WIDTH, max(LIST_MIN_WIDTH, host:GetWidth() - DETAILS_MIN_WIDTH))
    end,
  })
  addGear()
  host:HookScript("OnSizeChanged", function()
    if panelShown and view.parent == host then
      refresh()
    end
  end)
end

local function onShow(host)
  if view == nil or view.parent ~= host then
    build(host)
  end
  LeadsView.ResetTop(view)
  LeadsView.Clear(view)
  refresh()
  panelShown = true
end

local function onHide()
  panelShown = false
end

local function badge()
  return #visibleLeads()
end

-- The table for API.RegisterPanel.
function BridgePanel.Build()
  return { title = Localization.Text("Craft Alert"), icon = Theme.ICON, onShow = onShow, onHide = onHide, badge = badge }
end

-- Re-reads the leads into the view. A no-op while the panel is hidden.
function BridgePanel.Refresh()
  if panelShown then
    refresh()
  end
end

function BridgePanel.IsShown()
  return panelShown
end

-- The lead in the list's top row and GetTime() when it appeared there, or nil (hidden panel, hidden
-- UIParent, scrolled, empty).
function BridgePanel.TopRow()
  if not panelShown then
    return nil
  end
  local row = LeadsView.TopRow(view)
  if row == nil or row.lead == nil then
    return nil
  end
  return row.lead, row.shownAt
end

ns.BridgePanel = BridgePanel
return BridgePanel
