local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")

-- The Crafters page's recipe tooltip: Blizzard's own recipe lists show none, and the item
-- tooltip says nothing about who here can craft it. A recipe that makes an item shows the
-- client's tooltip of that item; one without (enchants, Classic name keys, or a link the client
-- rejects) a gold title and its profession in white. Under either: who knows it, and a grey note
-- when it is muted. The client rebuilds an item tooltip once the item loads, which drops our
-- lines, unless the owner has an UpdateTooltip: GameTooltip's own update calls that instead
-- (on the frame the item loads, else every 0.2 s while shown). So while ours shows an item
-- still loading, the row has one, and it shows the tooltip again once the item is cached.
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

-- true only when the client can tell and the item is not cached yet.
local function loading(itemID)
  local items = _G["C_Item"]
  local isCached = type(items) == "table" and items.IsItemDataCachedByID
  return type(isCached) == "function" and isCached(itemID) == false
end

-- row.UpdateTooltip, while the row's tooltip waits for its item (rows are our own frames).
local function waitFor(row, character)
  row.UpdateTooltip = function()
    local recipe = row.item and row.item.recipe
    if recipe ~= nil and recipe.item ~= nil and loading(recipe.item) then
      return
    end
    RecipeTooltip.Show(row, character)
  end
end

local function showItem(tooltip, itemID)
  return (pcall(tooltip.SetHyperlink, tooltip, "item:" .. itemID))
end

-- Reads row.item at hover time (scrolls reuse rows); `character` is the shown db.characters record.
function RecipeTooltip.Show(row, character)
  row.UpdateTooltip = nil
  local key, recipe = row.item.key, row.item.recipe
  local tooltip = _G["GameTooltip"]
  tooltip:SetOwner(row, "ANCHOR_RIGHT")
  if recipe.item ~= nil and showItem(tooltip, recipe.item) then
    if loading(recipe.item) then
      waitFor(row, character)
    end
  else
    _G["GameTooltip_SetTitle"](tooltip, recipe.name or tostring(key), _G["NORMAL_FONT_COLOR"])
    local profession = character and character.professions[recipe.prof]
    if profession and profession.name ~= "" then
      _G["GameTooltip_AddHighlightLine"](tooltip, profession.name)
    end
  end
  _G["GameTooltip_AddHighlightLine"](tooltip, Localization.Text("Known by: %s", knownBy(key)))
  if recipe.muted == true then
    tooltip:AddLine(Localization.Text("Muted"), GREY, GREY, GREY)
  end
  tooltip:Show()
end

ns.RecipeTooltip = RecipeTooltip
return RecipeTooltip
