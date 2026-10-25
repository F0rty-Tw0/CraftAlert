local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local SIZE = { key = "window", width = 840, height = 560, minWidth = 720, minHeight = 420 }

local function setup()
  local ns = UiFixture.load()
  local screen = rawget(_G, "UIParent")
  local target = _G["CreateFrame"]("Frame", nil, screen)
  target:SetSize(840, 560)
  target:SetPoint("CENTER", screen, "CENTER", 0, 0)
  target.left, target.top = 100, 900
  target:SetAlpha(0.7)
  local sizeCalls, setSize = 0, target.SetSize
  function target:SetSize(...)
    sizeCalls = sizeCalls + 1
    return setSize(self, ...)
  end
  local stopped = {}
  local grip = ns.GhostResize.Attach(target, SIZE, function(frame)
    stopped[#stopped + 1] = { frame:GetWidth(), frame:GetHeight() }
  end)
  return ns, target, grip, grip.ghost, stopped, function()
    return sizeCalls
  end
end

local function testGripArt()
  local ns, target, grip = setup()
  Assert.same({ grip:GetWidth(), grip:GetHeight() }, { 16, 16 })
  Assert.same(grip.points[1], { "BOTTOMRIGHT", target, "BOTTOMRIGHT", -6, 4 })
  Assert.equal(grip:GetNormalTexture().texture, ns.Theme.ART.SIZE_GRABBER_UP)
  Assert.equal(grip:GetPushedTexture().texture, ns.Theme.ART.SIZE_GRABBER_DOWN)
  Assert.equal(grip:GetHighlightTexture().texture, ns.Theme.ART.SIZE_GRABBER_HIGHLIGHT)
  Assert.equal(grip:GetFrameLevel(), target:GetFrameLevel() + 20, "no TitleContainer: level from the frame")
  Assert.equal(target.resizeGrip, grip)
end

local function testMouseDownStartsGhost()
  local ns, target, grip, ghost = setup()
  Widgets.fire(grip, "OnMouseDown", "RightButton")
  Assert.equal(ghost:IsShown(), false, "right button does nothing")
  Assert.equal(ns.GhostResize.IsResizing(), false)
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  Assert.equal(target:GetAlpha(), 0.08)
  Assert.equal(ghost:IsShown(), true)
  Assert.equal(ghost.sizing, "BOTTOMRIGHT")
  Assert.equal(ghost.sizingUsesCursor, true)
  Assert.same(ghost.points[1], { "TOPLEFT", rawget(_G, "UIParent"), "BOTTOMLEFT", 100, 900 })
  Assert.same({ ghost:GetWidth(), ghost:GetHeight() }, { 840, 560 })
  Assert.equal(ghost.strata, "DIALOG")
  Assert.equal(ghost.resizable, true)
  Assert.equal(ghost.clamped, true)
  Assert.same(ghost.resizeBounds, { 720, 420, 1920, 1080 })
  Assert.equal(target.sizing, nil, "the window itself is not sized")
  Assert.same({ target:GetWidth(), target:GetHeight() }, { 840, 560 })
  Assert.equal(ns.GhostResize.IsResizing(), true)
end

local function testMouseUpAppliesOnce()
  local ns, target, grip, ghost, stopped, sizeCalls = setup()
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  local before = sizeCalls()
  ghost:SetSize(1000, 700)
  Assert.equal(sizeCalls(), before, "dragging never sets the window's size")
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.same({ target:GetWidth(), target:GetHeight() }, { 1000, 700 })
  Assert.equal(sizeCalls(), before + 1, "set once")
  Assert.same(target.points[1], { "TOPLEFT", rawget(_G, "UIParent"), "BOTTOMLEFT", 100, 900 }, "top-left kept")
  Assert.equal(#target.points, 1)
  Assert.equal(ghost:IsShown(), false)
  Assert.equal(ghost.sizing, nil)
  Assert.equal(target:GetAlpha(), 0.7, "alpha restored")
  Assert.same(stopped, { { 1000, 700 } }, "onStopped once, after the size is set")
  Assert.equal(ns.GhostResize.IsResizing(), false)
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.equal(#stopped, 1, "a stray mouse up does nothing")
end

local function testClamp()
  local _, target, grip, ghost = setup()
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  ghost:SetSize(100, 100)
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.same({ target:GetWidth(), target:GetHeight() }, { 720, 420 }, "no smaller than the minimum")
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  ghost:SetSize(1e6, 1e6)
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.same({ target:GetWidth(), target:GetHeight() }, { 1920, 1080 }, "no bigger than the screen")
end

local function testHideMidDragSavesNothing()
  local ns, target, grip, ghost, stopped = setup()
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  ghost:SetSize(1000, 700)
  target:Hide()
  Assert.equal(ghost:IsShown(), false)
  Assert.equal(ghost.sizing, nil)
  Assert.equal(target:GetAlpha(), 0.7)
  Assert.same({ target:GetWidth(), target:GetHeight() }, { 840, 560 })
  Assert.equal(#stopped, 0)
  Assert.equal(ns.GhostResize.IsResizing(), false)
end

local function testNoOnUpdate()
  local _, target, grip, ghost = setup()
  for _, frame in ipairs({ target, grip, ghost }) do
    Assert.equal(frame.scripts.OnUpdate, nil)
  end
end

-- The real window: the grip replaces PanelResizeButtonTemplate, Refresh leaves the ghost alpha alone,
-- the size is saved, the grip sits above the border.
local function testLeadsWindowWiring()
  local ns, db = UiFixture.load({ leads = 2 })
  db.settings.opacity = 0.7
  ns.LeadsWindow.Toggle()
  local frame = rawget(_G, "CraftAlertLeadsWindow")
  local grip = frame.resizeGrip
  Assert.equal(frame.resizeButton, nil, "the template button is gone")
  Assert.equal(grip:GetFrameLevel(), frame.TitleContainer:GetFrameLevel() + 20)
  Assert.truthy(grip:GetFrameLevel() > frame.NineSlice:GetFrameLevel(), "above the border")
  Assert.same(frame.resizeBounds, { 720, 420 }, "bounds kept from WindowSize.Apply")
  frame.left, frame.top = 30, 600
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  ns.LeadsWindow.Refresh()
  Assert.equal(frame:GetAlpha(), 0.08, "a lead change mid-drag keeps the ghost alpha")
  grip.ghost:SetSize(900, 600)
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.equal(frame:GetAlpha(), 0.7, "the opacity setting is back")
  Assert.same(db.ui.window, { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 30, y = 600, width = 900, height = 600 })
end

return function()
  testGripArt()
  testMouseDownStartsGhost()
  testMouseUpAppliesOnce()
  testClamp()
  testHideMidDragSavesNothing()
  testNoOnUpdate()
  testLeadsWindowWiring()
  Wow.reset()
end
