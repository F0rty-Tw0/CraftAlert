local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

-- Spec §10.2 / §13 "CraftScanImport", over the synthetic tests/fixtures/craftscan_db.lua.
local BS = 164
local LINE = { professionID = 2872, parentProfessionID = BS, parentProfessionName = "Blacksmithing" }

-- Logged in as Me-OwnRealm; the client answers for recipes 9001-9005 (an alt's included).
local function load()
  local ns = Fixture.load("retail")
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "OwnRealm"
  end)
  ProfessionsRetail.install({
    recipes = {
      { id = 9001, name = "Sim Plate Belt", item = 190001 },
      { id = 9003, name = "Sim Iron Reagent", item = 190003 },
      { id = 9004, name = "Sim Plate Helm", item = 190004, ranks = { 190014, 190024 }, profession = LINE },
      { id = 9005, name = "Sim Iron Bar", item = 190005 },
    },
  })
  ns.PlayerName.Init()
  Fresh.require("Model.RealmTag")
  Fresh.require("Model.MainCrafter")
  local BindLookup = Fresh.require("Professions.BindLookup")
  Fresh.require("Professions.ModernReader")
  local CraftScanImport = Fresh.require("Persistence.CraftScanImport")
  local calls = { queued = {}, rebuilds = {} }
  BindLookup.Queue = function(item)
    calls.queued[#calls.queued + 1] = item
  end
  ns.Index.RequestRebuild = function(reason)
    calls.rebuilds[#calls.rebuilds + 1] = reason
  end
  return CraftScanImport, ns, calls
end

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, inner in pairs(value) do
    result[key] = copy(inner)
  end
  return result
end

local function fixture()
  return dofile("tests/fixtures/craftscan_db.lua")
end

-- States, the parent switch, realms, the primary, greetings; CraftScan_DB is only read.
local function testFreshImport()
  local CraftScanImport, ns, calls = load()
  local db, src = ns.Defaults.Db(), fixture()
  local before = copy(src)
  local counts
  CraftScanImport.Start(db, src, function(result)
    counts = result
  end)
  Assert.equal(counts, nil, "sliced: nothing before the job runs")
  ns.Slicer.Drain()
  Assert.same(counts, { characters = 3, recipes = 5, muted = 3, greetings = 2, skipped = 5 })
  Assert.same(calls.rebuilds, { "craftscan" })
  Assert.same(src, before, "CraftScan_DB is never written")
  Assert.same(db.characters["Scanalt-OwnRealm"], {
    source = "local",
    enabled = true,
    realms = { "OwnRealm", "PartnerRealm" },
    professions = { [BS] = { name = "Blacksmithing", primary = true, read = true } },
    recipes = {
      [9004] = { name = "Sim Plate Helm", prof = BS, item = 190004, ranks = { 190014, 190024 }, line = 2872 },
      [9005] = { name = "Sim Iron Bar", prof = BS, item = 190005, muted = true },
    },
  })
  Assert.equal(db.characters["Linked-OwnRealm"], nil, "a linked account's character")
  -- The legacy key lost the apostrophe; the connected group spells the realm.
  local nosource = db.characters["Nosource-Kel'Thuzad"]
  Assert.same(nosource.realms, { "Kel'Thuzad" })
  Assert.same(nosource.recipes[9003], { name = "Sim Iron Reagent", prof = BS, item = 190003, muted = true }, "scanning switched off")
  Assert.equal(nosource.professions[BS].name, "", "no recipe named the profession")
  local old = db.characters["Old-Legacyrealm"]
  Assert.same(old.realms, { "Legacyrealm" })
  Assert.equal(old.recipes[9003].muted, nil, "legacy enabled: listening")
  Assert.equal(old.recipes[9005].muted, true, "legacy not enabled: muted")
  local templates, defaults = db.settings.templates, ns.Defaults.Settings().templates
  Assert.equal(templates.item, "Hey, {crafter} makes {item}")
  Assert.equal(templates.profession, "I do {profession}, need anything?")
  Assert.equal(templates.altItem, defaults.altItem)
  table.sort(calls.queued)
  Assert.same(calls.queued, { 190003, 190003, 190004, 190005, 190005 })
end

-- Existing Craft Alert data wins: stored recipes, realms, names and the enabled flag stay, a main
-- crafter stays, an edited greeting stays; only what is missing comes in.
local function testExistingDataWins()
  local CraftScanImport, ns = load()
  local db = ns.Defaults.Db()
  db.settings.templates.item = "My own greeting {item}"
  db.characters["Main-OwnRealm"] = Fixture.character({ BS }, {})
  db.characters["Main-OwnRealm"].professions[BS].primary = true
  db.characters["Old-Legacyrealm"] = {
    source = "local",
    enabled = false,
    realms = { "Mine" },
    professions = { [BS] = { name = "Smithing", primary = false, read = true } },
    recipes = { [9003] = { name = "Sim Iron Reagent", prof = BS, muted = true } },
  }
  local counts = CraftScanImport.Run(db, fixture())
  Assert.same(counts, { characters = 3, recipes = 4, muted = 3, greetings = 1, skipped = 5 })
  local old = db.characters["Old-Legacyrealm"]
  Assert.same(old.recipes[9003], { name = "Sim Iron Reagent", prof = BS, muted = true })
  Assert.equal(old.recipes[9005].muted, true)
  Assert.same(old.realms, { "Mine" })
  Assert.equal(old.enabled, false)
  Assert.equal(old.professions[BS].name, "Smithing")
  Assert.equal(db.characters["Scanalt-OwnRealm"].professions[BS].primary, false, "a main crafter exists")
  Assert.equal(db.characters["Main-OwnRealm"].professions[BS].primary, true)
  Assert.equal(db.settings.templates.item, "My own greeting {item}")
end

-- Malformed pieces are skipped and counted without stopping the rest; "|" never reaches a key.
local function testMalformed()
  local CraftScanImport, ns = load()
  local db = ns.Defaults.Db()
  local src = {
    settings = {
      my_uuid = "u",
      greeting = { GREETING_I_CAN_CRAFT_ITEM = 5, GREETING_NEW = "x", GREETING_ALT_HAS_PROF = "Hi|r\nthere " .. string.rep("x", 300) },
    },
    realms = {
      Bad = { characters = "nope" },
      Good = {
        characters = {
          ["Pipe|r-Good"] = { professions = { { parentProfID = BS, recipes = { [9001] = { scan_state = 9 } } } } },
          ["Nopro-Good"] = { professions = 7 },
          ["Junk-Good"] = 1,
          ["Ok-Good"] = {
            professions = {
              { parentProfID = "x", recipes = {} },
              { parentProfID = BS, recipes = { [9001] = { scan_state = 2 } } },
              { parentProfID = 185, recipes = { [9001] = { scan_state = 2 } } }, -- Cooking: not listened for
            },
          },
        },
      },
    },
  }
  local counts = CraftScanImport.Run(db, src)
  Assert.same(counts, { characters = 2, recipes = 1, muted = 0, greetings = 1, skipped = 8 })
  Assert.equal(db.settings.templates.altProfession, string.sub("Hir there " .. string.rep("x", 300), 1, 255), "no escape, one line, capped")
  Assert.truthy(db.characters["Piper-Good"], "the pipe is dropped from the key")
  Assert.truthy(db.characters["Ok-Good"].recipes[9001])
  Assert.equal(db.characters["Ok-Good"].professions[185], nil)
  local none = CraftScanImport.Run(ns.Defaults.Db(), {})
  Assert.same(none, { characters = 0, recipes = 0, muted = 0, greetings = 0, skipped = 0 })
end

-- Two expansions of one profession: the one with only unlearned recipes names nothing, the other
-- names it, in either walk order (both orders are run, so pairs cannot hide the bad one).
local function testProfessionNamedByAnyExpansion()
  local CraftScanImport, ns = load()
  local unlearned = { parentProfID = BS, recipes = { [9001] = { scan_state = 4 } } }
  local learned = { parentProfID = BS, recipes = { [9004] = { scan_state = 2 } } }
  for _, professions in ipairs({ { unlearned, learned }, { learned, unlearned } }) do
    local db = ns.Defaults.Db()
    CraftScanImport.Run(db, { realms = { OwnRealm = { characters = { ["Two-OwnRealm"] = { professions = professions } } } } })
    Assert.equal(db.characters["Two-OwnRealm"].professions[BS].name, "Blacksmithing")
  end
end

-- A legacy profession (before scan_state) with all_enabled listens to every recipe, enabled or not.
local function testLegacyAllEnabled()
  local CraftScanImport, ns = load()
  local db = ns.Defaults.Db()
  local legacy = { parentProfID = BS, all_enabled = true, recipes = { [9005] = {}, [9003] = { enabled = false } } }
  CraftScanImport.Run(db, { realms = { OwnRealm = { characters = { ["Old-OwnRealm"] = { professions = { legacy } } } } } })
  local recipes = db.characters["Old-OwnRealm"].recipes
  Assert.equal(recipes[9005].muted, nil)
  Assert.equal(recipes[9003].muted, nil)
end

-- A long greeting is cut at 255 bytes without splitting a UTF-8 character ("é" is 2 bytes).
local function testGreetingCutWholeCharacters()
  local CraftScanImport, ns = load()
  local db = ns.Defaults.Db()
  local text = string.rep("x", 254) .. "é and more"
  CraftScanImport.Run(db, { settings = { greeting = { GREETING_I_CAN_CRAFT_ITEM = text } } })
  Assert.equal(#db.settings.templates.item, 254, 'the cut drops the whole "é"')
end

-- A key without a realm takes the one realm it is stored under, not the player's.
local function testBareKeyTakesItsRealm()
  local CraftScanImport, ns = load()
  local db = ns.Defaults.Db()
  CraftScanImport.Run(db, { realms = { Legacyrealm = { characters = { Bare = { professions = {} } } } } })
  Assert.truthy(db.characters["Bare-Legacyrealm"])
  Assert.equal(db.characters["Bare-OwnRealm"], nil)
end

-- CraftScan writes its data while the sliced import pauses: keys it adds then are left for the
-- next import, never walked by a `pairs` they were added under.
local function testKeysAddedDuringTheWalk()
  local CraftScanImport, ns = load()
  local recipes = { [9004] = { scan_state = 2 }, [9005] = { scan_state = 2 } }
  local characters = { ["Busy-OwnRealm"] = { professions = { [2872] = { parentProfID = BS, recipes = recipes } } } }
  local pauses = 0
  local counts = CraftScanImport.Run(ns.Defaults.Db(), { realms = { OwnRealm = { characters = characters } } }, function()
    pauses = pauses + 1
    if pauses <= 3 then
      for id = 1, 64 do
        recipes[500000 + pauses * 100 + id] = { scan_state = 2 }
      end
      characters["New" .. pauses .. "-OwnRealm"] = { professions = {} }
    end
  end)
  Assert.same(counts, { characters = 1, recipes = 2, muted = 0, greetings = 0, skipped = 0 })
end

-- Each recipe weighs a full Slicer.Run clock check (8): its client calls take up to ~500 us, so
-- four of them between checks overran the frame budget.
local function testClockReadPerRecipe()
  local CraftScanImport, ns = load()
  local weights = {}
  CraftScanImport.Run(ns.Defaults.Db(), fixture(), function(weight)
    weights[#weights + 1] = weight
  end)
  Assert.equal(#weights, 8, "one pause per recipe entry of this account")
  for _, weight in ipairs(weights) do
    Assert.equal(weight, 8)
  end
end

return function()
  testFreshImport()
  testExistingDataWins()
  testMalformed()
  testProfessionNamedByAnyExpansion()
  testKeysAddedDuringTheWalk()
  testLegacyAllEnabled()
  testBareKeyTakesItsRealm()
  testGreetingCutWholeCharacters()
  testClockReadPerRecipe()
  Wow.reset()
end
