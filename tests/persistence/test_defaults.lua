local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function load(flavorKey)
  Wow.reset()
  Wow.flavor(flavorKey or "retail")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.Constants")
  return Fresh.require("Persistence.Defaults")
end

local function testSpecDefaults()
  local Defaults = load()
  local settings = Defaults.Settings()
  Assert.equal(settings.enable, true)
  Assert.equal(settings.onlyResting, true)
  Assert.same(settings.channels, { trade = true, services = true, general = false, lfg = false, guild = false, communities = false })
  Assert.equal(settings.professionWordAlerts, true)
  Assert.equal(settings.includeUnbound, false)
  Assert.equal(settings.recipeMarkers, true)
  Assert.equal(settings.sound, 8959)
  Assert.equal(settings.flash, true)
  Assert.equal(settings.toastDuration, 20)
  Assert.equal(settings.leadTimeoutMin, 10)
  Assert.equal(settings.hideLauncherWhenNoLeads, false)
  Assert.equal(settings.opacity, 1.0)
  Assert.same(settings.notes, {})
  Assert.same(settings.extraSlang, {})
  Assert.equal(settings.craftScanImported, nil)
  Assert.equal(settings.craftScanPrompted, nil)
  Assert.truthy(#settings.intentWords > 0)
  Assert.truthy(#settings.blockerWords > 0)
  Assert.truthy(settings.templates.item)
end

-- Every call returns tables nobody else holds: editing one result never leaks into the next
-- or into Constants.
local function testFreshCopies()
  local Defaults = load()
  local Constants = Fresh.require("Core.Constants")
  local first = Defaults.Settings()
  first.channels.trade = false
  first.intentWords[1] = "changed"
  first.templates.item = "changed"
  first.notes.x = "y"
  local second = Defaults.Settings()
  Assert.equal(second.channels.trade, true)
  Assert.equal(second.intentWords[1], Constants.intentWords[1])
  Assert.equal(second.templates.item, Constants.templates.retail.item)
  Assert.same(second.notes, {})
end

local function testPerFlavor()
  local Defaults = load("tbc")
  local Constants = Fresh.require("Core.Constants")
  local settings = Defaults.Settings()
  Assert.equal(settings.templates.altItem, Constants.templates.tbc.altItem)
  Assert.equal(settings.sound, Constants.flavors.tbc.soundKits[1])
  -- The flavor's own channel row is not the setting: General is off everywhere by default.
  Assert.equal(settings.channels.general, false)
end

local function testDb()
  local Defaults = load()
  local db = Defaults.Db()
  Assert.equal(db.schema, 1)
  Assert.same(db.characters, {})
  Assert.same(db.leads, {})
  Assert.same(db.ledger, {})
  Assert.same(db.recentGreeted, {})
  Assert.equal(db.ignored, nil, "Blizzard's ignore list replaced the saved block list")
  Assert.same(db.ui, {})
  Assert.same(db.settings, Defaults.Settings())
end

return function()
  testSpecDefaults()
  testFreshCopies()
  testPerFlavor()
  testDb()
end
