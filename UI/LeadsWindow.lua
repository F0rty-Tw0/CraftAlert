local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadRow = ns.LeadRow or require("CraftAlert.UI.LeadRow")

-- Spec §7.3: the leads window, frame CraftAlertLeadsWindow, created on first open (§4.4 rule
-- 5). Rows newest first, as many as fit; the mouse wheel scrolls. Movable and resizable, with
-- position and size saved in CraftAlertDB.ui.window; ESC closes it (UISpecialFrames, the one
-- sanctioned insert). Ages and rows refresh on open and on each lead change, never on a ticker.
local LeadsWindow = {}

local floor = math.floor
local max = math.max
local min = math.min
local type = type

local FRAME_NAME = "CraftAlertLeadsWindow"
local UI_KEY = "window"
local FALLBACK_POSITION = { "CENTER", 0, 0 }

---@type table
local window = nil -- { frame, rows = { row, ... }, empty }, nil until the first open
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

-- Re-reads the leads into the rows. A no-op until the first open and while closed; Bootstrap
-- subscribes it to Leads.On("change").
function LeadsWindow.Refresh()
  if window == nil or not window.frame:IsShown() then
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
  window.frame:SetAlpha(settings().opacity or 1)
end

local function onMouseWheel(_, delta)
  offset = offset - delta
  LeadsWindow.Refresh()
end

local function saveFrame(frame)
  FrameKit.SavePosition(frame, UI_KEY)
  local saved = FrameKit.Saved(UI_KEY)
  if saved then
    saved.width, saved.height = frame:GetWidth(), frame:GetHeight()
  end
end

-- The saved size, at most the screen's (the Schema keeps any finite number).
local function applySavedSize(frame)
  local layout, saved, screen = Theme.LAYOUT, FrameKit.Saved(UI_KEY) or {}, _G["UIParent"]
  local width = type(saved.width) == "number" and saved.width or layout.WINDOW_WIDTH
  local height = type(saved.height) == "number" and saved.height or layout.WINDOW_HEIGHT
  width = max(min(width, screen:GetWidth()), layout.WINDOW_MIN_WIDTH)
  height = max(min(height, screen:GetHeight()), layout.WINDOW_MIN_HEIGHT)
  frame:SetSize(width, height)
  frame:SetResizable(true)
  frame:SetResizeBounds(layout.WINDOW_MIN_WIDTH, layout.WINDOW_MIN_HEIGHT)
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
  saveFrame(target)
  LeadsWindow.Refresh()
end

local function createResizeButton(frame)
  local layout, screen = Theme.LAYOUT, _G["UIParent"]
  local button = _G["CreateFrame"]("Button", nil, frame, "PanelResizeButtonTemplate")
  button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  -- Init wraps the frame's OnSizeChanged as it is now, so the refresh must already be set.
  frame:SetScript("OnSizeChanged", LeadsWindow.Refresh)
  button:Init(frame, layout.WINDOW_MIN_WIDTH, layout.WINDOW_MIN_HEIGHT, screen:GetWidth(), screen:GetHeight())
  button:SetOnResizeStoppedCallback(onResizeStopped)
  frame.resizeButton = button
  return button
end

local function createTexts(frame, resizeButton)
  local layout, inset = Theme.LAYOUT, frame.Inset
  local empty = FrameKit.Text(inset, Theme.FONTS.body, Theme.COLORS.textSecondary)
  empty:SetPoint("CENTER", inset, "CENTER", 0, 0)
  empty:SetJustifyH("CENTER")
  empty:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))
  local hint = FrameKit.Text(frame, Theme.FONTS.detail, Theme.COLORS.textTimestamp)
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", layout.PADDING, layout.PADDING)
  hint:SetPoint("RIGHT", resizeButton, "LEFT", -layout.PADDING, 0)
  hint:SetText(Localization.Text("Click: greet · Shift: edit first · Ctrl: empty whisper · Right: dismiss"))
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

local function create()
  local frame = _G["CreateFrame"]("Frame", FRAME_NAME, _G["UIParent"], "ButtonFrameTemplate")
  frame.onCloseCallback = onClose
  frame:SetFrameStrata("HIGH")
  _G["ButtonFrameTemplate_HidePortrait"](frame)
  frame:SetTitle(Localization.Text("Craft Alert — Leads"))
  anchorInset(frame)
  applySavedSize(frame)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", onMouseWheel)
  local resizeButton = createResizeButton(frame)
  local empty = createTexts(frame, resizeButton)
  frame:Hide()
  table.insert(_G["UISpecialFrames"], FRAME_NAME)
  return { frame = frame, rows = {}, empty = empty }
end

-- Opens the window at the top of the list (every row counts as shown from now), or closes it.
function LeadsWindow.Toggle()
  window = window or create()
  local frame = window.frame
  if frame:IsShown() then
    frame:Hide()
    return
  end
  offset = 0
  for _, row in ipairs(window.rows) do
    LeadRow.Clear(row)
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
