local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local MarkerFixture = require("tests.helpers.marker_fixture")
local RecipeListStub = require("tests.helpers.recipe_list_stub")

-- The mute switches on Blizzard's recipe rows (UI/RecipeMarkers/ModernRows.lua, spec
-- 2026-10-26-recipe-markers §6.3-6.5): which rows show a switch and how it looks, the window-wide
-- gates, what a click mutes, and repaints. Registration is test_modern_rows_install.lua. Rows,
-- nodes and recipe infos are write-trapping proxies, so any field written on a Blizzard table
-- fails the test.

local load, look = MarkerFixture.load, MarkerFixture.look
local switchOf = RecipeListStub.switchOf
local SPEAKER, MUTED = RecipeListStub.SPEAKER, RecipeListStub.MUTED

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

-- The row shows the highest learned rank's state, not the chain's last stored rank: rank 2 of
-- 301 < 302 < 303 has no binding (greyed), rank 3 is stored and bound but not learned. When that
-- rank is not stored (401 < 402), the chain's last stored record stands in for it.
local function testShownRankDecidesLook()
  local ns, db, list = load()
  local ranked, gap = list:row(301), list:row(401)
  ns.ModernRows.Install(db)
  Assert.same(look(ranked), { SPEAKER, true }, "rank 2 is learned and untracked; rank 3 would show on")
  Assert.same(look(gap), { SPEAKER, true }, "rank 2 is not stored: the last stored rank, untracked")
end

-- Blizzard's ForEachFrame stops at the first truthy return; the walk must paint the rows after a
-- category row and a hidden row, on install and on Refresh.
local function testWalkPaintsEveryRow()
  local ns, db, list = load()
  local category, hidden, first, second = list:row(nil), list:row(104), list:row(101), list:row(102)
  ns.ModernRows.Install(db)
  Assert.same({ look(first), look(second) }, { { SPEAKER, false }, { MUTED, false } }, "after the hide paths")
  db.settings.recipeMarkers = false
  ns.ModernRows.Refresh()
  db.settings.recipeMarkers = true
  ns.ModernRows.Refresh()
  Assert.same({ look(category), look(hidden) }, { "none", "none" })
  Assert.same({ look(first), look(second) }, { { SPEAKER, false }, { MUTED, false } }, "after a Refresh")
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
  testPaint()
  testPaintWithoutCharacter()
  testGates()
  testClickMutesChain()
  testRefreshRepaintsRows()
  testShownRankDecidesLook()
  testWalkPaintsEveryRow()
  testFallbackWithoutHelpers()
  Wow.reset()
end
