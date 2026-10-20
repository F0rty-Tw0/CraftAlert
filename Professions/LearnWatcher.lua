local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")

-- Spec §5.3 (Retail, Forever): a recipe learned while playing is read and stored at once,
-- listening on, without opening its profession window. `learned` is never checked: it is
-- still false inside the event.
local LearnWatcher = {}

local EVENT = "NEW_RECIPE_LEARNED"

-- Whether the last event stored a recipe, for the sim.
LearnWatcher.lastStored = nil

-- The base profession of a recipe: the parent skill line when there is one.
local function professionOf(recipeID)
  local api = _G["C_TradeSkillUI"]
  local info = type(api) == "table" and api.GetProfessionInfoByRecipeID(recipeID) or nil
  return type(info) == "table" and (info.parentProfessionID or info.professionID) or nil
end

local function onLearned(recipeID)
  LearnWatcher.lastStored = false
  if FlavorCompat.issecretvalue(recipeID) then
    return
  end
  local professionKey = professionOf(recipeID)
  if professionKey ~= nil then
    LearnWatcher.lastStored = ModernReader.ReadOne(recipeID, professionKey)
  end
end

function LearnWatcher.Install()
  EventRouter.On(EVENT, onLearned)
end

ns.LearnWatcher = LearnWatcher
return LearnWatcher
