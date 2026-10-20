local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local EVENT = "NEW_RECIPE_LEARNED"
local BS, ENCH, COOKING = 164, 333, 185
local CHAR = "Me-Realm"

-- "Me-Realm" knows Blacksmithing and Enchanting. Recipes are not `learned` yet, as inside the event.
local function setup(flavor)
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
  ModernReader.Install(db)
  LearnWatcher.Install()
  return ns, state, LearnWatcher, db, run
end

local function recipe(id, profession)
  return { id = id, name = "Recipe " .. id, item = 1000 + id, profession = profession or { professionID = 2872, parentProfessionID = BS } }
end

return function()
  for _, flavor in ipairs({ "retail", "forever" }) do
    local ns, state, LearnWatcher, db, run = setup(flavor)
    Assert.truthy(Wow.frames[1]:IsEventRegistered(EVENT), flavor)

    -- A learn adds the recipe, listening, through the parent profession (never `learned`).
    state.recipes = { recipe(1) }
    Wow.fireEvent(EVENT, 1)
    Assert.equal(LearnWatcher.lastStored, true)
    Assert.same(db.characters[CHAR].recipes[1], { item = 1001, name = "recipe 1", prof = BS })
    Assert.equal(#Wow.timers, 1)
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

  -- A secret recipe ID is ignored before anything else is called.
  local _, state, LearnWatcher, db, run = setup()
  state.recipes = { recipe(1) }
  _G["C_TradeSkillUI"].GetProfessionInfoByRecipeID = function()
    error("a secret recipeID reached the API")
  end
  Wow.fireEvent(EVENT, Wow.secret(1))
  Assert.equal(LearnWatcher.lastStored, false)
  Assert.same(db.characters[CHAR].recipes, {})
  Assert.equal(#Wow.timers, 0)
  Assert.equal(run.builds, 0)

  -- Bulk learning (Review Focus 4): 30 learns before the timers run → one rebuild.
  _, state, _, db, run = setup()
  for id = 1, 30 do
    state.recipes[id] = recipe(id)
  end
  for id = 1, 30 do
    Wow.fireEvent(EVENT, id)
  end
  Assert.equal(#Wow.timers, 1, "one pending C_Timer.After")
  Wow.runTimers()
  Assert.equal(run.builds, 1)
  for id = 1, 30 do
    Assert.truthy(db.characters[CHAR].recipes[id], "recipe " .. id)
  end
end
