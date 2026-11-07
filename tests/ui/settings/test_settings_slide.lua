local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Phone-style slide spec: the narrow nav <-> page changes slide (UI/ScreenSlide.lua); Show, width
-- crossings and the wide pane swap at once.
local function open(narrow)
  local ns = SettingsFixture.load()
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(400, 500)
  ns.SettingsPane.Attach(host, function() end)
  ns.SettingsPane.SetNarrow(narrow)
  ns.SettingsPane.Show()
  local nav = SettingsFixture.navButton("General").parent
  -- The fake does not size an all-points frame; 0 wide would be the instant swap.
  nav.parent:SetSize(400, 500)
  return ns, nav, nav.parent, assert(SettingsFixture.pageHeader(), "no page header").parent
end

local function pick(title)
  Widgets.click(SettingsFixture.navButton(title), "LeftButton")
end

local function fill(c)
  return { { "TOPLEFT", c, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0 } }
end

-- The client ends the slide: each frame's group finishes.
local function settle(ns, ...)
  for _, frame in ipairs({ ... }) do
    local group = ns.ScreenSlide.Group(frame)
    if group and group.playing then
      group:Finish()
    end
  end
end

local function testNavButtonSlidesToThePage()
  local ns, nav, container, right = open(true)
  pick("Alerts")
  Assert.same({ ns.SettingsPane.Screen(), ns.ScreenSlide.IsSliding(), nav:IsShown(), right:IsShown() }, { "page", true, true, true }, "mid-slide")
  Assert.same(right.points[1], { "TOPLEFT", container, "TOPLEFT", 400, 0 }, "the page enters from the right")
  settle(ns, nav, right)
  Assert.same({ ns.ScreenSlide.IsSliding(), nav:IsShown(), right:IsShown() }, { false, false, true })
  Assert.same(right.points, fill(container), "the page spans the pane at rest")
end

local function testHeaderArrowSlidesBack()
  local ns, nav, container, right = open(true)
  pick("Alerts")
  settle(ns, nav, right)
  Widgets.click(assert(SettingsFixture.pageHeader(), "no page header").back)
  Assert.same({ ns.SettingsPane.Screen(), ns.ScreenSlide.IsSliding(), nav:IsShown(), right:IsShown() }, { "nav", true, true, true })
  Assert.same(nav.points[1], { "TOPLEFT", container, "TOPLEFT", -400, 0 }, "the nav enters from the left")
  settle(ns, nav, right)
  Assert.same({ nav:IsShown(), right:IsShown() }, { true, false })
  Assert.same(nav.points, fill(container))
end

-- Show starts on the nav without a slide; hiding the pane mid-slide and widening end it.
local function testShowAndWidthCrossingsAreInstant()
  local ns, nav, _, right = open(true)
  pick("Alerts")
  ns.SettingsPane.Hide()
  ns.SettingsPane.Show()
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.SettingsPane.Screen(), nav:IsShown(), right:IsShown() }, { false, "nav", true, false })
  pick("Alerts")
  ns.SettingsPane.SetNarrow(false)
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.SettingsPane.Screen() }, { false, "split" })
end

local function testWideNeverAnimates()
  local ns, nav = open(false)
  pick("Alerts")
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.ScreenSlide.Group(nav) }, { false })
end

return function()
  testNavButtonSlidesToThePage()
  testHeaderArrowSlidesBack()
  testShowAndWidthCrossingsAreInstant()
  testWideNeverAnimates()
  Wow.reset()
end
