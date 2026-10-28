local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- The addon's one tooltip, made from Blizzard's GameTooltipTemplate so it looks like the shared
-- GameTooltip. CraftAlert never calls the shared GameTooltip: in 12.0 an addon call on it taints
-- it, and Blizzard's later unit tooltips (secret values in Mythic+) then fail in tainted code.
local Tooltip = {}

local ipairs = ipairs

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

-- Blizzard's tooltip hierarchy (Blizzard_SharedXML/SharedTooltipTemplates.lua, every flavour) on
-- `owner` at `anchor`: the gold `title`, each `body` line in white, a blank line only when both body
-- and clicks have lines, then one green instruction line per `clicks` entry. body and clicks: lists
-- of display text, or nil.
function Tooltip.ShowHint(owner, anchor, title, body, clicks)
  body, clicks = body or {}, clicks or {}
  local tip = Tooltip.Get()
  tip:SetOwner(owner, anchor)
  _G["GameTooltip_SetTitle"](tip, title, _G["NORMAL_FONT_COLOR"])
  for _, line in ipairs(body) do
    _G["GameTooltip_AddHighlightLine"](tip, line)
  end
  if #body > 0 and #clicks > 0 then
    _G["GameTooltip_AddBlankLineToTooltip"](tip)
  end
  for _, line in ipairs(clicks) do
    _G["GameTooltip_AddInstructionLine"](tip, line)
  end
  tip:Show()
end

local function paint(link, color)
  link.label:SetTextColor(color[1], color[2], color[3], color[4])
end

-- A text link's hover: its gold `link.label` turns white and showTip(link) runs on enter; gold
-- again and the tooltip hidden (while the link owns it) on leave.
function Tooltip.GoldLink(link, showTip)
  link:SetScript("OnEnter", function(self)
    paint(self, Theme.COLORS.white)
    showTip(self)
  end)
  link:SetScript("OnLeave", function(self)
    paint(self, Theme.COLORS.gold)
    Tooltip.HideIfOwned(self)
  end)
end

ns.Tooltip = Tooltip
return Tooltip
