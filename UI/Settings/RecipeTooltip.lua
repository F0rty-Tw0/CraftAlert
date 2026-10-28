local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")

-- The Crafters page's recipe tooltip: Blizzard's own recipe lists show none, and the item
-- tooltip says nothing about who here can craft it. A recipe that makes an item shows the
-- client's tooltip of that item; one without (enchants, Classic name keys, or a link the client
-- rejects) a gold title and its profession in white. Under either: who knows it, and a grey note
-- when it is muted. The rows' UpdateTooltip shows it again while hovered (RecipeList), so an
-- item that loads late gets its lines without the client's rebuild dropping ours.
local RecipeTooltip = {}

local GREY = 0.5
local pcall = pcall

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

local function showItem(tooltip, itemID)
  return (pcall(tooltip.SetHyperlink, tooltip, "item:" .. itemID))
end

-- Reads row.item at hover time (scrolls reuse rows); `character` is the shown db.characters record.
function RecipeTooltip.Show(row, character)
  local key, recipe = row.item.key, row.item.recipe
  local tooltip = Tooltip.Get()
  tooltip:SetOwner(row, "ANCHOR_RIGHT")
  if recipe.item == nil or not showItem(tooltip, recipe.item) then
    _G["GameTooltip_SetTitle"](tooltip, recipe.name or tostring(key), _G["NORMAL_FONT_COLOR"])
    local profession = character and character.professions[recipe.prof]
    if profession and profession.name ~= "" then
      _G["GameTooltip_AddHighlightLine"](tooltip, profession.name)
    end
  end
  -- A blank line sets our lines apart from the item tooltip (or the title and profession).
  _G["GameTooltip_AddBlankLineToTooltip"](tooltip)
  _G["GameTooltip_AddHighlightLine"](tooltip, Localization.Text("Known by: %s", knownBy(key)))
  if recipe.muted == true then
    tooltip:AddLine(Localization.Text("Muted"), GREY, GREY, GREY)
  end
  tooltip:Show()
end

ns.RecipeTooltip = RecipeTooltip
return RecipeTooltip
