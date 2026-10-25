local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- Spec D1, D3, D5, D10: the art the lead rows and the details header share, as WhisperMessenger
-- draws it. The round icon (UI/Helpers/Shapes.lua:184-211, WM), the status dot
-- (UI/ContactsList/StatusDot.lua:43-59), and a row's selected and hover overlays on BACKGROUND
-- sublayer 1 (UI/ContactsList/RowHoverOverlay.lua:22-27), the hover fading in and out over 0.1 s
-- (UI/Helpers/HoverFade.lua:17-91).
local RowArt = {}

local type = type

-- The texture outgrows its holder so the mask's soft edge falls outside the clip.
local ICON_ZOOM = 1.15
local DOT_SIZE = 10
local DOT_OFFSET = 2
local FADE_SECONDS = 0.1

-- A `size` frame clipping a round, zoomed icon texture (holder.texture). A client without
-- Texture:SetMask gets the plain square texture at `size`.
function RowArt.RoundIcon(parent, size)
  local holder = _G["CreateFrame"]("Frame", nil, parent)
  holder:SetSize(size, size)
  holder:SetClipsChildren(true)
  local texture = holder:CreateTexture(nil, "ARTWORK")
  texture:SetPoint("CENTER", holder, "CENTER", 0, 0)
  if type(texture.SetMask) == "function" then
    texture:SetMask(Theme.ART.CIRCLE_MASK)
    texture:SetSize(size * ICON_ZOOM, size * ICON_ZOOM)
  else
    texture:SetSize(size, size)
  end
  holder.texture = texture

  return holder
end

-- A round dot on the bottom-right corner of the `anchor` frame, above it; hidden until painted.
function RowArt.Dot(parent, anchor)
  local dot = _G["CreateFrame"]("Frame", nil, parent)
  dot:SetSize(DOT_SIZE, DOT_SIZE)
  dot:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", DOT_OFFSET, -DOT_OFFSET)
  dot:SetFrameLevel(anchor:GetFrameLevel() + 2)
  local texture = dot:CreateTexture(nil, "OVERLAY")
  texture:SetAllPoints(dot)
  texture:SetTexture(Theme.ART.CIRCLE_MASK)
  dot.texture = texture
  dot:Hide()

  return dot
end

-- Shows the dot in `color`; nil hides it.
function RowArt.PaintDot(dot, color)
  if not color then
    dot:Hide()

    return
  end
  dot.texture:SetVertexColor(color[1], color[2], color[3], color[4])
  dot:Show()
end

local function overlay(row, path)
  local texture = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  texture:SetAllPoints(row)
  texture:SetTexture(path)
  texture:SetBlendMode("ADD")
  texture:Hide()

  return texture
end

-- One 0.1 s Alpha fade of `hover` from `from` to `to`; on finishing it settles there, hidden at 0.
local function fade(hover, from, to)
  local group = hover:CreateAnimationGroup()
  local alpha = group:CreateAnimation("Alpha")
  alpha:SetDuration(FADE_SECONDS)
  alpha:SetFromAlpha(from)
  alpha:SetToAlpha(to)
  group:SetToFinalAlpha(true)
  group:SetScript("OnFinished", function()
    hover:SetAlpha(to)
    hover:SetShown(to > 0)
  end)

  return group
end

-- The row's hover and selected overlays, both hidden. The selected one is tinted; the hover one
-- carries its fades as hover.fadeIn and hover.fadeOut (RowArt.Hover plays them).
function RowArt.Overlays(row)
  local art = Theme.ART
  local tint = Theme.COLORS.selectedTint
  local selected = overlay(row, art.LIST_SELECTED)
  selected:SetVertexColor(tint[1], tint[2], tint[3])
  selected:SetAlpha(art.LIST_SELECTED_ALPHA)
  local hover = overlay(row, art.LIST_HOVER)
  hover:SetAlpha(0)
  hover.fadeIn = fade(hover, 0, art.LIST_HOVER_ALPHA)
  hover.fadeOut = fade(hover, art.LIST_HOVER_ALPHA, 0)

  return hover, selected
end

-- Fades the hover overlay in (`on`) or out; `instant` sets the end state at once. The other fade
-- stops first: a fade-out still running would hide the hover when it finished.
function RowArt.Hover(hover, on, instant)
  local play, other = hover.fadeIn, hover.fadeOut
  if not on then
    play, other = other, play
  end
  other:Stop()
  if instant then
    play:Stop()
    hover:SetAlpha(on and Theme.ART.LIST_HOVER_ALPHA or 0)
    hover:SetShown(on)
  elseif on or hover:IsShown() then
    hover:Show()
    play:Play()
  end
end

ns.RowArt = RowArt
return RowArt
