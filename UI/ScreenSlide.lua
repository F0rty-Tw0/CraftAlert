local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Phone-style slide spec: one narrow screen slides out while the next slides in, both inside
-- their shared parent. The clock is an engine Translation animation (SetSmoothing "OUT" is the
-- ease-out), because rule 1 of the design spec bans OnUpdate scripts. The parent clips only while
-- a slide runs, so pop-ups inside the screens are never cut at rest. Without a clip API, a laid
-- out and visible parent, simple anchors on the entering screen, or an enabled source answering
-- false, the swap is instant.
local ScreenSlide = {}

ScreenSlide.SLIDE_SECONDS = 0.20

local MAX_POINTS = 2

-- Set by the bridge (WhisperMessenger's Window animation); nil slides always.
local enabledSource = nil

local groups = setmetatable({}, { __mode = "k" })
local translations = setmetatable({}, { __mode = "k" })
local hookedParents = setmetatable({}, { __mode = "k" })

-- The one slide in flight (`to` is nil at rest). The entering screen's own anchors sit in the
-- fixed arrays, reused by every slide.
local state = { points = {}, relatives = {}, relativePoints = {}, xs = {}, ys = {}, count = 0 }

local function stopGroup(frame)
  local group = groups[frame]
  if group and group:IsPlaying() then
    group:Stop()
  end
end

local function saveAnchors(frame)
  state.count = frame:GetNumPoints()
  for index = 1, state.count do
    state.points[index], state.relatives[index], state.relativePoints[index], state.xs[index], state.ys[index] = frame:GetPoint(index)
  end
end

local function placeAnchors(frame, shift)
  for index = 1, state.count do
    frame:SetPoint(state.points[index], state.relatives[index], state.relativePoints[index], state.xs[index] + shift, state.ys[index])
  end
end

local function clearAnchors()
  for index = 1, state.count do
    state.relatives[index] = nil
  end
  state.count = 0
end

-- The one end of a slide, from the entering group's OnFinished, FinishNow or the parent's hide:
-- the leaving screen hidden, the entering one back on its own anchors, no clip; onDone runs last
-- and may start the next slide. A no-op at rest.
local function endSlide()
  local from, to, parent, onDone = state.from, state.to, state.parent, state.onDone
  if to == nil then
    return
  end
  state.from, state.to, state.parent, state.onDone = nil, nil, nil, nil
  stopGroup(from)
  placeAnchors(to, 0)
  clearAnchors()
  parent:SetClipsChildren(false)
  from:Hide()
  if onDone then
    onDone()
  end
end

-- The frame's group and Translation, made once; the client gives no order between the two
-- groups' OnFinished, so the leaving screen hides on its own finish and the entering one ends it.
local function groupFor(frame)
  local group = groups[frame]
  if group then
    return group, translations[frame]
  end
  group = frame:CreateAnimationGroup()
  local translation = group:CreateAnimation("Translation")
  translation:SetSmoothing("OUT")
  group:SetScript("OnFinished", function()
    if frame == state.from then
      frame:Hide()
    elseif frame == state.to then
      endSlide()
    end
  end)
  groups[frame], translations[frame] = group, translation

  return group, translation
end

local function startGroup(frame, offset)
  local group, translation = groupFor(frame)
  translation:SetOffset(offset, 0)
  translation:SetDuration(ScreenSlide.SLIDE_SECONDS)

  return group
end

-- A group on a hidden frame never finishes, so hiding the parent ends its slide.
local function onParentHide(parent)
  if parent == state.parent then
    ScreenSlide.FinishNow()
  end
end

local function canSlide(from, to, parent)
  if enabledSource and enabledSource() == false then
    return false
  end
  if ScreenSlide.SLIDE_SECONDS <= 0 or parent == nil or from:GetParent() ~= parent then
    return false
  end
  if not (from.SetClipsChildren and to.SetClipsChildren and parent.SetClipsChildren) then
    return false
  end
  if parent:GetWidth() <= 0 or not parent:IsVisible() then
    return false
  end
  local count = to:GetNumPoints()

  return count > 0 and count <= MAX_POINTS
end

function ScreenSlide.SetEnabledSource(fn)
  enabledSource = fn
end

function ScreenSlide.IsSliding()
  return state.to ~= nil
end

function ScreenSlide.Group(frame)
  return groups[frame]
end

function ScreenSlide.FinishNow()
  if state.to == nil then
    return
  end
  stopGroup(state.to)
  endSlide()
end

-- Direction 1: `from` leaves to the left and `to` enters from the right; -1 the reverse. Ends
-- with `from` hidden and `to` shown on its own anchors, then runs onDone once.
function ScreenSlide.Show(from, to, direction, onDone)
  ScreenSlide.FinishNow()
  local parent = to:GetParent()
  if not canSlide(from, to, parent) then
    from:Hide()
    to:Show()
    if onDone then
      onDone()
    end
    return
  end
  local width = parent:GetWidth()
  saveAnchors(to)
  placeAnchors(to, direction * width)
  local fromGroup = startGroup(from, -direction * width)
  local toGroup = startGroup(to, -direction * width)
  parent:SetClipsChildren(true)
  if not hookedParents[parent] then
    hookedParents[parent] = true
    parent:HookScript("OnHide", onParentHide)
  end
  state.from, state.to, state.parent, state.onDone = from, to, parent, onDone
  to:Show()
  from:Show()
  fromGroup:Play()
  toGroup:Play()
end

ns.ScreenSlide = ScreenSlide
return ScreenSlide
