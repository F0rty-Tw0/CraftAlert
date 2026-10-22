local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Spec 2026-10-22-crafter-quality-rank §4.3 / F3: what the game says a recipe reaches when
-- crafted with the best reagents and no concentration. QualityReach saves the answer.
local ReachQuery = {}

local ipairs = ipairs
local pcall = pcall
local type = type

local function isBestSlot(slot, enum)
  local variants = slot.reagents
  local isModified = slot.dataSlotType == enum.TradeskillSlotDataType.ModifiedReagent
  local isFinishing = slot.reagentType == enum.CraftingReagentType.Finishing
  local hasVariants = type(variants) == "table" and #variants > 0

  return isModified and slot.required == true and not isFinishing and hasVariants
end

-- The top variant of every required quality slot, as PublicOrdersReagentsColumn builds it;
-- mixing data slot types would repeat dataSlotIndex values and the game answers nil.
local function bestReagents(recipeID)
  local schematic = _G["C_TradeSkillUI"].GetRecipeSchematic(recipeID, false)
  local slots = type(schematic) == "table" and schematic.reagentSlotSchematics or {}
  local list = {}
  for _, slot in ipairs(slots) do
    if isBestSlot(slot, _G["Enum"]) then
      list[#list + 1] = { reagent = slot.reagents[#slot.reagents], dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
    end
  end

  return list
end

local function operationAnswer(recipeID, recipe)
  if recipe.ranks == nil then
    return nil
  end

  return _G["C_TradeSkillUI"].GetCraftingOperationInfo(recipeID, bestReagents(recipeID), nil, false)
end

local function isReachAnswer(answer)
  local isQuality = type(answer) == "table" and answer.isQualityCraft == true
  local hasRank = isQuality and type(answer.craftingQuality) == "number"
  local hasCost = isQuality and type(answer.concentrationCost) == "number"
  local hasCurrency = isQuality and type(answer.concentrationCurrencyID) == "number"

  return hasRank and hasCost and hasCurrency
end

-- → reachRank, reachCost, reachConc; all nil when the recipe has no quality ranks, the game
-- gives no quality answer, or the lookup raises.
function ReachQuery.Ask(recipeID, recipe)
  local ok, answer = pcall(operationAnswer, recipeID, recipe)
  if not ok or not isReachAnswer(answer) then
    return nil, nil, nil
  end

  return answer.craftingQuality, answer.concentrationCost, answer.concentrationCurrencyID
end

ns.ReachQuery = ReachQuery
return ReachQuery
