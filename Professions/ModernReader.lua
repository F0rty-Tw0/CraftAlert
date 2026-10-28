local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local BindLookup = ns.BindLookup or require("CraftAlert.Professions.BindLookup")
local RecipeStore = ns.RecipeStore or require("CraftAlert.Professions.RecipeStore")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local ReadJob = ns.ReadJob or require("CraftAlert.Professions.ReadJob")
local QualityReach = ns.QualityReach or require("CraftAlert.Professions.QualityReach")

-- Spec §5.2 row 1 (Retail, Forever): reads the learned recipes of the open profession
-- window into the current character's storage, as Slicer job "read" (spec 2026-10-22
-- §4.2). Guards skip other players' lists and special modes, a window of a profession the
-- character does not store (Cooking, Smelting) stores nothing, and reads only add. A job cut
-- off by a closed or switched window is kept and resumes when the same window reopens.
-- LearnKey and ReadOne serve the learn path (§5.3), with or without the window open.
local ModernReader = {}

local ipairs = ipairs
local type = type

local SHOW_EVENT = "TRADE_SKILL_SHOW"
local CLOSE_EVENT = "TRADE_SKILL_CLOSE"
local UPDATE_EVENT = "TRADE_SKILL_LIST_UPDATE"
local JOB_NAME = "read"
local GUARDS = { "IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsRuneforging" }

local db = nil
local reads = {} -- by profession: { count, settled } of the last read that stored a recipe for it
local windowOpen = false
local activeJob = nil -- the job last started; running only while Slicer.IsRunning(JOB_NAME)
local keptJob = nil -- a job its window cut off; the same key and recipe count resume it

-- The last window read, for the sim and /ca perf: { prof, stored, pendingBind, ms, steps }.
ModernReader.lastRead = nil

function ModernReader.Install(accountDb)
  db = accountDb
  BindLookup.Configure(accountDb)
  EventRouter.On(SHOW_EVENT, ModernReader.OnShow)
  EventRouter.On(CLOSE_EVENT, ModernReader.OnClose)
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

-- True while the open window is one the reader must not touch (NPC, guild, linked, runeforging).
function ModernReader.IsBlocked()
  local api = tradeSkillApi()
  return api ~= nil and isBlocked(api)
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

-- The expansion's skill line of a recipe: the ProfessionInfo's own professionID, only when it
-- names a child of a profession (non-zero parent) and is loaded (non-zero). A bare or unloaded
-- answer gives nil.
local function lineOf(profInfo)
  local parent = profInfo and profInfo.parentProfessionID
  local line = profInfo and profInfo.professionID
  if type(parent) == "number" and parent ~= 0 and type(line) == "number" and line ~= 0 then
    return line
  end
  return nil
end

-- → { item, ranks, name, line } of a usable recipe (usableInfo); `profInfo` is its
-- GetProfessionInfoByRecipeID answer, nil when there was none.
local function readFields(api, recipeID, info, profInfo)
  local schematic = api.GetRecipeSchematic(recipeID, false)
  -- Blizzard's spelling: the greeting names the recipe with it; Index lowercases for matching.
  return { item = schematic and schematic.outputItemID, ranks = copyList(info.qualityItemIDs), name = info.name, line = lineOf(profInfo) }
end

-- → changed, and queues the bind lookup when the output item's bind is unknown.
local function store(recipes, recipeID, fields, professionKey)
  local changed = RecipeStore.Merge(recipes, recipeID, fields, professionKey)
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

-- Mid-switch the list may still hold another profession's recipes: each is stored under its
-- own profession when the character stores that one, and skipped (nil) otherwise. A recipe
-- with no profession info (nil, or 0 before the data loads) belongs to the window, and so
-- does one answered with a bare skill line the character does not store: like the foreign-drop phase,
-- only a parented answer proves another profession.
-- → the key to store under (nil: skip), whether the recipe's own lookup named the window, and
-- that lookup's answer (the expansion line is read from it: no second call).
local function storeKey(charKey, recipeID, key)
  local info = professionInfo(recipeID)
  local parent = info and info.parentProfessionID
  local own = parent or (info and info.professionID)
  if own == key then
    return key, true, info
  end
  if own == nil or own == 0 then
    return key, false, info
  end
  if ProfessionList.IsStored(db, charKey, own) then
    return own, false, info
  end
  return parent == nil and key or nil, false, info
end

local function inWindowList(api, recipeID)
  for _, id in ipairs(api.GetAllRecipeIDs() or {}) do
    if id == recipeID then
      return true
    end
  end
  return false
end

-- The key a learned recipe is stored under (nil: skip). When an unblocked window of a stored
-- profession lists the recipe, storeKey's rule decides, so a parentless or unloaded answer
-- belongs to the window as in a window read; otherwise the recipe's base profession: the parent
-- skill line when there is one, else the skill line itself. A recipe the window does not list
-- borrows nothing from it: a bare Cooking line or a 0 then stores nothing.
function ModernReader.LearnKey(recipeID)
  local api = tradeSkillApi()
  local usable = windowOpen and db ~= nil and api ~= nil and not isBlocked(api)
  local key = usable and windowProfession(api) or nil
  if key ~= nil and inWindowList(api, recipeID) then
    return (storeKey(PlayerName.Own(), recipeID, key))
  end
  local info = professionInfo(recipeID)
  return info and (info.parentProfessionID or info.professionID) or nil
end

local OPS = {
  usableInfo = usableInfo,
  storeKey = storeKey,
  readFields = readFields,
  store = store,
  professionInfo = professionInfo,
}

-- → the trade skill api while the job's window is still open, unblocked and on its profession.
local function windowApiFor(job)
  local api = tradeSkillApi()
  if not windowOpen or api == nil or isBlocked(api) then
    return nil
  end
  return windowProfession(api) == job.key and api or nil
end

local function finishRead(job)
  ModernReader.lastRead = ReadJob.Finish(job)
  if job.readKeys[job.key] then
    reads[job.key] = { count = #job.recipeIDs, settled = job.named and not job.lineless and not job.learnedDuring }
  end
  if job.anyChanged then
    Index.RequestRebuild("read")
  end
  QualityReach.Queue(job.storedIDs)
end

-- One Slicer step. A window that closed, got blocked or switched profession keeps the job for
-- a resume and cancels it. → whether the job is done.
local function runStep(job)
  local api = windowApiFor(job)
  if api == nil then
    keptJob = job
    Slicer.Cancel(JOB_NAME)
    return false
  end
  local done = ReadJob.Step(job, api)
  if done then
    finishRead(job)
  end
  return done
end

local function newJob(key, recipeIDs)
  local job = ReadJob.New({ db = db, charKey = PlayerName.Own(), key = key, recipeIDs = recipeIDs, ops = OPS })
  job.step = function()
    return runStep(job)
  end
  -- A job cut off by a close, a guard, a replacing job or an error: what it stored so far goes
  -- to the index.
  job.onCancel = function()
    if job.anyChanged then
      job.anyChanged = false
      Index.RequestRebuild("read")
    end
  end
  return job
end

local function matches(job, key, count)
  return job ~= nil and job.key == key and #job.recipeIDs == count
end

-- A list update while the data source is rebuilding is yielded; a later update brings the
-- finished list.
local function isDataSourceChanging(api)
  local changing = api.IsDataSourceChanging
  return type(changing) == "function" and changing() == true
end

-- force: the window was just opened. An update starts a read only when the profession or the
-- recipe count differs from the running job, or from the last read that stored a recipe for
-- that profession. An open skips the walk too when that read was settled (a loaded answer named
-- the profession and every stored recipe has its line) and the character still stores recipes
-- for it; the reach job is queued instead. A kept job with the same profession and count
-- resumes instead of starting over. Nothing is read in an instance.
local function onWindowEvent(force)
  if FlavorCompat.InInstance() then
    return
  end
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
  local count = #recipeIDs
  local running = Slicer.IsRunning(JOB_NAME) and activeJob or nil
  if matches(running, key, count) then
    return
  end
  local resumable = matches(keptJob, key, count)
  local last = reads[key]
  local lastReadAgain = last ~= nil and last.count == count
  if running == nil and not resumable and lastReadAgain then
    if not force then
      return
    end
    if last.settled then
      local ids = ReadJob.RecipeIDsOf(db.characters[PlayerName.Own()], key)
      if #ids > 0 then
        QualityReach.Queue(ids)
        return
      end
    end
  end
  local job = resumable and keptJob or newJob(key, recipeIDs)
  keptJob, activeJob = nil, job
  Slicer.Start(JOB_NAME, job)
end

function ModernReader.OnShow()
  windowOpen = true
  onWindowEvent(true)
end

function ModernReader.OnClose()
  windowOpen = false
end

-- A learn keeps the window's recipe count the same, and the learn path may not have stored the
-- recipe (its data not loaded yet, or in an instance): the next open of any window reads again.
-- A running or kept job may have walked past that recipe, so its finish settles nothing. A kept
-- job is always activeJob: only the running job keeps itself, and each start clears keptJob.
function ModernReader.ForgetReads()
  reads = {}
  if activeJob ~= nil then
    activeJob.learnedDuring = true
  end
end

function ModernReader.OnListUpdate()
  onWindowEvent(false)
end

-- §10.2 CraftScan import: the stored fields of any recipe, an alt's included (`learned` is not
-- checked: it describes the logged-in character), after the §5.2 drops → { item, ranks, name,
-- line } and its GetProfessionInfoByRecipeID answer, or nil.
function ModernReader.FieldsOf(recipeID)
  local api = tradeSkillApi()
  local info = api and usableInfo(api, recipeID, false)
  if info == nil then
    return nil
  end
  local profInfo = professionInfo(recipeID)
  return readFields(api, recipeID, info, profInfo), profInfo
end

-- A newly learned recipe of an older line starts muted when the profession has a newestLine and
-- the recipe's ID is at or below that line's median rank; a stray high-ID one stays unmuted.
local function muteIfOlder(character, recipeID, professionKey, line)
  local record = character.professions[professionKey]
  local newest = record and record.newestLine
  if newest == nil or line == nil or line == newest then
    return
  end
  local rank = RecipeStore.LineRank(character.recipes, professionKey, newest)
  if rank and recipeID <= rank then
    character.recipes[recipeID].muted = true
  end
end

-- Reads one learned recipe (§5.3), the window open or not → whether it is now stored.
function ModernReader.ReadOne(recipeID, professionKey)
  local api = tradeSkillApi()
  if api == nil or db == nil or not ProfessionList.IsStored(db, PlayerName.Own(), professionKey) then
    return false
  end
  local info = usableInfo(api, recipeID, false)
  if info == nil then
    return false
  end
  local fields = readFields(api, recipeID, info, professionInfo(recipeID))
  local character = db.characters[PlayerName.Own()]
  local recipes = character.recipes
  local isNew = recipes[recipeID] == nil
  local changed = store(recipes, recipeID, fields, professionKey)
  if isNew and changed then
    muteIfOlder(character, recipeID, professionKey, fields.line)
  end
  if changed then
    Index.RequestRebuild("learn")
  end
  QualityReach.Queue({ recipeID })
  return true
end

ns.ModernReader = ModernReader
return ModernReader
