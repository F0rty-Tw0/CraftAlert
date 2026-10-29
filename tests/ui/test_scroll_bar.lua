local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local PainterLooks = require("tests.helpers.painter_looks")

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

local COLORS = PainterLooks.COLORS
local KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"
local THUMB_ATLASES = { "minimal-scrollbar-thumb-top", "minimal-scrollbar-thumb-middle", "minimal-scrollbar-thumb-bottom" }
local OVER_ATLASES = { "minimal-scrollbar-thumb-top-over", "minimal-scrollbar-thumb-middle-over", "minimal-scrollbar-thumb-bottom-over" }
local ALL, NONE = { true, true, true }, { false, false, false }

local function shown(slices)
  return { slices.top:IsShown(), slices.middle:IsShown(), slices.bottom:IsShown() }
end

-- Spec "Looks", native and retail on a client with the atlases: today's retail bar.
local function assertRetail(bar, retailPieces, label)
  local carrier = bar.carrier
  Assert.same({ carrier:GetAlpha(), carrier:GetWidth(), carrier:GetHeight(), carrier:IsShown() }, { 0, ATLAS_WIDTH, 32, true }, label .. ": carrier")
  Assert.same(shown(bar.track), ALL, label .. ": track shown")
  Assert.equal(bar.pieces, retailPieces, label .. ": pieces are the retail slices")
  local on = bar:IsShown()
  Assert.same(shown(bar.pieces), { on, on, on }, label .. ": pieces follow the bar")
  Assert.same(atlases(bar.pieces), THUMB_ATLASES, label .. ": thumb atlases")
  Widgets.fire(bar, "OnEnter")
  Assert.same(atlases(bar.pieces), OVER_ATLASES, label .. ": hover atlases")
  Widgets.fire(bar, "OnLeave")
  Assert.same(atlases(bar.pieces), THUMB_ATLASES, label .. ": left")
end

-- Spec "Looks", classic (and native/retail without the atlases): the gold knob, no hover swap.
local function assertKnob(bar, label)
  local knob = bar.carrier
  Assert.same(
    { knob.texture, knob.texCoord, knob:GetAlpha(), knob:GetWidth(), knob:GetHeight() },
    { KNOB, { 0.20, 0.80, 0.125, 0.875 }, 1, 12, 12 * (24 / 18) },
    label .. ": knob (12 px wide, the 18 x 24 art scaled whole)"
  )
  Assert.same({ bar.scripts.OnEnter, bar.scripts.OnLeave }, {}, label .. ": no hover scripts")
end

-- Spec "Looks", flat: thumb `scrollbar` 4 px wide, `scrollbar_hover` at 6 px while hovered.
local function assertFlat(bar, label)
  local thumb = bar.carrier
  Assert.same({ thumb.color, thumb:GetAlpha(), thumb:GetWidth(), thumb:GetHeight() }, { COLORS.scrollbar, 1, 4, 32 }, label .. ": thumb")
  Widgets.fire(bar, "OnEnter")
  Assert.same({ thumb.color, thumb:GetWidth() }, { COLORS.scrollbar_hover, 6 }, label .. ": hovered")
  Widgets.fire(bar, "OnLeave")
  Assert.same({ thumb.color, thumb:GetWidth() }, { COLORS.scrollbar, 4 }, label .. ": left")
end

local function testApplyLookOnRetailBar()
  local bar, ScrollBar = newBar(ATLAS_WIDTH)
  ScrollBar.Set(bar, 5, 0, 1)
  local retailPieces = bar.pieces
  local function apply(mode)
    ScrollBar.ApplyLook(bar, PainterLooks.look(mode))
    Assert.equal(bar:GetWidth(), ATLAS_WIDTH, mode .. ": the bar keeps its width")
  end
  assertRetail(bar, retailPieces, "new bar")
  apply("native")
  assertRetail(bar, retailPieces, "native")
  apply("flat")
  Assert.same(shown(bar.track), NONE, "flat: track hidden")
  Assert.same(shown(retailPieces), NONE, "flat: retail pieces hidden")
  assertFlat(bar, "flat")
  -- Set moves only what bar.pieces holds: the flat thumb, never the hidden retail slices.
  ScrollBar.Set(bar, 0, 0, 1)
  Assert.same({ bar.carrier:IsShown(), shown(retailPieces) }, { false, NONE }, "flat, no range")
  ScrollBar.Set(bar, 5, 0, 1)
  Assert.same({ bar.carrier:IsShown(), shown(retailPieces) }, { true, NONE }, "flat, with range")
  apply("classic")
  assertKnob(bar, "classic")
  Assert.same({ shown(bar.track), shown(retailPieces) }, { NONE, NONE }, "classic: retail parts hidden")
  apply("flat")
  apply("flat")
  assertFlat(bar, "flat twice")
  apply("native")
  assertRetail(bar, retailPieces, "native after flat")
  apply("retail")
  assertRetail(bar, retailPieces, "retail")
  -- No range: the bar is hidden, so the restored retail pieces stay hidden until Set.
  ScrollBar.Set(bar, 0, 0, 1)
  apply("flat")
  apply("native")
  Assert.same(shown(bar.pieces), NONE, "native on a bar without range")
end

local function testApplyLookOnKnobBar()
  local bar, ScrollBar = newBar(nil)
  local function apply(mode)
    ScrollBar.ApplyLook(bar, PainterLooks.look(mode))
    Assert.equal(bar:GetWidth(), 12, mode .. ": the bar keeps its width")
  end
  assertKnob(bar, "new bar")
  apply("retail")
  assertKnob(bar, "retail without atlases")
  apply("flat")
  assertFlat(bar, "flat")
  apply("native")
  assertKnob(bar, "native after flat")
  Assert.equal(bar.track, nil, "no trough, ever")
  apply("classic")
  assertKnob(bar, "classic")
  ScrollBar.Set(bar, 5, 0, 1)
  apply("flat")
  Assert.equal(bar.carrier:IsShown(), true, "flat thumb shows with the bar's range")
end

return function()
  testRetailSkin()
  testRetailWidthFallback()
  testKnobWithoutAtlas()
  testSet()
  testSetKnob()
  testApplyLookOnRetailBar()
  testApplyLookOnKnobBar()
  Wow.reset()
end
