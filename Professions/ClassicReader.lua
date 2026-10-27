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

-- Spec §5.2 row 2 (Era to MoP): reads the open TradeSkill window into the current character's
-- storage as Slicer job "read", one list row per step. The recipe key is the lowercase recipe
-- name; header and subheader rows, another player's list and a window of a profession the
-- character does not store are skipped, and reads only add. Watch serves CraftReader too, with
-- the Craft window's calls (row 3).
local ClassicReader = {}

local lower = string.lower
local match = string.match
local tonumber = tonumber
local type = type

local SKIPPED_KINDS = { header = true, subheader = true }

-- The window's events, job name and calls. row(index) → name, kind, link of one list row.
local TRADE_SKILL = {
  show = "TRADE_SKILL_SHOW",
  update = "TRADE_SKILL_UPDATE",
  close = "TRADE_SKILL_CLOSE",
  job = "read",
  line = "GetTradeSkillLine",
  count = "GetNumTradeSkills",
  linked = "IsTradeSkillLinked",
  row = function(index)
    local name, kind = _G["GetTradeSkillInfo"](index)
    return name, kind, _G["GetTradeSkillItemLink"](index)
  end,
}

-- The last TradeSkill window read, for the sim: { prof, stored, pendingBind, ms, steps }.
ClassicReader.lastRead = nil
-- The newer of the TradeSkill and Craft window reads, for /ca perf.
ClassicReader.newestRead = nil

-- → changed, and queues the bind lookup when the output item's bind is unknown.
local function store(recipes, recipeKey, fields, professionKey)
  local changed = RecipeStore.Merge(recipes, recipeKey, fields, professionKey)
  local recipe = recipes[recipeKey]
  if recipe.item and recipe.bind == nil then
    BindLookup.Queue(recipe.item)
    return changed, true
  end
  return changed, false
end

-- The open window's profession when the current character stores it: nil for another player's
-- list, Beast Training, Cooking, or a window not loaded yet ("UNKNOWN").
local function windowProfession(reader)
  local source = reader.source
  local linked = source.linked and _G[source.linked]
  if type(linked) == "function" and linked() then
    return nil
  end
  local getLine = _G[source.line]
  local name = type(getLine) == "function" and getLine() or nil
  local key = type(name) == "string" and lower(name) or nil
  if key ~= nil and ProfessionList.IsStored(reader.db, PlayerName.Own(), key) then
    return key
  end
  return nil
end

-- Only an item link names an output item: an enchant's |Henchant: link means none.
local function itemOf(link)
  return type(link) == "string" and tonumber(match(link, "|Hitem:(%d+)")) or nil
end

local function readRow(job)
  local name, kind, link = job.source.row(job.cursor)
  if type(name) ~= "string" or SKIPPED_KINDS[kind] then
    return
  end
  local recipes = job.db.characters[job.charKey].recipes
  -- The client's spelling: the greeting names the recipe with it; the key is lowercase.
  local changed, unknownBind = store(recipes, lower(name), { item = itemOf(link), name = name }, job.key)
  job.stored = job.stored + 1
  job.anyChanged = job.anyChanged or changed
  job.pendingBind = job.pendingBind + (unknownBind and 1 or 0)
end

-- Marks the profession read when the list held a recipe.
local function finish(reader, job)
  local result = { prof = job.key, stored = job.stored, pendingBind = job.pendingBind, ms = job.ms, steps = job.steps }
  if job.stored > 0 then
    job.db.characters[job.charKey].professions[job.key].read = true
  end
  reader.readKey, reader.readCount = job.key, job.count
  reader.owner.lastRead = result
  ClassicReader.newestRead = result
  if job.anyChanged then
    Index.RequestRebuild("read")
  end
end

-- One Slicer step. A window that closed or switched profession cancels the job. → whether the
-- job is done.
local function runStep(reader, job)
  if not reader.windowOpen or windowProfession(reader) ~= job.key then
    Slicer.Cancel(job.source.job)
    return false
  end
  local clock = _G["debugprofilestop"]
  local started = clock()
  if job.cursor <= job.count then
    readRow(job)
  end
  job.cursor = job.cursor + 1
  job.steps = job.steps + 1
  job.ms = job.ms + (clock() - started)
  local done = job.cursor > job.count
  if done then
    finish(reader, job)
  end
  return done
end

local function newJob(reader, key, count)
  local job = { db = reader.db, charKey = PlayerName.Own(), source = reader.source, key = key, count = count }
  job.cursor, job.stored, job.pendingBind, job.anyChanged, job.ms, job.steps = 1, 0, 0, false, 0, 0
  job.step = function()
    return runStep(reader, job)
  end
  -- A job cut off by a close, a switch, a restart or an error: what it stored so far goes to the
  -- index.
  job.onCancel = function()
    if job.anyChanged then
      job.anyChanged = false
      Index.RequestRebuild("read")
    end
  end
  return job
end

-- force: the window was just opened. An update starts a read only when the profession or the row
-- count differs from the running job, or from the last finished read; a running job with another
-- count restarts (reads only add, so a restart loses nothing). Nothing is read in an instance.
local function onWindowEvent(reader, force)
  if not reader.windowOpen or FlavorCompat.InInstance() then
    return
  end
  local getCount = _G[reader.source.count]
  local key = type(getCount) == "function" and windowProfession(reader) or nil
  if key == nil then
    return
  end
  local count = getCount() or 0
  local running = Slicer.IsRunning(reader.source.job) and reader.job or nil
  if running ~= nil and running.key == key and running.count == count then
    return
  end
  if running == nil and not force and key == reader.readKey and count == reader.readCount then
    return
  end
  reader.job = newJob(reader, key, count)
  Slicer.Start(reader.source.job, reader.job)
end

-- Reads the window `source` describes for `owner`, which gets the finished reads as lastRead.
function ClassicReader.Watch(owner, source, accountDb)
  local reader = { owner = owner, source = source, db = accountDb, windowOpen = false }
  BindLookup.Configure(accountDb)
  EventRouter.On(source.show, function()
    reader.windowOpen = true
    onWindowEvent(reader, true)
  end)
  EventRouter.On(source.update, function()
    onWindowEvent(reader, false)
  end)
  EventRouter.On(source.close, function()
    reader.windowOpen = false
    Slicer.Cancel(source.job)
  end)
end

function ClassicReader.Install(accountDb)
  ClassicReader.Watch(ClassicReader, TRADE_SKILL, accountDb)
end

ns.ClassicReader = ClassicReader
return ClassicReader
