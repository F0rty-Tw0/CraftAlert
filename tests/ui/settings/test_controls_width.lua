local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")
local Layout = require("tests.helpers.layout")

-- The settings controls on pages of any width: WhisperMessenger's panel gives a page about 240 px,
-- the leads window 400 px or more. Slider, input and dropdown sit under their label at the row's
-- full width (tests/ui/settings/test_controls_stacked.lua has the vertical layout).

local edges = Layout.edges

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

-- One of each control. → { name = region } for every region that must fit the page
local function build(Controls, column)
  local note = Controls.Note(column)
  note:SetText("A preview")
  local list = Controls.List(column, 2, function() end)
  return {
    toggle = Controls.Toggle(column, "Enable", function() end).input,
    slider = Controls.Slider(column, { label = "Timeout", min = 1, max = 60, step = 1, onChange = function() end }).input,
    input = Controls.Input(column, "Item", function() end).input,
    choice = Controls.Choice(column, "Sound", { { value = 0, text = "None" } }, function() end).input,
    note = note,
    list = list.frame,
    listRow = list.rows[2],
    listBar = list.bar,
  }
end

local function resize(parent, width)
  parent:SetWidth(width)
  Widgets.fire(parent, "OnSizeChanged", width, 400)
end

local function assertFits(regions, width, context)
  for name, region in pairs(regions) do
    local left, right = edges(region)
    Assert.truthy(left >= 0 and right <= width, context .. ": " .. name .. " ends at " .. right .. ", page " .. width)
  end
end

local function testNarrowPageFitsControls()
  local Controls, column = load(240)
  assertFits(build(Controls, column), 240, "built at 240")
end

-- A page is built once and kept: the host's resize reaches the controls.
local function testControlsFollowResize()
  local Controls, column, parent, layout = load(460)
  local regions = build(Controls, column)
  resize(parent, 240)
  assertFits(regions, 240, "resized to 240")
  resize(parent, 600)
  local left = (600 - layout.CONTROL_WIDTH) / 2
  Assert.same({ edges(regions.note) }, { left, left + layout.CONTROL_WIDTH }, "no wider than CONTROL_WIDTH, centered")
end

-- On a page wider than CONTROL_WIDTH the column is CONTROL_WIDTH wide, an equal gap either side.
local function testWidePageCentersColumn()
  local Controls, column, _, layout = load(460)
  local regions = build(Controls, column)
  local left = (460 - layout.CONTROL_WIDTH) / 2
  local right = left + layout.CONTROL_WIDTH
  local function span(name)
    return { edges(regions[name]) }
  end
  Assert.same(span("toggle"), { right - layout.CONTROL_HEIGHT, right })
  Assert.same(span("slider"), { left, right - layout.SLIDER_VALUE_WIDTH }, "room for the value text")
  Assert.same(span("input"), { left + 5, right }, "the box's art starts at the row's edge")
  Assert.same(span("choice"), { left, right })
  Assert.same(span("note"), { left, right })
  Assert.same(span("list"), { left, right })
  Assert.same(span("listBar"), { right - regions.listBar:GetWidth(), right }, "the list's bar at its right edge")
  Assert.same(span("listRow"), { left, right - regions.listBar:GetWidth() - layout.SCROLLBAR_GAP }, "rows end short of the bar")
end

-- With a page's padding the column sits inside it: centered and capped in the width less the
-- left and right padding, the first row the top padding down, the parent as tall as the rows and
-- both paddings.
local function testPaddedColumn()
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  local Theme = Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  local Controls = Fresh.require("UI.Settings.Controls")
  local padding, layout = Theme.LAYOUT.PAGE_PADDING, Theme.LAYOUT
  Assert.same(padding, { left = 16, right = 16, top = 12, bottom = 12 })
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  parent:SetWidth(240)
  local column = Controls.Column(parent, padding)
  local bar = Controls.Bar(column, 30)
  Assert.same({ edges(bar) }, { 16, 224 }, "240 less 16 a side")
  Assert.same({ Layout.ys(bar) }, { -12, -42 }, "the top padding above the first row")
  Assert.equal(parent:GetHeight(), 12 + 30 + 12, "both paddings in the height")
  resize(parent, 600)
  local left = 16 + math.floor((600 - 32 - layout.CONTROL_WIDTH) / 2)
  Assert.same({ edges(bar) }, { left, left + layout.CONTROL_WIDTH }, "capped and centered inside the padding")
end

-- The sound row: Play under the label at the row's start, the dropdown in the rest of the line.
local function testSoundRowFits()
  local ns = SettingsFixture.load()
  SettingsFixture.open(ns, "Alerts")
  local row = SettingsFixture.row("Alert sound")
  local layout = ns.Theme.LAYOUT
  local play = SettingsFixture.button(row, "Play")
  for _, width in ipairs({ 240, 460 }) do
    resize(row.parent, width)
    -- The page sits inside the window, so x is measured from the row's left edge.
    local rowLeft, rowRight = edges(row)
    local playLeft, playRight = edges(play)
    local left, right = edges(row.input)
    Assert.same({ playLeft - rowLeft, left - playRight }, { 0, layout.PADDING }, width .. ": Play, then the dropdown")
    Assert.equal(right, rowRight, width .. ": the dropdown ends at the row's end")
    local padding = layout.PAGE_PADDING
    local column = math.min(width - padding.left - padding.right, layout.CONTROL_WIDTH)
    Assert.equal(rowRight - rowLeft, column, width .. ": the row spans the column inside the page's padding")
    local rowTop, rowBottom = Layout.ys(row)
    local labelTop, labelBottom = Layout.ys(row.labelText)
    Assert.equal(labelTop, rowTop, width .. ": the label opens the row")
    for name, region in pairs({ play = play, dropdown = row.input }) do
      local top, bottom = Layout.ys(region)
      Assert.truthy(top <= labelBottom and bottom >= rowBottom, width .. ": " .. name .. " on the line under the label")
    end
  end
end

return function()
  testNarrowPageFitsControls()
  testControlsFollowResize()
  testWidePageCentersColumn()
  testPaddedColumn()
  testSoundRowFits()
end
