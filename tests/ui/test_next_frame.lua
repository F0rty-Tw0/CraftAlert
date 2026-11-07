local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- NextFrame: one call on the next frame however often it is asked for, on an engine animation
-- group (rule 1: no OnUpdate, no unlisted C_Timer.After).
local function setup()
  local ns = UiFixture.load()
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  local calls = 0
  local clock = ns.NextFrame.New(parent, function()
    calls = calls + 1
  end)
  return ns, clock, function()
    return calls
  end
end

local function testRequestsInOneFrameCallOnce()
  local ns, clock, calls = setup()
  ns.NextFrame.Request(clock)
  ns.NextFrame.Request(clock)
  Assert.equal(calls(), 0, "not before the frame ends")
  Widgets.nextFrame()
  Assert.equal(calls(), 1)
  Widgets.nextFrame()
  Assert.equal(calls(), 1, "an idle clock calls nothing")
  ns.NextFrame.Request(clock)
  Widgets.nextFrame()
  Assert.equal(calls(), 2, "a later request calls again")
end

local function testCancelDropsTheCall()
  local ns, clock, calls = setup()
  ns.NextFrame.Request(clock)
  ns.NextFrame.Cancel(clock)
  Widgets.nextFrame()
  Assert.equal(calls(), 0)
end

-- The clock lasts one frame on an animation; no OnUpdate script, no timer.
local function testClockIsAnAnimationGroup()
  local ns, clock = setup()
  local timers = 0
  Wow.stub("C_Timer", {
    After = function()
      timers = timers + 1
    end,
  })
  ns.NextFrame.Request(clock)
  Assert.same(clock.animations[1].calls, { { "SetDuration", ns.NextFrame.SECONDS } })
  Assert.truthy(ns.NextFrame.SECONDS <= Widgets.FRAME, "within one frame")
  Assert.equal(timers, 0)
  for _, frame in ipairs(Wow.frames) do
    Assert.equal(frame.scripts.OnUpdate, nil)
  end
end

return function()
  testRequestsInOneFrameCallOnce()
  testCancelDropsTheCall()
  testClockIsAnAnimationGroup()
  Wow.reset()
end
