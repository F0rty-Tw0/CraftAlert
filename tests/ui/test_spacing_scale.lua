local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function layout()
  Wow.reset()
  return Fresh.require("UI.Theme").LAYOUT
end

local function testScaleAndWidths()
  local l = layout()
  Assert.same(l.SPACE, { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 })
  Assert.same(l.BUTTON_WIDTH, { S = 48, M = 100, L = 140, XL = 180 })
  Assert.same({ l.ACTION_BUTTON_HEIGHT, l.STATUS_OFFSET, l.NAV_BUTTON_INSET }, { 22, { x = 64, y = -42 }, 2 })
end

-- Oracle: the literals Theme.lua held at f316061. Every gap key keeps its pixels and now equals a SPACE step.
local function testGapKeysKeepTheirPixels()
  local l = layout()
  Assert.same({ l.PADDING, l.DOCK_GAP, l.PANE_PADDING, l.CONTROL_GAP, l.SECTION_GAP, l.DETAILS_PADDING }, { 8, 8, 4, 16, 32, 16 })
  Assert.same(l.PAGE_PADDING, { left = 16, right = 16, top = 12, bottom = 12 })
  Assert.same({ l.SCROLLBAR_GAP, l.BUTTON_HEIGHT, l.INPUT_HEIGHT, l.CONTROL_HEIGHT }, { 5, 20, 22, 24 }, "off-scale and size keys untouched")
  Assert.same(
    { l.PADDING, l.DOCK_GAP, l.PANE_PADDING, l.CONTROL_GAP, l.SECTION_GAP, l.DETAILS_PADDING, l.PAGE_PADDING.top },
    { l.SPACE.S, l.SPACE.S, l.SPACE.XS, l.SPACE.L, l.SPACE.XXL, l.SPACE.L, l.SPACE.M }
  )
end

-- Later tasks add rows: GONE["UI/X.lua"] = { "old declaration text", ... }.
local GONE = {}

local function source(path)
  local handle = assert(io.open(path, "r"))
  local text = handle:read("*a")
  handle:close()
  return text
end

local function testNoMagicSpacingLeft()
  for path, patterns in pairs(GONE) do
    local text = source(path)
    for _, pattern in ipairs(patterns) do
      Assert.falsy(string.find(text, pattern, 1, true), path .. " still has: " .. pattern)
    end
  end
end

return function()
  testScaleAndWidths()
  testGapKeysKeepTheirPixels()
  testNoMagicSpacingLeft()
end
