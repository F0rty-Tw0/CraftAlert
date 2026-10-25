local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadRow = ns.LeadRow or require("CraftAlert.UI.LeadRow")
local ScrollBar = ns.ScrollBar or require("CraftAlert.UI.ScrollBar")

-- Spec A.3: the list half of the split view (UI/LeadsView.lua). 48 px rows (UI/LeadRow.lua) in
-- the list pane, newest first from the scroll offset, as many as the host's height fits; the
-- empty text when there are no leads, unless the rows are icon-only. Rows, the empty text and the scroll bar (UI/ScrollBar.lua,
-- scroll bars spec §3) sit above the pane's inset art; the bar shows only while more leads than
-- fit, and its width and SCROLLBAR_GAP are kept free right of full rows either way. Icon-only rows
-- (WM's rail) hide the bar; the wheel still scrolls them.
local LeadsList = {}

local floor = math.floor
local max = math.max
local min = math.min

-- The rows that fit `height` (the host's, never the pane's own: it may read 0 on the first open),
-- PANE_PADDING above the first row and below the last.
function LeadsList.Fit(height)
  local layout = Theme.LAYOUT
  return max(0, floor((height - 2 * layout.PANE_PADDING) / layout.ROW_HEIGHT))
end

-- Full rows keep the bar's width free at their right. Icon-only rows have the same inset on both
-- sides, so the centred icon sits on the pane's centre, as WM's rail icons do; the bar is hidden then.
local function placeRow(list, row, index)
  local layout, pane = Theme.LAYOUT, list.pane
  local top = layout.PANE_PADDING + (index - 1) * layout.ROW_HEIGHT
  local right = list.compact and layout.LIST_ROW_INSET or layout.PANE_PADDING + list.bar:GetWidth() + layout.SCROLLBAR_GAP
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", pane, "TOPLEFT", layout.LIST_ROW_INSET, -top)
  row:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -right, -top)
end

local function rowAt(list, index)
  local row = list.rows[index]
  if row then
    return row
  end
  row = LeadRow.Create(list.pane, index, list.onSelect)
  LeadRow.SetCompact(row, list.compact)
  row:SetFrameLevel(list.level)
  placeRow(list, row, index)
  list.rows[index] = row
  return row
end

-- A frame over the whole pane, at the rows' level, holding the centred, wrapping text.
local function createEmpty(pane, level)
  local empty = _G["CreateFrame"]("Frame", nil, pane)
  empty:SetAllPoints(pane)
  empty:SetFrameLevel(level)
  local text = FrameKit.Text(empty, Theme.FONTS.body, Theme.COLORS.textSecondary)
  text:SetPoint("LEFT", pane, "LEFT", Theme.LAYOUT.PANE_PADDING, 0)
  text:SetPoint("RIGHT", pane, "RIGHT", -Theme.LAYOUT.PANE_PADDING, 0)
  text:SetWordWrap(true)
  text:SetJustifyH("CENTER")
  text:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))
  empty.text = text
  empty:Hide()
  return empty
end

-- The bar at the pane's right, PANE_PADDING in from its edges, at the rows' level.
local function createBar(pane, level, onScroll)
  local padding = Theme.LAYOUT.PANE_PADDING
  local bar = ScrollBar.New(pane, onScroll)
  bar:SetFrameLevel(level)
  bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -padding, -padding)
  bar:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -padding, padding)
  return bar
end

-- The list in `pane`: no rows yet, scrolled to the top. onSelect(row): a row was left-clicked;
-- onScroll(value): the bar was dragged to `value` rows from the top.
function LeadsList.New(pane, onSelect, onScroll)
  local level = pane:GetFrameLevel() + 2
  return {
    pane = pane,
    rows = {},
    empty = createEmpty(pane, level),
    bar = createBar(pane, level, onScroll),
    offset = 0,
    onSelect = onSelect,
    level = level,
    compact = false,
  }
end

-- Icon-only rows (spec 6a), for the rows made and the ones to come; no empty text meanwhile, as
-- it cannot fit the rail.
function LeadsList.SetCompact(list, compact)
  list.compact = compact
  for index, row in ipairs(list.rows) do
    LeadRow.SetCompact(row, compact)
    placeRow(list, row, index)
  end
  if compact then
    list.empty:Hide()
  end
end

-- Re-reads `leads` (newest first) into the rows from the scroll offset, at most `fit` of them;
-- the row of the lead with id `selectedId` shows the selected mark. The bar's range is the leads
-- out of view.
function LeadsList.Refresh(list, leads, fit, selectedId)
  list.offset = max(0, min(list.offset, #leads - fit))
  -- Bounded by the leads, not the height: a huge saved height must not loop for ever.
  local shown = max(0, min(fit, #leads - list.offset))
  for index = 1, max(shown, #list.rows) do
    local lead = index <= shown and leads[list.offset + index] or nil
    if lead then
      local row = rowAt(list, index)
      LeadRow.Show(row, lead)
      LeadRow.SetSelected(row, lead.id == selectedId)
    elseif list.rows[index] then
      LeadRow.Clear(list.rows[index])
    end
  end
  list.empty:SetShown(#leads == 0 and not list.compact)
  ScrollBar.Set(list.bar, max(0, #leads - fit), list.offset, 1)
  if list.compact then
    list.bar:Hide()
  end
end

-- Hides every row, the empty text and each row's lead, so the next draw shows each one afresh
-- (its shownAt is then new, which VisibleLatest and SendGuard's look rule read).
function LeadsList.Clear(list)
  for _, row in ipairs(list.rows) do
    LeadRow.Clear(row)
  end
  list.empty:Hide()
end

-- The top row when the list is at the top and the row shows, else nil.
function LeadsList.TopRow(list)
  local row = list.rows[1]
  if list.offset ~= 0 or not row or not row:IsVisible() then
    return nil
  end
  return row
end

ns.LeadsList = LeadsList
return LeadsList
