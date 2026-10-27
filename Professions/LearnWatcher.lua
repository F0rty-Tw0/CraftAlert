local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")
local Index = ns.Index or require("CraftAlert.Model.Index")

-- Spec §5.3 (Retail, Forever): a recipe learned while playing is read and stored at once,
-- listening on, without opening its profession window. `learned` is never checked: it is
-- still false inside the event. Classic (InstallClassic): the learned name goes to the
-- session-only pending list, never to `recipes`; the next window open stores it.
local LearnWatcher = {}

local gsub = string.gsub
local match = string.match
local type = type

local EVENT = "NEW_RECIPE_LEARNED"
local SYSTEM_EVENT = "CHAT_MSG_SYSTEM"
-- Constants.flavors[...].learnSignal of the system-message signal, the one Classic ships.
local LEARN_BY_SYSTEM_MESSAGE = 1

-- Whether the last event stored a recipe, for the sim.
LearnWatcher.lastStored = nil
-- The name the last Classic learn added to the pending list, for the sim.
LearnWatcher.lastPending = nil

-- In an instance nothing runs: no profession API is asked and lastStored stays as it was. Any
-- learn makes the next window open read again, so a recipe stored here, or missed, is read there.
local function onLearned(recipeID)
  ModernReader.ForgetReads()
  if FlavorCompat.InInstance() then
    return
  end
  LearnWatcher.lastStored = false
  if FlavorCompat.issecretvalue(recipeID) then
    return
  end
  local professionKey = ModernReader.LearnKey(recipeID)
  if professionKey ~= nil then
    LearnWatcher.lastStored = ModernReader.ReadOne(recipeID, professionKey)
  end
end

function LearnWatcher.Install()
  EventRouter.On(EVENT, onLearned)
end

-- "You have learned how to create a new item: %s." → an anchored pattern capturing the %s.
local function learnPattern(format)
  local escaped = gsub(format, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  return "^" .. gsub(escaped, "%%%%s", "(.+)", 1) .. "$"
end

-- signal: the flavor's learnSignal. Only the system message is listened to; a client without
-- its global string, or with one that names no recipe, gets no listener.
function LearnWatcher.InstallClassic(signal)
  local format = _G["ERR_LEARN_RECIPE_S"]
  if signal ~= LEARN_BY_SYSTEM_MESSAGE or type(format) ~= "string" or not match(format, "%%s") then
    return
  end
  local pattern = learnPattern(format)
  EventRouter.On(SYSTEM_EVENT, function(text)
    if FlavorCompat.InInstance() then
      return
    end
    local name = match(text, pattern)
    if name ~= nil then
      LearnWatcher.lastPending = name
      Index.AddPending(name)
    end
  end)
end

ns.LearnWatcher = LearnWatcher
return LearnWatcher
