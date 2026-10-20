local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
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
-- Rebuild requests coalesce into one C_Timer.After(0) and wait out combat (§4.3 rule 1,
-- §4.4 rule 6).
local Index = {}

local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local type = type
local lower = string.lower
local sort = table.sort

local REGEN_EVENT = "PLAYER_REGEN_ENABLED"

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
    words = ItemKeywords.WordsFor(itemID, ctx.settings.extraSlang)
    ctx.words[itemID] = words
  end
  for _, word in ipairs(words) do
    append(index.wordIndex, word, entry)
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

-- → whether the character added at least one entry.
local function addCharacter(index, ctx, key, character)
  for profKey in pairs(character.professions or {}) do
    ctx.professions[profKey] = true
  end
  local added, stored, listening = false, {}, {}
  for recipeKey, recipe in pairs(character.recipes or {}) do
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
  noteMuted(index, key, stored, listening)
  return added
end

-- §5.3: session-only Classic learns match by name, crafted by the current character, in the
-- group an alt stores that name under (its item ID: one recipe in step 4.4), else the name.
local function addPending(index, ctx, own, pending)
  local ownRecipes = own and own.recipes or {}
  local added, storedGroup = false, {}
  if pending[1] then
    for _, item in ipairs(ctx.names) do
      storedGroup[item.name] = storedGroup[item.name] or item.entry.group
    end
  end
  for _, name in ipairs(pending) do
    if ownRecipes[name] == nil then
      local entry = { character = index.ownName, recipeKey = name, group = storedGroup[name] or name }
      addName(ctx, name, entry, true)
      index.size = index.size + 1
      added = true
    end
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

local function newIndex(db, settings, opts)
  local intentList, intentSet = wordList(settings.intentWords)
  local _, blockerSet = wordList(settings.blockerWords)
  return {
    itemIndex = {},
    nameIndex = {},
    wordIndex = {},
    professionWords = {},
    mutedProfessions = {}, -- characterKey -> { professionKey -> true }: every stored recipe muted
    blockSet = copySet(db.ignored),
    channelEnabled = copySet(settings.channels),
    intentList = intentList,
    intentSet = intentSet,
    blockerSet = blockerSet,
    professionOrder = opts.professionOrder and opts.professionOrder() or {},
    professionWordAlerts = settings.professionWordAlerts == true,
    ownName = opts.ownKey,
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
-- ownKey = "Name-Realm", pending = { lowerName, ... } }.
function Index.Build(db, settings, opts)
  opts = opts or {}
  local index = newIndex(db, settings, opts)
  local ctx = { settings = settings, names = {}, words = {}, professions = {} }
  local characters = db.characters or {}
  local crafters = {}
  -- Sorted, so entry lists come out in the same order on every build.
  for _, key in ipairs(sortedKeys(characters)) do
    local character = characters[key]
    if character.enabled ~= false and addCharacter(index, ctx, key, character) then
      crafters[key] = true
      index.crafterCount = index.crafterCount + 1
    end
  end
  local ownKey = opts.ownKey
  local own = ownKey and characters[ownKey]
  local ownEnabled = not (own and own.enabled == false)
  if ownKey and ownEnabled and addPending(index, ctx, own, opts.pending or {}) and not crafters[ownKey] then
    index.crafterCount = index.crafterCount + 1
  end
  addProfessionWords(index, ctx.professions)
  Aliases.Build(index, ctx.names)
  TypoPass.Build(index)
  WordGroups.Build(index)
  return index
end

-- Rebuild context and state.
local context = nil
local current = nil
local rebuilt = {}
local pendingNames = {}
local pendingSet = {}
local timerPending = false
local combatPending = false

Index.lastBuildMs = nil
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

local function reportError(err)
  local getHandler = _G["geterrorhandler"]
  if type(getHandler) == "function" then
    getHandler()(err)
  end
end

-- Synchronous build from the configured context; nil before Configure.
function Index.Rebuild()
  if context == nil then
    return nil
  end
  local clock = _G["debugprofilestop"]
  local started = clock()
  local opts = context.opts
  local index = Index.Build(context.db, context.db.settings, {
    professionOrder = opts.professionOrder,
    ownKey = opts.ownKey or PlayerName.Own(),
    pending = pendingNames,
  })
  Index.lastBuildMs = clock() - started
  current = index
  for i = 1, #rebuilt do
    local ok, err = pcall(rebuilt[i], index)
    if not ok then
      reportError(err)
    end
  end
  return index
end

local function inCombat()
  local fn = _G["InCombatLockdown"]
  return type(fn) == "function" and fn() == true
end

local function onRegenEnabled()
  EventRouter.Off(REGEN_EVENT, onRegenEnabled)
  combatPending = false
  Index.Rebuild()
end

local function deferToCombatEnd()
  combatPending = true
  EventRouter.On(REGEN_EVENT, onRegenEnabled)
end

local function runTimer()
  timerPending = false
  if inCombat() then
    deferToCombatEnd()
  else
    Index.Rebuild()
  end
end

function Index.RequestRebuild(reason)
  Index.lastReason = reason
  if timerPending or combatPending then
    return
  end
  if inCombat() then
    deferToCombatEnd()
    return
  end
  timerPending = true
  _G["C_Timer"].After(0, runTimer)
end

-- §5.3 Classic session learn: a lowercase recipe name, matched by name until logout.
function Index.AddPending(lowerName)
  if not pendingSet[lowerName] then
    pendingSet[lowerName] = true
    pendingNames[#pendingNames + 1] = lowerName
  end
  Index.RequestRebuild("learn")
end

ns.Index = Index
return Index
