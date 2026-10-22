local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local BS, ENCH, COOKING = 164, 333, 185
local CHAR = "Me-Realm"

-- What the reader handed QualityReach.Queue since the last setup.
local queued = {}

local function belt(id, item, extra)
  local recipe = { id = id, name = "Belt " .. id, item = item, learned = true }
  for key, value in pairs(extra or {}) do
    recipe[key] = value
  end
  return recipe
end

-- A logged-in "Me-Realm" with Blacksmithing and Enchanting, the Blacksmithing window open.
local function setup(flavor)
  local ns = Fixture.load(flavor)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  local state = ProfessionsRetail.install({
    slots = { { name = "Blacksmithing", skillLine = BS }, { name = "Enchanting", skillLine = ENCH } },
    base = BS,
  })
  ns.PlayerName.Init()
  local ProfessionList = Fresh.require("Professions.ProfessionList")
  Fresh.require("Professions.BindLookup")
  Fresh.require("Professions.ReadJob")
  queued = {}
  Fresh.require("Professions.QualityReach").Queue = function(recipeIDs)
    queued[#queued + 1] = recipeIDs
  end
  local Slicer = Fresh.require("Core.Slicer")
  local ModernReader = Fresh.require("Professions.ModernReader")
  local db = ns.Defaults.Db()
  ProfessionList.Refresh(db, CHAR)
  local run = { builds = 0, reasons = {} }
  ns.Index.Configure(db, {})
  ns.Index.OnRebuilt(function()
    run.builds = run.builds + 1
    run.reasons[#run.reasons + 1] = ns.Index.lastReason
  end)
  ModernReader.Install(db)
  return state, ModernReader, db, run, Slicer
end

local function recipesOf(db)
  return db.characters[CHAR].recipes
end

local function readFlow(flavor)
  local state, ModernReader, db, run, Slicer = setup(flavor)
  state.recipes = {
    belt(1, 100),
    belt(2, 200, { ranks = { 201, 202, 203 } }),
    { id = 3, name = "Enchant Bracer - Health", learned = true }, -- no output item
    belt(4, 400, { learned = false }),
    belt(5, 500, { isRecraft = true }),
    belt(6, 600, { isDummyRecipe = true }),
    belt(7, 700, { isSalvageRecipe = true }),
    belt(8, 800, { isGatheringRecipe = true }),
  }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.same(recipesOf(db), {
    [1] = { item = 100, name = "Belt 1", prof = BS },
    [2] = { item = 200, ranks = { 201, 202, 203 }, name = "Belt 2", prof = BS },
    [3] = { name = "Enchant Bracer - Health", prof = BS },
  }, flavor)
  Assert.equal(db.characters[CHAR].professions[BS].read, true)
  Assert.equal(db.characters[CHAR].professions[ENCH].read, false)
  Assert.same(state.requests, { 100, 200 }, "bind requested for items with an unknown bind")
  local lastRead = ModernReader.lastRead
  Assert.same({ lastRead.prof, lastRead.stored, lastRead.pendingBind }, { BS, 3, 2 }, flavor)
  Assert.equal(type(lastRead.ms), "number", flavor)
  Assert.equal(type(lastRead.steps), "number", flavor)
  Assert.equal(Wow.pendingTimers(0), 2, "the Slicer tick and one coalesced rebuild")
  Wow.runTimers()
  Assert.same(run.reasons, { "read" })
  Assert.equal(run.builds, 1)
  Assert.same(queued, { { 1, 2, 3 } }, "a finished read queues the stored IDs in read order")
end

-- Records the recipe IDs each GetRecipeInfo call gets and advances the profile clock past the
-- Slicer budget, so one tick reads exactly one recipe.
local function logRecipeReads()
  local api = _G["C_TradeSkillUI"]
  local original, calls = api.GetRecipeInfo, {}
  rawset(api, "GetRecipeInfo", function(id)
    calls[#calls + 1] = id
    Wow.clock.profile = Wow.clock.profile + 3
    return original(id)
  end)
  return calls
end

local function runOneTick()
  local timer = table.remove(Wow.timers, 1)
  timer.fn()
end

local function threeBelts()
  return { belt(1, 100), belt(2, 200), belt(3, 300) }
end

-- Opens the window, lets one tick read recipe 1 of 3, closes the window and lets the job notice.
local function closeMidRead()
  local state, _, db, _, Slicer = setup()
  state.recipes = threeBelts()
  local calls = logRecipeReads()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runOneTick()
  Wow.fireEvent("TRADE_SKILL_CLOSE")
  Wow.runTimers()
  return state, db, Slicer, calls
end

local function jobCases()
  -- Close mid-read keeps what was stored and marks nothing read; reopening resumes at the cursor.
  local _, db, Slicer, calls = closeMidRead()
  Assert.same(queued, {}, "a cut-off read queues no reach")
  Assert.truthy(recipesOf(db)[1])
  Assert.equal(recipesOf(db)[2], nil)
  Assert.equal(db.characters[CHAR].professions[BS].read, false, "a cut-off read marks nothing read")
  Assert.equal(Slicer.IsRunning("read"), false)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[3])
  Assert.equal(db.characters[CHAR].professions[BS].read, true)
  Assert.same(calls, { 1, 2, 3 }, "recipe 1 is not read again")
  Assert.same(queued, { { 1, 2, 3 } }, "reach waits for the resumed read to finish")

  -- A guard or a profession switch mid-read stops the job like a close does, and the recipes
  -- stored so far reach the index.
  local trips = {
    linked = function(tripped)
      tripped.guards.IsTradeSkillLinked = true
    end,
    switched = function(tripped)
      tripped.base = ENCH
    end,
    replaced = function(tripped)
      tripped.base = ENCH
      tripped.recipes = {}
      Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
    end,
  }
  for name, trip in pairs(trips) do
    local tripped, _, tripDb, tripRun, tripSlicer = setup()
    tripped.recipes = threeBelts()
    logRecipeReads()
    Wow.fireEvent("TRADE_SKILL_SHOW")
    runOneTick()
    trip(tripped)
    Wow.runTimers()
    Assert.truthy(recipesOf(tripDb)[1], name)
    Assert.equal(recipesOf(tripDb)[2], nil, name)
    Assert.equal(tripDb.characters[CHAR].professions[BS].read, false, name)
    Assert.equal(tripSlicer.IsRunning("read"), false, name)
    Assert.same(tripRun.reasons, { "read" }, name)
  end

  -- A resumed job that changes nothing more requests no second rebuild.
  local resumed, _, resumedDb, resumedRun = setup()
  resumed.recipes = threeBelts()
  recipesOf(resumedDb)[2] = { item = 200, name = "Belt 2", prof = BS }
  recipesOf(resumedDb)[3] = { item = 300, name = "Belt 3", prof = BS }
  local resumedCalls = logRecipeReads()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runOneTick()
  Wow.fireEvent("TRADE_SKILL_CLOSE")
  Wow.runTimers()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Wow.runTimers()
  Assert.equal(resumedDb.characters[CHAR].professions[BS].read, true)
  Assert.same(resumedRun.reasons, { "read" })
  Assert.same(resumedCalls, { 1, 2, 3 }, "the job resumed at the cursor")

  -- An interrupted read stores what an uninterrupted one does.
  local plain, _, plainDb, _, plainSlicer = setup()
  plain.recipes = threeBelts()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  plainSlicer.Drain()
  Assert.same(recipesOf(db), recipesOf(plainDb))

  -- Another recipe count starts over at the first recipe.
  local state
  state, db, Slicer, calls = closeMidRead()
  state.recipes[4] = belt(4, 400)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.same(calls, { 1, 1, 2, 3, 4 })
  Assert.truthy(recipesOf(db)[4])

  -- Repeated updates with the same count leave a running job alone.
  state, _, _, _, Slicer = setup()
  state.recipes = threeBelts()
  calls = logRecipeReads()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runOneTick()
  for _ = 1, 3 do
    Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  end
  Slicer.Drain()
  Assert.same(calls, { 1, 2, 3 }, "each recipe is read once")

  -- An update that differs from the running job restarts it, even when it matches the last finished read.
  state, _, _, _, Slicer = setup()
  state.recipes = { belt(1, 100), belt(2, 200) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  calls = logRecipeReads()
  state.recipes = threeBelts()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.recipes = { belt(1, 100), belt(2, 200) }
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.same(calls, { 1, 2 }, "the three-recipe job was replaced")

  -- A second window of another profession restarts the job and tags nothing of the first.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100), belt(2, 200) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.base = ENCH
  state.recipes = { belt(5, 500), belt(6, 600) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1], nil)
  Assert.equal(recipesOf(db)[2], nil)
  Assert.equal(recipesOf(db)[5].prof, ENCH)
  Assert.equal(recipesOf(db)[6].prof, ENCH)
  Assert.equal(db.characters[CHAR].professions[ENCH].read, true)
  Assert.equal(db.characters[CHAR].professions[BS].read, false)

  -- A list update with the window never opened reads nothing.
  state, _, db, _, Slicer = setup()
  state.recipes = threeBelts()
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.same(recipesOf(db), {})
end

return function()
  readFlow("retail")
  readFlow("forever")

  -- Guards: each one blocks the read on its own.
  for _, guard in ipairs({ "IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsRuneforging" }) do
    local state, _, db, run = setup()
    state.recipes = { belt(1, 100) }
    state.guards[guard] = true
    Wow.fireEvent("TRADE_SKILL_SHOW")
    Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
    Assert.same(recipesOf(db), {}, guard)
    Assert.equal(db.characters[CHAR].professions[BS].read, false, guard)
    Assert.equal(Wow.pendingTimers(0), 0, guard)
    Assert.equal(run.builds, 0, guard)
  end

  -- A window of a profession the character does not have (Cooking, Smelting), or no window info.
  local state, _, db = setup()
  state.recipes = { belt(1, 100) }
  state.base = COOKING
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.base = nil
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.same(recipesOf(db), {})
  Assert.equal(Wow.pendingTimers(0), 0)

  -- Reads only add: a partial read, then a full read, then a partial one again.
  local Slicer
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  state.recipes = { belt(1, 100), belt(2, 200), belt(3, 300) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  state.recipes = { belt(3, 300) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[1])
  Assert.truthy(recipesOf(db)[2])
  Assert.truthy(recipesOf(db)[3])

  -- A rescan keeps mute and bind, and takes a changed name or rank list.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100, { ranks = { 101 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  recipesOf(db)[1].muted = true
  recipesOf(db)[1].bind = 2
  state.recipes = { belt(1, 100, { name = "Renamed Belt", ranks = { 101, 102 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.same(recipesOf(db)[1], { item = 100, ranks = { 101, 102 }, name = "Renamed Belt", prof = BS, bind = 2, muted = true })
  state.recipes = { belt(1, 150, { name = "Renamed Belt", ranks = { 101, 102 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].bind, nil, "a new output item has an unknown bind")
  Assert.equal(recipesOf(db)[1].muted, true)

  -- Updates re-read only when the recipe count changed; opening the window always reads.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  state.recipes[1].name = "Changed"
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].name, "Belt 1", "same count: no re-read")
  state.recipes[2] = belt(2, 200)
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].name, "Changed")
  Assert.truthy(recipesOf(db)[2])
  state.recipes[1].name = "Again"
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].name, "Again")

  -- The list may still be empty at TRADE_SKILL_SHOW: nothing stored, not marked read.
  state, _, db, _, Slicer = setup()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(db.characters[CHAR].professions[BS].read, false)
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[1])
  Assert.equal(db.characters[CHAR].professions[BS].read, true)

  -- An unchanged re-read requests no rebuild.
  state, _, _, _, Slicer = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(Wow.pendingTimers(0), 1, "only the Slicer tick that will find no job")

  -- ReadOne: the recipe is stored on the current character even though `learned` is still false.
  local ModernReader, run
  state, ModernReader, db, run = setup()
  state.recipes = { belt(1, 100, { learned = false }), belt(2, 200, { isRecraft = true }), belt(3, 300) }
  Assert.equal(ModernReader.ReadOne(1, BS), true)
  Assert.same(recipesOf(db)[1], { item = 100, name = "Belt 1", prof = BS })
  Assert.same(queued, { { 1 } }, "a stored recipe queues reach")
  Assert.equal(ModernReader.ReadOne(2, BS), false, "a recraft recipe is dropped")
  Assert.equal(ModernReader.ReadOne(99, BS), false, "an unknown recipe")
  Assert.equal(ModernReader.ReadOne(3, COOKING), false, "a profession the character does not have")
  Assert.same(queued, { { 1 } }, "a recipe that is not stored queues nothing")
  Assert.equal(recipesOf(db)[3], nil)
  Assert.same(state.requests, { 100 })
  Wow.runTimers()
  Assert.equal(run.builds, 1)
  Assert.same(run.reasons, { "learn" })
  Assert.equal(ModernReader.ReadOne(1, BS), true)
  Assert.equal(Wow.pendingTimers(0), 0, "storing the same recipe again changes nothing")

  -- A list that also holds other professions' recipes (mid-switch on Retail): each recipe is
  -- stored under its own profession when the character has it, under the window's when its
  -- profession is unknown (0: not loaded yet), and not at all otherwise.
  state, ModernReader, db, _, Slicer = setup()
  local ownBs = { professionID = 2872, parentProfessionID = BS }
  local ownEnch = { professionID = 2909, parentProfessionID = ENCH }
  local ownCooking = { professionID = 2873, parentProfessionID = COOKING }
  state.recipes = {
    belt(1, 100, { profession = ownBs }),
    belt(2, 200, { profession = ownEnch }),
    belt(3, 300, { profession = ownCooking }),
    belt(4, 400, { profession = { professionID = 0 } }),
  }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].prof, BS)
  Assert.equal(recipesOf(db)[2].prof, ENCH, "an Enchanting recipe in the Blacksmithing window is stored as Enchanting")
  Assert.equal(recipesOf(db)[3], nil, "a recipe of a profession the character does not have")
  Assert.equal(recipesOf(db)[4].prof, BS, "profession 0 (not loaded yet) falls back to the window")
  Assert.equal(db.characters[CHAR].professions[ENCH].read, true, "Enchanting got a recipe from this read")
  local midRead = ModernReader.lastRead
  Assert.same({ midRead.prof, midRead.stored, midRead.pendingBind }, { BS, 3, 3 })
  Assert.equal(type(midRead.ms), "number")
  Assert.equal(type(midRead.steps), "number")
  state.base = ENCH
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].prof, BS, "the Enchanting window does not re-tag a Blacksmithing recipe")
  Assert.equal(recipesOf(db)[2].prof, ENCH)

  -- A skipped recipe costs no schematic, and an unlearned one no profession lookup either.
  state, _, _, _, Slicer = setup()
  local api, schematics, lookups = _G["C_TradeSkillUI"], {}, {}
  local getSchematic = api.GetRecipeSchematic
  ---@type fun(id: number): table|nil
  local getProfession = api.GetProfessionInfoByRecipeID
  rawset(api, "GetRecipeSchematic", function(id, isRecraft)
    schematics[#schematics + 1] = id
    return getSchematic(id, isRecraft)
  end)
  rawset(api, "GetProfessionInfoByRecipeID", function(id)
    lookups[#lookups + 1] = id
    return getProfession(id)
  end)
  state.recipes = { belt(1, 100), belt(2, 200, { profession = ownCooking }), belt(3, 300, { learned = false }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.same(schematics, { 1 })
  Assert.same(lookups, { 1, 2 })

  -- A list holding no recipe for the window leaves it unread, and the next update of the same
  -- count with the window's own recipes is read.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100, { profession = ownEnch }), belt(2, 200, { profession = ownCooking }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(db.characters[CHAR].professions[BS].read, false)
  Assert.equal(db.characters[CHAR].professions[ENCH].read, true)
  state.recipes = { belt(3, 300, { profession = ownBs }), belt(4, 400) }
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.equal(Slicer.IsRunning("read"), true, "the same count still reads: nothing was stored for the window")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[3].prof, BS)
  Assert.equal(recipesOf(db)[4].prof, BS)
  Assert.equal(db.characters[CHAR].professions[BS].read, true)

  -- Saved recipes an older read tagged Blacksmithing, though their own lookup names Cooking,
  -- are dropped on a Blacksmithing read, in the list or not, once some recipe's own lookup
  -- names Blacksmithing. A recipe the lookup does not resolve stays.
  state, _, db, run, Slicer = setup()
  recipesOf(db)[3] = { item = 300, name = "Belt 3", prof = BS }
  recipesOf(db)[7] = { item = 700, name = "Belt 7", prof = BS, muted = true }
  recipesOf(db)[9] = { item = 900, name = "Belt 9", prof = BS }
  recipesOf(db)[10] = { item = 1000, name = "Belt 10", prof = BS, muted = true }
  recipesOf(db)[11] = { item = 1100, name = "Belt 11", prof = BS, muted = true }
  recipesOf(db)[12] = { item = 1200, name = "Belt 12", prof = BS, muted = true }
  state.lookups = {
    [7] = ownCooking,
    [10] = ownEnch,
    [11] = { professionID = 2872 },
    [12] = { professionID = 0, parentProfessionID = 0 },
  }
  state.recipes = { belt(3, 300, { profession = ownCooking }), belt(5, 500, { profession = ownEnch }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[3], "no recipe named Blacksmithing: the lookup proves nothing")
  Assert.truthy(recipesOf(db)[7])
  state.recipes = { belt(4, 400, { profession = { professionID = 0 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[7], "a recipe filed under the window by a 0 lookup proves nothing")
  state.recipes = { belt(1, 100, { profession = ownBs }), belt(3, 300, { profession = ownCooking }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[3], nil, "in the list: a profession the character does not have")
  Assert.equal(recipesOf(db)[7], nil, "not in the list: the lookup names Cooking")
  Assert.truthy(recipesOf(db)[9], "no lookup answer: kept")
  Assert.same(recipesOf(db)[10], { item = 1000, name = "Belt 10", prof = BS, muted = true }, "a stored profession: kept")
  Assert.truthy(recipesOf(db)[11], "a bare skill line without a parent: kept")
  Assert.same(recipesOf(db)[12], { item = 1200, name = "Belt 12", prof = BS, muted = true }, "a 0 parent: kept")
  Assert.equal(recipesOf(db)[1].prof, BS)
  Wow.runTimers()
  local builds = run.builds
  recipesOf(db)[7] = { item = 700, name = "Belt 7", prof = BS }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[7], nil)
  Wow.runTimers()
  Assert.equal(run.builds, builds + 1, "a read that only drops a recipe still rebuilds the index")

  -- A recipe whose lookup answers a bare skill line the character does not store (no parent)
  -- belongs to the window, as when nothing loaded; a parented unstored answer is skipped.
  state, _, db, _, Slicer = setup()
  state.recipes = {
    belt(1, 100, { profession = { professionID = 2872 } }),
    belt(2, 200, { profession = ownCooking }),
    belt(3, 300, { profession = { professionID = 2872, parentProfessionID = 0 } }),
  }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[1].prof, BS, "a bare skill line proves no other profession")
  Assert.equal(recipesOf(db)[2], nil)
  Assert.equal(recipesOf(db)[3].prof, BS, "a 0 parent is not loaded yet")

  -- Opening the window reads even while the data source is still rebuilding.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100) }
  state.changing = true
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[1], "TRADE_SKILL_SHOW does not yield")

  -- A list update while the data source is still rebuilding is skipped; the next one reads.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  state.recipes[2] = belt(2, 200)
  state.changing = true
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.equal(recipesOf(db)[2], nil, "no read while the data source changes")
  state.changing = false
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[2])

  jobCases()
end
