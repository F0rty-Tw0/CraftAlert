local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

local W, H = 360, 400

-- A W x H parent with two full-size screens under a 20 px strip; `from` shown, `to` hidden.
local function rig()
  local ns = UiFixture.load()
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  parent:SetSize(W, H)
  local function screen()
    local frame = _G["CreateFrame"]("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -20)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    return frame
  end
  local from, to = screen(), screen()
  to:Hide()
  return ns.ScreenSlide, parent, from, to
end

local function rest(parent)
  return { { "TOPLEFT", parent, "TOPLEFT", 0, -20 }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0 } }
end

local function shifted(parent, x)
  return { { "TOPLEFT", parent, "TOPLEFT", x, -20 }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", x, 0 } }
end

local function counter()
  local box = { count = 0 }
  return box, function()
    box.count = box.count + 1
  end
end

-- The args of the last `method` call recorded on the group's animation.
local function lastCall(group, method)
  local found
  for _, call in ipairs(group.animations[1].calls) do
    if call[1] == method then
      found = call
    end
  end
  return found
end

-- The client ends a slide from the groups' OnFinished: the leaving frame, then the entering one.
local function finish(S, from, to)
  S.Group(from):Finish()
  S.Group(to):Finish()
end

local function testForwardSlideEndsAtRest()
  local S, parent, from, to = rig()
  local done, onDone = counter()
  S.Show(from, to, 1, onDone)
  Assert.same({ S.IsSliding(), from:IsShown(), to:IsShown(), parent.clipsChildren, done.count }, { true, true, true, true, 0 }, "mid-slide")
  Assert.same(to.points, shifted(parent, W), "to starts one width to the right")
  Assert.same(from.points, rest(parent), "from stays; its group moves it")
  Assert.same({ S.Group(from).playing, S.Group(to).playing }, { true, true })
  for _, frame in ipairs({ from, to }) do
    local group = S.Group(frame)
    Assert.same({ lastCall(group, "SetOffset")[2], lastCall(group, "SetOffset")[3] }, { -W, 0 }, "both travel one width left")
    Assert.equal(lastCall(group, "SetDuration")[2], 0.20)
    Assert.equal(lastCall(group, "SetSmoothing")[2], "OUT", "ease-out")
  end
  finish(S, from, to)
  Assert.same({ S.IsSliding(), from:IsShown(), to:IsShown(), parent.clipsChildren, done.count }, { false, false, true, false, 1 }, "at rest")
  Assert.same(to.points, rest(parent), "to is back at its own anchors")
  Assert.same(from.points, rest(parent))
end

local function testBackwardSlideMirrors()
  local S, parent, from, to = rig()
  S.Show(from, to, -1)
  Assert.same(to.points, shifted(parent, -W), "to starts one width to the left")
  Assert.equal(lastCall(S.Group(from), "SetOffset")[2], W, "both travel right")
  finish(S, from, to)
  Assert.same({ from:IsShown(), to:IsShown() }, { false, true })
end

-- The leaving frame hides when its own group finishes, even before the entering one.
local function testFromHidesOnItsOwnFinish()
  local S, _, from, to = rig()
  S.Show(from, to, 1)
  S.Group(from):Finish()
  Assert.same({ from:IsShown(), S.IsSliding() }, { false, true }, "from gone, slide still open")
  S.Group(to):Finish()
  Assert.equal(S.IsSliding(), false)
end

-- Rule 1 of the design spec: no OnUpdate, ever.
local function testNoOnUpdateEver()
  local S, _, from, to = rig()
  S.Show(from, to, 1)
  for _, frame in ipairs(Wow.frames) do
    Assert.equal(frame.scripts.OnUpdate, nil, "mid-slide")
    Assert.equal(frame.hooks and frame.hooks.OnUpdate, nil, "mid-slide hook")
  end
  S.FinishNow()
  S.Show(to, from, -1)
  finish(S, to, from)
  for _, frame in ipairs(Wow.frames) do
    Assert.equal(frame.scripts.OnUpdate, nil, "after")
  end
end

local function testFinishNowEndsItOnce()
  local S, parent, from, to = rig()
  local done, onDone = counter()
  S.FinishNow()
  S.Show(from, to, 1, onDone)
  S.FinishNow()
  S.FinishNow()
  Assert.same({ S.IsSliding(), from:IsShown(), to:IsShown(), parent.clipsChildren, done.count }, { false, false, true, false, 1 })
  Assert.same({ S.Group(from).playing, S.Group(to).playing }, { false, false }, "the groups are stopped")
  Assert.same(to.points, rest(parent))
end

-- Hiding the clip frame mid-slide (a panel hide, the settings pane taking over) ends the slide:
-- a group on a hidden frame never reports OnFinished.
local function testHidingTheParentFinishesIt()
  local S, parent, from, to = rig()
  local done, onDone = counter()
  S.Show(from, to, 1, onDone)
  parent:Hide()
  Assert.same({ S.IsSliding(), from:IsShown(), to:IsShown(), parent.clipsChildren, done.count }, { false, false, true, false, 1 })
  Assert.same(to.points, rest(parent), "no screen is left off to the side")
end

-- A second Show mid-slide finishes the first (its onDone runs once) and then starts its own.
local function testSecondShowFinishesTheFirst()
  local S, parent, from, to = rig()
  local first, onFirst = counter()
  local second, onSecond = counter()
  S.Show(from, to, 1, onFirst)
  S.Show(to, from, -1, onSecond)
  Assert.same({ first.count, second.count, S.IsSliding() }, { 1, 0, true })
  Assert.same({ from:IsShown(), to:IsShown() }, { true, true }, "the new slide has both on screen")
  Assert.same(from.points, shifted(parent, -W), "from is the entering frame of the direction -1 slide: one width to the left")
  finish(S, to, from)
  Assert.same({ first.count, second.count, from:IsShown(), to:IsShown() }, { 1, 1, true, false })
  Assert.same(from.points, rest(parent))
end

-- Each case breaks one precondition; the swap is instant, onDone runs at once, no group exists.
local function testInstantFallbacks()
  local cases = {
    ["no SetClipsChildren on to"] = function(_, _, _, to)
      to.SetClipsChildren = nil
    end,
    ["no SetClipsChildren on from"] = function(_, _, from)
      from.SetClipsChildren = nil
    end,
    ["no SetClipsChildren on the parent"] = function(_, parent)
      parent.SetClipsChildren = nil
    end,
    ["duration 0"] = function(S)
      S.SLIDE_SECONDS = 0
    end,
    ["parent not laid out"] = function(_, parent)
      parent:SetSize(0, H)
    end,
    ["parent hidden"] = function(_, parent)
      parent:Hide()
    end,
    ["three anchors"] = function(_, parent, _, to)
      to:SetPoint("TOP", parent, "TOP", 0, 0)
    end,
  }
  for name, break_ in pairs(cases) do
    local S, parent, from, to = rig()
    break_(S, parent, from, to)
    local before = {}
    for index, anchor in ipairs(to.points) do
      before[index] = { unpack(anchor) }
    end
    local done, onDone = counter()
    S.Show(from, to, 1, onDone)
    Assert.same({ S.IsSliding(), from:IsShown(), to:IsShown(), done.count }, { false, false, true, 1 }, name)
    Assert.equal(S.Group(to), nil, name .. ": no group")
    Assert.same(to.points, before, name .. ": anchors untouched")
  end
end

-- No group, frame or closure is made per slide: 1000 slides create the two groups once.
local function testNothingIsCreatedPerSlide()
  local S, _, from, to = rig()
  local made = 0
  for _, frame in ipairs({ from, to }) do
    local create = frame.CreateAnimationGroup
    frame.CreateAnimationGroup = function(self)
      made = made + 1
      return create(self)
    end
  end
  local frames = #Wow.frames
  for index = 1, 1000 do
    if index % 2 == 1 then
      S.Show(from, to, 1)
    else
      S.Show(to, from, -1)
    end
    S.FinishNow()
  end
  Assert.same({ made, #Wow.frames }, { 2, frames })
end

return function()
  testForwardSlideEndsAtRest()
  testBackwardSlideMirrors()
  testFromHidesOnItsOwnFinish()
  testNoOnUpdateEver()
  testFinishNowEndsItOnce()
  testHidingTheParentFinishesIt()
  testSecondShowFinishesTheFirst()
  testInstantFallbacks()
  testNothingIsCreatedPerSlide()
  Wow.reset()
end
