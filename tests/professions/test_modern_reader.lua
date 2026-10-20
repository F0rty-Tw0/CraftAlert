local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local BS, ENCH, COOKING = 164, 333, 185
local CHAR = "Me-Realm"

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
  return state, ModernReader, db, run
end

local function recipesOf(db)
  return db.characters[CHAR].recipes
end

local function readFlow(flavor)
  local state, ModernReader, db, run = setup(flavor)
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
  Assert.same(recipesOf(db), {
    [1] = { item = 100, name = "Belt 1", prof = BS },
    [2] = { item = 200, ranks = { 201, 202, 203 }, name = "Belt 2", prof = BS },
    [3] = { name = "Enchant Bracer - Health", prof = BS },
  }, flavor)
  Assert.equal(db.characters[CHAR].professions[BS].read, true)
  Assert.equal(db.characters[CHAR].professions[ENCH].read, false)
  Assert.same(state.requests, { 100, 200 }, "bind requested for items with an unknown bind")
  Assert.same(ModernReader.lastRead, { prof = BS, stored = 3, pendingBind = 2 })
  Assert.equal(Wow.pendingTimers(0), 1, "one coalesced rebuild")
  Wow.runTimers()
  Assert.same(run.reasons, { "read" })
  Assert.equal(run.builds, 1)
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
  state, _, db = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.recipes = { belt(1, 100), belt(2, 200), belt(3, 300) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.recipes = { belt(3, 300) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.truthy(recipesOf(db)[1])
  Assert.truthy(recipesOf(db)[2])
  Assert.truthy(recipesOf(db)[3])

  -- A rescan keeps mute and bind, and takes a changed name or rank list.
  state, _, db = setup()
  state.recipes = { belt(1, 100, { ranks = { 101 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  recipesOf(db)[1].muted = true
  recipesOf(db)[1].bind = 2
  state.recipes = { belt(1, 100, { name = "Renamed Belt", ranks = { 101, 102 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.same(recipesOf(db)[1], { item = 100, ranks = { 101, 102 }, name = "Renamed Belt", prof = BS, bind = 2, muted = true })
  state.recipes = { belt(1, 150, { name = "Renamed Belt", ranks = { 101, 102 } }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(recipesOf(db)[1].bind, nil, "a new output item has an unknown bind")
  Assert.equal(recipesOf(db)[1].muted, true)

  -- Updates re-read only when the recipe count changed; opening the window always reads.
  state, _, db = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.recipes[1].name = "Changed"
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.equal(recipesOf(db)[1].name, "Belt 1", "same count: no re-read")
  state.recipes[2] = belt(2, 200)
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.equal(recipesOf(db)[1].name, "Changed")
  Assert.truthy(recipesOf(db)[2])
  state.recipes[1].name = "Again"
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(recipesOf(db)[1].name, "Again")

  -- The list may still be empty at TRADE_SKILL_SHOW: nothing stored, not marked read.
  state, _, db = setup()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(db.characters[CHAR].professions[BS].read, false)
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.truthy(recipesOf(db)[1])
  Assert.equal(db.characters[CHAR].professions[BS].read, true)

  -- An unchanged re-read requests no rebuild.
  state = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Wow.runTimers()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(Wow.pendingTimers(0), 0)

  -- ReadOne: the recipe is stored on the current character even though `learned` is still false.
  local ModernReader, run
  state, ModernReader, db, run = setup()
  state.recipes = { belt(1, 100, { learned = false }), belt(2, 200, { isRecraft = true }), belt(3, 300) }
  Assert.equal(ModernReader.ReadOne(1, BS), true)
  Assert.same(recipesOf(db)[1], { item = 100, name = "Belt 1", prof = BS })
  Assert.equal(ModernReader.ReadOne(2, BS), false, "a recraft recipe is dropped")
  Assert.equal(ModernReader.ReadOne(99, BS), false, "an unknown recipe")
  Assert.equal(ModernReader.ReadOne(3, COOKING), false, "a profession the character does not have")
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
  state, ModernReader, db = setup()
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
  Assert.equal(recipesOf(db)[1].prof, BS)
  Assert.equal(recipesOf(db)[2].prof, ENCH, "an Enchanting recipe in the Blacksmithing window is stored as Enchanting")
  Assert.equal(recipesOf(db)[3], nil, "a recipe of a profession the character does not have")
  Assert.equal(recipesOf(db)[4].prof, BS, "profession 0 (not loaded yet) falls back to the window")
  Assert.equal(db.characters[CHAR].professions[ENCH].read, true, "Enchanting got a recipe from this read")
  Assert.same(ModernReader.lastRead, { prof = BS, stored = 3, pendingBind = 3 })
  state.base = ENCH
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(recipesOf(db)[1].prof, BS, "the Enchanting window does not re-tag a Blacksmithing recipe")
  Assert.equal(recipesOf(db)[2].prof, ENCH)

  -- A skipped recipe costs no schematic, and an unlearned one no profession lookup either.
  state = setup()
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
  Assert.same(schematics, { 1 })
  Assert.same(lookups, { 1, 2 })

  -- A list holding no recipe for the window leaves it unread, and the next update of the same
  -- count with the window's own recipes is read.
  state, _, db = setup()
  state.recipes = { belt(1, 100, { profession = ownEnch }), belt(2, 200, { profession = ownCooking }) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.equal(db.characters[CHAR].professions[BS].read, false)
  Assert.equal(db.characters[CHAR].professions[ENCH].read, true)
  state.recipes = { belt(3, 300, { profession = ownBs }), belt(4, 400) }
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.equal(recipesOf(db)[3].prof, BS)
  Assert.equal(recipesOf(db)[4].prof, BS)
  Assert.equal(db.characters[CHAR].professions[BS].read, true)

  -- Opening the window reads even while the data source is still rebuilding.
  state, _, db = setup()
  state.recipes = { belt(1, 100) }
  state.changing = true
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Assert.truthy(recipesOf(db)[1], "TRADE_SKILL_SHOW does not yield")

  -- A list update while the data source is still rebuilding is skipped; the next one reads.
  state, _, db = setup()
  state.recipes = { belt(1, 100) }
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.recipes[2] = belt(2, 200)
  state.changing = true
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.equal(recipesOf(db)[2], nil, "no read while the data source changes")
  state.changing = false
  Wow.fireEvent("TRADE_SKILL_LIST_UPDATE")
  Assert.truthy(recipesOf(db)[2])
end
