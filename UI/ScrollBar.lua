local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- The one scroll bar every scroller shows: a vertical Slider dressed as WhisperMessenger's retail
-- bar (UI/ScrollView/RetailSkin.lua), the professions recipe list's minimal scrollbar: a slim
-- three-slice track and a three-piece thumb riding on an invisible carrier, the hover atlases while
-- the pointer is on it. A client without those atlases gets UIPanelScrollBarTemplate's gold knob
-- (WM's HUD bar). Hidden until Set gives it a range; a drag calls onScroll(value), Set does not.
-- Where it sits is the caller's.
local ScrollBar = {}

local max = math.max
local min = math.min

-- The slider moves one thumb texture: the invisible carrier, a fixed height as in WM.
local THUMB_HEIGHT = 32
local PARTS = { "top", "middle", "bottom" }
-- The track's middle is a tiling atlas, hence the leading "!".
local TRACK = {
  top = "minimal-scrollbar-track-top",
  middle = "!minimal-scrollbar-track-middle",
  bottom = "minimal-scrollbar-track-bottom",
}
local THUMB = {
  top = "minimal-scrollbar-thumb-top",
  middle = "minimal-scrollbar-thumb-middle",
  bottom = "minimal-scrollbar-thumb-bottom",
}
local THUMB_OVER = {
  top = "minimal-scrollbar-thumb-top-over",
  middle = "minimal-scrollbar-thumb-middle-over",
  bottom = "minimal-scrollbar-thumb-bottom-over",
}
-- WM's SCROLLBAR_WIDTH_RETAIL, for a client that reports the thumb atlas without a width.
local RETAIL_WIDTH = 8
-- The knob, cropped of its padding and scaled whole from 18x24, with no trough; WM's
-- SCROLLBAR_WIDTH_HUD wide.
local KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"
local KNOB_WIDTH = 12
local KNOB_ASPECT = 24 / 18
local KNOB_COORDS = { 0.20, 0.80, 0.125, 0.875 }

-- The thumb atlas's own width; asked only once AtlasExists has seen the client answer.
local function retailWidth()
  local info = _G["C_Texture"].GetAtlasInfo(THUMB.top)
  if type(info.width) == "number" and info.width > 0 then
    return info.width
  end
  return RETAIL_WIDTH
end

-- Caps on the ends of `anchor`, the middle stretched between them.
local function threeSlice(slices, anchor)
  slices.top:SetPoint("TOP", anchor, "TOP", 0, 0)
  slices.bottom:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
  slices.middle:SetPoint("TOPLEFT", slices.top, "BOTTOMLEFT", 0, 0)
  slices.middle:SetPoint("BOTTOMRIGHT", slices.bottom, "TOPRIGHT", 0, 0)
end

-- The caps at their atlas size, the middle stretched.
local function paint(slices, atlases)
  for _, part in ipairs(PARTS) do
    slices[part]:SetAtlas(atlases[part], part ~= "middle")
  end
end

local function createSlices(bar, layer, atlases, anchor)
  local slices = {}
  for _, part in ipairs(PARTS) do
    slices[part] = bar:CreateTexture(nil, layer)
  end
  paint(slices, atlases)
  threeSlice(slices, anchor)
  return slices
end

-- RetailSkin.Apply: the track over the bar, the pieces on the carrier, the hover swap.
local function skinRetail(bar, carrier, width)
  bar.track = createSlices(bar, "BACKGROUND", TRACK, bar)
  carrier:SetSize(width, THUMB_HEIGHT)
  carrier:SetAlpha(0)
  bar.pieces = createSlices(bar, "ARTWORK", THUMB, carrier)
  bar:SetScript("OnEnter", function()
    paint(bar.pieces, THUMB_OVER)
  end)
  bar:SetScript("OnLeave", function()
    paint(bar.pieces, THUMB)
  end)
end

local function skinKnob(bar, knob)
  knob:SetTexture(KNOB)
  knob:SetTexCoord(KNOB_COORDS[1], KNOB_COORDS[2], KNOB_COORDS[3], KNOB_COORDS[4])
  knob:SetSize(KNOB_WIDTH, KNOB_WIDTH * KNOB_ASPECT)
  bar.pieces = { knob = knob }
end

-- A hidden bar on `parent`, range 0, as wide as its skin. → bar; bar.pieces are the thumb's
-- visible textures, bar.track the retail track's slices (nil for the knob).
function ScrollBar.New(parent, onScroll)
  local bar = _G["CreateFrame"]("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetObeyStepOnDrag(true)
  -- Dragged by the thumb: Blizzard's own sliders set enableMouse (MinimalSlider.xml).
  bar:EnableMouse(true)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  local width = KNOB_WIDTH
  if FrameKit.AtlasExists(THUMB.top) then
    width = retailWidth()
    skinRetail(bar, thumb, width)
  else
    skinKnob(bar, thumb)
  end
  bar:SetWidth(width)
  bar:SetThumbTexture(thumb)
  bar.setting = false
  bar:SetScript("OnValueChanged", function(_, value)
    if not bar.setting then
      onScroll(value)
    end
  end)
  bar:Hide()
  return bar
end

-- Range 0..`range` in steps of `step`, the value clamped into it, without calling onScroll. The
-- bar and its thumb show only while there is a range: as WM's Navigation.Sync, the thumb is hidden
-- too, as its texture showed through the bar's hide.
function ScrollBar.Set(bar, range, value, step)
  bar.setting = true
  bar:SetMinMaxValues(0, range)
  bar:SetValueStep(step)
  bar:SetValue(max(0, min(value, range)))
  bar.setting = false
  local shown = range > 0
  bar:SetShown(shown)
  for _, piece in pairs(bar.pieces) do
    piece:SetShown(shown)
  end
end

ns.ScrollBar = ScrollBar
return ScrollBar
