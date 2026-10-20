local Assert = require("tests.helpers.assert")
local Widgets = require("tests.helpers.widgets")
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
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Unmute"))
  Assert.equal(me.recipes[9001].muted, nil)
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

return function()
  testKeywordsPage()
  testCraftersPage()
end
