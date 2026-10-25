local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
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

return function()
  testRoundIcon()
  testDot()
  testOverlays()
  testHover()
  Wow.reset()
end
