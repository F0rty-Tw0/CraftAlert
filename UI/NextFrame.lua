local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- One call of a function on the next frame, however many times it is asked for during this one
-- (WhisperMessenger's panel lays out once per frame of host size events, UI/BridgePanel.lua). The
-- clock is an engine animation group, as UI/ScreenSlide.lua's: design spec §4.3 rule 1 bans
-- OnUpdate scripts and keeps C_Timer.After to its listed delays.
local NextFrame = {}

-- The shortest duration the animation API keeps (AceTimer-3.0 used the same floor when its timers
-- ran on animation groups): the group ends on the next frame up to 100 frames a second.
NextFrame.SECONDS = 0.01

-- A clock on its own frame inside `parent` (it ticks while `parent` shows) that calls fn() once
-- per Request that finds it idle.
function NextFrame.New(parent, fn)
  local frame = _G["CreateFrame"]("Frame", nil, parent)
  local group = frame:CreateAnimationGroup()
  group:CreateAnimation():SetDuration(NextFrame.SECONDS) -- a bare Animation: it only takes time
  group:SetScript("OnFinished", function()
    fn()
  end)
  return group
end

-- fn() runs on the next frame; asking again before then changes nothing.
function NextFrame.Request(group)
  if not group:IsPlaying() then
    group:Play()
  end
end

-- A pending call is dropped.
function NextFrame.Cancel(group)
  group:Stop()
end

ns.NextFrame = NextFrame
return NextFrame
