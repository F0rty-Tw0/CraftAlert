local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Phone-style slide spec through WM's panel: a slide never shows a top row, and hiding the panel,
-- the Settings link or a width crossing ends one in flight.
local function boot(opts)
  local ns, db, calls = UiFixture.load(opts or { leads = 3 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, db, calls, wm
end

local function newHost(width)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, 400)
  return host
end

-- Records the LeadsView the panel builds: captured.view.
local function capture(ns)
  local captured = {}
  local new = ns.LeadsView.New
  ns.LeadsView.New = function(...)
    captured.view = new(...)
    return captured.view
  end
  return captured
end

local function showWith(wm, width, listWidth)
  local host = newHost(width)
  wm.showPanel("CraftAlert", host, listWidth)
  return host
end

local function openSettings(host)
  Widgets.click(SettingsFixture.button(host, "Settings"))
end

-- Review Focus 1 through the panel: no top row and no visible lead while the slide runs or rests.
local function testNoTopRowAtAnyPointOfTheSlide()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  showWith(wm, 360)
  captured.view.frame:SetSize(360, 400)
  Widgets.click(captured.view.list.rows[2], "LeftButton")
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.BridgePanel.TopRow(), ns.WhisperBridge.VisibleLead() }, { true })
  ns.ScreenSlide.FinishNow()
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.BridgePanel.TopRow() }, { false })
end

-- Panel hide mid-slide: ended, details at rest, list hidden, clip off, no OnUpdate; the next show
-- starts on the List with no slide.
local function testPanelHideMidSlideFinishesIt()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  local host = showWith(wm, 360)
  local view = captured.view
  view.frame:SetSize(360, 400)
  Widgets.click(view.list.rows[2], "LeftButton")
  wm.hidePanel("CraftAlert")
  Assert.same(
    { ns.ScreenSlide.IsSliding(), view.listPane:IsShown(), view.detailsPane:IsShown(), view.frame.clipsChildren },
    { false, false, true, false }
  )
  Assert.same(view.detailsPane.points[1], { "TOPLEFT", view.parent, "TOPLEFT", 0, -20 }, "at rest")
  for _, frame in ipairs(Wow.frames) do
    Assert.equal(frame.scripts.OnUpdate, nil)
  end
  wm.showPanel("CraftAlert", host)
  Assert.same(
    { ns.LeadsView.Screen(view), ns.ScreenSlide.IsSliding(), view.listPane:IsShown(), view.detailsPane:IsShown() },
    { "list", false, true, false }
  )
end

-- The Settings link mid-slide: the leads frame hides, which ends the slide (parent-hide hook).
local function testSettingsLinkMidSlideEndsIt()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  local host = showWith(wm, 360)
  captured.view.frame:SetSize(360, 400)
  Widgets.click(captured.view.list.rows[2], "LeftButton")
  openSettings(host)
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.SettingsPane.Screen(), captured.view.frame:IsShown() }, { false, "nav", false })
  Assert.same(captured.view.detailsPane.points[1], { "TOPLEFT", captured.view.parent, "TOPLEFT", 0, -20 })
end

-- Back arrow mid-slide: the first slide ends, the reverse one starts.
local function testBackMidSlideReversesCleanly()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  showWith(wm, 360)
  local view = captured.view
  view.frame:SetSize(360, 400)
  Widgets.click(view.list.rows[2], "LeftButton")
  Widgets.click(view.details.back)
  Assert.same(
    { ns.LeadsView.Screen(view), ns.ScreenSlide.IsSliding(), view.listPane:IsShown(), view.detailsPane:IsShown() },
    { "list", true, true, true }
  )
  ns.ScreenSlide.FinishNow()
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { true, false })
end

-- A split-view host (>= 520) never animates.
local function testWideHostNeverAnimates()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  showWith(wm, 600)
  captured.view.frame:SetSize(600, 400) -- else the view is 0 wide and the test passes trivially
  Widgets.click(captured.view.list.rows[2], "LeftButton")
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.ScreenSlide.Group(captured.view.listPane) }, { false })
end

return function()
  testNoTopRowAtAnyPointOfTheSlide()
  testPanelHideMidSlideFinishesIt()
  testSettingsLinkMidSlideEndsIt()
  testBackMidSlideReversesCleanly()
  testWideHostNeverAnimates()
  Wow.reset()
end
