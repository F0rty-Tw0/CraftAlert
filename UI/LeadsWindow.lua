local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadsView = ns.LeadsView or require("CraftAlert.UI.LeadsView")
local WindowSize = ns.WindowSize or require("CraftAlert.UI.WindowSize")
local GhostResize = ns.GhostResize or require("CraftAlert.UI.GhostResize")
local SettingsGear = ns.SettingsGear or require("CraftAlert.UI.SettingsGear")
local SettingsPane = ns.SettingsPane or require("CraftAlert.UI.Settings.SettingsPane")

-- Spec §7.3, A.1: the leads window, frame CraftAlertLeadsWindow, created on first open (§4.4 rule
-- 5). The bell portrait, a status band with the lead count, and below them the content frame
-- holding the split view (UI/LeadsView.lua): the leads newest first on the left, the selected
-- lead's details on the right; the mouse wheel over the view scrolls the list. ESC closes it
-- (UISpecialFrames, the one sanctioned insert). Ages and rows refresh on open and on each lead
-- change, never on a ticker. Native-HUD spec §7.1: a gear swaps the view for the settings pane in
-- the same content frame. Movable and resizable: one position and one size
-- (CraftAlertDB.ui.window), shared by both modes. The mode is never saved: every open is the list,
-- at the top with the newest lead selected, except /ca config.
local LeadsWindow = {}

local FRAME_NAME = "CraftAlertLeadsWindow"
local UI_KEY = "window"
local FALLBACK_POSITION = { "CENTER", 0, 0 }
local LAYOUT = Theme.LAYOUT
-- The WindowSize both modes share.
local SIZE = { key = UI_KEY, width = LAYOUT.WINDOW_WIDTH, height = LAYOUT.WINDOW_HEIGHT }
SIZE.minWidth, SIZE.minHeight = LAYOUT.WINDOW_MIN_WIDTH, LAYOUT.WINDOW_MIN_HEIGHT

---@type table
local router = nil -- fn() -> true when it handled the toggle (WhisperMessenger's panel), else nil
---@type table
local window = nil -- { frame, view, mode = "list" | "settings" }, nil until the first open

local function settings()
  return _G["CraftAlertDB"].settings
end

-- Re-reads the leads into the view and the band. A no-op until the first open and while closed;
-- in Settings it only applies the opacity and empties the band. Bootstrap subscribes it to
-- Leads.On("change").
function LeadsWindow.Refresh()
  if window == nil or not window.frame:IsShown() then
    return
  end
  local frame = window.frame
  -- Mid-drag the window stays faded behind the ghost; the release restores the opacity.
  if not GhostResize.IsResizing() then
    frame:SetAlpha(settings().opacity or 1)
  end
  if window.mode == "settings" then
    frame.status:SetText("")
    return
  end
  local leads = Leads.List()
  LeadsView.Layout(window.view)
  LeadsView.Refresh(window.view, leads)
  frame.status:SetText(#leads > 0 and Localization.Text("%d leads", #leads) or "")
end

-- The bell in the template's portrait; a template without SetPortraitToAsset gets the texture set
-- directly, as WhisperMessenger does (RetailChrome.lua:25-34, WM).
local function paintPortrait(frame)
  if type(frame.SetPortraitToAsset) == "function" then
    frame:SetPortraitToAsset(Theme.ICON)
  else
    frame.PortraitContainer.portrait:SetTexture(Theme.ICON)
  end
end

-- The view's and the settings pane's host, below the portrait (WhisperMessenger's
-- RETAIL_HUD_INSET_*). It replaces the template's inset; each pane draws its own inset art.
local function createContent(frame)
  local inset = LAYOUT.CONTENT_INSET
  frame.Inset:Hide()
  local content = _G["CreateFrame"]("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", inset[1], inset[2])
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset[3], inset[4])
  frame.content = content
end

-- The lead count in the band between the title bar and the panes, right of the portrait.
local function createStatus(frame)
  local status = FrameKit.Text(frame, Theme.FONTS.body, Theme.COLORS.textSecondary)
  status:SetPoint("LEFT", frame, "TOPLEFT", 64, -42)
  frame.status = status
end

-- The view's height is the window's less the content frame's top and bottom insets: the content
-- frame's own height may read 0 on the first open.
local function createView(frame)
  local inset = LAYOUT.CONTENT_INSET
  frame.view = LeadsView.New(frame.content, {
    getHeight = function()
      return frame:GetHeight() + inset[2] - inset[4]
    end,
    getListWidth = function()
      return LAYOUT.LIST_WIDTH
    end,
  })
  return frame.view
end

local function onResizeStopped(target)
  WindowSize.Save(target, SIZE, UI_KEY)
  LeadsWindow.Refresh()
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
  window.view.frame:Show()
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  SettingsGear.Paint(frame.gear, false)
  window.mode = "list"
  LeadsWindow.Refresh()
end

local function enterSettings()
  local frame = window.frame
  window.mode = "settings"
  LeadsView.Clear(window.view)
  window.view.frame:Hide()
  SettingsPane.Build(frame.content, enterList)
  SettingsPane.Show()
  frame:SetTitle(Localization.Text("Craft Alert — Settings"))
  SettingsGear.Paint(frame.gear, true)
  LeadsWindow.Refresh()
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
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  paintPortrait(frame)
  createContent(frame)
  createStatus(frame)
  WindowSize.Apply(frame, SIZE)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  -- The grip sets the size once per drag; the client's OnSizeChanged then refits the rows.
  frame:SetScript("OnSizeChanged", LeadsWindow.Refresh)
  GhostResize.Attach(frame, SIZE, onResizeStopped)
  frame.gear = SettingsGear.Create(frame, onGearClick)
  local view = createView(frame)
  frame:Hide()
  table.insert(_G["UISpecialFrames"], FRAME_NAME)
  return { frame = frame, view = view, mode = "list" }
end

-- `fn()` runs first in every Toggle; returning true means it handled the toggle. nil clears it.
function LeadsWindow.SetRouter(fn)
  router = fn
end

-- Opens the window on the list, at the top with the newest lead selected (every row and the
-- details count as shown from now), or closes it in either mode. X and Esc only hide: a window
-- closed in Settings comes back on the list here. Silent no-op in an instance.
function LeadsWindow.Toggle()
  if FlavorCompat.InInstance() then
    return
  end
  if router and router() then
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
  LeadsView.ResetTop(window.view)
  LeadsView.Clear(window.view)
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
  local row = LeadsView.TopRow(window.view)
  if not row or not row.lead or not Leads.IsActive(row.lead.id) then
    return nil
  end
  return row.lead, row.shownAt
end

ns.LeadsWindow = LeadsWindow
return LeadsWindow
