local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local BindLookup = ns.BindLookup or require("CraftAlert.Professions.BindLookup")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local ReadJob = ns.ReadJob or require("CraftAlert.Professions.ReadJob")
local QualityReach = ns.QualityReach or require("CraftAlert.Professions.QualityReach")

-- Spec §5.2 row 1 (Retail, Forever): reads the learned recipes of the open profession
-- window into the current character's storage, as Slicer job "read" (spec 2026-10-22
-- §4.2). Guards skip other players' lists and special modes, a window of a profession the
-- character does not store (Cooking, Smelting) stores nothing, and reads only add. A job cut
-- off by a closed or switched window is kept and resumes when the same window reopens.
-- ReadOne serves the learn path (§5.3) with the window closed.
local ModernReader = {}

local ipairs = ipairs
local type = type

local SHOW_EVENT = "TRADE_SKILL_SHOW"
local CLOSE_EVENT = "TRADE_SKILL_CLOSE"
local UPDATE_EVENT = "TRADE_SKILL_LIST_UPDATE"
local JOB_NAME = "read"
local GUARDS = { "IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsRuneforging" }

local db = nil
local readKey = nil -- profession and recipe count of the window as last read
local readCount = nil
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
-- does one answered with a bare skill line the character does not store: like the foreign-drop phase,
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
    readKey, readCount = job.key, #job.recipeIDs
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
-- the window. A kept job with the same profession and count resumes instead of starting over.
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
  local count = #recipeIDs
  local running = Slicer.IsRunning(JOB_NAME) and activeJob or nil
  if matches(running, key, count) then
    return
  end
  local resumable = matches(keptJob, key, count)
  local lastReadAgain = key == readKey and count == readCount
  if running == nil and not force and not resumable and lastReadAgain then
    return
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
  QualityReach.Queue({ recipeID })
  return true
end

ns.ModernReader = ModernReader
return ModernReader
