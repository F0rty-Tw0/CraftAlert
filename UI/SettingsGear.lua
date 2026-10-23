local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Native-HUD spec §7.1: the gear left of the leads window's close button. A click switches
-- between the list and the settings pane; the gear stays lit while the pane shows.
local SettingsGear = {}

-- Blizzard's tooltip hierarchy (Blizzard_SharedXML/SharedTooltipTemplates.lua): gold title, a
-- blank line, one green instruction line naming what a click does now.
local function showTooltip(gear)
  local tooltip = _G["GameTooltip"]
  tooltip:SetOwner(gear, "ANCHOR_BOTTOMLEFT")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Settings"), _G["NORMAL_FONT_COLOR"])
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  local instruction = gear.inSettings and "Click: back to leads" or "Click: open settings"
  _G["GameTooltip_AddInstructionLine"](tooltip, Localization.Text(instruction))
  tooltip:Show()
end

local function hideTooltip()
  _G["GameTooltip"]:Hide()
end

-- The gear on `frame` (a ButtonFrameTemplate frame); a click runs onClick().
function SettingsGear.Create(frame, onClick)
  local size, art = Theme.LAYOUT.GEAR_SIZE, Theme.ART
  local gear = _G["CreateFrame"]("Button", nil, frame)
  gear:SetSize(size, size)
  gear:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
  -- With the title above the NineSlice border, whose metal top edge covers the title strip. Not the
  -- close button's level: the Classic template leaves that one under the border.
  gear:SetFrameLevel(frame.TitleContainer:GetFrameLevel())
  local normal = gear:CreateTexture(nil, "ARTWORK")
  FrameKit.Art(normal, art.GEAR_ATLAS, art.GEAR_FILE)
  gear:SetNormalTexture(normal)
  local highlight = gear:CreateTexture(nil, "HIGHLIGHT")
  FrameKit.Art(highlight, art.GEAR_ATLAS, art.GEAR_FILE, "ADD")
  gear:SetHighlightTexture(highlight)
  gear:SetScript("OnClick", function()
    onClick()
  end)
  gear:SetScript("OnEnter", showTooltip)
  gear:SetScript("OnLeave", hideTooltip)

  return gear
end

-- Lights the gear while the pane shows; an open tooltip follows the new mode.
function SettingsGear.Paint(gear, inSettings)
  gear.inSettings = inSettings
  if inSettings then
    gear:LockHighlight()
  else
    gear:UnlockHighlight()
  end
  if _G["GameTooltip"]:IsOwned(gear) then
    showTooltip(gear)
  end
end

ns.SettingsGear = SettingsGear
return SettingsGear
