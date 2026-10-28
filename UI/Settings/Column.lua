local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local ScrollBar = ns.ScrollBar or require("CraftAlert.UI.ScrollBar")

-- The settings pages' column: it stacks rows top to bottom. Rows, notes and lists are as wide as
-- the parent less its padding, at most CONTROL_WIDTH, through its resizes (a page is built once,
-- for hosts of any width); a wider parent centers them (WhisperMessenger's settings column). The
-- parent (a page's scroll child) is as tall as what the column holds and its padding. Pages reach
-- it through Controls.
local Column = {}

local floor = math.floor
local max = math.max
local min = math.min

local NO_PADDING = { left = 0, right = 0, top = 0, bottom = 0 }

-- An unnamed frame of `frameType` on `parent`, from `template` (optional); Controls builds on it too.
function Column.Create(frameType, parent, template)
  return _G["CreateFrame"](frameType, nil, parent, template)
end

local create = Column.Create

-- A font string is as tall as its text; a frame has its own height.
local function heightOf(region)
  if region.GetStringHeight then
    return region:GetStringHeight()
  end
  return region:GetHeight()
end

-- The parent as tall as the placed regions, the gaps above them and the top and bottom padding.
-- A collapsed region counts no height.
local function measure(column)
  local height = column.padding.top + column.padding.bottom
  for _, entry in ipairs(column.placed) do
    height = height + entry.gap + (entry.collapsed and 0 or heightOf(entry.region))
  end
  column.parent:SetHeight(height)
end

-- Widths set on the parent's OnSizeChanged, not by right anchors: no anchor caps a width. Then
-- the rows that follow the width (wrapped labels) refit, and the parent is measured. `padding`
-- ({ left, right, top, bottom }, default none) keeps the rows in from the parent's edges.
function Column.New(parent, padding)
  padding = padding or NO_PADDING
  local column = { parent = parent, padding = padding, last = nil, spans = {}, refits = {}, placed = {} }
  local function fit(_, width)
    local room = width - padding.left - padding.right
    column.width = max(0, min(room, Theme.LAYOUT.CONTROL_WIDTH))
    column.left = padding.left + max(0, floor((room - column.width) / 2))
    for _, region in ipairs(column.spans) do
      region:SetWidth(column.width)
    end
    for _, refit in ipairs(column.refits) do
      refit(column.width)
    end
    if column.first then
      column.first:SetPoint("TOPLEFT", parent, "TOPLEFT", column.left, -padding.top)
    end
    measure(column)
  end
  fit(parent, parent:GetWidth())
  parent:HookScript("OnSizeChanged", fit)
  return column
end

-- Keeps `region` as wide as the column.
function Column.Span(column, region)
  region:SetWidth(column.width)
  column.spans[#column.spans + 1] = region
end

-- Runs refit(column width) now and after each width change; the parent is measured after it.
function Column.OnWidth(column, refit)
  refit(column.width)
  column.refits[#column.refits + 1] = refit
  measure(column)
end

-- Anchors `region` below the column's last row (`gap` px; else the gap a heading left pending,
-- else CONTROL_GAP). The first row carries the centering gap; the rest hang off it.
function Column.Place(column, region, gap)
  local anchor = column.last
  local pending = column.nextGap
  column.nextGap = nil
  if anchor then
    gap = gap or pending or Theme.LAYOUT.CONTROL_GAP
    region:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
  else
    gap = 0
    column.first = region
    region:SetPoint("TOPLEFT", column.parent, "TOPLEFT", column.left, -column.padding.top)
  end
  column.last = region
  column.placed[#column.placed + 1] = { region = region, gap = gap, baseGap = gap, anchor = anchor }
  measure(column)
end

-- A collapsed region counts no gap above it and no height, and the rows after it hang from the
-- nearest row above that is not collapsed, so one gap stays between the neighbours. It is not
-- hidden: it sits under that row, over the next one, so the caller empties or hides it.
-- Uncollapsed, it gets its gap back.
function Column.Collapse(column, region, collapsed)
  local above
  for _, entry in ipairs(column.placed) do
    if entry.region == region then
      entry.collapsed = collapsed
      entry.gap = collapsed and 0 or entry.baseGap
    end
    if entry.anchor then
      entry.region:ClearAllPoints()
      entry.region:SetPoint("TOPLEFT", above or entry.anchor, "BOTTOMLEFT", 0, -entry.gap)
    end
    if not entry.collapsed then
      above = entry.region
    end
  end
  measure(column)
end

-- A wrapping text block as wide as the controls.
local function wrapped(column, font)
  local text = FrameKit.Text(column.parent, font)
  Column.Span(column, text)
  text:SetWordWrap(true)
  return text
end

-- The row under it hangs SPACE.S below.
function Column.Section(column, text)
  local label = wrapped(column, Theme.FONTS.name)
  label:SetText(text)
  Column.Place(column, label, column.last and Theme.LAYOUT.SECTION_GAP or 0)
  column.nextGap = Theme.LAYOUT.SPACE.S
  return label
end

-- Previews and results; a new text can change the note's height, so the parent is measured again.
-- An empty note is collapsed: it leaves no gap until text arrives.
function Column.Note(column, font)
  local text = wrapped(column, font or Theme.FONTS.body)
  Column.Place(column, text)
  Column.Collapse(column, text, true)
  _G["hooksecurefunc"](text, "SetText", function()
    Column.Collapse(column, text, (text:GetText() or "") == "")
  end)
  return text
end

-- An empty row as wide as the column, `height` tall, for controls side by side; `gap` as in Place.
function Column.Bar(column, height, gap)
  local bar = create("Frame", column.parent)
  bar:SetHeight(height)
  Column.Span(column, bar)
  Column.Place(column, bar, gap)
  return bar
end

-- `count` rows of LIST_ROW_HEIGHT, made by createRow(row, index), and a ScrollBar at the list's
-- right, its width and SCROLLBAR_GAP kept free of the rows. While more items than rows are listed the bar shows and
-- the mouse wheel pages the rows, also on a scrolling page (the hovered list takes the wheel);
-- otherwise the wheel falls through to the page. A drag pages to the nearest whole item.
-- Rows are Buttons, as only a button draws its HIGHLIGHT layer on hover.
-- Render(items, show) fills them from the current offset with show(row, item).
function Column.List(column, count, createRow)
  local layout = Theme.LAYOUT
  local frame = create("Frame", column.parent)
  frame:SetHeight(count * layout.LIST_ROW_HEIGHT)
  Column.Span(column, frame)
  Column.Place(column, frame)
  local list = { frame = frame, rows = {}, offset = 0, items = {}, show = nil }
  local paint
  local bar = ScrollBar.New(frame, function(value)
    list.offset = floor(value + 0.5)
    paint()
  end)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  list.bar = bar
  for index = 1, count do
    local row = create("Button", frame)
    local top = -(index - 1) * layout.LIST_ROW_HEIGHT
    row:SetHeight(layout.LIST_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(bar:GetWidth() + layout.SCROLLBAR_GAP), top)
    FrameKit.ListHighlight(row)
    createRow(row, index)
    list.rows[index] = row
  end
  function paint()
    local range = max(0, #list.items - count)
    list.offset = max(0, min(list.offset, range))
    for index, row in ipairs(list.rows) do
      local item = list.items[list.offset + index]
      if item ~= nil then
        list.show(row, item)
        row:Show()
      else
        row:Hide()
      end
    end
    ScrollBar.Set(bar, range, list.offset, 1)
    frame:EnableMouseWheel(range > 0)
  end
  function list.Render(items, show)
    list.items, list.show = items, show
    paint()
  end
  frame:EnableMouseWheel(false)
  frame:SetScript("OnMouseWheel", function(_, delta)
    list.offset = list.offset - delta
    paint()
  end)
  return list
end

ns.SettingsColumn = Column
return Column
