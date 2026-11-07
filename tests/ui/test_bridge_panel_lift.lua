local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

local LIFT = 60 -- HostLift.LIFT: over WM's divider handle (contacts pane + 50)
local HOST_LEVEL = 5

local function boot()
  local ns = UiFixture.load({ leads = 2 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, wm
end

local function newHost(width)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, 400)
  host:SetFrameLevel(HOST_LEVEL)
  return host
end

local function resize(host, width)
  host:SetSize(width, 400)
  Widgets.fire(host, "OnSizeChanged")
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

local function settingsContainer(host)
  for _, frame in ipairs(Wow.frames) do
    if frame.label and frame.label:GetText() == "Back to leads" then
      local container = frame.parent.parent
      Assert.equal(container.parent, host, "the pane is in the host")
      return container
    end
  end
  error("no settings pane")
end

local function testNarrowViewIsLiftedAndTakesTheMouse()
  local ns, wm = boot()
  local captured = capture(ns)
  wm.showPanel("CraftAlert", newHost(480))
  local frame = captured.view.frame
  Assert.equal(frame:GetFrameLevel(), HOST_LEVEL + LIFT)
  Assert.equal(frame.mouseEnabled, true, "nothing under it is clicked or dragged through it")
end

local function testWideViewKeepsItsPlace()
  local ns, wm = boot()
  local captured = capture(ns)
  wm.showPanel("CraftAlert", newHost(600))
  local frame = captured.view.frame
  Assert.equal(frame:GetFrameLevel(), HOST_LEVEL + 1, "a child's own level")
  Assert.equal(not frame.mouseEnabled, true, "no mouse capture in the split view")
end

local function testCrossingWidthsLiftsAndDrops()
  local ns, wm = boot()
  local captured = capture(ns)
  local host = newHost(600)
  wm.showPanel("CraftAlert", host)
  local frame = captured.view.frame
  resize(host, 519)
  Assert.same({ frame:GetFrameLevel(), frame.mouseEnabled }, { HOST_LEVEL + LIFT, true }, "519 px: narrow, lifted")
  resize(host, 520)
  Assert.same({ frame:GetFrameLevel(), not frame.mouseEnabled }, { HOST_LEVEL + 1, true }, "520 px: wide, dropped")
end

local function testDetailsScreenStaysLifted()
  local ns, wm = boot()
  local captured = capture(ns)
  wm.showPanel("CraftAlert", newHost(480))
  Widgets.click(captured.view.list.rows[1], "LeftButton")
  Assert.equal(ns.LeadsView.Screen(captured.view), "details")
  Assert.same({ captured.view.frame:GetFrameLevel(), captured.view.frame.mouseEnabled }, { HOST_LEVEL + LIFT, true })
end

-- Guard: SettingsPane.Attach already lifts; Phase 3's narrow nav and page share that container.
local function testNarrowSettingsAreLifted()
  local ns, wm = boot()
  local host = newHost(480)
  wm.showPanel("CraftAlert", host)
  ns.BridgePanel.ShowSettings()
  local container = settingsContainer(host)
  Assert.same({ container:GetFrameLevel(), container.mouseEnabled }, { HOST_LEVEL + LIFT, true })
end

return function()
  testNarrowViewIsLiftedAndTakesTheMouse()
  testWideViewKeepsItsPlace()
  testCrossingWidthsLiftsAndDrops()
  testDetailsScreenStaysLifted()
  testNarrowSettingsAreLifted()
  Wow.reset()
end
