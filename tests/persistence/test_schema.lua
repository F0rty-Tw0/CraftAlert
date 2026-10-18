local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function load(flavorKey)
  Wow.reset()
  Wow.flavor(flavorKey or "retail")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.Constants")
  Fresh.require("Core.Localization")
  Fresh.require("Core.ChatPrint")
  local Defaults = Fresh.require("Persistence.Defaults")
  return Fresh.require("Persistence.Schema"), Defaults
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

local function printedLines()
  return Wow.chat
end

local function testValidDbIsUntouched()
  local Schema, Defaults = load()
  local db = Defaults.Db()
  db.characters["Bob-Realm"] = {
    source = "local",
    enabled = true,
    realms = { "Realm" },
    professions = { [164] = { name = "Blacksmithing", primary = true, read = true } },
    recipes = { [9001] = { item = 190001, ranks = { 190001, 190002 }, name = "Belt", prof = 164, bind = 2, muted = true } },
  }
  db.ledger["2026-10-17"] = { seen = 3, greeted = 2, replied = 1, filled = 0 }
  db.recentGreeted["Cus-Realm"] = 100
  db.ignored["Bad-Realm"] = true
  db.leads[1] = { id = 1, customer = "Cus-Realm", time = 100, message = "LF belt" }
  db.ui.toast = { point = "TOP", x = 10, y = -20 }
  local before = deepCopy(db)
  Assert.same(Schema.Validate(db), before)
  Assert.equal(#printedLines(), 0)
end

local function testBadTopLevelTypes()
  local Schema, Defaults = load()
  Assert.same(Schema.Validate(nil), Defaults.Db())
  Assert.same(Schema.Validate("junk"), Defaults.Db())
  local db = Schema.Validate({
    schema = "one",
    settings = 5,
    characters = "x",
    leads = true,
    ledger = 1,
    recentGreeted = false,
    ignored = "no",
    ui = 7,
  })
  Assert.same(db, Defaults.Db())
  -- A missing schema counts as version 1.
  Assert.equal(Schema.Validate({}).schema, 1)
end

local function testSettingsTypesAndRanges()
  local Schema, Defaults = load()
  local defaults = Defaults.Settings()
  local db = Schema.Validate({
    settings = {
      enable = "yes",
      onlyResting = 1,
      toastDuration = "30", -- a string where a number belongs falls back to the default
      leadTimeoutMin = 9999,
      opacity = 0.01,
      sound = 12345, -- not a shipped kit
      flash = false,
      channels = { trade = "yes", general = true, bogus = true },
      templates = { item = 5, profession = "mine" },
      notes = { [164] = "hi", [333] = 5, bad = {} },
      intentWords = { "lf", 5, "wtb" },
      blockerWords = "wts",
      extraSlang = { wand = "weapon", bad = 3 },
      craftScanImported = "x",
      craftScanPrompted = true,
      unknownSetting = 1,
    },
  })
  local s = db.settings
  Assert.equal(s.enable, defaults.enable)
  Assert.equal(s.onlyResting, defaults.onlyResting)
  Assert.equal(s.toastDuration, defaults.toastDuration)
  Assert.equal(s.leadTimeoutMin, 60)
  Assert.equal(s.opacity, 0.3)
  Assert.equal(s.sound, defaults.sound)
  Assert.equal(s.flash, false)
  Assert.same(s.channels, { trade = true, services = true, general = true, lfg = false, guild = false, communities = false })
  Assert.equal(s.templates.item, defaults.templates.item)
  Assert.equal(s.templates.profession, "mine")
  Assert.same(s.notes, { [164] = "hi" })
  Assert.same(s.intentWords, { "lf", "wtb" })
  Assert.same(s.blockerWords, defaults.blockerWords)
  Assert.same(s.extraSlang, { wand = "weapon" })
  Assert.equal(s.craftScanImported, nil)
  Assert.equal(s.craftScanPrompted, true)
  Assert.equal(s.unknownSetting, nil)
end

local function testClampBounds()
  local Schema = load()
  local function clamped(key, value)
    return Schema.Validate({ settings = { [key] = value } }).settings[key]
  end
  Assert.equal(clamped("toastDuration", 1), 5)
  Assert.equal(clamped("toastDuration", 500), 120)
  Assert.equal(clamped("toastDuration", 45), 45)
  Assert.equal(clamped("leadTimeoutMin", 0), 1)
  Assert.equal(clamped("opacity", 5), 1.0)
  Assert.equal(clamped("opacity", 0.5), 0.5)
  -- NaN and infinity are not numbers worth keeping.
  Assert.equal(clamped("toastDuration", 0 / 0), 20)
  Assert.equal(clamped("toastDuration", math.huge), 20)
  Assert.equal(clamped("sound", 0), 0)
  Assert.equal(clamped("sound", 3081), 3081)
end

local function testCharactersUnknownKeysAndBadRecords()
  local Schema = load()
  local db = Schema.Validate({
    characters = {
      ["Bob-Realm"] = {
        source = "weird",
        enabled = "yes",
        realms = { "A", 5, "B" },
        extra = true,
        professions = {
          [164] = { name = "Blacksmithing", primary = true, read = true, junk = 1 },
          [333] = "nope",
          [{}] = { name = "table key" },
        },
        recipes = {
          [9001] = { item = 190001, name = "Belt", prof = 164, bind = 2, muted = true, foo = "x" },
          [9002] = { item = "bad", ranks = { 1, "x", 2 }, name = "Enchant", prof = 333, bind = "z", muted = "no" },
          [9003] = { name = 5, prof = 164 }, -- no usable name: dropped
          [9004] = { name = "No prof" }, -- no usable profession: dropped
          [9005] = "junk",
          belt = { name = "belt", prof = "blacksmithing" },
        },
      },
      ["Broken-Realm"] = "junk",
      [5] = { source = "local" },
    },
  })
  local bob = db.characters["Bob-Realm"]
  Assert.equal(bob.source, "local")
  Assert.equal(bob.enabled, true)
  Assert.equal(bob.extra, nil)
  Assert.same(bob.realms, { "A", "B" })
  Assert.same(bob.professions, { [164] = { name = "Blacksmithing", primary = true, read = true } })
  Assert.same(bob.recipes[9001], { item = 190001, name = "Belt", prof = 164, bind = 2, muted = true })
  Assert.same(bob.recipes[9002], { ranks = { 1, 2 }, name = "Enchant", prof = 333 })
  Assert.equal(bob.recipes[9003], nil)
  Assert.equal(bob.recipes[9004], nil)
  Assert.equal(bob.recipes[9005], nil)
  Assert.same(bob.recipes.belt, { name = "belt", prof = "blacksmithing" })
  Assert.equal(db.characters["Broken-Realm"], nil)
  Assert.equal(db.characters[5], nil)
end

local function testImportCharacter()
  local Schema = load()
  local db = Schema.Validate({
    characters = { ["Alt-Realm"] = { source = "import", importedAt = 500, enabled = false } },
  })
  local alt = db.characters["Alt-Realm"]
  Assert.equal(alt.source, "import")
  Assert.equal(alt.importedAt, 500)
  Assert.equal(alt.enabled, false)
  Assert.same(alt.realms, {})
  Assert.same(alt.professions, {})
  Assert.same(alt.recipes, {})
end

local function testLedgerRecentIgnoredLeadsUi()
  local Schema = load()
  local db = Schema.Validate({
    ledger = {
      ["2026-10-17"] = { seen = 3, greeted = "x", replied = -4, filled = 2, extra = 1 },
      ["yesterday"] = { seen = 1 },
      ["2026-10-16"] = "junk",
    },
    recentGreeted = { ["A-Realm"] = 100, ["B-Realm"] = "soon", [5] = 100 },
    ignored = { ["A-Realm"] = true, ["B-Realm"] = false, ["C-Realm"] = "yes" },
    leads = {
      { customer = "A-Realm", time = 10 },
      { customer = 5, time = 10 },
      { customer = "B-Realm", time = "soon" },
      "junk",
      { customer = "C-Realm", time = 20 },
    },
    ui = { toast = { point = "TOP", x = 1, nested = {} }, window = 5, launcher = {}, other = {} },
  })
  Assert.same(db.ledger, { ["2026-10-17"] = { seen = 3, greeted = 0, replied = 0, filled = 2 } })
  Assert.same(db.recentGreeted, { ["A-Realm"] = 100 })
  Assert.same(db.ignored, { ["A-Realm"] = true })
  Assert.equal(#db.leads, 2)
  Assert.equal(db.leads[2].customer, "C-Realm")
  Assert.same(db.ui, { toast = { point = "TOP", x = 1 }, launcher = {} })
end

-- Review Focus 5: a newer schema loads, keeps its data, and warns once.
local function testNewerSchema()
  local Schema = load()
  local db = Schema.Validate({
    schema = 2,
    futureTopLevel = { a = 1 },
    settings = { toastDuration = 999, futureSetting = "keep" },
    characters = {
      ["Bob-Realm"] = { futureField = 7, recipes = { [1] = { name = "x", prof = 1, futureRecipeField = true } } },
    },
  })
  Assert.equal(db.schema, 2)
  Assert.equal(db.settings.toastDuration, 120)
  Assert.equal(db.settings.futureSetting, "keep")
  Assert.equal(db.futureTopLevel.a, 1)
  Assert.equal(db.characters["Bob-Realm"].futureField, 7)
  Assert.equal(db.characters["Bob-Realm"].recipes[1].futureRecipeField, true)
  Assert.equal(#printedLines(), 1)
  Assert.truthy(string.find(printedLines()[1], "newer", 1, true))
  Assert.truthy(string.find(printedLines()[1], "2", 1, true))
end

local function testOlderSchemaIsRaisedAndNoWarning()
  local Schema = load()
  Assert.equal(Schema.Validate({ schema = 0 }).schema, 1)
  Assert.equal(Schema.Validate({ schema = -3 }).schema, 1)
  Assert.equal(#printedLines(), 0)
end

local function testIdempotent()
  local Schema = load()
  local db = Schema.Validate({
    settings = { toastDuration = 999 },
    characters = { ["A-B"] = { recipes = { [1] = { name = "x", prof = 1 } } } },
  })
  local before = deepCopy(db)
  Assert.same(Schema.Validate(db), before)
end

return function()
  testValidDbIsUntouched()
  testBadTopLevelTypes()
  testSettingsTypesAndRanges()
  testClampBounds()
  testCharactersUnknownKeysAndBadRecords()
  testImportCharacter()
  testLedgerRecentIgnoredLeadsUi()
  testNewerSchema()
  testOlderSchemaIsRaisedAndNoWarning()
  testIdempotent()
end
