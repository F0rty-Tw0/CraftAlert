local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- The Crafters page's recipe names in the crafted item's rarity colour (Blizzard's item-quality
-- colours). No colour is known for a recipe without an item, an uncached item or a client without
-- the calls: those are white. An uncached item is requested once per session; its answer
-- (GET_ITEM_INFO_RECEIVED, registered only while an item is pending) repaints the list through
-- the callback of the latest Paint, so a failed load stays white and is never asked for again.
local RecipeRarity = {}

local EVENT = "GET_ITEM_INFO_RECEIVED"
local QUALITY_INDEX = 3

local requested = {} -- itemID -> true once asked for; never cleared
local pending = {} -- itemID -> true until its answer
local pendingCount = 0
local onLoaded = nil

-- The item's quality, or nil for no item or an uncached one.
local function qualityOf(itemID)
  if type(itemID) ~= "number" then
    return nil
  end
  return (select(QUALITY_INDEX, FlavorCompat.GetItemInfo(itemID)))
end

-- One function made once, so EventRouter.On dedupes it and Off removes it.
local function onItemInfo(itemID)
  if not pending[itemID] then
    return
  end
  pending[itemID] = nil
  pendingCount = pendingCount - 1
  if pendingCount == 0 then
    EventRouter.Off(EVENT, onItemInfo)
  end
  if onLoaded then
    onLoaded()
  end
end

-- Asks the client for an uncached item, once per session; nothing happens without the call.
local function requestLoad(itemID)
  local items = _G["C_Item"]
  if requested[itemID] or type(items) ~= "table" or type(items.RequestLoadItemDataByID) ~= "function" then
    return
  end
  requested[itemID] = true
  pending[itemID] = true
  pendingCount = pendingCount + 1
  EventRouter.On(EVENT, onItemInfo)
  items.RequestLoadItemDataByID(itemID)
end

-- Colours `fontString` for the recipe's item; `dim` draws it at Theme.DIM_ALPHA (muted and
-- untracked rows). `repaint` runs when a pending item answers. Every call sets the colour: rows
-- are reused.
function RecipeRarity.Paint(fontString, itemID, dim, repaint)
  onLoaded = repaint
  local quality = qualityOf(itemID)
  if quality == nil and type(itemID) == "number" then
    requestLoad(itemID)
  end
  local r, g, b
  if quality ~= nil then
    r, g, b = FlavorCompat.GetItemQualityColor(quality)
  end
  fontString:SetTextColor(r or 1, g or 1, b or 1, dim and Theme.DIM_ALPHA or 1)
end

ns.RecipeRarity = RecipeRarity
return RecipeRarity
