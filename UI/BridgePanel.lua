local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LeadsView = ns.LeadsView or require("CraftAlert.UI.LeadsView")
local LedgerStrip = ns.LedgerStrip or require("CraftAlert.UI.LedgerStrip")
local SettingsGear = ns.SettingsGear or require("CraftAlert.UI.SettingsGear")
local SettingsPane = ns.SettingsPane or require("CraftAlert.UI.Settings.SettingsPane")

-- Spec C.2, C.4: the leads in WhisperMessenger's panel. The RegisterPanel table the bridge hands
-- over (UI/WhisperBridge.lua) and the split view WM's host frame shows: built once per host, sent
-- back to the top with the newest lead selected on every show, refreshed on lead changes while
-- shown. A gear with a "Settings" label at the ledger line's right swaps the view for the settings
-- pane inside the host (Back returns; the mode is not saved, so every show starts on the leads). The tab's badge
-- counts the unseen leads; WM's Mark all read marks them all seen at once.
local BridgePanel = {}

local max = math.max
local min = math.min

-- WM's CONTENT_MIN_WIDTH and CONTACTS_MIN_WIDTH (UI/Theme/Layout.lua:12-13, WM): the details keep
-- at least 340 px of the host, the list takes the rest between 180 and the standalone 260.
local DETAILS_MIN_WIDTH = 340
-- The settings pane's levels above the host: over WM's divider handle, which sits 50 above the
-- contacts pane, a sibling of the host (UI/MessengerWindow/LayoutBuilder/ContactsSection.lua:115-121
-- and UI/Theme/Layout.lua:17, WM), so its line never draws over the settings.
local SETTINGS_LIFT = 60

---@type table
local view = nil -- the LeadsView in the current host, nil until the first show
local currentHost = nil -- set before the view is built: LeadsView.New lays out once, at once
local panelShown = false
local mode = "list" -- "list" | "settings"; the settings pane replaces the view in the host
local splitWidth = nil -- WM's divider position from onSplit; nil until it calls, reset by a new host

-- Leads keeps its leads in an instance, where the addon shows none (spec C.3).
local function visibleLeads()
  if FlavorCompat.InInstance() then
    return {}
  end
  return Leads.List()
end

-- The list's width in the host: WM's divider once it called onSplit, else what the host leaves the
-- details, between the minimum and the standalone window's.
local function listWidth()
  if splitWidth ~= nil then
    return splitWidth
  end
  return min(Theme.LAYOUT.LIST_WIDTH, max(Theme.LAYOUT.LIST_MIN_WIDTH, currentHost:GetWidth() - DETAILS_MIN_WIDTH))
end

-- The settings nav keeps its minimum when WM's divider snaps to the rail.
local function navWidth()
  return max(listWidth(), Theme.LAYOUT.LIST_MIN_WIDTH)
end

local function refresh()
  if mode == "settings" then
    return
  end
  LeadsView.Layout(view)
  LeadsView.Refresh(view, visibleLeads())
end

-- The leads' look, without touching the pane: also the fallback when another host takes the pane,
-- maybe while the panel is hidden. A hidden panel does not refresh: that would select a lead, and
-- mark it seen, out of sight; the next show refreshes.
local function showLeads()
  view.frame:Show()
  mode = "list"
  if panelShown then
    refresh()
  end
end

local function enterLeads()
  SettingsPane.Hide()
  showLeads()
end

local function enterSettings()
  -- First: attaching to a new host runs the previous owner's showLeads, which must not undo the rest.
  SettingsPane.Attach(view.parent, enterLeads, showLeads, SETTINGS_LIFT)
  mode = "settings"
  LeadsView.Clear(view)
  view.frame:Hide()
  SettingsPane.SetNavWidth(navWidth())
  SettingsPane.Show()
end

-- The gear and its "Settings" label sit at the ledger line's right, centred on it vertically; the
-- counts end before them. They start right of the list: WM's divider hairline and its resize
-- handle's line run down the host at the split, through the ledger band, over the host's children
-- (UI/MessengerWindow/LayoutBuilder/ContactsSection.lua:107-130, WM), so they never cross the text.
local function placeLedger()
  local padding = Theme.LAYOUT.PADDING
  local link = SettingsGear.BuildLabeled(view.strip, BridgePanel.ToggleSettings)
  link:SetPoint("RIGHT", view.strip, "RIGHT", -padding, 0)
  LedgerStrip.SetRightInset(view.strip, padding + link:GetWidth() + padding)
  LedgerStrip.SetLeftEdge(view.strip, view.listPane)
end

local function build(host)
  currentHost = host
  splitWidth = nil
  view = LeadsView.New(host, {
    getHeight = function()
      return host:GetHeight()
    end,
    getListWidth = listWidth,
  })
  placeLedger()
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
  if mode == "settings" then
    enterLeads()
  end
  LeadsView.ResetTop(view)
  LeadsView.Clear(view)
  refresh()
  panelShown = true
end

local function onHide()
  panelShown = false
end

-- WM's divider moved (after onShow and on every relayout): the list takes `width`, the settings nav
-- follows. Another host's call, or one before the first show, changes nothing; a width that is not
-- a number keeps the fallback.
local function onSplit(host, width)
  if view == nil or view.parent ~= host then
    return
  end
  splitWidth = type(width) == "number" and width or nil
  if mode == "settings" then
    SettingsPane.SetNavWidth(navWidth())
  elseif panelShown then
    refresh()
  end
end

-- The tab's count (and WM's icon number): visible leads not yet greeted or whispered to, nor seen
-- (shown in the details, or Mark all read). WM calls it on every icon refresh, so one pass and no
-- WM call.
local function badge()
  local count = 0
  for _, lead in ipairs(visibleLeads()) do
    if Leads.IsUnseen(lead) then
      count = count + 1
    end
  end
  return count
end

-- WM's Mark all read (it took the preview down already and re-reads the badge after): the count
-- clears with one badge refresh, the leads stay listed and greetable, and the shown rows' dots
-- turn from the unseen gold to their state colour.
local function markAllRead()
  local ids = {}
  for _, lead in ipairs(visibleLeads()) do
    ids[#ids + 1] = lead.id
  end
  Leads.MarkAllSeen(ids)
  BridgePanel.Refresh()
end

-- The table for API.RegisterPanel.
function BridgePanel.Build()
  return {
    title = Localization.Text("Craft Alert"),
    icon = Theme.ICON,
    onShow = onShow,
    onHide = onHide,
    onSplit = onSplit,
    badge = badge,
    onMarkAllRead = markAllRead,
  }
end

-- Re-reads the leads into the view. A no-op while the panel is hidden; in an instance (the gate
-- refreshes on entering one) settings go back to the leads, as LeadsWindow.OnGate closes its window.
function BridgePanel.Refresh()
  if not panelShown then
    return
  end
  if mode == "settings" and FlavorCompat.InInstance() then
    enterLeads()
    return
  end
  refresh()
end

-- The gear: leads <-> settings in the shown panel. A no-op while hidden; in an instance it only
-- goes back to the leads.
function BridgePanel.ToggleSettings()
  if not panelShown or (mode ~= "settings" and FlavorCompat.InInstance()) then
    return
  end
  if mode == "settings" then
    enterLeads()
  else
    enterSettings()
  end
end

-- Settings in the shown panel; a no-op while hidden.
function BridgePanel.ShowSettings()
  if panelShown and mode == "list" then
    enterSettings()
  end
end

function BridgePanel.InSettings()
  return mode == "settings"
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
