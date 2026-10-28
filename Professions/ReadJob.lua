local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local RecipeStore = ns.RecipeStore or require("CraftAlert.Professions.RecipeStore")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")

-- The steps of ModernReader's Slicer job "read" (spec 2026-10-22 §4.2): phase 1 stores one
-- recipe per step, phase 2 drops one foreign recipe per step. ModernReader owns the window
-- state and the storing helpers; it hands them in as `ops` so this file holds only the walk.
local ReadJob = {}

local ipairs, pairs = ipairs, pairs

-- base: { db, charKey, key, recipeIDs, ops = { usableInfo, storeKey, readFields, store,
-- professionInfo } }. → the base table, with the walk's counters added (`lineless`: a stored
-- recipe had no expansion line; `newIDs`: the recipes this read stored first).
function ReadJob.New(base)
  base.phase = 1
  base.cursor = 1
  base.stored = 0
  base.pendingBind = 0
  base.anyChanged = false
  base.readKeys = {}
  base.named = false
  base.lineless = false
  base.storedIDs = {}
  base.newIDs = {}
  base.ms = 0
  base.steps = 0
  return base
end

-- The recipe IDs saved under a profession, copied so the walk never reads the live table.
local function recipeIDsOf(character, key)
  local ids = {}
  for recipeID, recipe in pairs(character.recipes) do
    if recipe.prof == key then
      ids[#ids + 1] = recipeID
    end
  end
  return ids
end

ReadJob.RecipeIDsOf = recipeIDsOf

-- Phase 1 unit: stores the recipe at the cursor when it is worth storing. Marks the job
-- `named` when the recipe's own lookup named the window's profession.
local function readRecipe(job, api, character)
  local ops = job.ops
  local recipeID = job.recipeIDs[job.cursor]
  local info = recipeID and ops.usableInfo(api, recipeID, true)
  if not info then
    return
  end
  local professionKey, ownNamed, profInfo = ops.storeKey(job.charKey, recipeID, job.key)
  job.named = job.named or ownNamed
  if not professionKey then
    return
  end
  local fields = ops.readFields(api, recipeID, info, profInfo)
  job.lineless = job.lineless or fields.line == nil
  local isNew = character.recipes[recipeID] == nil
  local changed, unknownBind = ops.store(character.recipes, recipeID, fields, professionKey)
  job.stored = job.stored + 1
  job.anyChanged = job.anyChanged or changed
  job.pendingBind = job.pendingBind + (unknownBind and 1 or 0)
  job.readKeys[professionKey] = true
  job.storedIDs[#job.storedIDs + 1] = recipeID
  if isNew then
    job.newIDs[#job.newIDs + 1] = recipeID
  end
end

-- Phase 2 unit: drops the saved recipe at the cursor when it is tagged with the window's
-- profession but its own lookup names a profession the character does not store. Only a
-- parented answer counts: a recipe the lookup does not resolve, or answers with a bare skill
-- line, is kept.
local function dropForeignRecipe(job, character)
  local recipeID = job.foreignIDs[job.cursor]
  local recipe = character.recipes[recipeID]
  if recipe == nil or recipe.prof ~= job.key then
    return
  end
  local info = job.ops.professionInfo(recipeID)
  local own = info and info.parentProfessionID
  local named = own ~= nil and own ~= 0 and own ~= job.key
  if named and not ProfessionList.IsStored(job.db, job.charKey, own) then
    character.recipes[recipeID] = nil
    job.anyChanged = true
  end
end

-- Moves the cursor on; phase 2 starts after the last recipe, only when some recipe's own
-- lookup named the window's profession: a lookup that resolves nothing (not loaded, or a
-- shape this code does not read) must never empty the saved data. → whether the job is done.
local function advance(job, character)
  job.cursor = job.cursor + 1
  if job.phase == 2 then
    return job.cursor > #job.foreignIDs
  end
  if job.cursor <= #job.recipeIDs then
    return false
  end
  if not job.named then
    return true
  end
  job.phase, job.cursor, job.foreignIDs = 2, 1, recipeIDsOf(character, job.key)
  return #job.foreignIDs == 0
end

-- Runs one unit of the walk. → whether the job is done.
function ReadJob.Step(job, api)
  local clock = _G["debugprofilestop"]
  local started = clock()
  local character = job.db.characters[job.charKey]
  if job.phase == 1 then
    readRecipe(job, api, character)
  else
    dropForeignRecipe(job, character)
  end
  local done = advance(job, character)
  job.steps = job.steps + 1
  job.ms = job.ms + (clock() - started)
  return done
end

-- Mutes the recipes this read first stored when their line is not `newest`. → whether any changed.
local function muteNewOlder(job, recipes, professionKey, newest)
  local changed = false
  for _, recipeID in ipairs(job.newIDs) do
    local recipe = recipes[recipeID]
    local older = recipe and recipe.prof == professionKey and recipe.line ~= nil and recipe.line ~= newest
    if older and not recipe.muted then
      recipe.muted = true
      changed = true
    end
  end
  return changed
end

-- Only the newest expansion line alerts. A first sight of a line, or a newer line than the
-- saved one, mutes every older recipe (the notice says so once); the same newest line mutes
-- just the recipes this read newly stored, so the player's own picks stay. A saved line with no
-- recipe left cannot be told "replaced", so it gets no notice. → whether any recipe changed.
local function applyNewest(job, professionKey)
  local character = job.db.characters[job.charKey]
  local recipes, record = character.recipes, character.professions[professionKey]
  local newest = record and RecipeStore.NewestLine(recipes, professionKey)
  if newest == nil then
    return false
  end
  local saved = record.newestLine
  record.newestLine = newest
  if saved == nil then
    return RecipeStore.OnlyNewest(recipes, professionKey, newest) > 0
  end
  if saved == newest or RecipeStore.LineRank(recipes, professionKey, saved) == nil then
    return muteNewOlder(job, recipes, professionKey, newest)
  end
  local changed = RecipeStore.OnlyNewest(recipes, professionKey, newest) > 0
  local expansion = RecipeStore.ExpansionName(newest) or Localization.Text("the newest expansion")
  ChatPrint.Line(Localization.Text("%s now alerts only for %s recipes.", record.name or "", expansion))
  return changed
end

-- Marks read only the professions that got a recipe, then applies only-newest to each.
-- → { prof, stored, pendingBind, ms, steps }.
function ReadJob.Finish(job)
  for professionKey in pairs(job.readKeys) do
    job.db.characters[job.charKey].professions[professionKey].read = true
    job.anyChanged = applyNewest(job, professionKey) or job.anyChanged
  end
  return { prof = job.key, stored = job.stored, pendingBind = job.pendingBind, ms = job.ms, steps = job.steps }
end

ns.ReadJob = ReadJob
return ReadJob
