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
  local Slicer = ns.Slicer -- the one Index runs its build job on
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
  -- The finished read requests the rebuild, a Slicer job that Drain runs right after it.
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

-- The expansion line (spec crafters-filters Design 1): a parented, non-zero ProfessionInfo
-- stores `professionID` as `line`; a bare or unloaded answer stores none and keeps a stored one.
local function lineCases()
  local lined = { professionID = 2918, parentProfessionID = BS }
  local state, _, db, run, Slicer = setup()
  state.recipes = {
    belt(1, 100, { profession = lined }),
    belt(2, 200, { profession = { professionID = 2918 } }),
    belt(3, 300, { profession = { professionID = 0, parentProfessionID = BS } }),
    belt(4, 400),
  }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  Assert.same(recipesOf(db)[1], { item = 100, name = "Belt 1", prof = BS, line = 2918 })
  Assert.equal(recipesOf(db)[2].line, nil, "a bare answer gives no line")
  Assert.equal(recipesOf(db)[3].line, nil, "an unloaded (0) line gives none")
  Assert.equal(recipesOf(db)[4].line, nil, "no answer gives none")
  Assert.same(run.reasons, { "read" })

  -- A re-read with no line keeps the stored one, and changes nothing.
  state.recipes[1].profession = { professionID = 2918 }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  Assert.equal(recipesOf(db)[1].line, 2918, "a lineless re-read keeps the line")
  Assert.same(run.reasons, { "read" }, "an unchanged re-read requests no rebuild")

  -- Even when the same read changes another field, the stored line stays.
  state.recipes[1].name = "Belt one"
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  Assert.same(recipesOf(db)[1], { item = 100, name = "Belt one", prof = BS, line = 2918 })
  Assert.same(run.reasons, { "read", "read" })

  -- A re-read with a new line replaces it and reports the change.
  state.recipes[1].profession = { professionID = 2950, parentProfessionID = BS }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  Assert.equal(recipesOf(db)[1].line, 2950)
  Assert.same(run.reasons, { "read", "read", "read" }, "a changed line counts as a change")

  -- The learn path (window closed) stores the line too.
  local ModernReader
  state, ModernReader, db = setup()
  state.recipes = { belt(1, 100, { learned = false, profession = lined }) }
  Assert.equal(ModernReader.ReadOne(1, BS), true)
  Assert.equal(recipesOf(db)[1].line, 2918)

  -- The line costs no lookup: N recipes → N in phase 1 (storeKey) and N in phase 2 (foreign drop).
  local Slicer2
  state, _, db, _, Slicer2 = setup()
  local api, lookups = _G["C_TradeSkillUI"], 0
  ---@type fun(id: number): table|nil
  local getProfession = api.GetProfessionInfoByRecipeID
  rawset(api, "GetProfessionInfoByRecipeID", function(id)
    lookups = lookups + 1
    return getProfession(id)
  end)
  state.recipes = { belt(1, 100, { profession = lined }), belt(2, 200, { profession = lined }), belt(3, 300, { profession = lined }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer2.Drain()
  Assert.equal(lookups, 6, "2N profession lookups")
  Assert.equal(recipesOf(db)[3].line, 2918)
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

-- The re-open skip: a window re-open whose last read of the profession was settled (a loaded
-- answer named it, every stored recipe has its line) and has the same count walks nothing and
-- only queues reach for the stored recipes.
local function reopenCases()
  local lined = { professionID = 2918, parentProfessionID = BS }
  local api = _G["C_TradeSkillUI"]
  local function sorted(ids)
    local copy = {}
    for i, id in ipairs(ids) do
      copy[i] = id
    end
    table.sort(copy)
    return copy
  end
  -- Counts the recipe getters a read would call.
  local function countGetters()
    local count = { n = 0 }
    for _, name in ipairs({ "GetRecipeInfo", "GetRecipeSchematic", "GetProfessionInfoByRecipeID" }) do
      local original = api[name]
      rawset(api, name, function(...)
        count.n = count.n + 1
        return original(...)
      end)
    end
    return count
  end
  local function readSettled(state, Slicer)
    state.recipes = { belt(1, 100, { profession = lined }), belt(2, 200, { profession = lined }) }
    Wow.fireEvent("TRADE_SKILL_SHOW")
    Slicer.Drain()
    Wow.runTimers()
  end

  -- Settled and unchanged: no read job, no getter call, no index rebuild, reach for the stored IDs.
  local state, ModernReader, _, _, Slicer = setup()
  readSettled(state, Slicer)
  local lastRead = ModernReader.lastRead
  queued = {}
  local getters = countGetters()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(Slicer.IsRunning("read"), false, "no read job on the re-open")
  Assert.equal(Slicer.IsRunning("index"), false, "no index rebuild on the re-open")
  Assert.equal(getters.n, 0, "no recipe getter is called")
  Assert.equal(#queued, 1)
  Assert.same(sorted(queued[1]), { 1, 2 }, "reach gets the stored IDs")
  Assert.equal(ModernReader.lastRead, lastRead, "a skip leaves the last read")

  -- Not settled: no loaded answer (nil, or an unloaded 0 line) → the re-open reads, and the
  -- line arrives once the answer is loaded.
  for name, answer in pairs({ none = false, unloaded = { professionID = 0, parentProfessionID = BS } }) do
    local unsettled, _, db, _, unsettledSlicer = setup()
    unsettled.recipes = { belt(1, 100, { profession = answer or nil }), belt(2, 200, { profession = lined }) }
    Wow.fireEvent("TRADE_SKILL_SHOW")
    unsettledSlicer.Drain()
    Wow.runTimers()
    Assert.equal(recipesOf(db)[1].line, nil, name)
    Wow.fireEvent("TRADE_SKILL_SHOW")
    Assert.equal(unsettledSlicer.IsRunning("read"), true, name .. ": the re-open reads")
    unsettled.recipes[1].profession = lined
    unsettledSlicer.Drain()
    Wow.runTimers()
    Assert.equal(recipesOf(db)[1].line, 2918, name .. ": the line is filled in")
    Wow.fireEvent("TRADE_SKILL_SHOW")
    Assert.equal(unsettledSlicer.IsRunning("read"), false, name .. ": settled now")
  end

  -- Per profession: Blacksmithing, then Enchanting, then Blacksmithing again with the same count.
  local ench = { professionID = 2909, parentProfessionID = ENCH }
  state, _, _, _, Slicer = setup()
  readSettled(state, Slicer)
  state.base = ENCH
  state.recipes = { belt(5, 500, { profession = ench }), belt(6, 600, { profession = ench }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  state.base = BS
  state.recipes = { belt(1, 100, { profession = lined }), belt(2, 200, { profession = lined }) }
  queued = {}
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.equal(Slicer.IsRunning("read"), false, "a same-count update skips after another profession was read")
  Assert.same(queued, {}, "an update queues no reach")
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(Slicer.IsRunning("read"), false, "the re-open skips")
  Assert.same(sorted(queued[1]), { 1, 2 }, "reach gets Blacksmithing's IDs only")

  -- A dropped profession (ProfessionList's drop) is read again.
  local db
  state, _, db, _, Slicer = setup()
  readSettled(state, Slicer)
  for recipeID in pairs(recipesOf(db)) do
    recipesOf(db)[recipeID] = nil
  end
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(Slicer.IsRunning("read"), true, "no stored recipe: read")
  Slicer.Drain()
  Assert.truthy(recipesOf(db)[1])

  -- A kept job for the same profession and count resumes; it outranks the skip.
  state, _, db, _, Slicer = setup()
  state.recipes = { belt(1, 100, { profession = lined }), belt(2, 200, { profession = lined }), belt(3, 300, { profession = lined }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
  for recipeID in pairs(recipesOf(db)) do
    recipesOf(db)[recipeID] = nil
  end
  local calls = logRecipeReads()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runOneTick()
  Wow.fireEvent("TRADE_SKILL_CLOSE")
  Wow.runTimers()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(Slicer.IsRunning("read"), true, "the kept job resumes, one stored recipe does not skip")
  Slicer.Drain()
  Assert.same(calls, { 1, 2, 3 })
end

-- §10.2: FieldsOf reads an alt's recipe the logged-in character never learned, with the §5.2
-- drops, its expansion line and its profession answer; it stores nothing.
local function fieldsOfAnyRecipe()
  local state, ModernReader, db = setup()
  local line = { professionID = 2872, parentProfessionID = BS, parentProfessionName = "Blacksmithing" }
  state.recipes = { belt(1, 100, { learned = false, ranks = { 101, 102 }, profession = line }), belt(2, 200, { isRecraft = true }) }
  local fields, profInfo = ModernReader.FieldsOf(1)
  Assert.same(fields, { item = 100, ranks = { 101, 102 }, name = "Belt 1", line = 2872 })
  Assert.equal(profInfo, line)
  Assert.equal(ModernReader.FieldsOf(2), nil, "recraft dropped")
  Assert.equal(ModernReader.FieldsOf(3), nil, "unknown recipe")
  Assert.same(recipesOf(db), {})
end

local function isBlockedCases()
  local _, ModernReader = setup()
  local names = { "IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsRuneforging" }
  local function stubGuards(blocked)
    local api = {}
    for _, name in ipairs(names) do
      api[name] = function()
        return name == blocked
      end
    end
    Wow.stub("C_TradeSkillUI", api)
  end
  stubGuards(nil)
  Assert.equal(ModernReader.IsBlocked(), false, "all guards false")
  for _, name in ipairs(names) do
    stubGuards(name)
    Assert.equal(ModernReader.IsBlocked(), true, name)
  end
  Wow.stub("C_TradeSkillUI", nil)
  Assert.equal(ModernReader.IsBlocked(), false, "no trade skill api")
end

local function lined(id, item, line)
  return belt(id, item, { profession = { professionID = line, parentProfessionID = BS } })
end

local function readWindow(Slicer)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Slicer.Drain()
  Wow.runTimers()
end

-- Chat lines the addon printed from now on.
local function captureChat()
  local lines = {}
  Wow.stub("DEFAULT_CHAT_FRAME", {
    AddMessage = function(_, text)
      lines[#lines + 1] = text
    end,
  })
  return lines
end

local PREFIX = "|cffffd100Craft Alert:|r "

-- Only the newest expansion line alerts: applied when a window read finishes.
local function newestCases()
  -- Lines {Classic 2540, Khaz Algar 2883} → older muted, newest on, silent; a manual unmute
  -- survives a re-read; a newer line 2918 drops picks, mutes both and prints once.
  local state, ModernReader, db, run, Slicer = setup()
  local chat = captureChat()
  state.recipes = {
    lined(2385, 100, 2540),
    lined(2386, 101, 2540),
    lined(446001, 102, 2883),
    lined(446002, 103, 2883),
  }
  readWindow(Slicer)
  Assert.same({ recipesOf(db)[2385].muted, recipesOf(db)[2386].muted }, { true, true }, "older line muted")
  Assert.same({ recipesOf(db)[446001].muted, recipesOf(db)[446002].muted }, {}, "newest line unmuted")
  Assert.equal(db.characters[CHAR].professions[BS].newestLine, 2883)
  Assert.same(chat, {}, "the first apply is silent")
  Assert.same(run.reasons, { "read" })

  recipesOf(db)[2385].muted = nil -- the player's own pick
  ModernReader.ForgetReads() -- same count + settled would skip the walk
  readWindow(Slicer)
  Assert.equal(recipesOf(db)[2385].muted, nil, "same newest line: picks kept")
  Assert.equal(#run.reasons, 1, "an unchanged re-read requests no rebuild")

  rawset(_G["C_TradeSkillUI"], "GetProfessionInfoBySkillLineID", function(id)
    return { professionID = id, expansionName = id == 2918 and "Midnight" or nil }
  end)
  state.recipes[#state.recipes + 1] = lined(450001, 104, 2918)
  state.recipes[#state.recipes + 1] = lined(450002, 105, 2918)
  readWindow(Slicer)
  Assert.same({ recipesOf(db)[2385].muted, recipesOf(db)[446001].muted, recipesOf(db)[450001].muted }, { true, true, nil }, "new line: picks dropped")
  Assert.equal(db.characters[CHAR].professions[BS].newestLine, 2918)
  Assert.same(chat, { PREFIX .. "Blacksmithing now alerts only for Midnight recipes." }, "one notice")
  ModernReader.ForgetReads()
  readWindow(Slicer)
  Assert.equal(#chat, 1, "a re-read prints nothing more")

  -- A first read on an existing character whose recipes otherwise match still requests exactly
  -- one rebuild.
  state, _, db, run, Slicer = setup()
  state.recipes = { lined(2385, 100, 2540), lined(446001, 102, 2883) }
  recipesOf(db)[2385] = { item = 100, name = "Belt 2385", prof = BS, line = 2540 }
  recipesOf(db)[446001] = { item = 102, name = "Belt 446001", prof = BS, line = 2883 }
  readWindow(Slicer)
  Assert.equal(recipesOf(db)[2385].muted, true)
  Assert.same(run.reasons, { "read" }, "only-newest alone forces the rebuild")

  -- Saved newest line with none of its recipes left: mutes kept, no notice.
  state, _, db, _, Slicer = setup()
  chat = captureChat()
  db.characters[CHAR].professions[BS].newestLine = 2540
  recipesOf(db)[446002] = { item = 103, name = "Manual", prof = BS, line = 2883, muted = true }
  state.recipes = { lined(446001, 102, 2883) }
  readWindow(Slicer)
  Assert.equal(db.characters[CHAR].professions[BS].newestLine, 2883)
  Assert.equal(recipesOf(db)[446002].muted, true, "mutes kept")
  Assert.same(chat, {}, "no notice")

  -- Same newest line: a read that newly stores an older-line recipe mutes only that one.
  state, _, db, _, Slicer = setup()
  state.recipes = { lined(446001, 102, 2883) }
  readWindow(Slicer)
  recipesOf(db)[446001].muted = true -- the player's pick
  state.recipes[2] = lined(2390, 105, 2540)
  readWindow(Slicer)
  Assert.equal(recipesOf(db)[2390].muted, true, "new older-line recipe starts muted")
  Assert.equal(recipesOf(db)[446001].muted, true, "other mutes alone")
  Assert.equal(db.characters[CHAR].professions[BS].newestLine, 2883)

  -- Lineless recipes and lineless professions: untouched / no-op.
  state, _, db, run, Slicer = setup()
  chat = captureChat()
  state.recipes = { belt(1, 100), belt(2, 200) }
  readWindow(Slicer)
  Assert.same({ recipesOf(db)[1].muted, recipesOf(db)[2].muted }, {})
  Assert.equal(db.characters[CHAR].professions[BS].newestLine, nil, "no line: newestLine untouched")
  Assert.same(chat, {})
  Assert.same(run.reasons, { "read" })
  state.recipes[3] = lined(446001, 102, 2883)
  recipesOf(db)[1].muted = true
  readWindow(Slicer)
  Assert.equal(recipesOf(db)[1].muted, true, "a lineless recipe is left alone")
  Assert.equal(recipesOf(db)[2].muted, nil)
end

return function()
  readFlow("retail")
  readFlow("forever")
  newestCases()
  fieldsOfAnyRecipe()

  -- In an instance a profession window is never read, on show or on a list update.
  do
    local state, _, db, run, Slicer = setup()
    state.recipes = { belt(1, 100) }
    Wow.stub("IsInInstance", function()
      return true, "party"
    end)
    Wow.fireEvent("TRADE_SKILL_SHOW")
    Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
    Assert.equal(Slicer.IsRunning("read"), false, "no read job")
    Assert.same(recipesOf(db), {})
    Assert.equal(Wow.pendingTimers(0), 0)
    Assert.equal(run.builds, 0)
    Wow.stub("IsInInstance", nil)
  end

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

  -- Updates re-read only when the recipe count changed; opening the window reads unless the last
  -- read of that profession was settled and the count is the same.
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
  state.recipes[3] = belt(13, 1300) -- a new count: the settled read above would skip the re-open
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

  lineCases()
  jobCases()
  reopenCases()
  isBlockedCases()
end
