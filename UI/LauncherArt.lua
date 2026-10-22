local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Spec §5.1–5.2: the launcher's CraftScan look (../CraftScan/Customer/AlertIcon.xml). A
-- Soulbinds ring as the button's normal, pushed and highlight art; a round-masked portrait
-- inside it; a ring glow while the cursor is over it; a circle glow that pulses for a new lead.
-- Without the atlases (Classic) the ring falls back to the minimap tracking border, and the
-- glow and pulse do not exist.
local LauncherArt = {}

local RING_NORMAL_ATLAS = "Soulbinds_Tree_Ring_Disabled"
local RING_NORMAL_FILE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local RING_LIT_ATLAS = "Soulbinds_Tree_Ring"
local RING_HIGHLIGHT_FILE = "Interface\\Buttons\\UI-Common-MouseHilight"
local GLOW_ATLAS = "Soulbinds_Tree_Ring_Glow"
local PULSE_ATLAS = "GarrLanding-CircleGlow"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MASK_WRAP = "CLAMPTOBLACKADDITIVE"
local ADD = "ADD"
local GLOW_SIZE = 54
local PORTRAIT_Y = -2
local MASK_INSET = { left = 2, right = -2, bottom = 4 }

-- Alpha 0→1, then 1→0 after a delay, while the glow scales up (CraftScan MinimapPulseAnim and
-- MinimapLoopPulseAnim).
local PULSE_ONCE = { fadeIn = 0.1, fadeOut = 0.5, fadeOutDelay = 0.1, scaleTo = 1.75, scaleDuration = 0.25 }
local PULSE_LOOP = { fadeIn = 0.5, fadeOut = 1, fadeOutDelay = 0.5, scaleTo = 1.1, scaleDuration = 0.75 }
local PULSE_SCALE_FROM = 0.75

local function centered(texture, frame, size)
  texture:ClearAllPoints()
  texture:SetSize(size, size)
  texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
end

-- A Button may stretch a state texture over itself, so each ring is re-anchored after hand-over.
local function buildRings(frame)
  local size = Theme.LAYOUT.RING_SIZE
  local normal = frame:CreateTexture(nil, "ARTWORK")
  FrameKit.Art(normal, RING_NORMAL_ATLAS, RING_NORMAL_FILE)
  frame:SetNormalTexture(normal)
  local pushed = frame:CreateTexture(nil, "ARTWORK")
  FrameKit.Art(pushed, RING_LIT_ATLAS)
  frame:SetPushedTexture(pushed)
  local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
  FrameKit.Art(highlight, RING_LIT_ATLAS, RING_HIGHLIGHT_FILE, ADD)
  frame:SetHighlightTexture(highlight, ADD)
  centered(normal, frame, size)
  centered(pushed, frame, size)
  centered(highlight, frame, size)
end

local function buildPortrait(frame)
  local size = Theme.LAYOUT.PORTRAIT_SIZE
  local portrait = frame:CreateTexture(nil, "BORDER")
  portrait:SetSize(size, size)
  portrait:SetPoint("CENTER", frame, "CENTER", 0, PORTRAIT_Y)
  local mask = frame:CreateMaskTexture()
  mask:SetTexture(PORTRAIT_MASK, MASK_WRAP, MASK_WRAP)
  mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", MASK_INSET.left, 0)
  mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", MASK_INSET.right, MASK_INSET.bottom)
  portrait:AddMaskTexture(mask)

  return portrait
end

local function buildGlow(frame)
  local glow = frame:CreateTexture(nil, "BORDER", nil, 1)
  centered(glow, frame, GLOW_SIZE)
  local hasAtlas = FrameKit.Art(glow, GLOW_ATLAS)
  if not hasAtlas then
    return nil
  end
  glow:Hide()

  return glow
end

local function addAlpha(group, from, to, duration, delay)
  local alpha = group:CreateAnimation("Alpha")
  alpha:SetFromAlpha(from)
  alpha:SetToAlpha(to)
  alpha:SetDuration(duration)
  alpha:SetStartDelay(delay)
end

local function pulseGroup(pulse, spec)
  local group = pulse:CreateAnimationGroup()
  addAlpha(group, 0, 1, spec.fadeIn, 0)
  addAlpha(group, 1, 0, spec.fadeOut, spec.fadeOutDelay)
  local scale = group:CreateAnimation("Scale")
  scale:SetScaleFrom(PULSE_SCALE_FROM, PULSE_SCALE_FROM)
  scale:SetScaleTo(spec.scaleTo, spec.scaleTo)
  scale:SetDuration(spec.scaleDuration)

  return group
end

-- The pulse stays shown at alpha 0, so only the animations make it visible. The atlas size is
-- not read back (FrameKit.Art draws without useAtlasSize), so the glow takes the ring's size.
local function buildPulse(frame)
  local pulse = frame:CreateTexture(nil, "ARTWORK")
  centered(pulse, frame, Theme.LAYOUT.RING_SIZE)
  pulse:SetAlpha(0)
  local hasAtlas = FrameKit.Art(pulse, PULSE_ATLAS, nil, ADD)
  if not hasAtlas then
    return nil
  end
  local pulseLoop = pulseGroup(pulse, PULSE_LOOP)
  pulseLoop:SetLooping("REPEAT")

  return pulse, pulseGroup(pulse, PULSE_ONCE), pulseLoop
end

-- Draws the launcher's art on `frame`. glow, pulse, pulseOnce and pulseLoop are nil without
-- their atlases.
function LauncherArt.Build(frame)
  buildRings(frame)
  local icon = buildPortrait(frame)
  local glow = buildGlow(frame)
  local pulse, pulseOnce, pulseLoop = buildPulse(frame)
  local art = { icon = icon, glow = glow, pulse = pulse, pulseOnce = pulseOnce, pulseLoop = pulseLoop }

  return art
end

ns.LauncherArt = LauncherArt
return LauncherArt
