local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadsList = ns.LeadsList or require("CraftAlert.UI.LeadsList")
local WindowSize = ns.WindowSize or require("CraftAlert.UI.WindowSize")
local SettingsGear = ns.SettingsGear or require("CraftAlert.UI.SettingsGear")
local SettingsPane = ns.SettingsPane or require("CraftAlert.UI.Settings.SettingsPane")

-- Spec §7.3: the leads window, frame CraftAlertLeadsWindow, created on first open (§4.4 rule
-- 5). The lead cards (UI/LeadsList.lua) show newest first, as many as fit, each with its details;
-- the mouse wheel scrolls them. ESC closes it (UISpecialFrames, the one sanctioned insert). Ages
-- and cards refresh on open and on each lead change, never on a ticker. Native-HUD spec §7.1: a
-- gear swaps the cards for the settings pane. Movable and resizable: one position and one size
-- (CraftAlertDB.ui.window), shared by both modes. The mode is never saved: every open is the list,
-- except /ca config.
local LeadsWindow = {}

local FRAME_NAME = "CraftAlertLeadsWindow"
local UI_KEY = "window"
local FALLBACK_POSITION = { "CENTER", 0, 0 }
local LAYOUT = Theme.LAYOUT
-- The WindowSize both modes share.
local SIZE = { key = UI_KEY, width = LAYOUT.WINDOW_WIDTH, height = LAYOUT.WINDOW_HEIGHT }
SIZE.minWidth, SIZE.minHeight = LAYOUT.WINDOW_MIN_WIDTH, LAYOUT.WINDOW_MIN_HEIGHT

---@type table
local window = nil -- { frame, list, mode = "list" | "settings" }, nil until the first open

local function settings()
  return _G["CraftAlertDB"].settings
end

-- Re-reads the leads into the rows. A no-op until the first open and while closed; in Settings it
-- only applies the opacity. Bootstrap subscribes it to Leads.On("change").
function LeadsWindow.Refresh()
  if window == nil or not window.frame:IsShown() then
    return
  end
  window.frame:SetAlpha(settings().opacity or 1)
  if window.mode == "settings" then
    return
  end
  LeadsList.Refresh(window.list, Leads.List())
end

local function onMouseWheel(_, delta)
  if window.mode == "settings" then
    return
  end
  LeadsList.Scroll(window.list, delta)
  LeadsWindow.Refresh()
end

-- The template's inset starts 60 below the top, room for a portrait; without one that wastes a row
-- (Blizzard re-anchors it the same way in FriendsFrame.lua).
local function anchorInset(frame)
  local layout, inset = Theme.LAYOUT, frame.Inset
  inset:ClearAllPoints()
  inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -layout.INSET_TOP)
  inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, layout.INSET_BOTTOM)
end

local function onResizeStopped(target)
  WindowSize.Save(target, SIZE, UI_KEY)
  LeadsWindow.Refresh()
end

local function createResizeButton(frame)
  local button = _G["CreateFrame"]("Button", nil, frame, "PanelResizeButtonTemplate")
  button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  button:SetFrameLevel(frame.TitleContainer:GetFrameLevel()) -- above the NineSlice border's corner
  -- Init wraps the frame's OnSizeChanged as it is now, so the refresh must already be set.
  frame:SetScript("OnSizeChanged", LeadsWindow.Refresh)
  button:Init(frame, SIZE.minWidth, SIZE.minHeight, _G["UIParent"]:GetWidth(), _G["UIParent"]:GetHeight())
  button:SetOnResizeStoppedCallback(onResizeStopped)
  frame.resizeButton = button
end

-- The template's close button runs UIPanelCloseButton_OnClick
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua:144-155): this callback first, and
-- HideUIPanel only when it returns truthy. HideUIPanel
-- (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:886-897) returns without hiding
-- in combat when called from addon code, so the callback hides the frame itself.
local function onClose(closeButton)
  closeButton:GetParent():Hide()
  return false
end

local function enterList()
  local frame = window.frame
  SettingsPane.Hide()
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  SettingsGear.Paint(frame.gear, false)
  window.mode = "list"
  LeadsWindow.Refresh()
end

local function enterSettings()
  local frame = window.frame
  window.mode = "settings"
  LeadsList.Clear(window.list)
  SettingsPane.Build(frame.Inset, enterList)
  SettingsPane.Show()
  frame:SetTitle(Localization.Text("Craft Alert — Settings"))
  SettingsGear.Paint(frame.gear, true)
end

local function onGearClick()
  if window.mode == "settings" then
    enterList()
  else
    enterSettings()
  end
end

local function create()
  local frame = _G["CreateFrame"]("Frame", FRAME_NAME, _G["UIParent"], "ButtonFrameTemplate")
  frame.onCloseCallback = onClose
  frame:SetFrameStrata("HIGH")
  _G["ButtonFrameTemplate_HidePortrait"](frame)
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  anchorInset(frame)
  WindowSize.Apply(frame, SIZE)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", onMouseWheel)
  createResizeButton(frame)
  frame.gear = SettingsGear.Create(frame, onGearClick)
  local list = LeadsList.New(frame.Inset)
  frame:Hide()
  table.insert(_G["UISpecialFrames"], FRAME_NAME)
  return { frame = frame, list = list, mode = "list" }
end

-- Opens the window on the list, at the top (every card counts as shown from now), or closes it in
-- either mode. X and Esc only hide: a window closed in Settings comes back on the list here.
-- Silent no-op in an instance.
function LeadsWindow.Toggle()
  if FlavorCompat.InInstance() then
    return
  end
  window = window or create()
  local frame = window.frame
  if frame:IsShown() then
    frame:Hide()
    return
  end
  if window.mode == "settings" then
    enterList()
  end
  LeadsList.ResetTop(window.list)
  LeadsList.Clear(window.list)
  frame:Show()
  LeadsWindow.Refresh()
end

-- /ca config: opens the window on the settings pane (from the list too), or closes it when the
-- pane shows. Reopened, the pane shows the page last shown, read again from the db. Silent no-op
-- in an instance.
function LeadsWindow.ToggleSettings()
  if FlavorCompat.InInstance() then
    return
  end
  window = window or create()
  local frame = window.frame
  if frame:IsShown() and window.mode == "settings" then
    frame:Hide()
    return
  end
  if window.mode == "list" then
    enterSettings()
  else
    SettingsPane.Show()
  end
  frame:Show()
  LeadsWindow.Refresh()
end

-- ScanGate.OnChange (wired by Bootstrap): entering an instance closes the window in either mode;
-- leaving does not reopen it. Arguments are ignored.
function LeadsWindow.OnGate()
  if window ~= nil and FlavorCompat.InInstance() then
    window.frame:Hide()
  end
end

-- The lead in the top row and GetTime() when it appeared there, or nil (closed, hidden by Alt+Z,
-- scrolled, empty). IsVisible, not IsShown: a window under a hidden UIParent stays shown.
function LeadsWindow.VisibleLatest()
  if window == nil or not window.frame:IsVisible() then
    return nil
  end
  local row = LeadsList.TopRow(window.list)
  if not row or not row.lead or not Leads.IsActive(row.lead.id) then
    return nil
  end
  return row.lead, row.shownAt
end

ns.LeadsWindow = LeadsWindow
return LeadsWindow
