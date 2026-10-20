local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Fixture = require("tests.helpers.matcher_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")

local open, row, take, texts = SettingsFixture.open, SettingsFixture.row, SettingsFixture.take, SettingsFixture.texts

-- §6.2: keyword and block-list changes rebuild the index (the hot path reads copies).
local function testKeywordsPage()
  local ns, db, refreshes = SettingsFixture.load({ leads = 2 })
  local settings = db.settings
  open(ns, "Keywords")
  take(refreshes)
  Assert.equal(row("Intent words").input:GetText(), "lf lfc wtb need needs looking any any1 anyone who recraft")
  Widgets.type(row("Intent words").input, "LF  need, wtb lf")
  Assert.same(settings.intentWords, { "lf", "need", "wtb" }, "lowercase, once each")
  Assert.same(take(refreshes), { "rebuild:keywords" })
  Widgets.type(row("Intent words").input, "  ")
  Assert.same(settings.intentWords, { "lf", "lfc", "wtb", "need", "needs", "looking", "any", "any1", "anyone", "who", "recraft" })
  Assert.equal(row("Intent words").input:GetText(), "lf lfc wtb need needs looking any any1 anyone who recraft", "empty → defaults")
  take(refreshes)
  Widgets.type(row("Blocker words").input, "")
  Assert.same(settings.blockerWords, {}, "no blocker words is allowed")
  Assert.same(take(refreshes), { "rebuild:keywords" })

  -- Extra slang: word=target pairs; anything else is dropped.
  Widgets.type(row("Extra slang (word=slot)").input, "Pauldron=shoulders, hat=helm junk =x y=")
  Assert.same(settings.extraSlang, { pauldron = "shoulders", hat = "helm" })
  Assert.same(take(refreshes), { "rebuild:keywords" })
  Assert.equal(row("Extra slang (word=slot)").input:GetText(), "hat=helm pauldron=shoulders")

  -- Blocking from here works as the leads-window button: ignored, leads gone, block set rebuilt.
  Widgets.type(row("Block a player").input, "Customer1-Draenor")
  Assert.same(db.ignored, { ["Customer1-Draenor"] = true })
  Assert.equal(#db.leads, 1)
  Assert.same(take(refreshes), { "rebuild:block" })
  Assert.equal(row("Block a player").input:GetText(), "", "the box empties")
  Widgets.type(row("Block a player").input, "Other")
  Assert.truthy(db.ignored["Other-Realm"], "normalized with the player's realm")
  take(refreshes)
  Assert.truthy(texts():find("Customer1-Draenor", 1, true))
  Assert.truthy(texts():find("Other-Realm", 1, true))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Unblock"))
  Assert.same(db.ignored, { ["Other-Realm"] = true }, "the first row (by name) unblocked")
  Assert.same(take(refreshes), { "rebuild:block" })
  Assert.falsy(texts():find("Customer1-Draenor", 1, true))
end

-- A typed name is cased as chat senders are, so the block matches them (§6.3 step 1).
local function testBlockTypedName()
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      for key, character in pairs(Fixture.db({ Defaults = require("CraftAlert.Persistence.Defaults") }).characters) do
        accountDb.characters[key] = character
      end
      local far = Fixture.character({}, {})
      far.realms = { "Area52" }
      accountDb.characters["Far-Area52"] = far
    end,
  })
  open(ns, "Keywords")
  Widgets.type(row("Block a player").input, "bob")
  Assert.same(db.ignored, { ["Bob-Realm"] = true })
  ns.Matcher.SetIndex(Fixture.index(ns, db))
  Assert.truthy(ns.Matcher.Match("trade", "lf lion heart", "Carl"), "another sender still matches")
  Assert.equal(ns.Matcher.Match("trade", "lf lion heart", "Bob"), nil)
  Assert.equal(ns.Matcher.lastStop, "blocked")
  Widgets.type(row("Block a player").input, "alice-area 52")
  Assert.equal(db.ignored["Alice-Area52"], true, "a known realm takes its stored spelling")
end

local BS, ENCH = 164, 333

local function crafters(accountDb)
  accountDb.characters["Me-Realm"] = {
    source = "local",
    enabled = true,
    realms = { "Realm" },
    professions = { [BS] = { name = "Blacksmithing", primary = false, read = true }, [ENCH] = { name = "Enchanting", primary = false, read = true } },
    recipes = {
      [9001] = { item = 501, name = "Thick Plate Belt", prof = BS },
      [9002] = { item = 502, name = "Plate Greaves", prof = BS },
      [9003] = { name = "Enchant Bracer - Health", prof = ENCH },
    },
  }
  accountDb.characters["Alt-Realm"] = {
    source = "local",
    enabled = true,
    realms = { "Realm" },
    professions = { [BS] = { name = "Blacksmithing", primary = true, read = true } },
    recipes = { [9001] = { item = 501, name = "Thick Plate Belt", prof = BS } },
  }
  accountDb.characters["Far-Away"] = { source = "import", importedAt = 1, enabled = true, realms = {}, professions = {}, recipes = {} }
end

-- The bell of the visible recipe row showing recipe `key`.
local function bellOf(key)
  for _, frame in ipairs(Wow.frames) do
    if frame.bell and frame.item and frame.item.key == key and SettingsFixture.visible(frame) then
      return frame.bell
    end
  end
  error("no visible recipe row " .. tostring(key))
end

-- §6.2: crafter enable/disable, removal and mute rebuild the index; the primary crafter is
-- read when a lead picks its crafter (§6.3 step 5), so it rebuilds nothing.
local function testCraftersPage()
  local ns, db, refreshes = SettingsFixture.load({ db = crafters })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local character = row("Character").input
  Assert.equal(character.label:GetText(), "Me-Realm (this character)", "opens on the current character")
  Widgets.click(character, "LeftButton")
  Assert.equal(character.label:GetText(), "Alt-Realm (same account)", "then by name, wrapping")
  Widgets.click(character, "LeftButton")
  Assert.equal(character.label:GetText(), "Far-Away (imported)")
  Widgets.click(character, "LeftButton")

  Widgets.click(row("Listen for this character").input)
  Assert.equal(me.enabled, false)
  Assert.same(take(refreshes), { "rebuild:crafter" })

  -- Primary: one crafter per profession; it is the shown character's for the shown profession.
  Assert.equal(row("Profession").input.label:GetText(), "Blacksmithing")
  Widgets.click(row("Primary crafter for this profession").input)
  Assert.equal(me.professions[BS].primary, true)
  Assert.equal(db.characters["Alt-Realm"].professions[BS].primary, false, "the other primary is cleared")
  Widgets.click(row("Primary crafter for this profession").input)
  Assert.equal(me.professions[BS].primary, false, "switched off again")
  Assert.equal(db.characters["Alt-Realm"].professions[BS].primary, false, "nobody else gains it")
  Widgets.click(row("Primary crafter for this profession").input)
  Assert.same(take(refreshes), {})

  -- Recipes of that profession by name, with search; mute toggles the bell and rebuilds.
  local shown = texts()
  Assert.truthy(shown:find("Plate Greaves / Mute / Thick Plate Belt / Mute", 1, true), shown)
  Assert.falsy(shown:find("Enchant Bracer", 1, true))
  Widgets.type(row("Search recipes").input, "BELT")
  Assert.falsy(texts():find("Plate Greaves", 1, true))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Mute"))
  Assert.equal(me.recipes[9001].muted, true)
  Assert.same(take(refreshes), { "rebuild:mute" })
  Assert.truthy(texts():find("Thick Plate Belt / Unmute", 1, true))
  Assert.equal(bellOf(9001).desaturated, true, "a muted recipe's bell is grey")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Unmute"))
  Assert.equal(me.recipes[9001].muted, nil)
  Assert.equal(bellOf(9001).desaturated, false)
  Assert.same(take(refreshes), { "rebuild:mute" })
  Widgets.click(row("Profession").input)
  Assert.truthy(texts():find("Enchant Bracer - Health", 1, true), "the search clears with the profession")

  -- Remove asks for a second click, then drops the character and shows the next one.
  local remove = SettingsFixture.button(SettingsFixture.window(), "Remove character")
  Widgets.click(remove)
  Assert.truthy(db.characters["Me-Realm"], "not on the first click")
  Assert.same(take(refreshes), {})
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  Assert.equal(db.characters["Me-Realm"], nil)
  Assert.same(take(refreshes), { "rebuild:crafter" })
  Assert.equal(character.label:GetText(), "Alt-Realm (same account)")
end

-- §9 Test: a line → result and "why", through Matcher.MatchUngated (no gate, no lead, no
-- ignore check); a line that stops says where.
local function testTestPage()
  local fixtureDb
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      fixtureDb = accountDb
      -- The fixture's three crafters (Fixture.db only needs Defaults, loaded by now).
      for key, character in pairs(Fixture.db({ Defaults = require("CraftAlert.Persistence.Defaults") }).characters) do
        accountDb.characters[key] = character
      end
    end,
    before = function(chain)
      chain.Matcher.SetIndex(Fixture.index(chain, fixtureDb))
    end,
  })
  db.ignored["Test-Realm"] = true -- the ignore check is skipped, as for /ca test
  open(ns, "Test")
  Widgets.type(row("Test a line").input, "lf lion heart")
  local shown = texts()
  Assert.truthy(shown:find("Item: Lionheart Helm", 1, true), shown)
  Assert.truthy(shown:find("Why: lf + lion + heart", 1, true), shown)
  Assert.truthy(shown:find("Crafter: Smith-Realm", 1, true), shown)
  Widgets.type(row("Test a line").input, "Any Enchaters in ORG?")
  shown = texts()
  Assert.truthy(shown:find("Profession: 333", 1, true), shown)
  Assert.truthy(shown:find("Crafter: Ench-Realm", 1, true), shown)
  Assert.falsy(shown:find("Lionheart", 1, true), "the last result is replaced")
  Widgets.type(row("Test a line").input, "hello there")
  Assert.truthy(texts():find("No match (stopped at: prefilter)", 1, true), texts())
  Assert.same(db.leads, {}, "no lead")
end

return function()
  testKeywordsPage()
  testBlockTypedName()
  testCraftersPage()
  testTestPage()
end
