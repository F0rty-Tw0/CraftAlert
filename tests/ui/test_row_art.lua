local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local PainterLooks = require("tests.helpers.painter_looks")
require("tests.helpers.widgets")

-- Spec D1, D3, D5, D10: the art the lead rows and the details header share, as WhisperMessenger
-- draws it (UI/Helpers/Shapes.lua, HoverFade.lua, UI/ContactsList/StatusDot.lua, WM): the round
-- icon, the status dot, and the selected and hover overlays with the hover's fade.

local ICON_SIZE = 34

-- A fresh RowArt over the fake client. `noMask` → textures without SetMask. → RowArt, Theme, a parent
local function load(noMask)
  Wow.reset()
  local Theme = Fresh.require("UI.Theme")
  if noMask then
    local createFrame = _G["CreateFrame"]
    Wow.stub("CreateFrame", function(...)
      local frame = createFrame(...)
      local createTexture = frame.CreateTexture
      function frame:CreateTexture(...)
        local texture = createTexture(self, ...)
        texture.SetMask = nil
        return texture
      end
      return frame
    end)
  end
  local RowArt = Fresh.require("UI.RowArt")
  return RowArt, Theme, _G["CreateFrame"]("Frame")
end

-- The arguments of the animation's last `method` call, or nil.
local function lastCall(animation, method)
  local found
  for _, call in ipairs(animation.calls) do
    if call[1] == method then
      found = { unpack(call, 2) }
    end
  end
  return found
end

local function testRoundIcon()
  local RowArt, Theme, parent = load()
  local holder = RowArt.RoundIcon(parent, ICON_SIZE)
  local texture = holder.texture
  Assert.same({ holder.width, holder.height, holder.clipsChildren }, { ICON_SIZE, ICON_SIZE, true })
  Assert.same({ texture.layer, texture.mask }, { "ARTWORK", Theme.ART.CIRCLE_MASK })
  Assert.same({ texture.width, texture.height }, { ICON_SIZE * 1.15, ICON_SIZE * 1.15 }, "zoomed past the mask's soft edge")
  Assert.same(texture.points[1], { "CENTER", holder, "CENTER", 0, 0 })

  RowArt, _, parent = load(true)
  texture = RowArt.RoundIcon(parent, ICON_SIZE).texture
  Assert.equal(texture.mask, nil)
  Assert.same({ texture.width, texture.height }, { ICON_SIZE, ICON_SIZE }, "without SetMask, today's square")
end

local function testDot()
  local RowArt, Theme, parent = load()
  local anchor = _G["CreateFrame"]("Frame", nil, parent)
  anchor:SetFrameLevel(5)
  local dot = RowArt.Dot(parent, anchor)
  Assert.same({ dot.width, dot.height }, { 10, 10 })
  Assert.same(dot.points[1], { "BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2 })
  Assert.equal(dot:GetFrameLevel(), 7)
  Assert.same({ dot.texture.layer, dot.texture.texture }, { "OVERLAY", Theme.ART.CIRCLE_MASK })

  RowArt.PaintDot(dot, { 1, 0.82, 0, 1 })
  Assert.equal(dot:IsShown(), true)
  Assert.same(dot.texture.vertexColor, { 1, 0.82, 0, 1 })
  RowArt.PaintDot(dot, nil)
  Assert.equal(dot:IsShown(), false)
end

local function testOverlays()
  local RowArt, Theme, row = load()
  local hover, selected = RowArt.Overlays(row)
  for _, texture in ipairs({ hover, selected }) do
    Assert.same({ texture.layer, texture.sublevel, texture.blendMode, texture.shown }, { "BACKGROUND", 1, "ADD", false })
  end
  Assert.same({ selected.texture, selected.vertexColor, selected.alpha }, { Theme.ART.LIST_SELECTED, { 1, 0.82, 0 }, 0.45 })
  Assert.same({ hover.texture, hover.alpha }, { Theme.ART.LIST_HOVER, 0 })
end

local function testHover()
  local RowArt, _, row = load()
  local hover = RowArt.Overlays(row)
  local fadeIn, fadeOut = hover.fadeIn, hover.fadeOut

  RowArt.Hover(hover, false)
  Assert.same({ hover.shown, fadeOut:IsPlaying() }, { false, false }, "off while hidden does nothing")

  RowArt.Hover(hover, true)
  local alpha = fadeIn.animations[1]
  Assert.same({ hover.shown, fadeIn:IsPlaying(), alpha.kind }, { true, true, "Alpha" })
  Assert.same({ lastCall(alpha, "SetDuration"), lastCall(alpha, "SetFromAlpha"), lastCall(alpha, "SetToAlpha") }, { { 0.1 }, { 0 }, { 0.18 } })
  fadeIn:Finish()
  Assert.equal(hover.alpha, 0.18)

  RowArt.Hover(hover, false)
  alpha = fadeOut.animations[1]
  Assert.same({ lastCall(alpha, "SetDuration"), lastCall(alpha, "SetFromAlpha"), lastCall(alpha, "SetToAlpha") }, { { 0.1 }, { 0.18 }, { 0 } })
  fadeOut:Finish()
  Assert.same({ hover.shown, hover.alpha }, { false, 0 })

  -- A quick re-enter stops the fade-out, whose OnFinished would hide the hover.
  RowArt.Hover(hover, true)
  RowArt.Hover(hover, false)
  RowArt.Hover(hover, true)
  Assert.equal(fadeOut:IsPlaying(), false)
  fadeIn:Finish()
  Assert.same({ hover.shown, hover.alpha }, { true, 0.18 })

  RowArt.Hover(hover, false, true)
  Assert.same({ hover.shown, hover.alpha, fadeIn:IsPlaying(), fadeOut:IsPlaying() }, { false, 0, false, false }, "instant: no fade")
  RowArt.Hover(hover, true, true)
  Assert.same({ hover.shown, hover.alpha, fadeIn:IsPlaying(), fadeOut:IsPlaying() }, { true, 0.18, false, false })
end

local PEAK = { native = 0.18, retail = 0.18, classic = 0.18, flat = 1 }

local function testApplyLookOverlays()
  local RowArt, Theme, row = load()
  local want = PainterLooks.overlays(Theme, Theme.COLORS.selectedTint)
  local hover, selected = RowArt.Overlays(row)
  for _, mode in ipairs(PainterLooks.SEQUENCE) do
    RowArt.ApplyLook(hover, selected, PainterLooks.look(mode), Theme.COLORS.selectedTint)
    PainterLooks.checkOverlay(selected, want.selected[mode], mode .. " selected")
    Assert.equal(selected.alpha, want.selected[mode].alpha, mode .. " selected alpha")
    PainterLooks.checkOverlay(hover, want.hover[mode], mode .. " hover")
    Assert.same({ selected.shown, hover.shown, hover.alpha }, { false, false, 0 }, mode .. ": shown flags and the hidden hover's alpha untouched")
    RowArt.Hover(hover, true, true)
    Assert.equal(hover.alpha, want.hover[mode].alpha, mode .. " hover alpha once shown")
    RowArt.Hover(hover, false, true)
  end
end

-- Every fade value follows the look: fade-in to the peak, fade-out from it, OnFinished and the instant alpha.
local function testHoverFadesPerLook()
  local RowArt, Theme, row = load()
  local hover, selected = RowArt.Overlays(row)
  for _, mode in ipairs(PainterLooks.SEQUENCE) do
    local peak = PEAK[mode]
    RowArt.ApplyLook(hover, selected, PainterLooks.look(mode), Theme.COLORS.selectedTint)
    RowArt.Hover(hover, true)
    local grow = hover.fadeIn.animations[1]
    Assert.same({ lastCall(grow, "SetFromAlpha"), lastCall(grow, "SetToAlpha") }, { { 0 }, { peak } }, mode .. " fade-in")
    hover.fadeIn:Finish()
    Assert.equal(hover.alpha, peak, mode .. ": fade-in settles at the peak")
    RowArt.Hover(hover, false)
    local shrink = hover.fadeOut.animations[1]
    Assert.same({ lastCall(shrink, "SetFromAlpha"), lastCall(shrink, "SetToAlpha") }, { { peak }, { 0 } }, mode .. " fade-out")
    hover.fadeOut:Finish()
    Assert.same({ hover.shown, hover.alpha }, { false, 0 }, mode .. ": fade-out hides")
    RowArt.Hover(hover, true, true)
    Assert.equal(hover.alpha, peak, mode .. ": instant")
    RowArt.Hover(hover, false, true)
  end
end

-- Review Focus 3: the look flips while a fade runs; alpha never stays at 0.18 under flat.
local function testLookFlipDuringFade()
  local RowArt, Theme, row = load()
  local hover, selected = RowArt.Overlays(row)
  local flat, native, tint = PainterLooks.look("flat"), PainterLooks.look("native"), Theme.COLORS.selectedTint
  RowArt.Hover(hover, true)
  RowArt.ApplyLook(hover, selected, flat, tint)
  Assert.same({ hover.fadeIn:IsPlaying(), hover.shown, hover.alpha }, { false, true, 1 }, "fade-in running at the flip to flat")
  RowArt.ApplyLook(hover, selected, native, tint)
  Assert.same({ hover.shown, hover.alpha }, { true, 0.18 }, "a shown hover follows native back to 0.18")
  RowArt.Hover(hover, false)
  Assert.equal(hover.fadeOut:IsPlaying(), true)
  RowArt.ApplyLook(hover, selected, flat, tint)
  Assert.same({ hover.fadeOut:IsPlaying(), hover.shown, hover.alpha }, { false, false, 0 }, "fade-out running at the flip ends hidden")
  RowArt.Hover(hover, true)
  hover.fadeIn:Finish()
  Assert.equal(hover.alpha, 1, "a fade finishing after the flip lands on the new peak")
end

return function()
  testRoundIcon()
  testDot()
  testOverlays()
  testHover()
  testApplyLookOverlays()
  testHoverFadesPerLook()
  testLookFlipDuringFade()
  Wow.reset()
end
