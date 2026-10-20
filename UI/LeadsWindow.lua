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

local function rowsThatFit(frame)
  local layout = Theme.LAYOUT
  local height = frame:GetHeight() - layout.TITLE_BAR_HEIGHT - layout.FOOTER_HEIGHT - 2 * layout.PADDING
  return max(0, floor((height + layout.ROW_GAP) / (layout.ROW_HEIGHT + layout.ROW_GAP)))
end

local function rowAt(index)
  local row = window.rows[index]
  if row then
    return row
  end
  local layout, frame = Theme.LAYOUT, window.frame
  row = LeadRow.Create(frame, index)
  local top = layout.TITLE_BAR_HEIGHT + layout.PADDING + (index - 1) * (layout.ROW_HEIGHT + layout.ROW_GAP)
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.PADDING, -top)
  row:SetPoint("RIGHT", frame, "RIGHT", -layout.PADDING, 0)
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
  for index = 1, max(fit, #window.rows) do
    local lead = index <= fit and leads[offset + index] or nil
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

local function applySavedSize(frame)
  local layout, saved = Theme.LAYOUT, FrameKit.Saved(UI_KEY) or {}
  local width = type(saved.width) == "number" and saved.width or layout.WINDOW_WIDTH
  local height = type(saved.height) == "number" and saved.height or layout.WINDOW_HEIGHT
  frame:SetSize(max(width, layout.WINDOW_MIN_WIDTH), max(height, layout.WINDOW_MIN_HEIGHT))
  frame:SetResizable(true)
  frame:SetResizeBounds(layout.WINDOW_MIN_WIDTH, layout.WINDOW_MIN_HEIGHT)
end

local function createTitleBar(frame)
  local layout = Theme.LAYOUT
  local bar = frame:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  bar:SetHeight(layout.TITLE_BAR_HEIGHT)
  FrameKit.Fill(bar, Theme.COLORS.chrome)
  local title = FrameKit.Text(frame, Theme.FONTS.title, Theme.COLORS.textPrimary)
  title:SetPoint("LEFT", bar, "LEFT", layout.PADDING, 0)
  title:SetText(Localization.Text("Craft Alert — Leads"))
  local close = _G["CreateFrame"]("Button", nil, frame)
  close:SetSize(layout.TITLE_BUTTON_SIZE, layout.TITLE_BUTTON_SIZE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  local glyph = FrameKit.Text(close, Theme.FONTS.name, Theme.COLORS.textSecondary)
  glyph:SetPoint("CENTER", close, "CENTER", 0, 0)
  glyph:SetText("X")
  close:SetScript("OnClick", function()
    frame:Hide()
  end)
end

local function createResizeGrip(frame)
  local size = Theme.LAYOUT.RESIZE_GRIP_SIZE
  local grip = _G["CreateFrame"]("Button", nil, frame)
  grip:SetSize(size, size)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  grip:EnableMouse(true)
  local texture = grip:CreateTexture(nil, "OVERLAY")
  texture:SetAllPoints(grip)
  texture:SetTexture(Theme.RESIZE_GRIP)
  grip:SetScript("OnMouseDown", function()
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    saveFrame(frame)
    LeadsWindow.Refresh()
  end)
  frame.resizeGrip = grip
end

local function createTexts(frame)
  local layout = Theme.LAYOUT
  local empty = FrameKit.Text(frame, Theme.FONTS.body, Theme.COLORS.textSecondary)
  empty:SetPoint("CENTER", frame, "CENTER", 0, 0)
  empty:SetJustifyH("CENTER")
  empty:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))
  local hint = FrameKit.Text(frame, Theme.FONTS.detail, Theme.COLORS.textTimestamp)
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", layout.PADDING, layout.PADDING / 2)
  hint:SetPoint("RIGHT", frame, "RIGHT", -layout.RESIZE_GRIP_SIZE - layout.PADDING, 0)
  hint:SetText(Localization.Text("Click: greet · Shift: edit first · Ctrl: empty whisper · Right: dismiss"))
  return empty
end

local function create()
  local frame = _G["CreateFrame"]("Frame", FRAME_NAME, _G["UIParent"])
  frame:SetFrameStrata("HIGH")
  applySavedSize(frame)
  FrameKit.Panel(frame)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  createTitleBar(frame)
  createResizeGrip(frame)
  local empty = createTexts(frame)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", onMouseWheel)
  frame:SetScript("OnSizeChanged", LeadsWindow.Refresh)
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

-- The lead in the top row and GetTime() when it appeared there, or nil (closed, scrolled, empty).
function LeadsWindow.VisibleLatest()
  if window == nil or not window.frame:IsShown() or offset ~= 0 then
    return nil
  end
  local row = window.rows[1]
  local lead = row and row:IsShown() and row.lead
  if not lead or not Leads.IsActive(lead.id) then
    return nil
  end
  return lead, row.shownAt
end

ns.LeadsWindow = LeadsWindow
return LeadsWindow
