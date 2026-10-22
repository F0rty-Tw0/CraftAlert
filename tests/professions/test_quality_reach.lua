local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local CHAR = "Me-Realm"
local STEP_COST_MS = 3
local MODIFIED, PLAIN = 1, 0
local FINISHING, BASIC = 3, 1

-- Recipe 1288335 as the probe saved it: three plain slots, two required ModifiedReagent slots
-- (the first with variants 239198 and 239200), one optional ModifiedReagent slot and one
-- Finishing slot.
local function probeSchematic()
  return {
    reagentSlotSchematics = {
      { dataSlotType = PLAIN, dataSlotIndex = 1, required = true, reagentType = BASIC, quantityRequired = 5, reagents = { { itemID = 1 } } },
      { dataSlotType = PLAIN, dataSlotIndex = 2, required = true, reagentType = BASIC, quantityRequired = 3, reagents = { { itemID = 2 } } },
      { dataSlotType = PLAIN, dataSlotIndex = 3, required = true, reagentType = BASIC, quantityRequired = 1, reagents = { { itemID = 3 } } },
      {
        dataSlotType = MODIFIED,
        dataSlotIndex = 1,
        required = true,
        reagentType = BASIC,
        quantityRequired = 2,
        reagents = { { itemID = 239198 }, { itemID = 239200 } },
      },
      {
        dataSlotType = MODIFIED,
        dataSlotIndex = 2,
        required = true,
        reagentType = BASIC,
        quantityRequired = 4,
        reagents = { { itemID = 5 }, { itemID = 6 } },
      },
      { dataSlotType = MODIFIED, dataSlotIndex = 3, required = false, reagentType = BASIC, quantityRequired = 1, reagents = { { itemID = 7 } } },
      { dataSlotType = MODIFIED, dataSlotIndex = 4, required = true, reagentType = FINISHING, quantityRequired = 1, reagents = { { itemID = 8 } } },
    },
  }
end

local function qualityAnswer(rank, cost, currencyID)
  return { isQualityCraft = true, craftingQuality = rank, concentrationCost = cost, concentrationCurrencyID = currencyID }
end

local function currency(amount)
  return { quantity = amount, maxQuantity = 1000, rechargingCycleDurationMS = 345600, rechargingAmountPerCycle = 1 }
end

-- A logged-in "Me-Realm" with `recipes`, the three APIs stubbed (state.answers[id] is what
-- GetCraftingOperationInfo gives; a function there raises), and the module installed.
-- state.calls logs { recipeID, reagents, third, concentrating } per operation call.
local function setup(recipes, noOperationApi)
  Wow.reset()
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  local state = { calls = {}, answers = {}, schematic = probeSchematic(), currencies = { [3167] = currency(698), [3168] = currency(100) } }
  local tradeSkill = {
    GetRecipeSchematic = function(_, isRecraft)
      assert(isRecraft == false, "reach passes isRecraft = false")
      return state.schematic
    end,
  }
  if not noOperationApi then
    tradeSkill.GetCraftingOperationInfo = function(recipeID, reagents, third, concentrating)
      state.calls[#state.calls + 1] = { recipeID, reagents, third, concentrating }
      Wow.clock.profile = Wow.clock.profile + STEP_COST_MS
      local answer = state.answers[recipeID]
      if type(answer) == "function" then
        answer()
      end
      return answer
    end
  end
  Wow.stub("C_TradeSkillUI", tradeSkill)
  Wow.stub("Enum", {
    TradeskillSlotDataType = { Reagent = PLAIN, ModifiedReagent = MODIFIED },
    CraftingReagentType = { Basic = BASIC, Finishing = FINISHING },
  })
  Wow.stub("C_CurrencyInfo", {
    GetCurrencyInfo = function(currencyID)
      return state.currencies[currencyID]
    end,
  })
  Fresh.require("Core.EventRouter")
  local PlayerName = Fresh.require("Core.PlayerName")
  PlayerName.Init()
  local Slicer = Fresh.require("Core.Slicer")
  local QualityReach = Fresh.require("Professions.QualityReach")
  local db = { characters = { [CHAR] = { recipes = recipes } } }
  QualityReach.Install(db)
  return state, QualityReach, Slicer, db
end

local function isRegistered(event)
  for _, frame in ipairs(Wow.frames) do
    if frame.events[event] then
      return true
    end
  end
  return false
end

local function idsOf(calls)
  local ids = {}
  for i, call in ipairs(calls) do
    ids[i] = call[1]
  end
  return ids
end

local function reachOf(recipe)
  return { recipe.reachRank, recipe.reachCost, recipe.reachConc }
end

local function testReagentListTakesTopVariantOfRequiredModifiedSlots()
  local state, QualityReach, Slicer = setup({ [1288335] = { ranks = { 1, 2 } } })
  state.answers[1288335] = qualityAnswer(1, 376, 3168)
  QualityReach.Queue({ 1288335 })
  Slicer.Drain()

  Assert.same(state.calls[1][2], {
    { reagent = { itemID = 239200 }, dataSlotIndex = 1, quantity = 2 },
    { reagent = { itemID = 6 }, dataSlotIndex = 2, quantity = 4 },
  })
  Assert.equal(state.calls[1][3], nil)
  Assert.equal(state.calls[1][4], false)
end

local function testQualityAnswerIsStored()
  local state, QualityReach, Slicer, db = setup({ [10] = { ranks = { 1, 2 } } })
  state.answers[10] = qualityAnswer(1, 376, 3168)
  QualityReach.Queue({ 10 })
  Slicer.Drain()

  Assert.same(reachOf(db.characters[CHAR].recipes[10]), { 1, 376, 3168 })
end

local function testAnyOtherAnswerClearsAllThreeFields()
  local stale = function()
    return { ranks = { 1, 2 }, reachRank = 2, reachCost = 0, reachConc = 3167 }
  end
  local state, QualityReach, Slicer, db = setup({ [1] = stale(), [2] = stale(), [3] = stale(), [4] = stale(), [5] = stale() })
  state.answers[2] = { isQualityCraft = false, craftingQuality = 1, concentrationCost = 5, concentrationCurrencyID = 3167 }
  state.answers[3] = function()
    error("boom", 0)
  end
  state.answers[4] = { isQualityCraft = true, craftingQuality = 1 }
  db.characters[CHAR].recipes[5].ranks = nil
  QualityReach.Queue({ 1, 2, 3, 4, 5 })
  Slicer.Drain()

  for id = 1, 5 do
    Assert.same(reachOf(db.characters[CHAR].recipes[id]), {}, "recipe " .. id)
  end
  Assert.equal(db.characters[CHAR].recipes[1].ranks ~= nil, true, "ranks stay")
end

local function testRecipeNotStoredIsSkipped()
  local state, QualityReach, Slicer = setup({ [10] = { ranks = { 1 } } })
  QualityReach.Queue({ 99, 10 })
  Slicer.Drain()

  Assert.same(idsOf(state.calls), { 10 })
end

local function testQueueKeepsFifoWithoutDuplicates()
  local recipes = {}
  for id = 1, 3 do
    recipes[id] = { ranks = { 1, 2 } }
  end
  local state, QualityReach, Slicer = setup(recipes)
  QualityReach.Queue({ 1, 2 })
  table.remove(Wow.timers, 1).fn()
  QualityReach.Queue({ 2, 3 })
  Slicer.Drain()

  Assert.same(idsOf(state.calls), { 1, 2, 3 })
  QualityReach.Queue({ 1 })
  Slicer.Drain()
  Assert.same(idsOf(state.calls), { 1, 2, 3, 1 }, "the seen-set is clear after the last step")
end

local function testCombatHoldsTheJobUntilRegenEnabled()
  local state, QualityReach, Slicer = setup({ [10] = { ranks = { 1, 2 } } })
  Wow.combat = true
  QualityReach.Queue({ 10 })
  Wow.runTimers()
  Assert.equal(#state.calls, 0)

  Wow.combat = false
  Wow.fireEvent("PLAYER_REGEN_ENABLED")
  Wow.runTimers()
  Assert.same(idsOf(state.calls), { 10 })
  Assert.falsy(Slicer.IsRunning("reach"))
end

local function testSaveConcentrationWritesOneEntryPerCurrency()
  local recipes = {
    [1] = { reachRank = 1, reachCost = 5, reachConc = 3167 },
    [2] = { reachRank = 1, reachCost = 5, reachConc = 3167 },
    [3] = { reachRank = 2, reachCost = 0, reachConc = 3168 },
    [4] = { ranks = { 1 } },
  }
  local _, QualityReach, _, db = setup(recipes)
  db.characters[CHAR].concentration = nil
  Wow.clock.time = 5000
  QualityReach.SaveConcentration()

  Assert.same(db.characters[CHAR].concentration, {
    [3167] = { amount = 698, at = 5000, cycleMs = 345600, perCycle = 1, max = 1000 },
    [3168] = { amount = 100, at = 5000, cycleMs = 345600, perCycle = 1, max = 1000 },
  })
end

local function testSaveConcentrationSkipsACurrencyWithoutRechargeData()
  local recipes = { [1] = { reachRank = 1, reachCost = 5, reachConc = 3167 }, [2] = { reachRank = 1, reachCost = 5, reachConc = 3168 } }
  local state, QualityReach, _, db = setup(recipes)
  state.currencies[3167].rechargingCycleDurationMS = nil
  state.currencies[3168].rechargingCycleDurationMS = 0
  db.characters[CHAR].concentration = nil
  QualityReach.SaveConcentration()

  Assert.equal(db.characters[CHAR].concentration, nil, "no valid snapshot creates no table")
end

local function testInstallSavesAtLoginAndAtLogout()
  local recipes = { [1] = { reachRank = 1, reachCost = 5, reachConc = 3167 } }
  local state, QualityReach, _, db = setup(recipes)
  Assert.equal(db.characters[CHAR].concentration[3167].amount, 698, "the login save")
  Assert.truthy(isRegistered("PLAYER_LOGOUT"))

  state.currencies[3167].quantity = 640
  Wow.clock.time = 9000
  Wow.fireEvent("PLAYER_LOGOUT")
  Assert.same(db.characters[CHAR].concentration[3167], { amount = 640, at = 9000, cycleMs = 345600, perCycle = 1, max = 1000 })
  Assert.equal(QualityReach.Available(), true)
end

local function testNothingRunsWithoutTheOperationApi()
  local recipes = { [1] = { ranks = { 1, 2 }, reachRank = 1, reachCost = 5, reachConc = 3167 } }
  local _, QualityReach, Slicer, db = setup(recipes, true)

  Assert.equal(QualityReach.Available(), false)
  Assert.falsy(isRegistered("PLAYER_LOGOUT"))
  QualityReach.Queue({ 1 })
  Assert.falsy(Slicer.IsRunning("reach"))
  QualityReach.SaveConcentration()
  Assert.equal(db.characters[CHAR].concentration, nil)
  Assert.equal(Wow.pendingTimers(0), 0)
end

return function()
  testReagentListTakesTopVariantOfRequiredModifiedSlots()
  testQualityAnswerIsStored()
  testAnyOtherAnswerClearsAllThreeFields()
  testRecipeNotStoredIsSkipped()
  testQueueKeepsFifoWithoutDuplicates()
  testCombatHoldsTheJobUntilRegenEnabled()
  testSaveConcentrationWritesOneEntryPerCurrency()
  testSaveConcentrationSkipsACurrencyWithoutRechargeData()
  testInstallSavesAtLoginAndAtLogout()
  testNothingRunsWithoutTheOperationApi()
  Wow.reset()
end
