local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Fixture = require("tests.helpers.matcher_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

-- Spec §9 Linked accounts, §10.1, §10.2: export, import and the CraftScan button.
local BS = 164
local TITLE = "Linked accounts"

local function withSmith(db)
  db.characters["Me-Realm"] = Fixture.character({ BS }, { [9001] = { name = "Sim Plate Belt", prof = BS, item = 190001 } })
end

local function load(flavor)
  local ns, db, refreshes = SettingsFixture.load({ flavor = flavor, db = withSmith })
  SettingsFixture.open(ns, TITLE)
  return ns, db, refreshes
end

local function button(label)
  return SettingsFixture.button(SettingsFixture.window(), label)
end

local function box(label)
  return SettingsFixture.row(label).input
end

-- Another account's export string: Alt-Other with one Blacksmithing recipe.
local function otherAccount(ns, flavorKey)
  local other = ns.Defaults.Db()
  other.characters["Alt-Other"] = Fixture.character({ BS }, { [9004] = { name = "Sim Plate Helm", prof = BS, item = 190004 } })
  return ns.ExportString.Encode(other, flavorKey)
end

-- The export box: sliced, then this account's string; typing puts it back, focus selects it.
local function testExport()
  local ns = load()
  local export = box("Export string")
  Assert.equal(export:GetText(), "Making the string...")
  ns.Slicer.Drain()
  local text = export:GetText()
  Assert.truthy(text:find("^CA1:retail:c,Me%-Realm,"), text)
  Widgets.type(export, "typed over")
  Assert.equal(export:GetText(), text, "read-only")
  export.HighlightTextArgs = nil
  Widgets.fire(export, "OnEditFocusGained")
  Assert.truthy(export.HighlightTextArgs, "the focus selects the string")
  Assert.equal(export.maxLetters, 0, "no cap: a large account's string is about 100 KB")
end

-- Import: one click runs one sliced job; the result line, the list and the rebuild follow.
local function testImport()
  local ns, db, refreshes = load()
  ns.Slicer.Drain()
  SettingsFixture.take(refreshes)
  local import = box("Import string")
  Assert.truthy(SettingsFixture.texts():find("No characters imported yet.", 1, true))
  import:SetText(otherAccount(ns, "retail"))
  Widgets.click(button("Import"))
  Assert.equal(button("Import"):IsEnabled(), false, "one import at a time")
  Assert.truthy(SettingsFixture.texts():find("Importing...", 1, true))
  ns.Slicer.Drain()
  Assert.equal(button("Import"):IsEnabled(), true)
  Assert.same(SettingsFixture.take(refreshes), { "rebuild:import" })
  Assert.equal(db.characters["Alt-Other"].source, "import")
  Assert.equal(import:GetText(), "")
  local texts = SettingsFixture.texts()
  Assert.truthy(texts:find("Imported 1 character, 1 recipe (0 skipped).", 1, true), texts)
  Assert.truthy(texts:find("Alt-Other, imported " .. os.date("%Y-%m-%d", 1000), 1, true), texts)

  -- A refused string: its message, nothing stored, no rebuild.
  import:SetText("not a string")
  Widgets.click(button("Import"))
  ns.Slicer.Drain()
  Assert.truthy(SettingsFixture.texts():find("Not a Craft Alert export string.", 1, true))
  Assert.same(SettingsFixture.take(refreshes), {})
  import:SetText(otherAccount(ns, "tbc"))
  Widgets.click(button("Import"))
  ns.Slicer.Drain()
  Assert.truthy(SettingsFixture.texts():find("This string was made on tbc; this game is retail.", 1, true))
end

-- CraftScan: enabled only while CraftScan_DB is loaded; the import sets craftScanImported.
local function testCraftScan()
  local ns, db, refreshes = load()
  ns.Slicer.Drain()
  Assert.equal(button("Import from CraftScan"):IsEnabled(), false)
  Assert.truthy(SettingsFixture.texts():find("CraftScan's data is not loaded", 1, true))
  ProfessionsRetail.install({ recipes = { { id = 9004, name = "Sim Plate Helm", item = 190004 } } })
  Wow.stub("CraftScan_DB", dofile("tests/fixtures/craftscan_db.lua"))
  SettingsFixture.open(ns, "General")
  SettingsFixture.open(ns, TITLE)
  ns.Slicer.Drain()
  SettingsFixture.take(refreshes)
  Assert.equal(button("Import from CraftScan"):IsEnabled(), true)
  Widgets.click(button("Import from CraftScan"))
  Assert.equal(button("Import from CraftScan"):IsEnabled(), false)
  ns.Slicer.Drain()
  Assert.same(SettingsFixture.take(refreshes), { "rebuild:craftscan" })
  Assert.equal(db.settings.craftScanImported, 1000)
  Assert.truthy(db.characters["Scanalt-OwnRealm"].recipes[9004])
  local texts = SettingsFixture.texts()
  Assert.truthy(texts:find("CraftScan import: 3 characters, 1 recipe (0 muted) and 2 greetings (9 skipped).", 1, true), texts)
end

-- Enter in the import box imports as the button does; a second Enter while it runs does nothing.
local function testEnterImports()
  local ns, db = load()
  ns.Slicer.Drain()
  local import = box("Import string")
  Widgets.type(import, otherAccount(ns, "retail"))
  Assert.equal(button("Import"):IsEnabled(), false, "Enter started the import")
  Widgets.type(import, "not a string")
  ns.Slicer.Drain()
  Assert.equal(db.characters["Alt-Other"].source, "import")
  local texts = SettingsFixture.texts()
  Assert.truthy(texts:find("Imported 1 character, 1 recipe (0 skipped).", 1, true), texts)
end

-- A job that errors or is replaced (Slicer cancels it): the button comes back and no
-- "Importing..." or "Making the string..." stays behind; reopening restarts the export cleanly.
local function testCancelRecovers()
  local ns = load()
  local export = box("Export string")
  SettingsFixture.open(ns, "General")
  SettingsFixture.open(ns, TITLE)
  Assert.equal(export:GetText(), "Making the string...", "the restart's own placeholder stays")
  ns.Slicer.Cancel("export")
  Assert.equal(export:GetText(), "")
  box("Import string"):SetText(otherAccount(ns, "retail"))
  Widgets.click(button("Import"))
  ns.Slicer.Cancel("import")
  Assert.equal(button("Import"):IsEnabled(), true)
  ProfessionsRetail.install({ recipes = {} })
  Wow.stub("CraftScan_DB", dofile("tests/fixtures/craftscan_db.lua"))
  SettingsFixture.open(ns, "General")
  SettingsFixture.open(ns, TITLE)
  Widgets.click(button("Import from CraftScan"))
  ns.Slicer.Cancel("craftscan")
  Assert.equal(button("Import from CraftScan"):IsEnabled(), true)
  Assert.falsy(SettingsFixture.texts():find("Importing...", 1, true), SettingsFixture.texts())
end

-- Classic: no CraftScan section; the string names the client.
local function testClassic()
  local ns = load("tbc")
  ns.Slicer.Drain()
  Assert.truthy(box("Export string"):GetText():find("^CA1:tbc:"))
  Assert.falsy(SettingsFixture.texts():find("CraftScan", 1, true))
end

-- The import box says what goes in it.
local function testImportHint()
  load()
  Assert.truthy(SettingsFixture.texts():find("Paste the string from your other account here, then click Import.", 1, true))
end

return function()
  testExport()
  testImportHint()
  testImport()
  testCraftScan()
  testEnterImports()
  testCancelRecovers()
  testClassic()
  Wow.reset()
end
