local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")

-- The Crafters page's recipe tooltip: Blizzard's own recipe lists show none, and the item
-- tooltip says nothing about who here can craft it. A recipe that makes an item shows the
-- client's tooltip of that item; one without (enchants, Classic name keys, or a link the client
-- rejects) a gold title and its profession in white. Under either: who knows it, and a grey note
-- when it is muted. A client with C_TooltipInfo rebuilds an item tooltip once the item loads,
-- which drops our lines: while ours shows an item still loading, TOOLTIP_DATA_UPDATE is
-- registered and the tooltip is shown again once the item is cached.
local RecipeTooltip = {}

local GREY = 0.5
local DATA_EVENT = "TOOLTIP_DATA_UPDATE"
local pcall = pcall

---@type { row: table, character: table? }?
local waiting = nil -- { row, character } while our tooltip shows an item the client is loading
local onDataUpdate

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

local function stopWaiting()
  if waiting ~= nil then
    waiting = nil
    EventRouter.Off(DATA_EVENT, onDataUpdate)
  end
end

-- Only a client with C_TooltipInfo rebuilds tooltips (and has the event).
local function waitFor(row, character)
  if type(_G["C_TooltipInfo"]) ~= "table" then
    return
  end
  waiting = { row = row, character = character }
  EventRouter.On(DATA_EVENT, onDataUpdate)
end

local function showItem(tooltip, itemID)
  return (pcall(tooltip.SetHyperlink, tooltip, "item:" .. itemID))
end

-- Reads row.item at hover time (scrolls reuse rows); `character` is the shown db.characters record.
function RecipeTooltip.Show(row, character)
  stopWaiting()
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

-- Waits out other tooltips' updates; stops once ours is gone or its item has loaded (then shows
-- it again, our lines included). A row repainted to a recipe without an item stops too.
onDataUpdate = function()
  if waiting == nil then
    return
  end
  local row, character = waiting.row, waiting.character
  local recipe = row.item and row.item.recipe
  if not _G["GameTooltip"]:IsOwned(row) or recipe == nil or recipe.item == nil then
    stopWaiting()
  elseif not loading(recipe.item) then
    RecipeTooltip.Show(row, character)
  end
end

ns.RecipeTooltip = RecipeTooltip
return RecipeTooltip
