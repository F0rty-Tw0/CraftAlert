local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LeadsView = ns.LeadsView or require("CraftAlert.UI.LeadsView")
local PanelLook = ns.PanelLook or require("CraftAlert.UI.PanelLook")
local LedgerStrip = ns.LedgerStrip or require("CraftAlert.UI.LedgerStrip")
local SettingsGear = ns.SettingsGear or require("CraftAlert.UI.SettingsGear")
local SettingsPane = ns.SettingsPane or require("CraftAlert.UI.Settings.SettingsPane")
local HostLift = ns.HostLift or require("CraftAlert.UI.HostLift")
local BridgeWidths = ns.BridgeWidths or require("CraftAlert.UI.BridgeWidths")
local ScreenSlide = ns.ScreenSlide or require("CraftAlert.UI.ScreenSlide")

-- Spec C.2, C.4: the leads in WhisperMessenger's panel. The RegisterPanel table the bridge hands
-- over (UI/WhisperBridge.lua) and the split view WM's host frame shows: built once per host, sent
-- back to the top with the newest lead selected on every show, refreshed on lead changes while
-- shown, painted in WM's look, read at every show (UI/PanelLook.lua). A "Settings" link at the
-- ledger line's right swaps the view for the settings pane inside the host (Back returns; the mode
-- is not saved, so every show starts on the leads). The tab's badge counts the unseen leads; WM's
-- Mark all read marks them all seen at once. The table opts in to WM's narrow window (`compact`;
-- an older WM drops the unknown field, so the window still widens and the page shows the split view).
-- A host too narrow for both panes shows one screen at a time, lifted over WM's divider
-- (UI/HostLift.lua): the leads' List or Details (LeadsView.SetNarrow), or the settings' nav or a
-- page (SettingsPane.SetNarrow); every show starts on the List.
local BridgePanel = {}

---@type table
local view = nil -- the LeadsView in the current host, nil until the first show
---@type table
local currentHost = nil -- set before the view is built: LeadsView.New lays out once, at once
local panelShown = false
local mode = "list" -- "list" | "settings"; the settings pane replaces the view in the host
local splitWidth = nil -- WM's divider position from onSplit; nil until it calls, reset by a new host
local narrow = false -- whether LeadsView was last told the host is narrow; a new host starts wide
local look = PanelLook.NATIVE -- WM's look as read at the last show; the settings pane paints with it too

-- Leads keeps its leads in an instance, where the addon shows none (spec C.3).
local function visibleLeads()
  if FlavorCompat.InInstance() then
    return {}
  end
  return Leads.List()
end

-- The pane widths in the current host (UI/BridgeWidths.lua).
local function listWidth()
  return BridgeWidths.List(currentHost:GetWidth(), splitWidth, narrow)
end

local function navWidth()
  return BridgeWidths.Nav(currentHost:GetWidth(), splitWidth)
end

-- Tells the view whenever the host crosses the narrow threshold; a host not laid out yet (0) is wide.
-- On every run (a new host that starts wide never crosses), narrow screens lift over WM's divider.
local function decide()
  local isNarrow = BridgeWidths.IsNarrow(currentHost:GetWidth())
  if isNarrow ~= narrow then
    narrow = isNarrow
    LeadsView.SetNarrow(view, isNarrow)
  end
  HostLift.Apply(view.frame, currentHost, isNarrow)
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

-- The pane takes the host's mode (narrow: the nav first); narrow Details go back to the List first,
-- so Back to leads, or the instance gate, lands on it.
local function enterSettings()
  LeadsView.Back(view)
  -- Attaching to a new host runs the previous owner's showLeads, which must not undo the rest.
  SettingsPane.Attach(view.parent, enterLeads, showLeads, HostLift.LIFT)
  SettingsPane.ApplyLook(look)
  mode = "settings"
  LeadsView.Clear(view)
  view.frame:Hide()
  SettingsPane.SetNarrow(narrow)
  SettingsPane.SetNavWidth(navWidth())
  SettingsPane.Show()
end

-- The Settings link sits at the ledger line's right, centred on it vertically; the
-- counts end before it. They start right of the list (LeadsView sets that edge): WM's divider
-- hairline and its resize handle's line run down the host at the split, through the ledger band,
-- over the host's children (UI/MessengerWindow/LayoutBuilder/ContactsSection.lua:107-130, WM), so
-- they never cross the text.
local function placeLedger()
  local padding = Theme.LAYOUT.PADDING
  local link = SettingsGear.BuildLabeled(view.strip, BridgePanel.ToggleSettings)
  link:SetPoint("RIGHT", view.strip, "RIGHT", -padding, 0)
  LedgerStrip.SetRightInset(view.strip, padding + link:GetWidth() + padding)
end

local function build(host)
  currentHost = host
  splitWidth = nil
  narrow = false
  view = LeadsView.New(host, {
    getHeight = function()
      return host:GetHeight()
    end,
    getListWidth = listWidth,
  })
  placeLedger()
  -- Settings open here follow the host's mode too; in "list" mode the pane may be the standalone
  -- window's, so it is left alone.
  host:HookScript("OnSizeChanged", function()
    if panelShown and view.parent == host then
      decide()
      if mode == "settings" then
        SettingsPane.SetNarrow(narrow)
        SettingsPane.SetNavWidth(navWidth())
      end
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
  -- Resolved here: WhisperBridge loads after this module and requires it.
  look = (ns.WhisperBridge or require("CraftAlert.UI.WhisperBridge")).Look()
  LeadsView.ApplyLook(view, look)
  decide()
  LeadsView.ResetTop(view)
  LeadsView.Clear(view)
  refresh()
  panelShown = true
end

-- A slide in flight ends here, not only through its parent's hide (UI/ScreenSlide.lua).
local function onHide()
  ScreenSlide.FinishNow()
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
  return Leads.CountUnseen(visibleLeads())
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
    compact = true,
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
