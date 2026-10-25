local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")

-- The one skinned scroll bar (UI/ScrollBar.lua): WhisperMessenger's retail bar (RetailSkin.lua)
-- when the client has the minimal-scrollbar atlases, else the gold knob; hidden until Set gives it
-- a range; a drag reports the value, Set does not.

local ATLAS_WIDTH = 7

-- A fresh ScrollBar; `atlasWidth` nil → no C_Texture (no atlases). → ScrollBar
local function load(atlasWidth)
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  if atlasWidth then
    Wow.stub("C_Texture", {
      GetAtlasInfo = function()
        return { width = atlasWidth, height = 1 }
      end,
    })
  else
    Wow.stub("C_Texture", nil)
  end
  return Fresh.require("UI.ScrollBar")
end

local function newBar(atlasWidth, onScroll)
  local ScrollBar = load(atlasWidth)
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  return ScrollBar.New(parent, onScroll or function() end), ScrollBar, parent
end

local function atlases(slices)
  return { slices.top.atlas, slices.middle.atlas, slices.bottom.atlas }
end

local function testRetailSkin()
  local bar, _, parent = newBar(ATLAS_WIDTH)
  Assert.equal(bar.frameType, "Slider")
  Assert.equal(bar.parent, parent)
  Assert.equal(bar.orientation, "VERTICAL")
  Assert.equal(bar.mouseEnabled, true, "the thumb can be dragged")
  Assert.equal(bar:GetWidth(), ATLAS_WIDTH, "as wide as the thumb atlas")
  Assert.same(atlases(bar.track), { "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom" })
  Assert.same(atlases(bar.pieces), { "minimal-scrollbar-thumb-top", "minimal-scrollbar-thumb-middle", "minimal-scrollbar-thumb-bottom" })
  Assert.equal(bar.track.top.layer, "BACKGROUND")
  Assert.equal(bar.pieces.top.layer, "ARTWORK")
  local carrier = bar.thumb
  Assert.equal(carrier:GetAlpha(), 0, "the slider moves an invisible carrier")
  Assert.same({ carrier:GetWidth(), carrier:GetHeight() }, { ATLAS_WIDTH, 32 })
  Assert.same(bar.pieces.top.points[1], { "TOP", carrier, "TOP", 0, 0 }, "the pieces ride on the carrier")
  Assert.same(bar.pieces.bottom.points[1], { "BOTTOM", carrier, "BOTTOM", 0, 0 })
  Assert.same(bar.track.top.points[1], { "TOP", bar, "TOP", 0, 0 }, "the track spans the bar")
  Assert.same(bar.track.bottom.points[1], { "BOTTOM", bar, "BOTTOM", 0, 0 })
  Widgets.fire(bar, "OnEnter")
  Assert.same(
    atlases(bar.pieces),
    { "minimal-scrollbar-thumb-top-over", "minimal-scrollbar-thumb-middle-over", "minimal-scrollbar-thumb-bottom-over" }
  )
  Widgets.fire(bar, "OnLeave")
  Assert.same(atlases(bar.pieces), { "minimal-scrollbar-thumb-top", "minimal-scrollbar-thumb-middle", "minimal-scrollbar-thumb-bottom" })
  Assert.equal(bar:IsShown(), false, "hidden until it has a range")
end

-- An atlas the client reports without a width: WM's retail width, 8.
local function testRetailWidthFallback()
  local ScrollBar = load(ATLAS_WIDTH)
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      return {}
    end,
  })
  Assert.equal(ScrollBar.New(_G["CreateFrame"]("Frame"), function() end):GetWidth(), 8)
end

local function testKnobWithoutAtlas()
  local bar = newBar(nil)
  Assert.equal(bar.thumb.texture, "Interface\\Buttons\\UI-ScrollBar-Knob", "the gold knob")
  Assert.same(bar.thumb.texCoord, { 0.20, 0.80, 0.125, 0.875 })
  Assert.equal(bar:GetWidth(), 12)
  Assert.equal(bar.thumb:GetWidth(), 12)
  Assert.equal(bar.track, nil, "no trough")
end

local function testSet()
  local calls = {}
  local bar, ScrollBar = newBar(ATLAS_WIDTH, function(value)
    calls[#calls + 1] = value
  end)
  local function piecesShown()
    return { bar.pieces.top:IsShown(), bar.pieces.middle:IsShown(), bar.pieces.bottom:IsShown() }
  end
  ScrollBar.Set(bar, 0, 0, 1)
  Assert.equal(bar:IsShown(), false, "no range: no bar")
  Assert.same(piecesShown(), { false, false, false }, "nor its thumb")
  ScrollBar.Set(bar, 3, 0, 1)
  Assert.equal(bar:IsShown(), true)
  Assert.same(piecesShown(), { true, true, true })
  Assert.same({ bar:GetMinMaxValues() }, { 0, 3 })
  ScrollBar.Set(bar, 100, 150, 24)
  Assert.equal(bar:IsShown(), true)
  Assert.equal(bar:GetValue(), 100, "clamped into the range")
  Assert.equal(bar:GetValueStep(), 24)
  Assert.same(calls, {}, "Set does not report a scroll")
  bar:SetValue(40)
  Assert.same(calls, { 40 }, "a drag reports its value once")
  ScrollBar.Set(bar, 0, 40, 24)
  Assert.equal(bar:GetValue(), 0)
  Assert.equal(bar:IsShown(), false)
  Assert.same(calls, { 40 })
end

-- The knob shows and hides with the bar too.
local function testSetKnob()
  local bar, ScrollBar = newBar(nil)
  ScrollBar.Set(bar, 5, 0, 1)
  Assert.equal(bar.thumb:IsShown(), true)
  ScrollBar.Set(bar, 0, 0, 1)
  Assert.equal(bar.thumb:IsShown(), false)
end

return function()
  testRetailSkin()
  testRetailWidthFallback()
  testKnobWithoutAtlas()
  testSet()
  testSetKnob()
  Wow.reset()
end
