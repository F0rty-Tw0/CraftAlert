local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local ProfessionsClassic = require("tests.helpers.professions_classic")

-- Spec §5.1 on Classic: the professionKey is the lowercase profession name. Era, TBC and Wrath
-- read the skill-line list, Cata and MoP GetProfessions.
local CHAR = "Crafter-OwnRealm"
local BS, ENCH, MINING, COOKING = 164, 333, 186, 185
local SKILL_LINE_FLAVORS = { "era", "tbc", "wrath" }
local SLOT_FLAVORS = { "cata", "mop" }

local function load(flavor)
  Wow.reset()
  Wow.flavor(flavor)
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Model.ProfessionWords")
  return Fresh.require("Professions.ProfessionList"), Fresh.require("Persistence.Defaults")
end

local function header(name)
  return { name = name, header = true }
end

local function line(name)
  return { name = name }
end

-- The skill frame as a fresh Era/TBC/Wrath character sees it: crafting, gathering and secondary
-- skills under their headers.
local function skillLines()
  return {
    header("Professions"),
    line("Blacksmithing"),
    line("Mining"),
    header("Secondary Skills"),
    line("Cooking"),
    line("First Aid"),
    header("Weapon Skills"),
    line("Swords"),
  }
end

local function stored(db)
  return db.characters[CHAR]
end

-- One shape for both paths: the lowercase name keys the profession, the client's spelling is its name.
local function testReadsProfessions(flavor, install)
  local ProfessionList, Defaults = load(flavor)
  local db = Defaults.Db()
  install()
  Assert.equal(ProfessionList.Refresh(db, CHAR), true, flavor)
  Assert.same(stored(db).professions, { blacksmithing = { name = "Blacksmithing", primary = false, read = false } }, flavor)
  Assert.same(ProfessionList.Order(), { "blacksmithing" }, flavor)
  Assert.truthy(ProfessionList.IsStored(db, CHAR, "blacksmithing"), flavor)
  Assert.falsy(ProfessionList.IsStored(db, CHAR, BS), flavor .. ": no skill-line ID key on Classic")
  Assert.same(ProfessionList.UnreadNames(db, CHAR), { "Blacksmithing" }, flavor)
end

-- Unknown data writes nothing: a collapsed header (its lines are hidden), or no line at all while
-- professions are stored. A real list without a profession drops it, with its recipes.
local function testSkillLineGuards(flavor)
  local ProfessionList, Defaults = load(flavor)
  local db = Defaults.Db()
  local state = ProfessionsClassic.install({ skillLines = { header("Professions"), line("Blacksmithing"), line("Enchanting") } })
  ProfessionList.Refresh(db, CHAR)
  stored(db).recipes["sim plate belt"] = { name = "Sim Plate Belt", prof = "blacksmithing", muted = true }
  stored(db).recipes["enchant bracer - minor health"] = { name = "Enchant Bracer - Minor Health", prof = "enchanting" }
  Assert.same(ProfessionList.Order(), { "blacksmithing", "enchanting" }, flavor)

  state.skillLines = { { name = "Professions", header = true, collapsed = true }, header("Secondary Skills"), line("Cooking") }
  Assert.equal(ProfessionList.Refresh(db, CHAR), false, flavor .. ": collapsed header")
  Assert.truthy(stored(db).recipes["sim plate belt"], flavor .. ": a collapsed header drops no recipe")
  Assert.truthy(ProfessionList.IsStored(db, CHAR, "enchanting"), flavor)

  state.skillLines = {}
  Assert.equal(ProfessionList.Refresh(db, CHAR), false, flavor .. ": no lines")
  Assert.truthy(stored(db).recipes["enchant bracer - minor health"], flavor .. ": no lines drop no recipe")
  Assert.same(ProfessionList.Order(), { "blacksmithing", "enchanting" }, flavor)

  state.skillLines = { header("Professions"), line("Blacksmithing"), line("Herbalism") }
  Assert.equal(ProfessionList.Refresh(db, CHAR), true, flavor)
  Assert.same(stored(db).recipes, { ["sim plate belt"] = { name = "Sim Plate Belt", prof = "blacksmithing", muted = true } }, flavor)
  Assert.same(ProfessionList.Order(), { "blacksmithing" }, flavor)

  -- A new character with no crafting profession, or with its headers collapsed, gets no record.
  local empty = Defaults.Db()
  state.skillLines = { header("Professions"), line("Mining") }
  ProfessionList.Refresh(empty, CHAR)
  Assert.equal(empty.characters[CHAR], nil, flavor)
  state.skillLines = { { name = "Professions", header = true, collapsed = true } }
  ProfessionList.Refresh(empty, CHAR)
  Assert.equal(empty.characters[CHAR], nil, flavor)
end

-- Before the first usable read the stored name keys seed the order, sorted; the skill-line IDs
-- a Retail db would hold are left out (sorting a mix raises).
local function testSeedsNameKeys(flavor)
  local ProfessionList, Defaults = load(flavor)
  local db = Defaults.Db()
  db.characters[CHAR] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = {
      enchanting = { name = "Enchanting", primary = false, read = true },
      blacksmithing = { name = "Blacksmithing", primary = false, read = true },
      [ENCH] = { name = "Enchanting", primary = false, read = true },
    },
    recipes = {},
  }
  ProfessionsClassic.install({ skillLines = {} })
  Assert.equal(ProfessionList.Refresh(db, CHAR), false, flavor)
  Assert.same(ProfessionList.Order(), { "blacksmithing", "enchanting" }, flavor)
end

return function()
  for _, flavor in ipairs(SKILL_LINE_FLAVORS) do
    testReadsProfessions(flavor, function()
      ProfessionsClassic.install({ skillLines = skillLines() })
    end)
    testSkillLineGuards(flavor)
    testSeedsNameKeys(flavor)
  end
  for _, flavor in ipairs(SLOT_FLAVORS) do
    testReadsProfessions(flavor, function()
      ProfessionsClassic.install({
        slots = {
          { name = "Blacksmithing", skillLine = BS },
          { name = "Mining", skillLine = MINING },
          false,
          false,
          { name = "Cooking", skillLine = COOKING },
        },
      })
    end)
    testSeedsNameKeys(flavor)
  end
end
