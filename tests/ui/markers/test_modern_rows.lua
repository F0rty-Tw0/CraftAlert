local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local RecipeListStub = require("tests.helpers.recipe_list_stub")

-- The mute switches on Blizzard's recipe rows (UI/RecipeMarkers/ModernRows.lua, spec
-- 2026-10-26-recipe-markers §6.2-6.5): when the hook registers, which rows show a switch and how
-- it looks, the window-wide gates, what a click mutes, and repaints. Rows, nodes and recipe infos
-- are write-trapping proxies, so any field written on a Blizzard table fails the test.

-- Blizzard's recipes: single ranks 101-106 and the rank chain 201 < 202 < 203.
local RECIPES = {
  [101] = { learned = true },
  [102] = { learned = true },
  [103] = { learned = true },
  [104] = { learned = true },
  [105] = { learned = false },
  [106] = { learned = true, disabled = true },
  [201] = { learned = true },
  [202] = { learned = true },
  [203] = { learned = true },
}
local CHAINS = { { 201, 202, 203 } }

-- Me-Realm's stored records: 104 is not stored; 105 is stored though unlearned (the learn path
-- does not check `learned`).
local function stored()
  return {
    [101] = { name = "On", bind = 4 },
    [102] = { name = "Muted", bind = 4, muted = true },
    [103] = { name = "Unbound", bind = 0 },
    [105] = { name = "Unlearned", bind = 4 },
    [106] = { name = "Disabled", bind = 4 },
    [201] = { name = "Rank 1", bind = 4 },
    [202] = { name = "Rank 2", bind = 4 },
    [203] = { name = "Rank 3", bind = 4 },
  }
end

-- opts.loaded / noHelpers / noScrollBox / noScrollUtil: RecipeListStub's; opts.loaded defaults to
-- true. opts.noCharacter: no Me-Realm record. opts.db(db): edits before the modules load.
local function load(opts)
  opts = opts or {}
  local ns, db = UiFixture.load({
    db = function(accountDb)
      if not opts.noCharacter then
        accountDb.characters["Me-Realm"] = { source = "local", enabled = true, realms = { "Realm" }, professions = {}, recipes = stored() }
      end
      if opts.db then
        opts.db(accountDb)
      end
    end,
  })
  local loaded = opts.loaded
  if loaded == nil and not opts.apiMissing then
    loaded = true
  end
  local list = RecipeListStub.install({
    recipes = RECIPES,
    chains = CHAINS,
    loaded = loaded,
    noHelpers = opts.noHelpers,
    noScrollBox = opts.noScrollBox,
    noScrollUtil = opts.noScrollUtil,
  })
  return ns, db, list
end

-- Our switch on `row` (its only child frame), or nil.
local function switchOf(row)
  for _, frame in ipairs(Wow.frames) do
    if frame.parent == row then
      return frame
    end
  end
  return nil
end

local function shown(row)
  local switch = switchOf(row)
  return switch ~= nil and switch:IsShown()
end

-- What the switch on `row` shows: { atlas, desaturated }, or "none".
local function look(row)
  if not shown(row) then
    return "none"
  end
  local switch = assert(switchOf(row))
  return { switch.icon.atlas, switch.icon.desaturated == true }
end

local SPEAKER, MUTED = "voicechat-icon-speaker", "voicechat-icon-speaker-mute"

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

-- Only a learned, enabled, stored recipe row gets a switch; it is 14 × 14 at the row's right end
-- and shows the recipe's state: speaker, crossed out while muted, greyed while untracked.
local function testPaint()
  local ns, db, list = load()
  local rows = {}
  for _, id in ipairs({ 101, 102, 103, 104, 105, 106 }) do
    rows[id] = list:row(id)
  end
  local category = list:row(nil)
  ns.ModernRows.Install(db)
  Assert.same(look(rows[101]), { SPEAKER, false }, "on")
  Assert.same(look(rows[102]), { MUTED, false }, "muted")
  Assert.same(look(rows[103]), { SPEAKER, true }, "untracked: greyed")
  Assert.equal(look(rows[104]), "none", "not stored")
  Assert.equal(look(rows[105]), "none", "not learned")
  Assert.equal(look(rows[106]), "none", "disabled: the lock sits there")
  Assert.equal(look(category), "none", "category row")
  local switch = assert(switchOf(rows[101]))
  Assert.same({ switch:GetWidth(), switch:GetHeight() }, { 14, 14 })
  Assert.same(switch.points[1], { "RIGHT", rows[101], "RIGHT", 0, 0 })
  Assert.equal(switch.recipe, db.characters["Me-Realm"].recipes[101], "the tooltip's recipe is our record")
end

-- A character with no stored record shows nothing.
local function testPaintWithoutCharacter()
  local ns, db, list = load({ noCharacter = true })
  local row = list:row(101)
  ns.ModernRows.Install(db)
  Assert.equal(look(row), "none")
end

-- Window-wide gates hide every switch on Refresh, and rows initialized meanwhile stay hidden;
-- once cleared, Refresh shows them again.
local function testGates()
  local ns, db, list = load()
  local on, muted = list:row(101), list:row(102)
  ns.ModernRows.Install(db)
  local function both()
    return { look(on), look(muted) }
  end
  local visible = { { SPEAKER, false }, { MUTED, false } }
  Assert.same(both(), visible)

  local inInstance = true
  Wow.stub("IsInInstance", function()
    return inInstance
  end)
  ns.ModernRows.Refresh()
  Assert.same(both(), { "none", "none" }, "instance")
  list:init(on, 101)
  Assert.equal(look(on), "none", "a row initialized in an instance stays hidden")
  inInstance = false
  ns.ModernRows.Refresh()
  Assert.same(both(), visible, "left the instance")

  Wow.stub("C_TradeSkillUI", {
    IsTradeSkillLinked = function()
      return true
    end,
  })
  ns.ModernRows.Refresh()
  Assert.same(both(), { "none", "none" }, "a linked list")
  Wow.stub("C_TradeSkillUI", {})
  ns.ModernRows.Refresh()
  Assert.same(both(), visible)

  db.settings.recipeMarkers = false
  ns.ModernRows.Refresh()
  Assert.same(both(), { "none", "none" }, "setting off")
  db.settings.recipeMarkers = true
  ns.ModernRows.Refresh()
  Assert.same(both(), visible)
end

local function mutedRanks(db)
  local recipes = db.characters["Me-Realm"].recipes
  return { recipes[201].muted, recipes[202].muted, recipes[203].muted }
end

-- A click mutes every stored rank of the chain unless all are muted already, repaints at once and
-- requests a rebuild; it never reaches the row (no select, no favorite menu).
local function testClickMutesChain()
  local ns, db, list = load()
  local row = list:row(201)
  ns.ModernRows.Install(db)
  local recipes = db.characters["Me-Realm"].recipes
  Assert.equal(switchOf(row).recipe, recipes[203], "the row shows the highest learned rank")

  ns.Index.lastReason = nil
  Widgets.click(switchOf(row))
  Assert.same(mutedRanks(db), { true, true, true }, "all unmuted → all muted")
  Assert.same(look(row), { MUTED, false }, "repainted at once")
  Assert.equal(ns.Index.lastReason, "mute")

  recipes[201].muted, recipes[203].muted = nil, nil
  ns.ModernRows.Refresh()
  Assert.same(look(row), { SPEAKER, false }, "partly muted shows on")
  Widgets.click(switchOf(row))
  Assert.same(mutedRanks(db), { true, true, true }, "partly muted → all muted")

  Widgets.click(switchOf(row))
  Assert.same(mutedRanks(db), { nil, nil, nil }, "all muted → all unmuted")
  Assert.same(look(row), { SPEAKER, false })
  Assert.same(list.clicks, { method = 0, script = 0 }, "the row's own click never ran")
end

-- One recipe on two rows (Favorites): the refresh after a click repaints both. A reused row shows
-- its new recipe, and a click on it mutes that recipe, not the one it showed before.
local function testRefreshRepaintsRows()
  local ns, db, list = load()
  local first, second = list:row(101), list:row(101)
  ns.ModernRows.Install(db)
  Widgets.click(switchOf(first))
  ns.ModernRows.Refresh()
  Assert.same({ look(first), look(second) }, { { MUTED, false }, { MUTED, false } })

  local recipes = db.characters["Me-Realm"].recipes
  list:init(first, 103)
  Assert.same(look(first), { SPEAKER, true }, "reused for the untracked recipe")
  Widgets.click(switchOf(first))
  Assert.equal(recipes[103].muted, true)
  Assert.equal(recipes[101].muted, true, "the old recipe is untouched")
  Widgets.click(switchOf(first))
  Assert.equal(recipes[103].muted, nil)
  Assert.equal(recipes[101].muted, true)
end

-- Without the Professions rank helpers the chain is the shown recipe's own record.
local function testFallbackWithoutHelpers()
  local ns, db, list = load({ noHelpers = true })
  local ranked, unstored, unlearned = list:row(202), list:row(104), list:row(105)
  ns.ModernRows.Install(db)
  Assert.same(look(ranked), { SPEAKER, false })
  Assert.equal(look(unstored), "none")
  Assert.equal(look(unlearned), "none")
  Widgets.click(switchOf(ranked))
  Assert.same(mutedRanks(db), { nil, true, nil }, "only the shown rank")
end

return function()
  testInstallWhenLoaded()
  testInstallWaitsForAddon()
  testInstallWithoutApi()
  testSettingOffRegistersNothing()
  testSettingOnAfterAddonLoaded()
  testMissingClientParts()
  testRefreshBeforeInstall()
  testPaint()
  testPaintWithoutCharacter()
  testGates()
  testClickMutesChain()
  testRefreshRepaintsRows()
  testFallbackWithoutHelpers()
  Wow.reset()
end
