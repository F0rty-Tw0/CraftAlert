local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The addon's one tooltip, made from Blizzard's GameTooltipTemplate so it looks like the shared
-- GameTooltip. CraftAlert never calls the shared GameTooltip: in 12.0 an addon call on it taints
-- it, and Blizzard's later unit tooltips (secret values in Mythic+) then fail in tainted code.
local Tooltip = {}

local NAME = "CraftAlertTooltip"

-- The tooltip, made on first use; its global frame name is the cache.
function Tooltip.Get()
  return _G[NAME] or _G["CreateFrame"]("GameTooltip", NAME, _G["UIParent"], "GameTooltipTemplate")
end

ns.Tooltip = Tooltip
return Tooltip
