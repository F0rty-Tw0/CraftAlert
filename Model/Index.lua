local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local ItemKeywords = ns.ItemKeywords or require("CraftAlert.Model.ItemKeywords")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")
local Aliases = ns.Aliases or require("CraftAlert.Model.Aliases")
local TypoPass = ns.TypoPass or require("CraftAlert.Model.TypoPass")
local WordGroups = ns.WordGroups or require("CraftAlert.Model.WordGroups")

-- Spec §6.2: everything the hot path (§6.3 steps 1-4) reads, built in one pass from the
-- enabled crafters' listening recipes and the settings, so a chat line never reads
-- CraftAlertDB. Build may allocate and call the item API; it never runs per line. Phrase
-- records, aliases and the join and stat + slot structures come from Aliases, typo targets
-- from TypoPass, the step 4.4 group structures from WordGroups.
-- A rebuild request runs Build as the Slicer job "index", a coroutine that yields at pause
-- points, so a rebuild after login takes no long frame; the Slicer waits out combat (§4.3 rule
-- 1, §4.4 rule 6). Login's Rebuild stays synchronous (spec 2026-10-26-sliced-index-build).
local Index = {}

local pairs = pairs
local ipairs = ipairs
local type = type
local lower = string.lower
local sort = table.sort

local JOB = "index"

local function append(map, key, value)
  local list = map[key]
  if list == nil then
    map[key] = { value }
  elseif list[#list] ~= value then -- an item that is also one of its ranks is listed once
    list[#list + 1] = value
  end
end

-- Names go to Aliases.Build after every recipe is seen (kind c needs all names).
local function addName(ctx, name, entry, pending)
  ctx.names[#ctx.names + 1] = { name = name, entry = entry, pending = pending }
end

local function addItem(index, ctx, itemID, entry)
  append(index.itemIndex, itemID, entry)
  local words = ctx.words[itemID]
  if words == nil then
    local worn
    words, worn = ItemKeywords.WordsFor(itemID, ctx.settings.extraSlang)
    ctx.words[itemID] = words
    if worn and #words == 0 then
      index.wordlessGear[entry.group] = true -- the group is the item, so once per group
    end
  end
  for _, word in ipairs(words) do
    append(index.wordIndex, word, entry)
  end
end

local function sameEntries(a, b)
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

-- User ruling 2026-10-24 ("Share synonym lists"): words whose lists hold the same entries in
-- the same order (a slot's synonyms, an extraSlang key and its target) become one table, so
-- the index and WordGroups' per-list data are held once. A hash of the entries finds the
-- candidates; a collision just leaves a list unshared. Lists are read-only after the build.
local function shareLists(wordIndex, pause)
  local ids, count, shared = {}, 0, {}
  for word, list in pairs(wordIndex) do
    local hash = #list
    for i = 1, #list do
      local entry = list[i]
      local id = ids[entry]
      if id == nil then
        count = count + 1
        id = count
        ids[entry] = id
      end
      hash = (hash * 31 + id) % 2147483647
    end
    local first = shared[hash]
    if first == nil then
      shared[hash] = list
    elseif first ~= list and sameEntries(first, list) then
      wordIndex[word] = first
    end
    pause(#list)
  end
end

local function indexed(recipe, includeUnbound)
  if recipe.muted then
    return false
  end
  return includeUnbound or recipe.bind ~= 0
end

local function addRecipe(index, ctx, character, recipeKey, recipe)
  local name = lower(recipe.name)
  local entry = { character = character, recipeKey = recipeKey, group = recipe.item or name, prof = recipe.prof }
  if recipe.item then
    addItem(index, ctx, recipe.item, entry)
  end
  for _, rank in ipairs(recipe.ranks or {}) do
    append(index.itemIndex, rank, entry)
  end
  addName(ctx, name, entry, nil)
  index.size = index.size + 1
end

-- The professions of which the character stores recipes and has muted every one (unbound
-- recipes count as listening), so CrafterRank skips it without walking its recipes.
local function noteMuted(index, key, stored, listening)
  for prof in pairs(stored) do
    if not listening[prof] then
      local muted = index.mutedProfessions[key] or {}
      muted[prof] = true
      index.mutedProfessions[key] = muted
    end
  end
end

-- → whether the character added at least one entry. The recipe keys are copied first (pairs
-- order), so no db table is traversed across a pause; a recipe gone by then is skipped.
local function addCharacter(index, ctx, key, character, pause)
  for profKey in pairs(character.professions or {}) do
    ctx.professions[profKey] = true
  end
  local recipes, keys = character.recipes or {}, {}
  for recipeKey in pairs(recipes) do
    keys[#keys + 1] = recipeKey
  end
  local added, stored, listening = false, {}, {}
  for i = 1, #keys do
    local recipeKey = keys[i]
    local recipe = recipes[recipeKey]
    if recipe ~= nil then
      local prof = recipe.prof
      if prof ~= nil then
        stored[prof] = true
        listening[prof] = listening[prof] or not recipe.muted
      end
      if indexed(recipe, ctx.settings.includeUnbound) then
        addRecipe(index, ctx, key, recipeKey, recipe)
        added = true
      end
    end
    pause()
  end
  noteMuted(index, key, stored, listening)
  return added
end

-- §5.3: session-only Classic learns match by name, crafted by the current character, in the
-- group an alt stores that name under (its item ID: one recipe in step 4.4), else the name.
local function addPending(index, ctx, own, pending, pause)
  local ownRecipes = own and own.recipes or {}
  local added, storedGroup = false, {}
  if pending[1] then
    for _, item in ipairs(ctx.names) do
      storedGroup[item.name] = storedGroup[item.name] or item.entry.group
      pause()
    end
  end
  for _, name in ipairs(pending) do
    if ownRecipes[name] == nil then
      local entry = { character = index.ownName, recipeKey = name, group = storedGroup[name] or name }
      addName(ctx, name, entry, true)
      index.size = index.size + 1
      added = true
    end
    pause()
  end
  return added
end

local function addProfessionWords(index, professions)
  for _, entry in ipairs(ProfessionWords.entries) do
    local key = FlavorCompat.isClassic and entry.englishName or entry.skillLineID
    if professions[key] then
      for _, word in ipairs(entry.words) do
        index.professionWords[word] = key
      end
    end
  end
end

-- Lowercase, non-empty, first occurrence only.
local function wordList(words)
  local list, set = {}, {}
  for _, word in ipairs(words or {}) do
    if type(word) == "string" and word ~= "" then
      word = lower(word)
      if not set[word] then
        set[word] = true
        list[#list + 1] = word
      end
    end
  end
  return list, set
end

local function copySet(map)
  local copy = {}
  for key, value in pairs(map or {}) do
    copy[key] = value
  end
  return copy
end

local function newIndex(settings, opts)
  local intentList, intentSet = wordList(settings.intentWords)
  local _, blockerSet = wordList(settings.blockerWords)
  return {
    itemIndex = {},
    nameIndex = {},
    wordIndex = {},
    wordlessGear = {}, -- group -> true: a worn item without words (profession gear), read by WordGroups.Build
    professionWords = {},
    mutedProfessions = {}, -- characterKey -> { professionKey -> true }: every stored recipe muted
    channelEnabled = copySet(settings.channels),
    intentList = intentList,
    intentSet = intentSet,
    blockerSet = blockerSet,
    professionOrder = opts.professionOrder and opts.professionOrder() or {},
    professionWordAlerts = settings.professionWordAlerts == true,
    ownName = opts.ownKey,
    extraSlang = settings.extraSlang or {}, -- WordGroups.Build reads it (R2: slot-word keys)
    armorTags = ItemKeywords.ArmorTags(settings.extraSlang), -- §4 rule 1 tags (class-armor spec), read by step 4.4
    size = 0,
    crafterCount = 0,
  }
end

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  sort(keys)
  return keys
end

-- Pure: reads db and settings, writes neither. opts = { professionOrder = fn → key[],
-- ownKey = "Name-Realm", pending = { lowerName, ... }, pause = fn(weight) }. pause runs inside the
-- long loops (the sliced build yields there); weight (default 1) is the loop body's work, such as
-- a list's length; a no-op when absent.
function Index.Build(db, settings, opts)
  opts = opts or {}
  local pause = opts.pause or Slicer.NoPause
  local index = newIndex(settings, opts)
  local ctx = { settings = settings, names = {}, words = {}, professions = {} }
  local characters = db.characters or {}
  local crafters = {}
  -- Sorted, so entry lists come out in the same order on every build.
  for _, key in ipairs(sortedKeys(characters)) do
    local character = characters[key]
    if character and character.enabled ~= false and addCharacter(index, ctx, key, character, pause) then
      crafters[key] = true
      index.crafterCount = index.crafterCount + 1
    end
  end
  local ownKey = opts.ownKey
  local own = ownKey and characters[ownKey]
  local ownEnabled = not (own and own.enabled == false)
  if ownKey and ownEnabled and addPending(index, ctx, own, opts.pending or {}, pause) and not crafters[ownKey] then
    index.crafterCount = index.crafterCount + 1
  end
  shareLists(index.wordIndex, pause)
  addProfessionWords(index, ctx.professions)
  Aliases.Build(index, ctx.names, pause)
  TypoPass.Build(index)
  WordGroups.Build(index, pause)
  return index
end

-- Rebuild context and state.
local context = nil
local current = nil
local rebuilt = {}
local pendingNames = {}
local pendingSet = {} -- lowercase name -> the client's spelling

Index.lastBuildMs = nil -- CPU ms of the last build: the sum of its steps
Index.lastBuildSteps = nil -- Slicer steps of the last build; 1 for a synchronous one
Index.lastReason = nil

function Index.Configure(db, opts)
  context = { db = db, opts = opts or {} }
end

function Index.Current()
  return current
end

-- Called with the new index after every build, in subscription order; one that raises is
-- reported and the rest still run.
function Index.OnRebuilt(fn)
  rebuilt[#rebuilt + 1] = fn
end

local function buildOpts(opts, pause)
  return {
    professionOrder = opts.professionOrder,
    ownKey = opts.ownKey or PlayerName.Own(),
    pending = pendingNames,
    pause = pause,
  }
end

local function swapIn(index, ms, steps)
  Index.lastBuildMs, Index.lastBuildSteps = ms, steps
  current = index
  EventRouter.CallAll(rebuilt, index)
end

-- Synchronous build from the configured context (login); cancels a running sliced build. nil
-- before Configure.
function Index.Rebuild()
  if context == nil then
    return nil
  end
  Slicer.Cancel(JOB)
  local clock = _G["debugprofilestop"]
  local started = clock()
  local index = Index.Build(context.db, context.db.settings, buildOpts(context.opts))
  swapIn(index, clock() - started, 1)
  return index
end

-- The sliced build runs through Slicer.Run, which yields at the pause points and carries a step
-- error's coroutine stack. An abandoned coroutine (the job restarted or cancelled) is never
-- resumed, so StatSlot.Begin's reset holds for the next. A subscriber may request a rebuild
-- from swapIn: the new job replaces this one under the same name and runs on.
local function startJob(db, opts)
  local run
  run = Slicer.Run(JOB, function(pause)
    return Index.Build(db, db.settings, buildOpts(opts, pause))
  end, function(index)
    swapIn(index, run.ms, run.steps)
  end)
end

-- Starts the sliced build, or restarts it: the db may have changed under a half-built index,
-- so a request during a build drops that work. The old index stays live until a build ends.
function Index.RequestRebuild(reason)
  Index.lastReason = reason
  if context ~= nil then
    startJob(context.db, context.opts)
  end
end

-- §5.3 Classic session learn: a recipe name as the client spells it, matched by its lowercase
-- copy until logout.
function Index.AddPending(name)
  local lowerName = lower(name)
  if not pendingSet[lowerName] then
    pendingSet[lowerName] = name
    pendingNames[#pendingNames + 1] = lowerName
  end
  Index.RequestRebuild("learn")
end

-- The client's spelling of a pending recipe key (the first learn's), or nil.
function Index.PendingName(recipeKey)
  return pendingSet[recipeKey]
end

ns.Index = Index
return Index
