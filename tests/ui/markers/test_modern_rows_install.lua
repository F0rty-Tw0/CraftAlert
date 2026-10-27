local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local MarkerFixture = require("tests.helpers.marker_fixture")
local RecipeListStub = require("tests.helpers.recipe_list_stub")

-- When the recipe markers register their row callback (UI/RecipeMarkers/ModernRows.lua, spec
-- 2026-10-26-recipe-markers §6.2): at login or when Blizzard_Professions loads, only while the
-- setting is on and the client has the list; the rows already on screen get their switch.

local load, look = MarkerFixture.load, MarkerFixture.look
local SPEAKER, MUTED = RecipeListStub.SPEAKER, RecipeListStub.MUTED

-- Blizzard_Professions loaded at login: one callback, without Blizzard's iterate (we walk the
-- existing rows ourselves), and the rows already on screen get their switch.
local function testInstallWhenLoaded()
  local ns, db, list = load()
  local row = list:row(101)
  ns.ModernRows.Install(db)
  Assert.equal(#list.callbacks, 1)
  local call = list.callbacks[1]
  Assert.same({ call.box, call.owner, call.iterate }, { list.box, ns.ModernRows, false })
  Assert.same(look(row), { SPEAKER, false }, "existing row painted")
  local fresh = list:row(102)
  list:init(fresh, 102)
  Assert.same(look(fresh), { MUTED, false }, "a row initialized later is painted through the callback")
end

-- Not loaded at login: hooks on ADDON_LOADED of Blizzard_Professions only, then stops listening.
local function testInstallWaitsForAddon()
  local ns, db, list = load({ loaded = false })
  local row = list:row(101)
  ns.ModernRows.Install(db)
  Assert.equal(#list.callbacks, 0, "not loaded: nothing registered")
  Wow.fireEvent("ADDON_LOADED", "SomeOtherAddon")
  Assert.equal(#list.callbacks, 0)
  Wow.fireEvent("ADDON_LOADED", "Blizzard_Professions")
  Assert.equal(#list.callbacks, 1)
  Assert.equal(list.callbacks[1].iterate, false)
  Assert.same(look(row), { SPEAKER, false })
  for _, frame in ipairs(Wow.frames) do
    Assert.falsy(frame.events.ADDON_LOADED, "stopped listening")
  end
end

-- No IsAddOnLoaded on the client: treated as not loaded, so Install listens.
local function testInstallWithoutApi()
  local ns, db, list = load({ apiMissing = true })
  ns.ModernRows.Install(db)
  Assert.equal(#list.callbacks, 0)
  Wow.fireEvent("ADDON_LOADED", "Blizzard_Professions")
  Assert.equal(#list.callbacks, 1)
end

-- Setting off: nothing registered at all; turned on, Refresh registers once.
local function testSettingOffRegistersNothing()
  local ns, db, list = load({
    db = function(accountDb)
      accountDb.settings.recipeMarkers = false
    end,
  })
  local row = list:row(101)
  ns.ModernRows.Install(db)
  Assert.equal(#list.callbacks, 0)
  Assert.equal(look(row), "none")
  db.settings.recipeMarkers = true
  ns.ModernRows.Refresh()
  Assert.equal(#list.callbacks, 1)
  Assert.same(look(row), { SPEAKER, false })
  ns.ModernRows.Refresh()
  Assert.equal(#list.callbacks, 1, "registered once")
end

-- Setting off when Blizzard_Professions loads: no hook, no more listening; turned on later, the
-- loaded addon is remembered even without IsAddOnLoaded.
local function testSettingOnAfterAddonLoaded()
  local ns, db, list = load({
    apiMissing = true,
    db = function(accountDb)
      accountDb.settings.recipeMarkers = false
    end,
  })
  local row = list:row(101)
  ns.ModernRows.Install(db)
  Wow.fireEvent("ADDON_LOADED", "Blizzard_Professions")
  Assert.equal(#list.callbacks, 0)
  db.settings.recipeMarkers = true
  ns.ModernRows.Refresh()
  Assert.equal(#list.callbacks, 1)
  Assert.same(look(row), { SPEAKER, false })
end

-- A client without the list's ScrollBox or without ScrollUtil: nothing registered, no error.
local function testMissingClientParts()
  local ns, db, list = load({ noScrollBox = true })
  ns.ModernRows.Install(db)
  ns.ModernRows.Refresh()
  Assert.equal(#list.callbacks, 0)

  ns, db, list = load({ noScrollUtil = true })
  local row = list:row(101)
  ns.ModernRows.Install(db)
  ns.ModernRows.Refresh()
  Assert.equal(look(row), "none")
end

-- Refresh before Install (a settings toggle before login, or on Classic) reads nothing.
local function testRefreshBeforeInstall()
  local ns = load()
  local trap = setmetatable({}, {
    __index = function(_, key)
      error("read " .. tostring(key))
    end,
  })
  Wow.stub("ProfessionsFrame", trap)
  Wow.stub("ScrollUtil", trap)
  ns.ModernRows.Refresh()
end

return function()
  testInstallWhenLoaded()
  testInstallWaitsForAddon()
  testInstallWithoutApi()
  testSettingOffRegistersNothing()
  testSettingOnAfterAddonLoaded()
  testMissingClientParts()
  testRefreshBeforeInstall()
  Wow.reset()
end
