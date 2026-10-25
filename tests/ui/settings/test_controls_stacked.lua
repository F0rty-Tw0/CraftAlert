local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Layout = require("tests.helpers.layout")

-- Stacked as WhisperMessenger's settings (UI/Shared/SettingsControls.lua): slider, input and
-- dropdown on the line under their label, at the row's width. A toggle keeps its label left of
-- the check, wrapped short of it; section labels and notes wrap at the column's width. The
-- column's parent (a page's scroll child) is as tall as what the column holds.

local PAGE = 240
-- 41 characters, 246 px in the fake font: two lines beside the check at 240, one at 350.
local LONG = "Hide the launcher when there are no leads"

local function nothing() end

-- Fresh Controls on a parent `width` px wide. → Controls, column, parent, layout
local function load(width)
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  local Theme = Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  local Controls = Fresh.require("UI.Settings.Controls")
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  parent:SetWidth(width)
  return Controls, Controls.Column(parent), parent, Theme.LAYOUT
end

local function resize(parent, width)
  parent:SetWidth(width)
  Widgets.fire(parent, "OnSizeChanged", width, 400)
end

local function testStackedRows()
  local Controls, column, _, layout = load(PAGE)
  local controls = {
    slider = Controls.Slider(column, { label = "Timeout", min = 1, max = 60, step = 1, onChange = nothing }),
    input = Controls.Input(column, "Item", nothing),
    choice = Controls.Choice(column, "Sound", { { value = 0, text = "None" } }, nothing),
  }
  -- Left and right gaps between the row's edges and the control's.
  local insets = { slider = { 0, layout.SLIDER_VALUE_WIDTH }, input = { 5, 0 }, choice = { 0, 0 } }
  for name, control in pairs(controls) do
    local row, label = control.row, control.row.labelText
    local rowLeft, rowRight = Layout.edges(row)
    local rowTop, rowBottom = Layout.ys(row)
    local labelTop, labelBottom = Layout.ys(label)
    local left, right = Layout.edges(control.input)
    local top, bottom = Layout.ys(control.input)
    Assert.equal(rowRight - rowLeft, PAGE, name .. ": the row spans the page")
    Assert.equal(labelTop, rowTop, name .. ": the label opens the row")
    Assert.same({ Layout.edges(label) }, { rowLeft, rowRight }, name .. ": the label ends at the row's end")
    Assert.equal(labelBottom - top, 6, name .. ": 6 px under the label (WM's SETTINGS_LABEL_SPACING)")
    Assert.truthy(bottom >= rowBottom, name .. ": the control is inside the row")
    Assert.same({ left - rowLeft, rowRight - right }, insets[name], name .. ": the control spans the row")
    Assert.equal(label.font, "GameFontHighlight", name .. ": WM's settings label font")
  end
  -- The input's text in the label font, clear of the template's 8 px end caps (the left one starts
  -- 5 px out of the box): 3 px past each cap.
  Assert.same(controls.input.input.SetFontObjectArgs, { "GameFontHighlight" })
  Assert.same(controls.input.input.SetTextInsetsArgs, { 6, 11, 0, 0 })
end

-- Row gaps as WM's settings: 16 px between rows (SETTINGS_TOGGLE_ROW_SPACING), 32 px above a
-- section label (SETTINGS_SLIDER_ROW_SPACING, WM's gap before a section title).
local function testRowGaps()
  local Controls, column = load(PAGE)
  local first = Controls.Section(column, "General")
  local one = Controls.Toggle(column, "One", nothing).row
  local two = Controls.Toggle(column, "Two", nothing).row
  local second = Controls.Section(column, "Alerts")
  local function gap(above, below)
    local _, bottom = Layout.ys(above)
    local top = Layout.ys(below)
    return bottom - top
  end
  Assert.same({ gap(first, one), gap(one, two), gap(two, second) }, { 16, 16, 32 })
  Assert.equal(one.labelText.font, "GameFontHighlight", "a toggle's label too")
  local labelTop, labelBottom = Layout.ys(one.labelText)
  local rowTop, rowBottom = Layout.ys(one)
  Assert.equal(rowTop - labelTop, labelBottom - rowBottom, "one line: the label is centred on the check's row")
end

-- The label wraps short of the check; the row grows to hold it, and shrinks back on a wider page.
local function testToggleLabelWraps()
  local Controls, column, parent, layout = load(PAGE)
  local toggle = Controls.Toggle(column, LONG, nothing)
  local row, label, check = toggle.row, toggle.row.labelText, toggle.input
  local function assertHeld(context)
    local _, labelRight = Layout.edges(label)
    local checkLeft = Layout.edges(check)
    local _, rowBottom = Layout.ys(row)
    local _, labelBottom = Layout.ys(label)
    local _, checkBottom = Layout.ys(check)
    Assert.truthy(labelRight <= checkLeft - layout.PADDING, context .. ": the label ends before the check")
    Assert.truthy(labelBottom >= rowBottom and checkBottom >= rowBottom, context .. ": the row holds label and check")
  end
  Assert.equal(label.wordWrap, true)
  assertHeld("at 240")
  local tall = row:GetHeight()
  Assert.truthy(tall > layout.CONTROL_HEIGHT, "two lines make a taller row")
  resize(parent, 600)
  assertHeld("at 600")
  Assert.equal(row:GetHeight(), layout.CONTROL_HEIGHT, "one line: the usual height")
  resize(parent, PAGE)
  Assert.equal(row:GetHeight(), tall, "narrow again: tall again")
end

local function testSectionAndNoteWrap()
  local Controls, column = load(PAGE)
  local header = Controls.Section(column, "Templates ({item} {crafter} {profession} {customer})")
  local note = Controls.Note(column)
  note:SetText(LONG)
  for name, text in pairs({ header = header, note = note }) do
    Assert.same({ Layout.edges(text) }, { 0, PAGE }, name .. " spans the column")
    Assert.equal(text.wordWrap, true, name .. " wraps")
  end
  Assert.equal(Layout.height(header), 2 * Widgets.LINE_HEIGHT, "the header takes two lines")
end

-- The parent is as tall as the rows, from the first one's top to the last one's bottom, also after
-- a note's new text and a width change.
local function testParentAsTallAsContent()
  local Controls, column, parent = load(PAGE)
  Controls.Section(column, "Section")
  Controls.Toggle(column, LONG, nothing)
  Controls.Slider(column, { label = "Timeout", min = 1, max = 60, step = 1, onChange = nothing })
  local note = Controls.Note(column)
  note:SetText("short")
  local list = Controls.List(column, 3, nothing)
  local function content()
    local _, bottom = Layout.ys(list.frame)
    return -bottom
  end
  Assert.truthy(content() > 0)
  Assert.equal(parent:GetHeight(), content(), "as tall as the rows")
  note:SetText(string.rep("word ", 100))
  Assert.equal(parent:GetHeight(), content(), "a longer note: taller")
  resize(parent, 120)
  Assert.equal(parent:GetHeight(), content(), "narrower, more lines: taller")
end

return function()
  testStackedRows()
  testRowGaps()
  testToggleLabelWraps()
  testSectionAndNoteWrap()
  testParentAsTallAsContent()
end
