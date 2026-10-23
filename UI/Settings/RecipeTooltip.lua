local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")

-- The Crafters page's recipe tooltip: Blizzard's own recipe lists show none, and the item or
-- spell tooltip says nothing about who here can craft it. Gold title, the profession in white,
-- who knows it, and a grey note when it is muted.
local RecipeTooltip = {}

local GREY = 0.5

-- The characters (of every source) that hold recipe `key`, as Greeting.CrafterName text, sorted.
local function knownBy(key)
  local names = {}
  for charKey, character in pairs(_G["CraftAlertDB"].characters) do
    if character.recipes[key] ~= nil then
      names[#names + 1] = Greeting.CrafterName(charKey)
    end
  end
  table.sort(names)
  return table.concat(names, ", ")
end

-- Reads row.item at hover time (scrolls reuse rows); `character` is the shown db.characters record.
function RecipeTooltip.Show(row, character)
  local key, recipe = row.item.key, row.item.recipe
  local tooltip = _G["GameTooltip"]
  tooltip:SetOwner(row, "ANCHOR_RIGHT")
  _G["GameTooltip_SetTitle"](tooltip, recipe.name or tostring(key), _G["NORMAL_FONT_COLOR"])
  local profession = character and character.professions[recipe.prof]
  if profession and profession.name ~= "" then
    _G["GameTooltip_AddHighlightLine"](tooltip, profession.name)
  end
  _G["GameTooltip_AddHighlightLine"](tooltip, Localization.Text("Known by: %s", knownBy(key)))
  if recipe.muted == true then
    tooltip:AddLine(Localization.Text("Muted"), GREY, GREY, GREY)
  end
  tooltip:Show()
end

ns.RecipeTooltip = RecipeTooltip
return RecipeTooltip
