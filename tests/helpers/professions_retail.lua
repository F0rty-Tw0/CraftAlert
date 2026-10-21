-- Retail/Forever profession API stubs with a configurable recipe list, shared by the
-- reader tests and tools/sim.lua.
--   local state = ProfessionsRetail.install({ slots = {...}, base = 164, recipes = {...} })
--   state.recipes[#state.recipes + 1] = { id = 7, name = "Belt", item = 100, learned = true }
--   state.guards.IsTradeSkillLinked = true   -- the open window is somebody else's list
-- state.slots: GetProfessions positions, each { name = "Blacksmithing", skillLine = 164 } or false.
-- state.base: professionID C_TradeSkillUI.GetBaseProfessionInfo reports for the open window.
-- state.changing: C_TradeSkillUI.IsDataSourceChanging() (the list is still rebuilding).
-- state.lookups[id]: what GetProfessionInfoByRecipeID reports for a recipe not in the list.
-- A recipe: { id, name, item, ranks, learned, profession = {professionID, parentProfessionID},
-- isRecraft, isDummyRecipe, isSalvageRecipe, isGatheringRecipe }.
local Wow = require("tests.helpers.wow")

local ProfessionsRetail = {}

local MAX_SLOTS = 6
local GUARDS = { "IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsRuneforging" }

local function findRecipe(state, id)
  for _, recipe in ipairs(state.recipes) do
    if recipe.id == id then
      return recipe
    end
  end
  return nil
end

local function installProfessionList(state)
  Wow.stub("GetProfessions", function()
    local positions = {}
    for position = 1, MAX_SLOTS do
      positions[position] = state.slots[position] and position or nil
    end
    return unpack(positions, 1, MAX_SLOTS)
  end)
  Wow.stub("GetProfessionInfo", function(index)
    local slot = state.slots[index]
    return slot.name, "icon", 1, 100, 0, 0, slot.skillLine
  end)
end

local function recipeInfo(recipe)
  return {
    recipeID = recipe.id,
    name = recipe.name,
    learned = recipe.learned == true,
    qualityItemIDs = recipe.ranks,
    isRecraft = recipe.isRecraft == true,
    isDummyRecipe = recipe.isDummyRecipe == true,
    isSalvageRecipe = recipe.isSalvageRecipe == true,
    isGatheringRecipe = recipe.isGatheringRecipe == true,
  }
end

local function installTradeSkill(state)
  local api = {
    GetAllRecipeIDs = function()
      local ids = {}
      for i, recipe in ipairs(state.recipes) do
        ids[i] = recipe.id
      end
      return ids
    end,
    GetRecipeInfo = function(id)
      local recipe = findRecipe(state, id)
      return recipe and recipeInfo(recipe) or nil
    end,
    GetRecipeSchematic = function(id, isRecraft)
      assert(isRecraft == false, "readers pass isRecraft = false")
      local recipe = findRecipe(state, id)
      return recipe and { outputItemID = recipe.item } or nil
    end,
    GetBaseProfessionInfo = function()
      return { professionID = state.base }
    end,
    GetProfessionInfoByRecipeID = function(id)
      local recipe = findRecipe(state, id)
      if recipe == nil then
        return state.lookups and state.lookups[id] or nil
      end
      return recipe.profession
    end,
    IsDataSourceChanging = function()
      return state.changing == true
    end,
  }
  for _, name in ipairs(GUARDS) do
    api[name] = function()
      return state.guards[name] == true
    end
  end
  Wow.stub("C_TradeSkillUI", api)
end

-- C_Item data: state.bind[itemID] is served once the item is cached. A load request is
-- recorded in state.requests; it caches the item at once when state.autoCache is set,
-- otherwise the test sets state.cached[itemID] itself (data arrives later in the game).
local function installItems(state)
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      local item = state.items[itemID]
      if item then
        return itemID, "type", "subtype", item[1], 0, item[2], item[3]
      end
    end,
    GetItemInfo = function(itemID)
      if state.cached[itemID] then
        local link = "|cffffffff|Hitem:" .. itemID .. "|h[Item " .. itemID .. "]|h|r"
        return "Item " .. itemID, link, 1, 1, 1, "type", "subtype", 1, "", 0, 0, 0, 0, state.bind[itemID]
      end
    end,
    RequestLoadItemDataByID = function(itemID)
      state.requests[#state.requests + 1] = itemID
      state.cached[itemID] = state.cached[itemID] or state.autoCache or nil
    end,
  })
end

function ProfessionsRetail.install(state)
  state = state or {}
  state.slots = state.slots or {}
  state.recipes = state.recipes or {}
  state.guards = state.guards or {}
  state.items = state.items or {}
  state.bind = state.bind or {}
  state.cached = state.cached or {}
  state.requests = state.requests or {}
  installProfessionList(state)
  installTradeSkill(state)
  installItems(state)
  return state
end

return ProfessionsRetail
