local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")

-- The scroll view of a settings page and of the lead details, as WhisperMessenger's: a plain
-- ScrollFrame with its own size, clipping; the content anchored and sized before it becomes the
-- scroll child; the retail ScrollBar (UI/ScrollBar.lua) shown only on overflow, synced both ways
-- with the frame's offset, its width always kept free right of the frame. The fakes do not lay
-- out: a test sizes the box as the client would and fires its OnSizeChanged. The default C_Texture
-- stub reports every atlas 1 px wide, so the bar is the retail one, 1 px wide.

local WIDTH, HEIGHT = 400, 300

-- A fresh ScrollView module. → ScrollView, Theme
local function loadModule()
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  local Theme = Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  Fresh.require("UI.ScrollBar")
  return Fresh.require("UI.ScrollView"), Theme
end

local function newBox()
  local box = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  box:SetSize(WIDTH, HEIGHT)
  return box
end

-- A fresh view in a box WIDTH x HEIGHT. → view, ScrollView, Theme
local function load()
  local ScrollView, Theme = loadModule()
  return ScrollView.Create(newBox()), ScrollView, Theme
end

local function resize(view, width, height)
  view.box:SetSize(width, height)
  Widgets.fire(view.box, "OnSizeChanged", width, height)
end

-- Without these the client left most rows undrawn (2026-10-25: no rect).
local function testSetUp()
  local view = load()
  local frame, content, bar = view.frame, view.content, view.bar
  local room = bar:GetWidth()
  Assert.equal(room, 1, "the retail bar, as wide as its atlas")
  Assert.equal(frame.frameType, "ScrollFrame")
  Assert.equal(frame.template, nil, "a plain ScrollFrame, no template")
  Assert.same(frame.points, { { "TOPLEFT", view.box, "TOPLEFT", 0, 0 } }, "one anchor, its own size")
  Assert.equal(frame:GetWidth(), WIDTH - room, "the bar's width is kept free")
  Assert.equal(frame:GetHeight(), HEIGHT)
  Assert.equal(frame.clipsChildren, true, "the frame clips its rows")
  Assert.equal(frame:GetScrollChild(), content)
  Assert.same(frame.childAtScrollChild, {
    points = { { "TOPLEFT", frame, "TOPLEFT", 0, 0 } },
    width = WIDTH - room,
    height = HEIGHT,
  }, "the content is anchored and sized before SetScrollChild")
  Assert.equal(bar.frameType, "Slider")
  Assert.equal(bar.parent, view.box)
  Assert.same(bar.points, { { "TOPRIGHT", view.box, "TOPRIGHT", 0, 0 } }, "the bar hugs the box's right")
  Assert.equal(bar:GetHeight(), HEIGHT, "the box's full height")
  Assert.equal(bar.pieces.top.atlas, "minimal-scrollbar-thumb-top", "WM's retail thumb")
  Assert.equal(frame.mouseWheelEnabled, false, "no overflow: the wheel falls through")
end

-- The bar shows only while the content is taller than the frame; its range is the overflow; the
-- frame takes the wheel only then. The frame's width never changes with it.
local function testBarFollowsContent()
  local view = load()
  local bar, frame = view.bar, view.frame
  Assert.equal(bar:IsShown(), false, "a short page has no bar")
  view.content:SetHeight(HEIGHT + 200)
  Assert.equal(bar:IsShown(), true, "a tall page shows the bar")
  Assert.equal(bar.pieces.top:IsShown(), true)
  Assert.same({ bar:GetMinMaxValues() }, { 0, 200 }, "range = content - viewport")
  Assert.equal(bar:GetValueStep(), 24)
  Assert.equal(frame.mouseWheelEnabled, true)
  Assert.equal(frame:GetWidth(), WIDTH - bar:GetWidth(), "the width is the same with the bar")
  view.content:SetHeight(HEIGHT + 3)
  Assert.equal(bar:IsShown(), false, "a few px over is rounding, not a page to scroll")
  Assert.equal(bar.pieces.top:IsShown(), false)
  Assert.equal(frame.mouseWheelEnabled, false)
  Assert.equal(frame:GetWidth(), WIDTH - bar:GetWidth())
end

-- The wheel and the bar move the frame's offset, each kept inside the range, and mirror it.
local function testWheelAndBar()
  local view = load()
  local frame, bar = view.frame, view.bar
  view.content:SetHeight(HEIGHT + 100)
  Widgets.fire(frame, "OnMouseWheel", -1)
  Assert.equal(frame:GetVerticalScroll(), 24, "a notch down scrolls one step")
  Assert.equal(bar:GetValue(), 24, "the bar follows the wheel")
  for _ = 1, 10 do
    Widgets.fire(frame, "OnMouseWheel", -1)
  end
  Assert.equal(frame:GetVerticalScroll(), 100, "the wheel stops at the bottom")
  Widgets.fire(frame, "OnMouseWheel", 1)
  Assert.equal(frame:GetVerticalScroll(), 76)
  bar:SetValue(40)
  Assert.equal(frame:GetVerticalScroll(), 40, "dragging the bar scrolls the frame")
  for _ = 1, 10 do
    Widgets.fire(frame, "OnMouseWheel", 1)
  end
  Assert.equal(frame:GetVerticalScroll(), 0, "the wheel stops at the top")
  Assert.equal(bar:GetValue(), 0)
end

-- ScrollTo clamps and moves the frame and the bar together.
local function testScrollTo()
  local view, ScrollView = load()
  view.content:SetHeight(HEIGHT + 100)
  ScrollView.ScrollTo(view, 9999)
  Assert.equal(view.frame:GetVerticalScroll(), 100)
  Assert.equal(view.bar:GetValue(), 100)
  ScrollView.ScrollTo(view, -5)
  Assert.equal(view.frame:GetVerticalScroll(), 0)
  Assert.equal(view.bar:GetValue(), 0)
end

-- A resize sets the frame's size, the content's width, the bar's height and the range again, and
-- keeps the offset inside the new range.
local function testResize()
  local view = load()
  local frame, bar = view.frame, view.bar
  view.content:SetHeight(HEIGHT + 100)
  bar:SetValue(100)
  resize(view, 600, 350)
  Assert.equal(frame:GetWidth(), 600 - bar:GetWidth())
  Assert.equal(frame:GetHeight(), 350)
  Assert.equal(view.content:GetWidth(), 600 - bar:GetWidth(), "the content follows the frame's width")
  Assert.equal(bar:GetHeight(), 350)
  Assert.same({ bar:GetMinMaxValues() }, { 0, 50 })
  Assert.equal(frame:GetVerticalScroll(), 50, "the offset is clamped into the new range")
  resize(view, 600, 500)
  Assert.equal(bar:IsShown(), false, "taller than the content: no bar")
  Assert.equal(frame:GetVerticalScroll(), 0)
  Assert.equal(frame.mouseWheelEnabled, false)
  Assert.equal(frame:GetWidth(), 600 - bar:GetWidth())
end

-- Before its first layout the box may read 0 wide: the content starts CONTROL_WIDTH wide, so a
-- page's rows are built at a real width.
local function testUnlaidBox()
  local ScrollView, Theme = loadModule()
  local view = ScrollView.Create(_G["CreateFrame"]("Frame", nil, _G["UIParent"]))
  Assert.equal(view.content:GetWidth(), Theme.LAYOUT.CONTROL_WIDTH)
  Assert.equal(view.bar:IsShown(), false)
end

-- A caller's content (the details body): moved into the frame, anchored TOPLEFT only, its height
-- kept, its width the view's from then on.
local function testCallerContent()
  local ScrollView = loadModule()
  local body = _G["CreateFrame"]("Button", nil, _G["UIParent"])
  body:SetPoint("BOTTOMRIGHT", _G["UIParent"], "BOTTOMRIGHT", 0, 0)
  body:SetHeight(HEIGHT + 60)
  local view = ScrollView.Create(newBox(), body)
  local frame = view.frame
  Assert.equal(view.content, body)
  Assert.equal(body:GetParent(), frame, "the content moves into the scroll frame")
  Assert.same(body.points, { { "TOPLEFT", frame, "TOPLEFT", 0, 0 } }, "its only point")
  Assert.same(frame.childAtScrollChild, {
    points = { { "TOPLEFT", frame, "TOPLEFT", 0, 0 } },
    width = WIDTH - view.bar:GetWidth(),
    height = HEIGHT + 60,
  }, "anchored and sized before SetScrollChild, its height kept")
  Assert.equal(view.bar:IsShown(), true, "a body taller than the box scrolls")
  Assert.same({ view.bar:GetMinMaxValues() }, { 0, 60 })
  resize(view, 500, HEIGHT)
  Assert.equal(body:GetWidth(), 500 - view.bar:GetWidth(), "the view owns its width")
  Assert.equal(body:GetHeight(), HEIGHT + 60)
end

-- A column on the content: a note's new text makes the content taller and the range follows.
local function testColumnHeightSyncs()
  local view = load()
  local Column = Fresh.require("UI.Settings.Column")
  local column = Column.New(view.content)
  local note = Column.Note(column)
  note:SetText("short")
  Assert.equal(view.bar:IsShown(), false)
  note:SetText(string.rep("a long preview line ", 400))
  Assert.equal(view.bar:IsShown(), true, "the note's height reached the range")
  local _, top = view.bar:GetMinMaxValues()
  Assert.equal(top, view.content:GetHeight() - HEIGHT)
end

-- Showing the box again re-reads its size, as WM re-Syncs on show.
local function testShowResyncs()
  local view = load()
  view.content:SetHeight(HEIGHT + 100)
  view.box:Hide()
  view.box:SetSize(WIDTH, HEIGHT + 100)
  view.box:Show()
  Assert.equal(view.frame:GetHeight(), HEIGHT + 100)
  Assert.equal(view.bar:IsShown(), false)
end

return function()
  testSetUp()
  testBarFollowsContent()
  testWheelAndBar()
  testScrollTo()
  testResize()
  testUnlaidBox()
  testCallerContent()
  testColumnHeightSyncs()
  testShowResyncs()
  Wow.reset()
end
