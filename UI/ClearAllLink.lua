local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")

-- "Clear all" on the ledger line, in the "Settings" link's look (UI/SettingsGear.lua): a gold
-- label, white under the mouse; a click dismisses every lead (Leads.DismissAll). No confirm and no
-- undo. Grey and disabled while the view lists no lead; a disabled Button gets no OnEnter, so no
-- tooltip then.
local ClearAllLink = {}

local function paint(link, color)
  link.label:SetTextColor(color[1], color[2], color[3], color[4])
end

-- Blizzard's tooltip hierarchy: gold title, white body; no click line, the label names the click.
local function showTooltip(link)
  local tooltip = Tooltip.Get()
  tooltip:SetOwner(link, "ANCHOR_BOTTOMLEFT")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text("Clear all leads"), _G["NORMAL_FONT_COLOR"])
  _G["GameTooltip_AddHighlightLine"](tooltip, Localization.Text("Dismisses every lead in the list."))
  tooltip:Show()
end

-- The link Button under `parent`, LEDGER_HEIGHT tall and as wide as its label, not placed.
function ClearAllLink.Build(parent)
  local link = _G["CreateFrame"]("Button", nil, parent)
  link.label = FrameKit.Text(link, Theme.FONTS.body, Theme.COLORS.gold)
  link.label:SetText(Localization.Text("Clear all"))
  link.label:SetPoint("LEFT", link, "LEFT", 0, 0)
  -- English only: the label never changes, so it is measured once.
  link:SetSize(link.label:GetStringWidth(), Theme.LAYOUT.LEDGER_HEIGHT)
  link:SetScript("OnClick", Leads.DismissAll)
  link:SetScript("OnEnter", function(self)
    paint(self, Theme.COLORS.white)
    showTooltip(self)
  end)
  link:SetScript("OnLeave", function(self)
    paint(self, Theme.COLORS.gold)
    Tooltip.HideIfOwned(self)
  end)
  return link
end

-- Enabled (gold) when the view lists a lead, else disabled (grey).
function ClearAllLink.SetEnabled(link, enabled)
  link:SetEnabled(enabled)
  paint(link, enabled and Theme.COLORS.gold or Theme.COLORS.grey)
end

ns.ClearAllLink = ClearAllLink
return ClearAllLink
