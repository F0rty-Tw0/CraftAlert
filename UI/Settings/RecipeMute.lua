local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")

-- The mute switch at a recipe row's right end, on the Crafters page and on Blizzard's profession
-- window rows: the speaker, crossed out while muted, greyed for an untracked recipe, and its house
-- tooltip (gold title, white text, green instruction) saying what the recipe does now and what a
-- click changes. The caller owns the row, what a click mutes and when to repaint
-- (UI/Settings/RecipeList.lua, UI/RecipeMarkers/MarkerSwitch.lua).
local RecipeMute = {}

-- A recipe whose item has no binding is not indexed while "Track unbound items" is off (Index).
function RecipeMute.Untracked(recipe)
  return recipe.bind == 0 and not _G["CraftAlertDB"].settings.includeUnbound
end

-- The tooltip for the switch's recipe as it is now: `mute.recipe` and `mute.muted`, the switch's
-- own state (its parent may be a Blizzard row we do not write to). An untracked recipe says why it
-- does not alert, muted or not.
local function showTooltip(mute)
  local recipe, muted = mute.recipe, mute.muted == true
  local title, text, instruction
  if recipe and RecipeMute.Untracked(recipe) then
    title, text = "Not tracked", "Items with no binding (materials, potions, gems) do not alert"
    instruction = "Turn on Track unbound items in Craft Alert's General settings"
  else
    title = muted and "Muted" or "Alerts on"
    text = muted and "Requests for this recipe do not alert you" or "Requests for this recipe alert you"
    instruction = muted and "Click: unmute" or "Click: mute"
  end
  local tooltip = Tooltip.Get()
  tooltip:SetOwner(mute, "ANCHOR_RIGHT")
  _G["GameTooltip_SetTitle"](tooltip, Localization.Text(title), _G["NORMAL_FONT_COLOR"])
  _G["GameTooltip_AddHighlightLine"](tooltip, Localization.Text(text))
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  _G["GameTooltip_AddInstructionLine"](tooltip, Localization.Text(instruction))
  tooltip:Show()
end

-- The switch on `row`, anchored at its right end; a click runs onClick(). The caller sets
-- `mute.recipe` (the recipe it stands for) and paints it.
function RecipeMute.Create(row, onClick)
  local size = Theme.LAYOUT.MUTE_SIZE
  local mute = _G["CreateFrame"]("Button", nil, row)
  mute:SetSize(size, size)
  mute:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  mute.icon = mute:CreateTexture(nil, "ARTWORK")
  mute.icon:SetAllPoints(mute)
  mute:SetHighlightTexture(Theme.ART.ICON_HIGHLIGHT, "ADD")
  mute:SetScript("OnClick", onClick)
  mute:SetScript("OnEnter", showTooltip)
  mute:SetScript("OnLeave", Tooltip.HideIfOwned)
  return mute
end

-- The art swaps whole: greying would dull the muted speaker's red slash. Only an unmuted,
-- untracked speaker is greyed. A tooltip the switch shows follows the new state.
function RecipeMute.Paint(mute, muted, greyed)
  mute.muted = muted
  local art = Theme.ART
  if muted then
    FrameKit.Art(mute.icon, art.MUTED_ATLAS, art.MUTED_FILE)
  else
    FrameKit.Art(mute.icon, art.SPEAKER_ATLAS, art.SPEAKER_FILE)
  end
  mute.icon:SetDesaturated(greyed and not muted)
  if Tooltip.Get():IsOwned(mute) then
    showTooltip(mute)
  end
end

ns.RecipeMute = RecipeMute
return RecipeMute
