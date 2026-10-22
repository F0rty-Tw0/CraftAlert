local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local ReachQuery = ns.ReachQuery or require("CraftAlert.Professions.ReachQuery")

-- Spec 2026-10-22-crafter-quality-rank §4.3: Slicer job "reach" asks the game, per recipe of
-- the current character, which quality rank the best reagents reach and what the next rank
-- costs in concentration, and saves the answer on the recipe. The character's concentration
-- currencies are snapshotted at login, logout and after each finished pass. Does nothing on
-- clients without the operation API (Classic, Forever).
local QualityReach = {}

local ipairs = ipairs
local pairs = pairs
local remove = table.remove
local select = select
local type = type

local JOB_NAME = "reach"

local db = nil
local pending = {} -- recipe IDs in queue order
local seen = {} -- IDs queued since the pass started

local function areNumbers(...)
  for i = 1, select("#", ...) do
    if type((select(i, ...))) ~= "number" then
      return false
    end
  end

  return true
end

local function hasFunction(owner, name)
  return type(owner) == "table" and type(owner[name]) == "function"
end

function QualityReach.Available()
  local enum = _G["Enum"]
  local hasOperation = hasFunction(_G["C_TradeSkillUI"], "GetCraftingOperationInfo")
  local hasCurrency = hasFunction(_G["C_CurrencyInfo"], "GetCurrencyInfo")
  local hasSlotTypes = type(enum) == "table" and type(enum.TradeskillSlotDataType) == "table"

  return hasOperation and hasCurrency and hasSlotTypes
end

local function characterRecord()
  return db and db.characters[PlayerName.Own()]
end

local function snapshotOf(info)
  if type(info) ~= "table" then
    return nil
  end
  local snapshot = {
    amount = info.quantity,
    at = _G["time"](),
    cycleMs = info.rechargingCycleDurationMS,
    perCycle = info.rechargingAmountPerCycle,
    max = info.maxQuantity,
  }
  local isValid = areNumbers(snapshot.amount, snapshot.cycleMs, snapshot.perCycle, snapshot.max) and snapshot.cycleMs > 0

  return isValid and snapshot or nil
end

function QualityReach.SaveConcentration()
  local character = characterRecord()
  if character == nil or not QualityReach.Available() then
    return
  end
  local done = {}
  for _, recipe in pairs(character.recipes) do
    local currencyID = recipe.reachConc
    if currencyID and not done[currencyID] then
      done[currencyID] = true
      local snapshot = snapshotOf(_G["C_CurrencyInfo"].GetCurrencyInfo(currencyID))
      if snapshot then
        character.concentration = character.concentration or {}
        character.concentration[currencyID] = snapshot
      end
    end
  end
end

-- One Slicer step: the next queued recipe. → whether the queue is empty.
local function step()
  local recipeID = remove(pending, 1)
  local character = characterRecord()
  local recipe = character and character.recipes[recipeID]
  if recipe then
    recipe.reachRank, recipe.reachCost, recipe.reachConc = ReachQuery.Ask(recipeID, recipe)
  end
  if #pending > 0 then
    return false
  end
  seen = {}
  QualityReach.SaveConcentration()

  return true
end

function QualityReach.Queue(recipeIDs)
  if db == nil or not QualityReach.Available() then
    return
  end
  for _, recipeID in ipairs(recipeIDs) do
    if not seen[recipeID] then
      seen[recipeID] = true
      pending[#pending + 1] = recipeID
    end
  end
  if #pending > 0 and not Slicer.IsRunning(JOB_NAME) then
    Slicer.Start(JOB_NAME, { step = step })
  end
end

function QualityReach.Install(accountDb)
  if not QualityReach.Available() then
    return
  end
  db = accountDb
  EventRouter.On("PLAYER_LOGOUT", QualityReach.SaveConcentration)
  QualityReach.SaveConcentration()
end

ns.QualityReach = QualityReach
return QualityReach
