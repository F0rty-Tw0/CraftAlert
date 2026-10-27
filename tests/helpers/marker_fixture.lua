-- The recipe markers' test world (UI/RecipeMarkers/ModernRows.lua): Blizzard's recipe list
-- (RecipeListStub) over the real UI modules, with Me-Realm's stored records.
--   local ns, db, list = MarkerFixture.load({ loaded = false })
--   MarkerFixture.look(row)   -- what the switch on `row` shows: { atlas, desaturated }, or "none"
-- opts.loaded / noHelpers / noScrollBox / noScrollUtil: RecipeListStub's; opts.loaded defaults to
-- true unless opts.apiMissing, which leaves C_AddOns and IsAddOnLoaded missing.
-- opts.noCharacter: no Me-Realm record. opts.db(db): edits before the modules load.
local UiFixture = require("tests.helpers.ui_fixture")
local RecipeListStub = require("tests.helpers.recipe_list_stub")

local MarkerFixture = {}

-- Blizzard's recipes: single ranks 101-106 and the rank chains 201 < 202 < 203, 301 < 302 < 303
-- (303 not learned) and 401 < 402.
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
  [301] = { learned = true },
  [302] = { learned = true },
  [303] = { learned = false },
  [401] = { learned = true },
  [402] = { learned = true },
}
local CHAINS = { { 201, 202, 203 }, { 301, 302, 303 }, { 401, 402 } }

-- Me-Realm's stored records: 104 and 402 are not stored; 105 and 303 are stored though unlearned
-- (the learn path does not check `learned`); 302 and 401 have no binding.
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
    [301] = { name = "Ranked 1", bind = 4 },
    [302] = { name = "Ranked 2", bind = 0 },
    [303] = { name = "Ranked 3", bind = 4 },
    [401] = { name = "Gap 1", bind = 0 },
  }
end

function MarkerFixture.load(opts)
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

function MarkerFixture.look(row)
  local switch = RecipeListStub.switchOf(row)
  if switch == nil or not switch:IsShown() then
    return "none"
  end
  return { switch.icon.atlas, switch.icon.desaturated == true }
end

return MarkerFixture
