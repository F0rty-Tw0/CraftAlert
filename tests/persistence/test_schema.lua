local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

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
  db.leads[1] = { id = 1, customer = "Cus-Realm", crafter = "Me-Realm", time = 100, message = "LF belt" }
  db.ui.toast = { point = "TOP", x = 10, y = -20 }
  db.ui.window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 40, width = 640, height = 500 }
  local before = deepCopy(db)
  Assert.same(Schema.Validate(db), before)
  Assert.equal(#printedLines(), 0)
end

-- The leads window has one size under ui.window; the per-mode ui.settings of older saves goes.
local function testLegacySettingsSizeDropped()
  local Schema = load()
  local db = Schema.Validate({ ui = { window = { width = 640, height = 500 }, settings = { width = 700, height = 520 } } })
  Assert.equal(db.ui.settings, nil)
  Assert.same(db.ui.window, { width = 640, height = 500 })
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
        realms = { "A", 5, "B", "", "Area 52", " - ", "Twisting-Nether", "Kel'Thuzad" },
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
  Assert.same(bob.realms, { "A", "B", "Area52", "TwistingNether", "Kel'Thuzad" }, "realms lose spaces and hyphens once, here; blank ones go")
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

-- An own character's class token is optional: kept when a string, cleared otherwise.
local function testCharacterClass()
  local Schema = load()
  local db = Schema.Validate({
    characters = { ["Mage-Realm"] = { class = "MAGE" }, ["Bad-Realm"] = { class = 7 } },
  })
  Assert.equal(db.characters["Mage-Realm"].class, "MAGE")
  Assert.equal(db.characters["Bad-Realm"].class, nil)
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
      { customer = "A-Realm", crafter = "Me-Realm", time = 10 },
      { customer = 5, time = 10 },
      { customer = "B-Realm", time = "soon" },
      "junk",
      { customer = "C-Realm", crafter = "Me-Realm", time = 20 },
    },
    ui = { toast = { point = "TOP", x = 1, nested = {} }, window = 5, launcher = {}, other = {} },
  })
  Assert.same(db.ledger, { ["2026-10-17"] = { seen = 3, greeted = 0, replied = 0, filled = 2 } })
  Assert.same(db.recentGreeted, { ["A-Realm"] = 100 })
  Assert.equal(db.ignored, nil, "the saved block list of an old save is dropped")
  Assert.equal(#db.leads, 2)
  Assert.equal(db.leads[2].customer, "C-Realm")
  Assert.same(db.ui, { toast = { point = "TOP", x = 1 }, launcher = {} })
end

-- A list with a hole (an entry set to nil) keeps every entry after it, in key order.
-- Keys are written 3 before 2 because Lua 5.1 pairs returns them in that order here.
local function testListWithHoles()
  local Schema = load()
  local db = Schema.Validate({
    leads = { [3] = { customer = "B-Realm", crafter = "Me-Realm", time = 20 }, [2] = { customer = "A-Realm", crafter = "Me-Realm", time = 10 } },
    settings = { intentWords = { [1] = "a", [0] = "zero", [1.5] = "half", foo = "b", [3] = "c" } },
  })
  Assert.equal(#db.leads, 2)
  Assert.equal(db.leads[1].customer, "A-Realm")
  Assert.equal(db.leads[2].customer, "B-Realm")
  -- Only positive integer keys count as list entries; string keys must not reach table.sort.
  Assert.same(db.settings.intentWords, { "a", "c" })
end

local function testNewerSchemaKeepsNestedUiValues()
  local Schema = load()
  local db = Schema.Validate({ schema = 2, ui = { window = { point = "TOP", size = { w = 1, h = 2 } } } })
  Assert.same(db.ui.window.size, { w = 1, h = 2 })
  Assert.equal(db.ui.window.point, "TOP")
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
    leads = { { customer = "A-Realm", crafter = "Me-Realm", time = 10, futureLeadField = { a = 1 } } },
  })
  Assert.same(db.leads[1].futureLeadField, { a = 1 }, "a newer schema keeps unknown lead fields")
  Assert.equal(db.schema, 2)
  Assert.equal(db.settings.toastDuration, 120)
  Assert.equal(db.settings.futureSetting, "keep")
  Assert.equal(db.futureTopLevel.a, 1)
  Assert.equal(db.characters["Bob-Realm"].futureField, 7)
  Assert.equal(db.characters["Bob-Realm"].recipes[1].futureRecipeField, true)
  -- Validate only holds the warning; Bootstrap prints it with the login lines.
  Assert.equal(#printedLines(), 0)
  Schema.WarnNewer()
  Assert.equal(#printedLines(), 1)
  Assert.truthy(string.find(printedLines()[1], "newer", 1, true))
  Assert.truthy(string.find(printedLines()[1], "2", 1, true))
  -- Known fields were repaired (toastDuration clamped), so the warning must not claim "as is".
  Assert.falsy(string.find(printedLines()[1], "as is", 1, true))
end

-- Review Focus 3: a save from a newer schema keeps `ignored`, as it keeps every unknown key.
local function testNewerSchemaKeepsIgnored()
  local Schema = load()
  local newer = deepCopy(require("tests.fixtures.db_schema2"))
  newer.ignored = { ["A-Realm"] = true }
  local db = Schema.Validate(newer)
  Assert.equal(db.ignored["A-Realm"], true)
end

local function testOlderSchemaIsRaisedAndNoWarning()
  local Schema = load()
  Assert.equal(Schema.Validate({ schema = 0 }).schema, 1)
  Assert.equal(Schema.Validate({ schema = -3 }).schema, 1)
  Schema.WarnNewer()
  Assert.equal(#printedLines(), 0)
  -- A later Validate of a current save drops the warning an earlier newer one held.
  Schema.Validate({ schema = 2 })
  Schema.Validate({ schema = 1 })
  Schema.WarnNewer()
  Assert.equal(#printedLines(), 0)
end

-- Review Focus 5: a lead the UI or the greeting would choke on is dropped (no customer, crafter
-- or time) or loses the wrong-typed field (nil is what a lead without that field has).
local function testLeadFieldTypes()
  local Schema = load()
  local wellTyped = {
    id = 5,
    customer = "E-Realm",
    crafter = "Alt-Realm",
    time = 30,
    guid = "Player-1-0A",
    message = "LF belt",
    channel = "trade",
    kind = "item",
    prof = 164,
    group = 501,
    why = "lf + belt",
    cannotOrder = true,
    greeted = true,
    replied = true,
    seen = true,
    arrivedWhileAfk = true,
    profName = "Blacksmithing",
    recipeName = "Belt",
    recipeKey = 9001,
    itemID = 501,
    itemLink = "|cff1eff00|Hitem:501|h[Belt]|h|r",
  }
  local expected = deepCopy(wellTyped)
  local db = Schema.Validate({
    leads = {
      { id = 1, customer = "A-Realm", crafter = "Me-Realm", time = 10, profName = true, junk = 1 },
      { id = 2, customer = "B-Realm", crafter = {}, time = 10 },
      { id = 3, customer = "C-Realm", time = 10 },
      {
        id = "x",
        customer = "D-Realm",
        crafter = "Me-Realm",
        time = 20,
        guid = 7,
        message = {},
        channel = 9,
        kind = 5,
        prof = {},
        group = {},
        why = {},
        cannotOrder = "yes",
        greeted = "no",
        replied = 1,
        seen = "x",
        arrivedWhileAfk = "x",
        recipeName = 5,
        recipeKey = {},
        itemID = "501",
        itemLink = {},
      },
      wellTyped,
    },
  })
  Assert.equal(#db.leads, 3)
  Assert.same(db.leads[1], { id = 1, customer = "A-Realm", crafter = "Me-Realm", time = 10 }, "an unknown lead field is dropped")
  Assert.same(db.leads[2], { customer = "D-Realm", crafter = "Me-Realm", time = 20 })
  Assert.same(db.leads[3], expected, "a well-typed lead keeps every field")
  -- A recipe key is a number or a string (Classic recipes are keyed by name).
  local keyed = Schema.Validate({
    leads = {
      { id = 1, customer = "A-Realm", crafter = "Me-Realm", time = 10, recipeKey = "belt" },
      { id = 2, customer = "B-Realm", crafter = "Me-Realm", time = 10, recipeKey = 9001 },
    },
  })
  Assert.same({ keyed.leads[1].recipeKey, keyed.leads[2].recipeKey }, { "belt", 9001 })
end

-- Every field Model/Leads.lua writes survives a /reload: leads built by the real Leads.OnMatch
-- (an item lead and a profession lead, greeted, replied, arrived while AFK, with a guid and a
-- realm tag) come out of Schema.Validate unchanged.
local LEAD_WRITES = {
  "id",
  "customer",
  "crafter",
  "time",
  "guid",
  "message",
  "channel",
  "kind",
  "prof",
  "group",
  "why",
  "cannotOrder",
  "greeted",
  "replied",
  "seen",
  "arrivedWhileAfk",
  "profName",
  "recipeName",
  "recipeKey",
  "itemID",
  "itemLink",
}

local function leadsFromOnMatch()
  local ns = Fixture.load("retail")
  Wow.clock.time = 1000
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("UnitIsAFK", function()
    return true
  end)
  local db
  Fixture.itemIndex(ns, function(captured)
    db = captured
    db.characters["Alt-Realm"].realms = { "Realm" }
    db.characters["Smith-Realm"].realms = { "Realm" }
  end)
  Wow.stub("C_Item", {
    GetItemInfoInstant = _G["C_Item"].GetItemInfoInstant,
    GetItemInfo = function(itemID)
      return "Item " .. itemID, "|cff1eff00|Hitem:" .. itemID .. "|h[Item " .. itemID .. "]|h|r"
    end,
  })
  ns.PlayerName.Init()
  ns.RealmTag = Fresh.require("Model.RealmTag")
  ns.CrafterRank = Fresh.require("Model.CrafterRank")
  ns.Leads = Fresh.require("Model.Leads")
  ns.Leads.Restore(db)
  for _, text in ipairs({ "LF plate belt", "LF blacksmith" }) do
    local lead = ns.Leads.OnMatch(ns.Matcher.Match("trade", text, "Someone-Else"), "Bob-Draenor", text, "trade", "Player-1-0A")
    ns.Leads.MarkGreeted(lead.id)
    ns.Leads.MarkReplied(lead.id)
  end
  return db
end

local function testLeadsFromOnMatchSurvive()
  local db = leadsFromOnMatch()
  local itemLead, professionLead = db.leads[1], db.leads[2]
  Assert.equal(itemLead.kind, "item")
  Assert.equal(professionLead.kind, "profession")
  for _, field in ipairs(LEAD_WRITES) do
    Assert.truthy(itemLead[field] ~= nil, "the item lead sets " .. field)
  end
  local expected = deepCopy(db.leads)
  -- crafters is a live-only list: Validate drops it, so a restored lead has none.
  for _, lead in ipairs(expected) do
    lead.crafters = nil
  end
  Fresh.require("Core.Localization")
  Fresh.require("Core.ChatPrint")
  local Schema = Fresh.require("Persistence.Schema")
  Assert.same(Schema.Validate(db).leads, expected, "leads written by Leads.lua are unchanged")
end

-- `test` marks a synthetic lead (Leads.TEST_GUID_PREFIX): a boolean like the other flags.
local function testLeadTestFlag()
  local Schema = load()
  local db = Schema.Validate({
    leads = {
      { id = 1, customer = "A-Realm", crafter = "Me-Realm", time = 10, test = true },
      { id = 2, customer = "B-Realm", crafter = "Me-Realm", time = 10, test = "yes" },
    },
  })
  Assert.equal(db.leads[1].test, true)
  Assert.equal(db.leads[2].test, nil, "a wrong-typed test flag is dropped")
end

-- Quality rank: recipe reach fields travel together, concentration snapshots are validated
-- per entry, and a lead keeps its rank.
local function testReachConcentrationAndLeadRank()
  local Schema = load()
  local snapshot = { amount = 698, at = 100, cycleMs = 345600, perCycle = 1, max = 1000 }
  local db = Schema.Validate({
    characters = {
      ["Bob-Realm"] = {
        concentration = {
          [3167] = snapshot,
          [3168] = { amount = "x", at = 1, cycleMs = 1, perCycle = 1, max = 1 },
          [3041] = { amount = 1, at = 1, cycleMs = 0, perCycle = 1, max = 1 },
        },
        recipes = {
          [1] = { name = "A", prof = 164, reachRank = 3, reachCost = 40, reachConc = 2 },
          [2] = { name = "B", prof = 164, reachRank = 3, reachConc = 2 },
        },
      },
      ["Eve-Realm"] = { concentration = { [3168] = "junk" } },
    },
    leads = {
      { id = 1, customer = "A-Realm", crafter = "Me-Realm", time = 10, rank = 2, rankConc = true },
      { id = 2, customer = "B-Realm", crafter = "Me-Realm", time = 10, rank = "2", rankConc = "yes" },
    },
  })
  local bob = db.characters["Bob-Realm"]
  Assert.same(bob.concentration, { [3167] = snapshot }, "only the valid snapshot stays")
  Assert.equal(db.characters["Eve-Realm"].concentration, nil, "nothing valid left: nil")
  Assert.same({ bob.recipes[1].reachRank, bob.recipes[1].reachCost, bob.recipes[1].reachConc }, { 3, 40, 2 })
  Assert.same({ bob.recipes[2].reachRank, bob.recipes[2].reachCost, bob.recipes[2].reachConc }, {}, "partial reach is cleared together")
  Assert.same({ db.leads[1].rank, db.leads[1].rankConc }, { 2, true })
  Assert.same({ db.leads[2].rank, db.leads[2].rankConc }, {}, "wrong-typed rank fields are cleared")
end

-- The expansion line a read stores per recipe: a number stays, any other type is dropped.
local function testRecipeLine()
  local Schema = load()
  local db = Schema.Validate({
    characters = {
      ["Bob-Realm"] = {
        recipes = {
          [1] = { name = "A", prof = 164, line = 2918 },
          [2] = { name = "B", prof = 164, line = "2918" },
        },
      },
    },
  })
  local bob = db.characters["Bob-Realm"]
  Assert.equal(bob.recipes[1].line, 2918)
  Assert.equal(bob.recipes[2].line, nil, "a string line is dropped")
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
  testLegacySettingsSizeDropped()
  testBadTopLevelTypes()
  testSettingsTypesAndRanges()
  testClampBounds()
  testCharactersUnknownKeysAndBadRecords()
  testImportCharacter()
  testCharacterClass()
  testLedgerRecentIgnoredLeadsUi()
  testListWithHoles()
  testNewerSchemaKeepsNestedUiValues()
  testNewerSchema()
  testNewerSchemaKeepsIgnored()
  testOlderSchemaIsRaisedAndNoWarning()
  testLeadFieldTypes()
  testLeadsFromOnMatchSurvive()
  testLeadTestFlag()
  testReachConcentrationAndLeadRank()
  testRecipeLine()
  testIdempotent()
end
