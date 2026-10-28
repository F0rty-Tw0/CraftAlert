local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local SettingsFixture = require("tests.helpers.settings_fixture")
local CraftersFixture = require("tests.helpers.crafters_fixture")
local UiFixture = require("tests.helpers.ui_fixture")
local DetailsFixture = require("tests.helpers.details_fixture")

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

-- Oracle: the widths the settings pages' buttons held at f316061.
local function testButtonWidthsKeepTheirPixels()
  local ns = SettingsFixture.load({ db = CraftersFixture.crafters })
  local expected = {
    Alerts = { Play = 48 },
    ["Linked accounts"] = { Import = 100, ["Import from CraftScan"] = 180 },
    Crafters = { ["Remove character"] = 140 },
  }
  for page, widths in pairs(expected) do
    SettingsFixture.open(ns, page)
    for label, width in pairs(widths) do
      Assert.equal(SettingsFixture.button(SettingsFixture.window(), label):GetWidth(), width, page .. ": " .. label)
    end
  end
end

-- Stub points are { point, relativeTo, relativePoint, x, y }; [4] is x. Mute all and Unmute all meet at the bar's middle.
local function testMuteAllHalves()
  local ns = SettingsFixture.load({ db = CraftersFixture.crafters })
  SettingsFixture.open(ns, "Crafters")
  local mute = SettingsFixture.button(SettingsFixture.window(), "Mute all")
  local unmute = SettingsFixture.button(SettingsFixture.window(), "Unmute all")
  Assert.same({ mute.points[2][4], unmute.points[1][4] }, { -4, 4 }, "4 px each side of the bar's middle")
end

-- The details action bar: Whisper sits BUTTON_GAP (SPACE.S) right of Greet, every button 22 tall.
local function testDetailsActionBar()
  local _, d = DetailsFixture.open({ UiFixture.lead(1, "Buyer-Realm") })
  local b = d.buttons
  Assert.same(b.whisper.points[1], { "LEFT", b.greet, "RIGHT", 8, 0 })
  Assert.same({ b.greet:GetHeight(), b.whisper:GetHeight(), b.dismiss:GetHeight() }, { 22, 22, 22 })
end

-- Oracle: the CraftScan prompt's anchors at d4386b3 (text 16 in, buttons 4 up and 4 off the middle).
local function testCraftScanPromptAnchors()
  local ns, db = SettingsFixture.load()
  Wow.stub("CraftScan_DB", dofile("tests/fixtures/craftscan_db.lua"))
  ns.CraftScanPrompt.MaybeShow(db)
  local window = rawget(_G, "CraftAlertCraftScanPrompt")
  Assert.same(window.text.points[1], { "TOPLEFT", window.Inset, "TOPLEFT", 16, -16 })
  Assert.same(window.accept.points[1], { "BOTTOMRIGHT", window, "BOTTOM", -4, 4 })
  Assert.same(window.decline.points[1], { "BOTTOMLEFT", window, "BOTTOM", 4, 4 })
  Assert.same({ window.accept:GetWidth(), window.decline:GetWidth() }, { 110, 110 })
end

local function nothing() end

-- Fresh Controls on a parent `width` px wide, as test_controls_stacked.lua. → Controls, column
local function load(width)
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  local Controls = Fresh.require("UI.Settings.Controls")
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  parent:SetWidth(width)
  return Controls, Controls.Column(parent)
end

local function create(parent)
  return _G["CreateFrame"]("Frame", nil, parent)
end

-- The row under a heading hangs SPACE.S below it, once; a collapsed empty note spends it (the
-- next row sits 16 below the heading until the note gets text).
local function testHeadingGap()
  local Controls, column = load(240)
  Controls.Section(column, "A")
  local note = Controls.Note(column)
  local after = Controls.Toggle(column, "T", nothing).row
  Assert.same({ -note.points[1][5], -after.points[1][5] }, { 0, 16 }, "a collapsed note spends the 8: the next row 16")
  note:SetText("x") -- an empty note is collapsed to gap 0 (Task 5.9); text restores its baseGap
  Assert.equal(-note.points[1][5], 8, "a note under a heading: 8")
  Assert.equal(-after.points[1][5], 16, "the next row: 16, the 8 is spent once")
  local other = Controls.Section(column, "B")
  Assert.equal(-other.points[1][5], 32, "heading to heading: 32")
  Controls.Section(column, "C")
  local explicit = create(column.parent)
  Controls.Place(column, explicit, 4) -- an explicit gap wins over the pending 8
  Assert.equal(-explicit.points[1][5], 4)
end

-- The recipe toolbar rows hang SPACE.S below each other; the list below them stays a block (16).
local function below(frame)
  for _, candidate in ipairs(Wow.frames) do
    local point = candidate.points and candidate.points[1]
    if point and point[2] == frame and point[3] == "BOTTOMLEFT" then
      return candidate
    end
  end
end

local function testToolbarGaps()
  local ns = SettingsFixture.load({ db = CraftersFixture.crafters })
  SettingsFixture.open(ns, "Crafters")
  local muteBar = SettingsFixture.button(SettingsFixture.window(), "Mute all").parent
  local onlyBar = below(muteBar)
  local list = below(onlyBar)
  Assert.equal(-muteBar.points[1][5], 8, "search to Mute all: 8")
  Assert.equal(-onlyBar.points[1][5], 8, "Mute all to Only: 8")
  Assert.equal(-list.points[1][5], 16, "Only to the list: 16")
end

-- Later tasks add rows: GONE["UI/X.lua"] = { "old declaration text", ... }.
local GONE = {
  ["UI/Settings/PageAlerts.lua"] = { 'Localization.Text("Play"), 48,' },
  ["UI/Settings/PageCrafters.lua"] = { "REMOVE_WIDTH = 140" },
  ["UI/Settings/PageLinked.lua"] = { "IMPORT_WIDTH = 100", "CRAFTSCAN_WIDTH = 180" },
  ["UI/LeadDetails.lua"] = { "BUTTON_GAP, BUTTON_WIDTH, BUTTON_HEIGHT = 8, 100, 22" },
  ["UI/CraftScanPrompt.lua"] = { "local BUTTON_WIDTH = 110", "TEXT_INSET = 16", "BUTTON_GAP = 8", "BUTTON_GAP / 2, 4)" },
  ["UI/LeadsWindow.lua"] = { '"TOPLEFT", 64, -42' },
  ["UI/SettingsGear.lua"] = { "local LABEL_GAP = 4" },
  ["UI/LeadRow.lua"] = { "EDGE, ICON_GAP, MARK_GAP, NAME_GAP = 6, 10, 4, 2" },
  ["UI/Settings/SettingsPane.lua"] = {
    "-(4 + (index - 1)",
    '"TOPLEFT", pane.nav, "TOPLEFT", 2, top',
    '"LEFT", button, "LEFT", 12, 0',
    '"BOTTOMLEFT", nav, "BOTTOMLEFT", 4, 4',
  },
  ["UI/Settings/RecipeList.lua"] = { "Theme.LAYOUT.PADDING / 2" },
  ["UI/DetailsBody.lua"] = {
    "BLOCK_GAP, LABEL_HEIGHT, LABEL_GAP, BUBBLE_PAD_X, BUBBLE_PAD_Y = 18, 14, 5, 12, 10",
    "LABEL_WIDTH, COLUMN_GAP, LINE_HEIGHT, ROW_GAP = 84, 12, 14, 9",
  },
  ["UI/DetailsHeader.lua"] = { "ICON_GAP, NAME_TOP, NAME_SIZE, LINE_GAP = 10, -8, 17, -3" },
}

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
  testButtonWidthsKeepTheirPixels()
  testMuteAllHalves()
  testDetailsActionBar()
  testCraftScanPromptAnchors()
  testHeadingGap()
  testToolbarGaps()
  testNoMagicSpacingLeft()
end
