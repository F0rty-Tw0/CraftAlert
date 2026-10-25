local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The addon's one tooltip, made from Blizzard's GameTooltipTemplate so it looks like the shared
-- GameTooltip. CraftAlert never calls the shared GameTooltip: in 12.0 an addon call on it taints
-- it, and Blizzard's later unit tooltips (secret values in Mythic+) then fail in tainted code.
local Tooltip = {}

local NAME = "CraftAlertTooltip"

-- A minimum width (a lead row's tooltip sets one) lasts until the tooltip hides, so the next
-- owner starts from none.
local function create()
  local tip = _G["CreateFrame"]("GameTooltip", NAME, _G["UIParent"], "GameTooltipTemplate")
  tip:HookScript("OnHide", function(self)
    self:SetMinimumWidth(0)
  end)
  return tip
end

-- The tooltip, made on first use; its global frame name is the cache.
function Tooltip.Get()
  return _G[NAME] or create()
end

-- Hides the tooltip while `frame` owns it (an OnLeave): one another frame shows is left alone.
function Tooltip.HideIfOwned(frame)
  local tip = Tooltip.Get()
  if tip:IsOwned(frame) then
    tip:Hide()
  end
end

ns.Tooltip = Tooltip
return Tooltip
