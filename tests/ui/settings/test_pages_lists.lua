local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Fixture = require("tests.helpers.matcher_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")

local open, row, take, texts = SettingsFixture.open, SettingsFixture.row, SettingsFixture.take, SettingsFixture.texts

-- §6.2: keyword changes rebuild the index (the hot path reads copies).
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

  -- A word list longer than a chat line is kept whole, also through a reopen and a focus loss
  -- (a capped box would commit its cut text).
  local long, slang = {}, {}
  for i = 1, 60 do
    long[i] = "word" .. i
    slang[i] = "w" .. i .. "=belt"
  end
  Widgets.type(row("Intent words").input, table.concat(long, " "))
  Widgets.type(row("Extra slang (word=slot)").input, table.concat(slang, " "))
  ns.LeadsWindow.ToggleSettings()
  open(ns, "Keywords")
  for _, label in ipairs({ "Intent words", "Extra slang (word=slot)" }) do
    local box = row(label).input
    box:SetFocus()
    box:ClearFocus()
  end
  Assert.truthy(#table.concat(long, " ") > 255)
  Assert.same(settings.intentWords, long)
  local slangCount = 0
  for _ in pairs(settings.extraSlang) do
    slangCount = slangCount + 1
  end
  Assert.equal(slangCount, 60)
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

-- The visible recipe row showing recipe `key`.
local function rowOf(key)
  for _, frame in ipairs(Wow.frames) do
    if frame.icon and frame.item and frame.item.key == key and SettingsFixture.visible(frame) then
      return frame
    end
  end
  error("no visible recipe row " .. tostring(key))
end

local function iconOf(key)
  return rowOf(key).icon
end

-- §6.2: crafter enable/disable, removal and mute rebuild the index; the primary crafter is
-- read when a lead picks its crafter (§6.3 step 5), so it rebuilds nothing.
local function testCraftersPage()
  local ns, db, refreshes = SettingsFixture.load({ db = crafters })
  local me = db.characters["Me-Realm"]
  open(ns, "Crafters")
  take(refreshes)
  local character = row("Character").input
  Assert.equal(character.Text:GetText(), "Me-Realm (this character)", "opens on the current character")
  Widgets.pick(character, "Alt-Realm")
  Assert.equal(character.Text:GetText(), "Alt-Realm (same account)")
  Widgets.pick(character, "Far-Away")
  Assert.equal(character.Text:GetText(), "Far-Away (imported)")
  Widgets.pick(character, "Me-Realm")

  Widgets.click(row("Listen for this character").input)
  Assert.equal(me.enabled, false)
  Assert.same(take(refreshes), { "rebuild:crafter" })

  -- Primary: one crafter per profession; it is the shown character's for the shown profession.
  Assert.equal(row("Profession").input.Text:GetText(), "Blacksmithing")
  Widgets.click(row("Primary crafter for this profession").input)
  Assert.equal(me.professions[BS].primary, true)
  Assert.equal(db.characters["Alt-Realm"].professions[BS].primary, false, "the other primary is cleared")
  Widgets.click(row("Primary crafter for this profession").input)
  Assert.equal(me.professions[BS].primary, false, "switched off again")
  Assert.equal(db.characters["Alt-Realm"].professions[BS].primary, false, "nobody else gains it")
  Widgets.click(row("Primary crafter for this profession").input)
  Assert.same(take(refreshes), {})

  -- Recipes of that profession by name, with search; mute toggles the icon and rebuilds.
  local shown = texts()
  Assert.truthy(shown:find("Plate Greaves / Mute / Thick Plate Belt / Mute", 1, true), shown)
  Assert.falsy(shown:find("Enchant Bracer", 1, true))
  Widgets.type(row("Search recipes").input, "BELT")
  Assert.falsy(texts():find("Plate Greaves", 1, true))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Mute"))
  Assert.equal(me.recipes[9001].muted, true)
  Assert.same(take(refreshes), { "rebuild:mute" })
  Assert.truthy(texts():find("Thick Plate Belt / Unmute", 1, true))
  Assert.equal(iconOf(9001).desaturated, true, "a muted recipe's icon is grey")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Unmute"))
  Assert.equal(me.recipes[9001].muted, nil)
  Assert.equal(iconOf(9001).desaturated, false)
  Assert.same(take(refreshes), { "rebuild:mute" })
  Widgets.pick(row("Profession").input, ENCH)
  Assert.truthy(texts():find("Enchant Bracer - Health", 1, true), "the search clears with the profession")

  -- Remove asks for a second click, then drops the character and shows the next one.
  local remove = SettingsFixture.button(SettingsFixture.window(), "Remove character")
  Widgets.click(remove)
  Assert.truthy(db.characters["Me-Realm"], "not on the first click")
  Assert.same(take(refreshes), {})
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  Assert.equal(db.characters["Me-Realm"], nil)
  Assert.same(take(refreshes), { "rebuild:crafter" })
  Assert.equal(character.Text:GetText(), "Alt-Realm (same account)")
end

-- The recipe keys of the visible recipe rows, top to bottom.
local function shownRecipeKeys()
  local keys = {}
  for _, frame in ipairs(Wow.frames) do
    if frame.icon and frame.item and SettingsFixture.visible(frame) then
      keys[#keys + 1] = frame.item.key
    end
  end
  return keys
end

-- Names stored lowercase (read before the client spelling was kept) sort among the others, not
-- after them; names equal but for case keep one order, by recipe key.
local function testCraftersRecipeOrder()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { name = "Thick Plate Belt", prof = BS },
        [9002] = { name = "plate greaves", prof = BS },
        [9003] = { name = "Iron Rivet", prof = BS },
        [9004] = { name = "iron rivet", prof = BS },
        [10] = { name = "Copper Bar", prof = BS },
        [9] = { name = "copper bar", prof = BS },
        -- Name keys (as Classic stores recipes) among the IDs: text order alone would loop
        -- (9 < 10 by number, 10 < "1x" and "1x" < 9 as text).
        ["1x"] = { name = "Copper Bar", prof = BS },
        ["25y"] = { name = "Copper Bar", prof = BS },
      }
    end,
  })
  open(ns, "Crafters")
  -- Equal names: recipe IDs in number order (9 before 10), then name keys. The page shows 8 rows.
  Assert.same(shownRecipeKeys(), { 9, 10, "1x", "25y", 9003, 9004, 9002, 9001 })
end

-- Recipe rows show the crafted item's icon, else the recipe spell's (number keys), else the
-- addon icon (a name key from Classic has neither); a muted row is grey and dim.
local function testCraftersRecipeIcons()
  local ns, db = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      accountDb.characters["Me-Realm"].recipes = {
        [9001] = { item = 501, name = "Belt", prof = BS },
        [9002] = { name = "Bracer", prof = BS },
        ["Old Recipe"] = { name = "Old Recipe", prof = BS },
      }
    end,
  })
  Wow.stub("GetItemInfoInstant", function(id)
    return id, nil, nil, nil, "item-icon"
  end)
  Wow.stub("C_Spell", {
    GetSpellTexture = function(id)
      return id == 9002 and "spell-icon" or nil
    end,
  })
  open(ns, "Crafters")
  Assert.equal(iconOf(9001).texture, "item-icon", "item recipe")
  Assert.equal(iconOf(9002).texture, "spell-icon", "no item: the spell")
  Assert.equal(iconOf("Old Recipe").texture, ns.Theme.ICON, "name key: the addon icon")
  Assert.equal(iconOf(9001).desaturated, false)
  db.characters["Me-Realm"].recipes[9001].muted = true
  Widgets.pick(row("Profession").input, ENCH)
  Widgets.pick(row("Profession").input, BS)
  Assert.equal(iconOf(9001).desaturated, true, "muted: grey")
  Assert.equal(iconOf(9001).alpha, ns.Theme.DIM_ALPHA, "muted: dim")
  Assert.equal(iconOf(9001).texture, "item-icon", "muted keeps its icon")
end

-- Hovering a recipe row shows the item's tooltip, else the spell's, else none. Rows are reused
-- by the scroll: the tooltip reads the row's recipe at hover time, and a tooltip a row owns
-- follows the repaint.
local function testCraftersRecipeTooltip()
  local ns = SettingsFixture.load({
    db = function(accountDb)
      crafters(accountDb)
      local recipes = {
        [9001] = { item = 501, name = "A Belt", prof = BS },
        [9002] = { name = "B Bracer", prof = BS },
        ["Old Recipe"] = { name = "C Old Recipe", prof = BS },
      }
      for id = 1, 8 do
        recipes[9100 + id] = { item = 600 + id, name = "D " .. id, prof = BS }
      end
      accountDb.characters["Me-Realm"].recipes = recipes
    end,
  })
  open(ns, "Crafters")
  local tooltip = _G["GameTooltip"]
  local itemRow, spellRow, oldRow = rowOf(9001), rowOf(9002), rowOf("Old Recipe")

  Widgets.fire(itemRow, "OnEnter")
  Assert.equal(tooltip.owner, itemRow)
  Assert.equal(tooltip.anchor, "ANCHOR_RIGHT")
  Assert.equal(tooltip.itemId, 501)
  Assert.equal(tooltip.shown, true)
  Widgets.fire(itemRow, "OnLeave")
  Assert.equal(tooltip.shown, false)

  Widgets.fire(spellRow, "OnEnter")
  Assert.equal(tooltip.spellId, 9002)
  Assert.equal(tooltip.itemId, nil, "spell row: no item tooltip")
  Assert.equal(tooltip.shown, true)
  Widgets.fire(spellRow, "OnLeave")

  Widgets.fire(oldRow, "OnEnter")
  Assert.equal(tooltip.shown, false, "name key without an item: no tooltip")

  -- 11 recipes, 8 rows: each wheel step moves the rows one recipe. A row that owns the tooltip repaints it.
  local list = itemRow.parent
  Widgets.fire(itemRow, "OnEnter")
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.equal(itemRow.item.key, 9002)
  Assert.equal(tooltip.owner, itemRow)
  Assert.equal(tooltip.spellId, 9002, "repainted to the row's new recipe")
  Assert.equal(tooltip.itemId, nil)
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.equal(itemRow.item.key, "Old Recipe")
  Assert.equal(tooltip.shown, false, "repainted onto a name key: hidden")

  -- No tooltip open: the scroll shows none, the next hover shows the row's new recipe.
  Widgets.fire(itemRow, "OnLeave")
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.equal(tooltip.shown, false)
  Assert.equal(itemRow.item.key, 9101)
  Widgets.fire(itemRow, "OnEnter")
  Assert.equal(tooltip.itemId, 601)
  Assert.equal(tooltip.shown, true)
end

-- Removing the current character stores it again from the client at once (as at login), so its
-- profession windows keep recording instead of waiting for the next login.
local function testRemoveOwnCharacter()
  local ns, db = SettingsFixture.load({ db = crafters })
  Wow.stub("GetProfessions", function()
    return 1
  end)
  Wow.stub("GetProfessionInfo", function()
    return "Blacksmithing", nil, 1, 100, nil, nil, BS
  end)
  Wow.stub("C_AutoComplete", {
    GetAutoCompleteRealms = function()
      return { "Realm", "Twisting Nether" }
    end,
  })
  open(ns, "Crafters")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Remove character"))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  local me = db.characters["Me-Realm"]
  Assert.truthy(me, "stored again")
  Assert.same(me.recipes, {}, "its recipes are gone")
  Assert.same(me.professions, { [BS] = { name = "Blacksmithing", primary = false, read = false } })
  Assert.equal(ns.ProfessionList.IsStored(db, "Me-Realm", BS), true)
  -- Its connected realms are stored again too, as at login, so the realm tag knows them now.
  Assert.same(me.realms, { "Realm", "TwistingNether" })
  Assert.equal(ns.RealmTag.CannotOrder(db, "Me-Realm", "Bob-Draenor"), true)
  Assert.truthy(db.characters["Alt-Realm"].recipes[9001], "other characters are untouched")

  -- Another character is not the client's: it stays removed.
  local character = row("Character").input
  Widgets.pick(character, "Alt-Realm")
  Assert.equal(character.Text:GetText(), "Alt-Realm (same account)")
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Remove character"))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Click again to remove"))
  Assert.equal(db.characters["Alt-Realm"], nil, "an alt is not stored again")
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
  Wow.stub("C_FriendList", {
    IsIgnored = function()
      return true
    end,
  })
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
  testCraftersPage()
  testCraftersRecipeOrder()
  testCraftersRecipeIcons()
  testCraftersRecipeTooltip()
  testRemoveOwnCharacter()
  testTestPage()
end
