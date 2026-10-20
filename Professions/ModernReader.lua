local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local BindLookup = ns.BindLookup or require("CraftAlert.Professions.BindLookup")

-- Spec §5.2 row 1 (Retail, Forever): reads the learned recipes of the open profession
-- window into the current character's storage. Guards skip other players' lists and special
-- modes, a window of a profession the character does not store (Cooking, Smelting) stores
-- nothing, and reads only add. ReadOne serves the learn path (§5.3) with the window closed.
local ModernReader = {}

local ipairs = ipairs
local lower = string.lower
local type = type

local SHOW_EVENT = "TRADE_SKILL_SHOW"
local UPDATE_EVENT = "TRADE_SKILL_LIST_UPDATE"
local GUARDS = { "IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsRuneforging" }

local db = nil
local readKey = nil -- profession and recipe count of the window as last read
local readCount = nil

-- The last window read, for the sim: { prof, stored, pendingBind }.
ModernReader.lastRead = nil

function ModernReader.Install(accountDb)
  db = accountDb
  BindLookup.Configure(accountDb)
  EventRouter.On(SHOW_EVENT, ModernReader.OnShow)
  EventRouter.On(UPDATE_EVENT, ModernReader.OnListUpdate)
end

local function tradeSkillApi()
  local api = _G["C_TradeSkillUI"]
  return type(api) == "table" and api or nil
end

local function isBlocked(api)
  for _, name in ipairs(GUARDS) do
    local guard = api[name]
    if type(guard) == "function" and guard() then
      return true
    end
  end
  return false
end

local function copyList(list)
  if type(list) ~= "table" or #list == 0 then
    return nil
  end
  local copy = {}
  for i = 1, #list do
    copy[i] = list[i]
  end
  return copy
end

local function sameList(a, b)
  if a == nil or b == nil then
    return a == b
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- → { item, ranks, name } for a recipe worth storing, else nil. `learned` is checked by the
-- window read only: it is still false inside NEW_RECIPE_LEARNED (§5.3).
local function readRecipe(api, recipeID, requireLearned)
  local info = api.GetRecipeInfo(recipeID)
  if type(info) ~= "table" or type(info.name) ~= "string" then
    return nil
  end
  if info.isRecraft or info.isDummyRecipe or info.isSalvageRecipe or info.isGatheringRecipe then
    return nil
  end
  if requireLearned and not info.learned then
    return nil
  end
  local schematic = api.GetRecipeSchematic(recipeID, false)
  return { item = schematic and schematic.outputItemID, ranks = copyList(info.qualityItemIDs), name = lower(info.name) }
end

-- Adds the recipe or updates it in place (mute and bind survive) → whether storage changed.
local function merge(recipes, recipeID, fields, professionKey)
  local old = recipes[recipeID]
  if old == nil then
    fields.prof = professionKey
    recipes[recipeID] = fields
    return true
  end
  local changed = old.item ~= fields.item or old.name ~= fields.name or old.prof ~= professionKey or not sameList(old.ranks, fields.ranks)
  if changed then
    if old.item ~= fields.item then
      old.bind = nil
    end
    old.item, old.name, old.prof, old.ranks = fields.item, fields.name, professionKey, fields.ranks
  end
  return changed
end

-- → changed, and queues the bind lookup when the output item's bind is unknown.
local function store(recipes, recipeID, fields, professionKey)
  local changed = merge(recipes, recipeID, fields, professionKey)
  local recipe = recipes[recipeID]
  if recipe.item and recipe.bind == nil then
    BindLookup.Queue(recipe.item)
    return changed, true
  end
  return changed, false
end

-- The base profession of the open window when it is one the current character stores.
local function windowProfession(api)
  local getBase = api.GetBaseProfessionInfo
  local info = type(getBase) == "function" and getBase() or nil
  local key = type(info) == "table" and info.professionID or nil
  if key ~= nil and ProfessionList.IsStored(db, PlayerName.Own(), key) then
    return key
  end
  return nil
end

local function readWindow(api, character, key, recipeIDs)
  local stored, pendingBind, anyChanged = 0, 0, false
  for _, recipeID in ipairs(recipeIDs) do
    local fields = readRecipe(api, recipeID, true)
    if fields then
      local changed, unknownBind = store(character.recipes, recipeID, fields, key)
      stored = stored + 1
      anyChanged = anyChanged or changed
      pendingBind = pendingBind + (unknownBind and 1 or 0)
    end
  end
  if #recipeIDs > 0 then
    character.professions[key].read = true
  end
  ModernReader.lastRead = { prof = key, stored = stored, pendingBind = pendingBind }
  if anyChanged then
    Index.RequestRebuild("read")
  end
end

-- force: the window was just opened. An update re-reads only when the profession or the
-- recipe count differs from the last read.
local function onWindowEvent(force)
  local api = tradeSkillApi()
  if api == nil or db == nil or isBlocked(api) then
    return
  end
  local key = windowProfession(api)
  if key == nil then
    return
  end
  local recipeIDs = api.GetAllRecipeIDs() or {}
  if not force and key == readKey and #recipeIDs == readCount then
    return
  end
  readKey, readCount = key, #recipeIDs
  readWindow(api, db.characters[PlayerName.Own()], key, recipeIDs)
end

function ModernReader.OnShow()
  onWindowEvent(true)
end

function ModernReader.OnListUpdate()
  onWindowEvent(false)
end

-- Reads one recipe with the window closed (§5.3) → whether it is now stored.
function ModernReader.ReadOne(recipeID, professionKey)
  local api = tradeSkillApi()
  if api == nil or db == nil or not ProfessionList.IsStored(db, PlayerName.Own(), professionKey) then
    return false
  end
  local fields = readRecipe(api, recipeID, false)
  if fields == nil then
    return false
  end
  local changed = store(db.characters[PlayerName.Own()].recipes, recipeID, fields, professionKey)
  if changed then
    Index.RequestRebuild("learn")
  end
  return true
end

ns.ModernReader = ModernReader
return ModernReader
