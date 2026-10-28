local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local BS, ENCH = 164, 333

local function load()
  Wow.reset()
  return Fresh.require("Professions.RecipeStore")
end

local function r(prof, line, extra)
  local recipe = { name = "r", prof = prof, line = line }
  for key, value in pairs(extra or {}) do
    recipe[key] = value
  end
  return recipe
end

local function testLineRank()
  local RecipeStore = load()
  local recipes = {
    [100] = r(BS, 1),
    [300] = r(BS, 1),
    [900] = r(BS, 1),
    [50] = r(BS, 2),
    [60] = r(BS, 2),
    [5] = r(ENCH, 1),
    ["named"] = r(BS, 1),
    [7] = r(BS, nil),
  }
  Assert.equal(RecipeStore.LineRank(recipes, BS, 1), 300, "median of 100, 300, 900; name key and other profession ignored")
  Assert.equal(RecipeStore.LineRank(recipes, BS, 2), 55, "even count: mean of the middle two")
  Assert.equal(RecipeStore.LineRank(recipes, BS, 3), nil, "no recipe of that line")
  Assert.equal(RecipeStore.LineRank({}, BS, 1), nil)
end

local function testNewestLine()
  local RecipeStore = load()
  -- 8.0 renumbering: Classic is 2540, Kul Tiran 2533 (lower ID, newer recipes).
  local renumbered = {
    [2385] = r(BS, 2540),
    [3908] = r(BS, 2540),
    [3909] = r(BS, 2540),
    [250001] = r(BS, 2533),
    [250002] = r(BS, 2533),
  }
  Assert.equal(RecipeStore.NewestLine(renumbered, BS), 2533, "newest by recipe-ID rank, not by line ID")
  -- A stray high-ID recipe patched into an old line does not make it newest (median).
  local stray = {
    [2385] = r(BS, 2540),
    [3908] = r(BS, 2540),
    [3909] = r(BS, 2540),
    [440000] = r(BS, 2540),
    [446001] = r(BS, 2883),
    [446002] = r(BS, 2883),
    [446003] = r(BS, 2883),
  }
  Assert.equal(RecipeStore.NewestLine(stray, BS), 2883)
  -- Equal ranks: the higher line ID wins ({1, 3} and {2} both rank 2).
  Assert.equal(RecipeStore.NewestLine({ [1] = r(BS, 10), [3] = r(BS, 10), [2] = r(BS, 20) }, BS), 20)
  Assert.equal(RecipeStore.NewestLine({ [1] = r(BS, 20), [3] = r(BS, 20), [2] = r(BS, 10) }, BS), 20)
  -- No line at all (Classic name keys, lineless recipes, other profession) → nil.
  Assert.equal(RecipeStore.NewestLine({ ["a"] = r(BS, 5), [1] = r(BS, nil), [2] = r(ENCH, 9) }, BS), nil)
  Assert.equal(RecipeStore.NewestLine({}, BS), nil)
end

local function testOnlyNewest()
  local RecipeStore = load()
  local recipes = {
    [1] = r(BS, 10),
    [2] = r(BS, 20, { muted = true }),
    [3] = r(BS, nil),
    [4] = r(ENCH, 10),
    [5] = r(BS, 10, { muted = true }),
    [6] = r(BS, nil, { muted = true }),
  }
  Assert.equal(RecipeStore.OnlyNewest(recipes, BS, 20), 2, "[1] muted, [2] unmuted; [5] already muted")
  Assert.equal(recipes[1].muted, true)
  Assert.equal(recipes[2].muted, nil, "an unmuted recipe keeps no muted field")
  Assert.equal(recipes[3].muted, nil, "lineless recipe untouched")
  Assert.equal(recipes[4].muted, nil, "other profession untouched")
  Assert.equal(recipes[6].muted, true, "lineless muted recipe untouched")
  Assert.equal(RecipeStore.OnlyNewest(recipes, BS, 20), 0, "second call changes nothing")
end

local function testExpansionName()
  local RecipeStore = load()
  Wow.stub("C_TradeSkillUI", nil)
  Assert.equal(RecipeStore.ExpansionName(2918), nil, "no api")
  Wow.stub("C_TradeSkillUI", {})
  Assert.equal(RecipeStore.ExpansionName(2918), nil, "no GetProfessionInfoBySkillLineID")
  local names = { [2918] = "Midnight", [2883] = "" }
  Wow.stub("C_TradeSkillUI", {
    GetProfessionInfoBySkillLineID = function(id)
      return { professionID = id, expansionName = names[id] }
    end,
  })
  Assert.equal(RecipeStore.ExpansionName(2918), "Midnight")
  Assert.equal(RecipeStore.ExpansionName(2883), nil, "empty name")
  Assert.equal(RecipeStore.ExpansionName(1), nil, "no name")
end

return function()
  testLineRank()
  testNewestLine()
  testOnlyNewest()
  testExpansionName()
end
