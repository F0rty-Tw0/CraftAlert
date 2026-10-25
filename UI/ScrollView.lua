local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local ScrollBar = ns.ScrollBar or require("CraftAlert.UI.ScrollBar")

-- A scrolling area, in the order and calls of WhisperMessenger's scroll view (UI/ScrollView/
-- Factory.lua, Navigation.lua, Metrics.lua): a plain ScrollFrame with its own size, clipping; the
-- content anchored TOPLEFT and sized before it becomes the scroll child; the wheel scrolls by STEP;
-- the ScrollBar (UI/ScrollBar.lua) mirrors the offset both ways and shows, and the frame takes the
-- wheel, only while the content is taller than the frame. The view fills a box, the bar at its
-- right and its width always kept free, so the content's width never depends on its own overflow.
-- Each resize or show of the box sets the frame's size, the content's width and the range again
-- (WM's Navigation.Sync). UIPanelScrollFrameTemplate on two anchors and no size left most rows
-- without a rect in game (2026-10-25).
local ScrollView = {}

local max = math.max
local min = math.min

local STEP = 24
-- WM's MICRO_OVERFLOW_TOLERANCE: a few px over is rounding, not a page to scroll.
local OVERFLOW_TOLERANCE = 5

-- The frame's size in the box: its width less the bar's, all its height. Before its first layout
-- the box may read 0 wide; CONTROL_WIDTH then, so a page's rows are built at a real width.
local function sizeIn(box, bar)
  local width = box:GetWidth() - bar:GetWidth()
  if width <= 0 then
    width = Theme.LAYOUT.CONTROL_WIDTH
  end
  return width, box:GetHeight()
end

local function rangeOf(view)
  local overflow = view.content:GetHeight() - view.frame:GetHeight()
  if overflow <= OVERFLOW_TOLERANCE then
    return 0
  end
  return overflow
end

-- The offset, clamped to the range, on the frame and on the bar; the bar shows and the frame takes
-- the wheel on overflow only.
function ScrollView.ScrollTo(view, offset)
  local range = rangeOf(view)
  local clamped = max(0, min(offset, range))
  view.frame:SetVerticalScroll(clamped)
  ScrollBar.Set(view.bar, range, clamped, STEP)
  view.frame:EnableMouseWheel(range > 0)
end

local function sync(view)
  ScrollView.ScrollTo(view, view.frame:GetVerticalScroll())
end

local function resize(view)
  local width, height = sizeIn(view.box, view.bar)
  view.frame:SetSize(width, height)
  view.content:SetWidth(width)
  view.bar:SetHeight(height)
  view.frame:UpdateScrollChildRect()
  sync(view)
end

-- Fills `box`: the frame at its top left, the bar at its top right. `content` (optional) is what
-- scrolls: a frame with its height set, which the view moves into the frame and owns the width
-- of; without one the view makes a plain Frame. → { box, frame, content, bar }; a page draws on
-- view.content, whose SetHeight re-syncs.
function ScrollView.Create(box, content)
  local frame = _G["CreateFrame"]("ScrollFrame", nil, box)
  local view = { box = box, frame = frame }
  view.bar = ScrollBar.New(box, function(value)
    ScrollView.ScrollTo(view, value)
  end)
  view.bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  local width, height = sizeIn(box, view.bar)
  frame:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  frame:SetSize(width, height)
  frame:SetClipsChildren(true)
  if content then
    content:SetParent(frame)
    content:ClearAllPoints()
  else
    content = _G["CreateFrame"]("Frame", nil, frame)
    content:SetHeight(height)
  end
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  content:SetWidth(width)
  frame:SetScrollChild(content)
  view.content = content
  frame:SetScript("OnMouseWheel", function(_, delta)
    ScrollView.ScrollTo(view, frame:GetVerticalScroll() - delta * STEP)
  end)
  _G["hooksecurefunc"](content, "SetHeight", function()
    sync(view)
  end)
  box:HookScript("OnSizeChanged", function()
    resize(view)
  end)
  box:HookScript("OnShow", function()
    resize(view)
  end)
  resize(view)
  return view
end

ns.ScrollView = ScrollView
return ScrollView
