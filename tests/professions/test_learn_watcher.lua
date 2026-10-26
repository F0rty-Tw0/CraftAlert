local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local EVENT = "NEW_RECIPE_LEARNED"
local BS, ENCH, COOKING = 164, 333, 185
local CHAR = "Me-Realm"

-- "Me-Realm" knows Blacksmithing and Enchanting. Recipes are not `learned` yet, as inside the event.
-- withoutDb: the reader is installed before the saved data loaded.
local function setup(flavor, withoutDb)
  local ns = Fixture.load(flavor)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  local state = ProfessionsRetail.install({
    slots = { { name = "Blacksmithing", skillLine = BS }, { name = "Enchanting", skillLine = ENCH } },
  })
  ns.PlayerName.Init()
  local db = ns.Defaults.Db()
  Fresh.require("Professions.ProfessionList").Refresh(db, CHAR)
  Fresh.require("Professions.BindLookup")
  local ModernReader = Fresh.require("Professions.ModernReader")
  local LearnWatcher = Fresh.require("Professions.LearnWatcher")
  local run = { builds = 0, reasons = {} }
  ns.Index.Configure(db, {})
  ns.Index.OnRebuilt(function()
    run.builds = run.builds + 1
    run.reasons[#run.reasons + 1] = ns.Index.lastReason
  end)
  ModernReader.Install(not withoutDb and db or nil)
  LearnWatcher.Install()
  return ns, state, LearnWatcher, db, run
end

local function recipe(id, profession)
  return { id = id, name = "Recipe " .. id, item = 1000 + id, profession = profession or { professionID = 2872, parentProfessionID = BS } }
end

-- Makes the recipe-to-profession lookup raise `message`: proves a handler stopped before it.
local function trapProfessionApi(message)
  _G["C_TradeSkillUI"].GetProfessionInfoByRecipeID = function()
    error(message)
  end
end

return function()
  for _, flavor in ipairs({ "retail", "forever" }) do
    local ns, state, LearnWatcher, db, run = setup(flavor)
    Assert.truthy(Wow.frames[1]:IsEventRegistered(EVENT), flavor)

    -- A learn adds the recipe, listening, through the parent profession (never `learned`).
    state.recipes = { recipe(1) }
    Wow.fireEvent(EVENT, 1)
    Assert.equal(LearnWatcher.lastStored, true)
    Assert.same(db.characters[CHAR].recipes[1], { item = 1001, name = "Recipe 1", prof = BS, line = 2872 })
    Assert.equal(Wow.pendingTimers(0), 1)
    Wow.runTimers()
    Assert.same(run.reasons, { "learn" })
    Assert.truthy(ns.Index.Current().itemIndex[1001], "the new recipe is in the index")

    -- A profession without a parent is its own key.
    state.recipes[2] = recipe(2, { professionID = ENCH })
    Wow.fireEvent(EVENT, 2)
    Assert.equal(db.characters[CHAR].recipes[2].prof, ENCH)

    -- A profession the character does not store (Cooking) and an unknown recipe store nothing.
    state.recipes[3] = recipe(3, { professionID = COOKING })
    Wow.fireEvent(EVENT, 3)
    Assert.equal(LearnWatcher.lastStored, false)
    Assert.equal(db.characters[CHAR].recipes[3], nil)
    Wow.fireEvent(EVENT, 404)
    Assert.equal(LearnWatcher.lastStored, false)
  end

  -- With a stored profession's window open, a learn the window lists answered with a bare skill
  -- line the character does not store (no parent) belongs to the window, as in the window read;
  -- a parented unstored answer is still skipped, a recipe the window does not list borrows no
  -- key, and a blocked or closed window lends no key.
  local _, state, LearnWatcher, db = setup()
  state.base = BS
  Wow.fireEvent("TRADE_SKILL_SHOW")
  local bareCooking = recipe(5, { professionID = COOKING })
  bareCooking.unlisted = true
  local unloaded = recipe(6, { professionID = 0 })
  unloaded.unlisted = true
  state.recipes = {
    recipe(1, { professionID = 2872 }),
    recipe(2, { professionID = 2872, parentProfessionID = COOKING }),
    recipe(3, { professionID = 2872 }),
    recipe(4, { professionID = 2872 }),
    bareCooking,
    unloaded,
  }
  Wow.fireEvent(EVENT, 1)
  Assert.equal(LearnWatcher.lastStored, true, "a bare skill line proves no other profession")
  Assert.equal(db.characters[CHAR].recipes[1].prof, BS)
  Wow.fireEvent(EVENT, 2)
  Assert.equal(LearnWatcher.lastStored, false, "a parented unstored answer")
  Assert.equal(db.characters[CHAR].recipes[2], nil)
  Wow.fireEvent(EVENT, 5)
  Assert.equal(LearnWatcher.lastStored, false, "a bare Cooking learn the window does not list")
  Assert.equal(db.characters[CHAR].recipes[5], nil)
  Wow.fireEvent(EVENT, 6)
  Assert.equal(LearnWatcher.lastStored, false, "an unloaded answer the window does not list")
  Assert.equal(db.characters[CHAR].recipes[6], nil)
  state.guards.IsTradeSkillLinked = true
  Wow.fireEvent(EVENT, 3)
  Assert.equal(LearnWatcher.lastStored, false, "a linked window is somebody else's")
  state.guards.IsTradeSkillLinked = nil
  Wow.fireEvent("TRADE_SKILL_CLOSE")
  Wow.fireEvent(EVENT, 4)
  Assert.equal(LearnWatcher.lastStored, false, "no window to fall back to")
  Assert.equal(db.characters[CHAR].recipes[4], nil)

  -- A learn with the window open before the saved data loaded reads no data and stores nothing.
  _, state, LearnWatcher = setup(nil, true)
  state.base = BS
  Wow.fireEvent("TRADE_SKILL_SHOW")
  state.recipes = { recipe(1, { professionID = 2872 }) }
  Wow.fireEvent(EVENT, 1)
  Assert.equal(LearnWatcher.lastStored, false, "no saved data yet")

  -- A secret recipe ID is ignored before anything else is called.
  local run
  _, state, LearnWatcher, db, run = setup()
  state.recipes = { recipe(1) }
  trapProfessionApi("a secret recipeID reached the API")
  Wow.fireEvent(EVENT, Wow.secret(1))
  Assert.equal(LearnWatcher.lastStored, false)
  Assert.same(db.characters[CHAR].recipes, {})
  Assert.equal(Wow.pendingTimers(0), 0)
  Assert.equal(run.builds, 0)

  -- Bulk learning (Review Focus 4): 30 learns before the timers run → one rebuild.
  _, state, _, db, run = setup()
  for id = 1, 30 do
    state.recipes[id] = recipe(id)
  end
  for id = 1, 30 do
    Wow.fireEvent(EVENT, id)
  end
  Assert.equal(Wow.pendingTimers(0), 1, "one pending C_Timer.After")
  Wow.runTimers()
  Assert.equal(run.builds, 1)
  for id = 1, 30 do
    Assert.truthy(db.characters[CHAR].recipes[id], "recipe " .. id)
  end

  -- In an instance a learn calls no profession API and stores nothing.
  _, state, LearnWatcher, db, run = setup()
  state.recipes = { recipe(1) }
  trapProfessionApi("a learn in an instance reached the API")
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  LearnWatcher.lastStored = nil
  Wow.fireEvent(EVENT, 1)
  Assert.equal(LearnWatcher.lastStored, nil, "the handler stopped first")
  Assert.same(db.characters[CHAR].recipes, {})
  Assert.equal(run.builds, 0)
  Wow.stub("IsInInstance", nil)
end
