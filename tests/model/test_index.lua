local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local CLASS_ARMOR = 4
local BS, ENCH, TAILOR = 164, 333, 197

-- itemID -> { equipLoc, classID, subclassID }, served through the C_Item stub.
local ITEMS = {
  [501] = { "INVTYPE_WAIST", CLASS_ARMOR, 4 }, -- plate belt
  [502] = { "INVTYPE_WRIST", CLASS_ARMOR, 4 }, -- plate bracers
  [503] = { "", 7, 0 }, -- trade goods: no words
  [504] = { "INVTYPE_HEAD", CLASS_ARMOR, 4 },
  [601] = { "INVTYPE_ROBE", CLASS_ARMOR, 1 },
}

local function load(flavor)
  Wow.reset()
  if flavor then
    Wow.flavor(flavor)
  end
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      local item = ITEMS[itemID]
      if not item then
        return nil
      end
      return itemID, "type", "subtype", item[1], 0, item[2], item[3]
    end,
  })
  for _, path in ipairs({ "Core.FlavorCompat", "Core.Constants", "Core.EventRouter", "Core.Slicer", "Core.PlayerName" }) do
    Fresh.require(path)
  end
  for _, path in ipairs({
    "Model.Tokenizer",
    "Model.Slang",
    "Model.ItemKeywords",
    "Model.ProfessionWords",
    "Model.StatSlot",
    "Model.MatchCandidates",
    "Model.PhraseMatch",
    "Model.Aliases",
    "Model.TypoPass",
    "Model.WordGroups",
  }) do
    Fresh.require(path)
  end
  local Defaults = Fresh.require("Persistence.Defaults")
  return Fresh.require("Model.Index"), Defaults
end

local function profession(name)
  return { name = name, primary = false, read = true }
end

local function fixtureDb(Defaults)
  local db = Defaults.Db()
  db.characters["Smith-Realm"] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = { [BS] = profession("Blacksmithing") },
    recipes = {
      [1001] = { item = 501, name = "Thick Plate Belt", prof = BS, bind = 1 },
      [1002] = { item = 502, ranks = { 502, 512 }, name = "Iron Bracers", prof = BS }, -- bind unknown
      [1003] = { item = 503, name = "Iron Bar Stack", prof = BS, bind = 0 }, -- unbound
      [1004] = { item = 504, name = "Muted Helm", prof = BS, bind = 1, muted = true },
    },
  }
  db.characters["Alt-Realm"] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = { [BS] = profession("Blacksmithing"), [ENCH] = profession("Enchanting") },
    recipes = {
      [1001] = { item = 501, name = "Thick Plate Belt", prof = BS, bind = 1 },
      [2001] = { name = "Enchant Bracer - Minor Health", prof = ENCH },
    },
  }
  db.characters["Off-Realm"] = {
    source = "import",
    enabled = false,
    realms = {},
    professions = { [TAILOR] = profession("Tailoring") },
    recipes = { [3001] = { item = 601, name = "Cloth Robe", prof = TAILOR, bind = 1 } },
  }
  return db
end

local function order()
  return { ENCH, BS }
end

local function build(Index, db, opts)
  opts = opts or {}
  opts.professionOrder = opts.professionOrder or order
  opts.ownKey = opts.ownKey or "Smith-Realm"
  return Index.Build(db, db.settings, opts)
end

local function characters(list)
  local names = {}
  for _, entry in ipairs(list or {}) do
    names[#names + 1] = entry.character
  end
  table.sort(names)
  return names
end

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, inner in pairs(value) do
    copy[key] = deepCopy(inner)
  end
  return copy
end

-- §5.2: bind 0 is left out unless "Include unbound items"; an unknown bind is indexed.
local function testUnboundFilter()
  local Index, Defaults = load()
  local db = fixtureDb(Defaults)
  local index = build(Index, db)
  Assert.equal(index.itemIndex[503], nil, "bind 0 excluded")
  Assert.equal(#index.itemIndex[502], 1, "nil bind included")
  Assert.equal(#index.itemIndex[501], 2, "bind 1 included")
  db.settings.includeUnbound = true
  Assert.equal(#build(Index, db).itemIndex[503], 1, "bind 0 with includeUnbound")
end

local function testMutedAndDisabledAbsent()
  local Index, Defaults = load()
  local index = build(Index, fixtureDb(Defaults))
  Assert.equal(index.itemIndex[504], nil, "muted")
  Assert.equal(index.nameIndex.muted, nil, "muted name")
  Assert.equal(index.itemIndex[601], nil, "disabled crafter")
  Assert.equal(index.nameIndex.cloth, nil, "disabled crafter name")
  Assert.equal(index.wordIndex.robe, nil, "disabled crafter words")
  Assert.equal(index.professionWords.tailor, nil, "disabled crafter profession")
  -- Smith: 1001, 1002; Alt: 1001, 2001.
  Assert.equal(index.size, 4)
  Assert.equal(index.crafterCount, 2)
end

-- A profession whose stored recipes are all muted is noted per character, for CrafterRank;
-- an unmuted unbound recipe (not indexed) still counts as listening.
local function testMutedProfessions()
  local Index, Defaults = load()
  local db = fixtureDb(Defaults)
  Assert.same(build(Index, db).mutedProfessions, {}, "every crafter has an unmuted recipe")
  local recipes = db.characters["Smith-Realm"].recipes
  recipes[1001].muted, recipes[1002].muted = true, true
  Assert.same(build(Index, db).mutedProfessions, {}, "the unbound recipe still listens")
  recipes[1003].muted = true
  Assert.same(build(Index, db).mutedProfessions, { ["Smith-Realm"] = { [BS] = true } })
  db.characters["Off-Realm"].recipes[3001].muted = true
  Assert.same(build(Index, db).mutedProfessions, { ["Smith-Realm"] = { [BS] = true } }, "disabled crafters are left out")
end

-- §6.2: one entry per recipe and character, referenced by every index.
local function testSharedEntry()
  local Index, Defaults = load()
  local index = build(Index, fixtureDb(Defaults))
  local fromItem = index.itemIndex[502][1]
  local fromRank = index.itemIndex[512][1]
  local fromName = index.nameIndex.iron[1]
  Assert.equal(fromName.phrase, "iron bracers")
  Assert.truthy(rawequal(fromName, index.phraseSet["iron bracers"]), "nameIndex and phraseSet share the record")
  Assert.truthy(rawequal(fromItem, fromName.entries[1]), "itemIndex and nameIndex share the entry")
  Assert.truthy(rawequal(fromItem, fromRank), "item and rank share the entry")
  Assert.truthy(rawequal(fromItem, index.wordIndex.bracers[1]), "wordIndex shares the entry")
  Assert.same(fromItem, { character = "Smith-Realm", recipeKey = 1002, group = 502, prof = BS })
end

local function testIndexes()
  local Index, Defaults = load()
  local db = fixtureDb(Defaults)
  db.settings.extraSlang = { cuffs = "bracers" }
  local index = build(Index, db)
  Assert.same(characters(index.itemIndex[501]), { "Alt-Realm", "Smith-Realm" })
  Assert.same(characters(index.wordIndex.plate), { "Alt-Realm", "Smith-Realm", "Smith-Realm" })
  Assert.same(characters(index.wordIndex.belt), { "Alt-Realm", "Smith-Realm" })
  Assert.same(characters(index.wordIndex.cuffs), { "Smith-Realm" })
  -- Class-armor spec §4 rule 1 tags; the extra slang word takes its target's tag.
  Assert.equal(index.armorTags.cuffs, "slot")
  Assert.equal(index.armorTags.plate, "type")
  -- Phrases are normalized like Tokenizer.normalized: runs of non-word characters -> one space.
  local enchant = index.nameIndex.enchant[1]
  Assert.equal(enchant.phrase, "enchant bracer minor health")
  Assert.equal(enchant.full, true)
  Assert.same(enchant.entries, { { character = "Alt-Realm", recipeKey = 2001, group = "enchant bracer - minor health", prof = ENCH } })
  -- §6.2 item 1: one record per phrase, shared by both characters; aliases follow the full name.
  local thick = index.nameIndex.thick[1]
  Assert.equal(thick.phrase, "thick plate belt")
  Assert.same(characters(thick.entries), { "Alt-Realm", "Smith-Realm" })
  Assert.truthy(index.phraseSet["thick plate belt"])
  Assert.equal(index.phraseSet["thick plate"], nil, "aliases are not in phraseSet")
  Assert.equal(index.nameIndex.thick[2].full, false)
  -- Only professions some enabled crafter has.
  Assert.equal(index.professionWords.bs, BS)
  Assert.equal(index.professionWords.enchanter, ENCH)
  Assert.equal(index.professionWords.alch, nil)
end

-- User ruling 2026-10-24 ("Share synonym lists"): words whose lists hold the same entries in
-- the same order (slot synonyms, an extraSlang key and its target) are one table, and so is
-- their derived step 4.4 info; a word with other entries keeps its own.
local function testSynonymListsShared()
  local Index, Defaults = load()
  local db = fixtureDb(Defaults)
  db.settings.extraSlang = { wristies = "bracers" }
  local index = build(Index, db)
  local words, info = index.wordIndex, index.wordInfo
  Assert.truthy(rawequal(words.bracers, words.bracer), "slot synonyms share one list")
  Assert.truthy(rawequal(words.bracers, words.wristies), "an extraSlang key shares its target's list")
  Assert.truthy(rawequal(words.belt, words.waist), "another slot's synonyms share theirs")
  Assert.truthy(rawequal(info.bracers, info.wristies), "and one wordInfo")
  Assert.falsy(rawequal(words.bracers, words.belt), "other entries, another list")
  Assert.falsy(rawequal(words.plate, words.belt), "a type word with more entries, another list")
  Assert.falsy(rawequal(info.plate, info.belt), "and another wordInfo")
  Assert.same(characters(words.wristies), { "Smith-Realm" })
end

local function testSettingsCopies()
  local Index, Defaults = load()
  local db = fixtureDb(Defaults)
  db.settings.intentWords = { "LF", "wtb", "", "lf" }
  db.settings.blockerWords = { "WTS" }
  db.settings.professionWordAlerts = false
  local index = build(Index, db)
  Assert.same(index.intentList, { "lf", "wtb" })
  Assert.same(index.intentSet, { lf = true, wtb = true })
  Assert.same(index.blockerSet, { wts = true })
  Assert.same(index.channelEnabled, db.settings.channels)
  Assert.falsy(rawequal(index.channelEnabled, db.settings.channels), "channels copied")
  Assert.same(index.professionOrder, { ENCH, BS })
  Assert.equal(index.professionWordAlerts, false)
  Assert.equal(index.ownName, "Smith-Realm")
end

-- Index.Build reads db and settings only.
local function testBuildIsPure()
  local Index, Defaults = load()
  local db = fixtureDb(Defaults)
  local before = deepCopy(db)
  build(Index, db)
  Assert.same(db, before)
end

-- Classic keys professions by lowercase English name (§5.1).
local function testClassicProfessionKeys()
  local Index, Defaults = load("tbc")
  local db = Defaults.Db()
  db.characters["Tai-Realm"] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = { tailoring = profession("Tailoring") },
    recipes = { ["bolt of linen cloth"] = { name = "bolt of linen cloth", prof = "tailoring" } },
  }
  local index = build(Index, db, { ownKey = "Tai-Realm" })
  Assert.equal(index.professionWords.tailor, "tailoring")
  Assert.equal(index.nameIndex.bolt[1].entries[1].group, "bolt of linen cloth")
end

local function testEmptyIndex()
  local Index, Defaults = load()
  local index = Index.Build(Defaults.Db(), Defaults.Settings(), {})
  Assert.equal(index.size, 0)
  Assert.equal(index.crafterCount, 0)
  Assert.same(index.professionOrder, {})
  Assert.same(index.professionWords, {})
end

local function configure(Index, Defaults)
  local db = fixtureDb(Defaults)
  Index.Configure(db, { professionOrder = order, ownKey = "Smith-Realm" })
  return db
end

local function testRebuild()
  local Index, Defaults = load()
  Assert.equal(Index.Rebuild(), nil, "not configured")
  Assert.equal(Index.Current(), nil)
  configure(Index, Defaults)
  local calls = {}
  Index.OnRebuilt(function(index)
    calls[#calls + 1] = { "first", index }
  end)
  Index.OnRebuilt(function(index)
    calls[#calls + 1] = { "second", index }
  end)
  local stamps = { 10, 17.5 }
  Wow.stub("debugprofilestop", function()
    return table.remove(stamps, 1)
  end)
  local index = Index.Rebuild()
  Assert.truthy(rawequal(Index.Current(), index))
  Assert.equal(index.size, 4)
  Assert.equal(Index.lastBuildMs, 7.5)
  Assert.equal(Index.lastBuildSteps, 1, "a synchronous build is one step")
  Assert.equal(#calls, 2)
  Assert.equal(calls[1][1], "first")
  Assert.equal(calls[2][1], "second")
  Assert.truthy(rawequal(calls[1][2], index) and rawequal(calls[2][2], index))
end

-- A callback that raises is reported through geterrorhandler; the ones after it still run.
local function testFailingCallback()
  local Index, Defaults = load()
  configure(Index, Defaults)
  local reported, after = {}, 0
  Wow.stub("geterrorhandler", function()
    return function(err)
      reported[#reported + 1] = err
    end
  end)
  Index.OnRebuilt(function()
    error("callback broke")
  end)
  Index.OnRebuilt(function()
    after = after + 1
  end)
  local index = Index.Rebuild()
  Assert.truthy(rawequal(Index.Current(), index))
  Assert.equal(after, 1)
  Assert.equal(#reported, 1)
  assert(string.find(tostring(reported[1]), "callback broke", 1, true), tostring(reported[1]))
end

local function countBuilds(Index)
  local builds = { n = 0 }
  Index.OnRebuilt(function()
    builds.n = builds.n + 1
  end)
  return builds
end

-- Review Focus 4: 30 requests in one frame -> one pending timer, one build.
local function testCoalescing()
  local Index, Defaults = load()
  configure(Index, Defaults)
  local builds = countBuilds(Index)
  for _ = 1, 30 do
    Index.RequestRebuild("learn")
  end
  Assert.equal(#Wow.timers, 1)
  Assert.equal(Wow.timers[1].delay, 0)
  Assert.equal(builds.n, 0, "nothing built before the timer")
  Wow.runTimers()
  Assert.equal(builds.n, 1)
  Assert.truthy(Index.Current())
  -- The next request after the build arms a new timer.
  Index.RequestRebuild("mute")
  Assert.equal(#Wow.timers, 1)
  Wow.runTimers()
  Assert.equal(builds.n, 2)
end

local function regenRegistered()
  for _, frame in ipairs(Wow.frames) do
    if frame:IsEventRegistered("PLAYER_REGEN_ENABLED") then
      return true
    end
  end
  return false
end

-- §4.4 rule 6: the index job waits out combat in the Slicer, which builds once on
-- PLAYER_REGEN_ENABLED and is registered for it only while waiting.
local function testCombatDeferral()
  local Index, Defaults = load()
  local Slicer = require("CraftAlert.Core.Slicer")
  configure(Index, Defaults)
  local builds = countBuilds(Index)
  Wow.combat = true
  for _ = 1, 5 do
    Index.RequestRebuild("bind")
  end
  Wow.runTimers()
  Assert.equal(builds.n, 0, "no build in combat")
  Assert.truthy(Slicer.IsRunning("index"), "the job waits")
  Assert.truthy(regenRegistered(), "PLAYER_REGEN_ENABLED registered")
  Wow.combat = false
  Wow.fireEvent("PLAYER_REGEN_ENABLED")
  Wow.runTimers()
  Assert.equal(builds.n, 1)
  Assert.falsy(regenRegistered(), "unregistered after the build")
  Wow.fireEvent("PLAYER_REGEN_ENABLED")
  Wow.runTimers()
  Assert.equal(builds.n, 1)
end

-- A job started out of combat whose tick comes in combat waits instead of building.
local function testCombatStartsBeforeTimer()
  local Index, Defaults = load()
  configure(Index, Defaults)
  local builds = countBuilds(Index)
  Index.RequestRebuild("read")
  Wow.combat = true
  Wow.runTimers()
  Assert.equal(builds.n, 0)
  Assert.truthy(regenRegistered())
  Wow.combat = false
  Wow.fireEvent("PLAYER_REGEN_ENABLED")
  Wow.runTimers()
  Assert.equal(builds.n, 1)
  Assert.equal(#Wow.timers, 0)
end

-- §5.3: Classic session learns go to nameIndex only, crafted by the own character.
local function testAddPending()
  local Index, Defaults = load("tbc")
  local db = Defaults.Db()
  Index.Configure(db, { professionOrder = order, ownKey = "Me-Realm" })
  Index.AddPending("enchant bracer - minor health")
  Index.AddPending("enchant bracer - minor health")
  Assert.equal(#Wow.timers, 1)
  Wow.runTimers()
  local index = Index.Current()
  Assert.equal(#index.nameIndex.enchant, 1, "added once")
  local pending = index.nameIndex.enchant[1]
  Assert.equal(pending.phrase, "enchant bracer minor health")
  Assert.same(pending.entries, { { character = "Me-Realm", recipeKey = "enchant bracer - minor health", group = "enchant bracer - minor health" } })
  Assert.same(index.nameIndex, { enchant = { pending } }, "full-name record only, no aliases")
  Assert.same(index.itemIndex, {})
  Assert.same(index.wordIndex, {})
  Assert.equal(index.size, 1)
  Assert.equal(index.crafterCount, 1)
end

-- A session learn of a recipe an alt stores joins the alt's group (its item ID), so the two
-- count as one recipe in step 4.4; a name nobody stores keeps the name as its group.
local function testPendingSharesStoredGroup()
  local Index, Defaults = load()
  local index = build(Index, fixtureDb(Defaults), { ownKey = "Me-Realm", pending = { "thick plate belt", "iron shield" } })
  local groups = {}
  for _, entry in ipairs(index.nameIndex.thick[1].entries) do
    groups[#groups + 1] = entry.character .. ":" .. tostring(entry.group)
  end
  Assert.same(groups, { "Alt-Realm:501", "Smith-Realm:501", "Me-Realm:501" })
  Assert.equal(index.nameIndex.iron[2].entries[1].group, "iron shield")
end

return function()
  testUnboundFilter()
  testMutedAndDisabledAbsent()
  testMutedProfessions()
  testSharedEntry()
  testIndexes()
  testSynonymListsShared()
  testSettingsCopies()
  testBuildIsPure()
  testClassicProfessionKeys()
  testEmptyIndex()
  testRebuild()
  testFailingCallback()
  testCoalescing()
  testCombatDeferral()
  testCombatStartsBeforeTimer()
  testAddPending()
  testPendingSharesStoredGroup()
  Wow.reset()
end
