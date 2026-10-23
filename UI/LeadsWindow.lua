local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadRow = ns.LeadRow or require("CraftAlert.UI.LeadRow")
local WindowSize = ns.WindowSize or require("CraftAlert.UI.WindowSize")
local SettingsGear = ns.SettingsGear or require("CraftAlert.UI.SettingsGear")
local SettingsPane = ns.SettingsPane or require("CraftAlert.UI.Settings.SettingsPane")

-- Spec §7.3: the leads window, frame CraftAlertLeadsWindow, created on first open (§4.4 rule
-- 5). Rows newest first, as many as fit; the mouse wheel scrolls. ESC closes it (UISpecialFrames,
-- the one sanctioned insert). Ages and rows refresh on open and on each lead change, never on a
-- ticker. Native-HUD spec §7.1: a gear swaps the rows for the settings pane. Movable and resizable:
-- one position (CraftAlertDB.ui.window), a size per mode (ui.window, ui.settings). The mode is
-- never saved: every open is the list, except /ca config.
local LeadsWindow = {}

local floor = math.floor
local max = math.max
local min = math.min

local FRAME_NAME = "CraftAlertLeadsWindow"
local UI_KEY = "window"
local FALLBACK_POSITION = { "CENTER", 0, 0 }
local LAYOUT = Theme.LAYOUT
-- The WindowSize of each mode; the settings pane is never smaller than its default size.
local LIST = { key = UI_KEY, width = LAYOUT.WINDOW_WIDTH, height = LAYOUT.WINDOW_HEIGHT }
LIST.minWidth, LIST.minHeight = LAYOUT.WINDOW_MIN_WIDTH, LAYOUT.WINDOW_MIN_HEIGHT
local SETTINGS = { key = "settings", width = LAYOUT.SETTINGS_WIDTH, height = LAYOUT.SETTINGS_HEIGHT }
SETTINGS.minWidth, SETTINGS.minHeight = SETTINGS.width, SETTINGS.height

---@type table
local window = nil -- { frame, rows = { row, ... }, empty, mode = "list" | "settings" }, nil until the first open
local offset = 0 -- leads scrolled past the top row

-- The inset's height from the frame's own size and the offsets anchorInset gives it: the client
-- sizes the inset from its anchors only, which may still read 0 on the first open.
local function rowsThatFit(frame)
  local layout = Theme.LAYOUT
  local insetHeight = frame:GetHeight() - layout.INSET_TOP - layout.INSET_BOTTOM
  local height = insetHeight - 2 * layout.PADDING
  return max(0, floor((height + layout.ROW_GAP) / (layout.ROW_HEIGHT + layout.ROW_GAP)))
end

local function rowAt(index)
  local row = window.rows[index]
  if row then
    return row
  end
  local layout, inset = Theme.LAYOUT, window.frame.Inset
  row = LeadRow.Create(inset, index)
  local top = layout.PADDING + (index - 1) * (layout.ROW_HEIGHT + layout.ROW_GAP)
  row:SetPoint("TOPLEFT", inset, "TOPLEFT", layout.PADDING, -top)
  row:SetPoint("RIGHT", inset, "RIGHT", -layout.PADDING, 0)
  window.rows[index] = row
  return row
end

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
  local leads = Leads.List()
  local fit = rowsThatFit(window.frame)
  offset = max(0, min(offset, #leads - fit))
  -- Bounded by the leads, not the frame height: a huge saved height must not loop for ever.
  local shown = max(0, min(fit, #leads - offset))
  for index = 1, max(shown, #window.rows) do
    local lead = index <= shown and leads[offset + index] or nil
    if lead then
      LeadRow.Show(rowAt(index), lead)
    elseif window.rows[index] then
      LeadRow.Clear(window.rows[index])
    end
  end
  if #leads == 0 then
    window.empty:Show()
  else
    window.empty:Hide()
  end
end

local function onMouseWheel(_, delta)
  if window.mode == "settings" then
    return
  end
  offset = offset - delta
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
  WindowSize.Save(target, window.mode == "settings" and SETTINGS or LIST, UI_KEY)
  LeadsWindow.Refresh()
end

local function createResizeButton(frame)
  local button = _G["CreateFrame"]("Button", nil, frame, "PanelResizeButtonTemplate")
  button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  button:SetFrameLevel(frame.CloseButton:GetFrameLevel()) -- above the NineSlice border's corner
  -- Init wraps the frame's OnSizeChanged as it is now, so the refresh must already be set.
  frame:SetScript("OnSizeChanged", LeadsWindow.Refresh)
  button:Init(frame, LAYOUT.WINDOW_MIN_WIDTH, LAYOUT.WINDOW_MIN_HEIGHT, _G["UIParent"]:GetWidth(), _G["UIParent"]:GetHeight())
  button:SetOnResizeStoppedCallback(onResizeStopped)
  frame.resizeButton = button
end

local function createEmptyText(frame)
  local inset = frame.Inset
  local empty = FrameKit.Text(inset, Theme.FONTS.body, Theme.COLORS.textSecondary)
  empty:SetPoint("CENTER", inset, "CENTER", 0, 0)
  empty:SetJustifyH("CENTER")
  empty:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))

  return empty
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

-- Hides every row and drops its lead, so the next list draw shows each one afresh (its shownAt
-- is then new, which VisibleLatest and SendGuard's look rule read).
local function clearRows()
  for _, row in ipairs(window.rows) do
    LeadRow.Clear(row)
  end
end

local function enterSettings()
  local frame = window.frame
  window.mode = "settings"
  WindowSize.Apply(frame, SETTINGS)
  clearRows()
  window.empty:Hide()
  SettingsPane.Build(frame.Inset)
  SettingsPane.Show()
  frame:SetTitle(Localization.Text("Craft Alert — Settings"))
  SettingsGear.Paint(frame.gear, true)
end

local function enterList()
  local frame = window.frame
  SettingsPane.Hide()
  WindowSize.Apply(frame, LIST)
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  SettingsGear.Paint(frame.gear, false)
  window.mode = "list"
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
  _G["ButtonFrameTemplate_HidePortrait"](frame)
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  anchorInset(frame)
  WindowSize.Apply(frame, LIST)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", onMouseWheel)
  createResizeButton(frame)
  frame.gear = SettingsGear.Create(frame, onGearClick)
  local empty = createEmptyText(frame)
  frame:Hide()
  table.insert(_G["UISpecialFrames"], FRAME_NAME)
  return { frame = frame, rows = {}, empty = empty, mode = "list" }
end

-- Opens the window on the list, at the top (every row counts as shown from now), or closes it in
-- either mode. X and Esc only hide: a window closed in Settings comes back on the list here.
function LeadsWindow.Toggle()
  window = window or create()
  local frame = window.frame
  if frame:IsShown() then
    frame:Hide()
    return
  end
  if window.mode == "settings" then
    enterList()
  end
  offset = 0
  clearRows()
  frame:Show()
  LeadsWindow.Refresh()
end

-- /ca config: opens the window on the settings pane (from the list too), or closes it when the
-- pane shows. Reopened, the pane shows the page last shown, read again from the db.
function LeadsWindow.ToggleSettings()
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

-- The lead in the top row and GetTime() when it appeared there, or nil (closed, hidden by Alt+Z,
-- scrolled, empty). IsVisible, not IsShown: a window under a hidden UIParent stays shown.
function LeadsWindow.VisibleLatest()
  if window == nil or not window.frame:IsVisible() or offset ~= 0 then
    return nil
  end
  local row = window.rows[1]
  local lead = row and row:IsVisible() and row.lead
  if not lead or not Leads.IsActive(lead.id) then
    return nil
  end
  return lead, row.shownAt
end

ns.LeadsWindow = LeadsWindow
return LeadsWindow
