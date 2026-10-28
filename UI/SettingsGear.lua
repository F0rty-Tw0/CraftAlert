local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")

-- Native-HUD spec §7.1: the gear left of the leads window's close button. A click switches
-- between the list and the settings pane; the gear turns into a back arrow while the pane shows.
local SettingsGear = {}

local LABEL_GAP = Theme.LAYOUT.SPACE.XS

-- One green instruction line naming what a click does now (Tooltip.ShowHint, no body).
local function showTooltip(gear)
  local instruction = gear.inSettings and "Click: back to leads" or "Click: open settings"
  Tooltip.ShowHint(gear, "ANCHOR_BOTTOMLEFT", Localization.Text("Settings"), nil, { Localization.Text(instruction) })
end

-- The gear's art on `button`: its normal texture (button.normal) and an additive copy as its
-- highlight (button.highlight), the atlas or, without it, the file.
local function addGearArt(button)
  local art = Theme.ART
  button.normal = button:CreateTexture(nil, "ARTWORK")
  FrameKit.Art(button.normal, art.GEAR_ATLAS, art.GEAR_FILE)
  button:SetNormalTexture(button.normal)
  button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
  FrameKit.Art(button.highlight, art.GEAR_ATLAS, art.GEAR_FILE, "ADD")
  button:SetHighlightTexture(button.highlight)
end

-- The gear Button under `parent`, sized and painted but not placed; a click runs onClick().
function SettingsGear.Build(parent, onClick)
  local size = Theme.LAYOUT.GEAR_SIZE
  local gear = _G["CreateFrame"]("Button", nil, parent)
  gear:SetSize(size, size)
  addGearArt(gear)
  gear:SetScript("OnClick", function()
    onClick()
  end)
  gear:SetScript("OnEnter", showTooltip)
  gear:SetScript("OnLeave", Tooltip.HideIfOwned)

  return gear
end

-- The gear with a gold "Settings" label on its right, for WhisperMessenger's ledger line: one
-- Button under `parent`, sized and painted but not placed; a click runs onClick(). The client
-- stretches a state texture over the whole button on assignment, so the gear and its highlight are
-- anchored after it: the highlight lights the gear, never the label. Never in settings mode (the
-- line hides with the list), so no back arrow.
function SettingsGear.BuildLabeled(parent, onClick)
  local size = Theme.LAYOUT.GEAR_SIZE
  local link = _G["CreateFrame"]("Button", nil, parent)
  addGearArt(link)
  for _, texture in ipairs({ link.normal, link.highlight }) do
    texture:ClearAllPoints()
    texture:SetSize(size, size)
    texture:SetPoint("LEFT", link, "LEFT", 0, 0)
  end
  link.label = FrameKit.Text(link, Theme.FONTS.body, Theme.COLORS.gold)
  link.label:SetText(Localization.Text("Settings"))
  link.label:SetPoint("LEFT", link.normal, "RIGHT", LABEL_GAP, 0)
  -- English only: the label never changes, so it is measured once.
  link:SetSize(size + LABEL_GAP + link.label:GetStringWidth(), size)
  link:SetScript("OnClick", function()
    onClick()
  end)
  Tooltip.GoldLink(link, showTooltip)

  return link
end

-- The gear on `frame` (a ButtonFrameTemplate frame); a click runs onClick().
function SettingsGear.Create(frame, onClick)
  local gear = SettingsGear.Build(frame, onClick)
  -- off-scale: close button art nudge.
  gear:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
  -- With the title above the NineSlice border, whose metal top edge covers the title strip. Not the
  -- close button's level: the Classic template leaves that one under the border.
  gear:SetFrameLevel(frame.TitleContainer:GetFrameLevel())

  return gear
end

-- Swaps the gear for a back arrow while the pane shows; an open tooltip follows the new mode.
function SettingsGear.Paint(gear, inSettings)
  gear.inSettings = inSettings
  local art = Theme.ART
  local atlas, file = art.GEAR_ATLAS, art.GEAR_FILE
  if inSettings then
    atlas, file = art.BACK_ATLAS, art.BACK_FILE
  end
  FrameKit.Art(gear.normal, atlas, file)
  FrameKit.Art(gear.highlight, atlas, file, "ADD")
  if Tooltip.Get():IsOwned(gear) then
    showTooltip(gear)
  end
end

ns.SettingsGear = SettingsGear
return SettingsGear
