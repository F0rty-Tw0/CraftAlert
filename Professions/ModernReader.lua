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

local pairs = pairs
local ipairs = ipairs
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

-- → the recipe info of a recipe worth storing, else nil. `learned` is checked by the window
-- read only: it is still false inside NEW_RECIPE_LEARNED (§5.3).
local function usableInfo(api, recipeID, requireLearned)
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
  return info
end

-- → { item, ranks, name } of a usable recipe (usableInfo).
local function readFields(api, recipeID, info)
  local schematic = api.GetRecipeSchematic(recipeID, false)
  -- Blizzard's spelling: the greeting names the recipe with it; Index lowercases for matching.
  return { item = schematic and schematic.outputItemID, ranks = copyList(info.qualityItemIDs), name = info.name }
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

local function professionInfo(recipeID)
  local api = tradeSkillApi()
  local getInfo = api and api.GetProfessionInfoByRecipeID
  local info = type(getInfo) == "function" and getInfo(recipeID) or nil
  return type(info) == "table" and info or nil
end

-- The base profession of a recipe: the parent skill line when there is one, else the skill
-- line itself; nil when the lookup gives nothing.
function ModernReader.ProfessionOf(recipeID)
  local info = professionInfo(recipeID)
  return info and (info.parentProfessionID or info.professionID) or nil
end

-- Mid-switch the list may still hold another profession's recipes: each is stored under its
-- own profession when the character stores that one, and skipped (nil) otherwise. A recipe
-- with no profession info (nil, or 0 before the data loads) belongs to the window, and so
-- does one answered with a bare skill line the character does not store: like dropForeign,
-- only a parented answer proves another profession.
-- → the key to store under (nil: skip), and whether the recipe's own lookup named the window.
local function storeKey(charKey, recipeID, key)
  local info = professionInfo(recipeID)
  local parent = info and info.parentProfessionID
  local own = parent or (info and info.professionID)
  if own == key then
    return key, true
  end
  if own == nil or own == 0 then
    return key, false
  end
  if ProfessionList.IsStored(db, charKey, own) then
    return own, false
  end
  return parent == nil and key or nil, false
end

-- Drops the saved recipes tagged with the window's profession whose own lookup names a
-- profession the character does not store (an older read tagged a mid-switch list with the
-- window's). Only a parented answer counts: a recipe the lookup does not resolve, or answers
-- with a bare skill line, is kept. → whether any was dropped.
local function dropForeign(character, charKey, key)
  local dropped = false
  for recipeID, recipe in pairs(character.recipes) do
    if recipe.prof == key then
      local info = professionInfo(recipeID)
      local own = info and info.parentProfessionID
      if own ~= nil and own ~= 0 and own ~= key and not ProfessionList.IsStored(db, charKey, own) then
        character.recipes[recipeID] = nil
        dropped = true
      end
    end
  end
  return dropped
end

-- Marks read only the professions that got a recipe. → whether the window's profession did.
-- Saved recipes of other professions are dropped only when some recipe's own lookup named
-- the window's profession: a lookup that resolves nothing (not loaded, or a shape this code
-- does not read) must never empty the saved data.
local function readWindow(api, character, charKey, key, recipeIDs)
  local stored, pendingBind, anyChanged, readKeys, named = 0, 0, false, {}, false
  for _, recipeID in ipairs(recipeIDs) do
    local info = usableInfo(api, recipeID, true)
    local professionKey, ownNamed
    if info then
      professionKey, ownNamed = storeKey(charKey, recipeID, key)
      named = named or ownNamed
    end
    if professionKey then
      local changed, unknownBind = store(character.recipes, recipeID, readFields(api, recipeID, info), professionKey)
      stored = stored + 1
      anyChanged = anyChanged or changed
      pendingBind = pendingBind + (unknownBind and 1 or 0)
      readKeys[professionKey] = true
    end
  end
  if named and dropForeign(character, charKey, key) then
    anyChanged = true
  end
  for professionKey in pairs(readKeys) do
    character.professions[professionKey].read = true
  end
  ModernReader.lastRead = { prof = key, stored = stored, pendingBind = pendingBind }
  if anyChanged then
    Index.RequestRebuild("read")
  end
  return readKeys[key] == true
end

-- A list update while the data source is rebuilding is yielded; a later update brings the
-- finished list.
local function isDataSourceChanging(api)
  local changing = api.IsDataSourceChanging
  return type(changing) == "function" and changing() == true
end

-- force: the window was just opened. An update re-reads only when the profession or the
-- recipe count differs from the last read that stored a recipe for the window.
local function onWindowEvent(force)
  local api = tradeSkillApi()
  if api == nil or db == nil or isBlocked(api) then
    return
  end
  if not force and isDataSourceChanging(api) then
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
  local charKey = PlayerName.Own()
  if readWindow(api, db.characters[charKey], charKey, key, recipeIDs) then
    readKey, readCount = key, #recipeIDs
  end
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
  local info = usableInfo(api, recipeID, false)
  if info == nil then
    return false
  end
  local changed = store(db.characters[PlayerName.Own()].recipes, recipeID, readFields(api, recipeID, info), professionKey)
  if changed then
    Index.RequestRebuild("learn")
  end
  return true
end

ns.ModernReader = ModernReader
return ModernReader
