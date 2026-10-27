local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- The recipe marker's state (UI/RecipeMarkers/MarkerState.lua): which look the mute switch paints
-- for a recipe's rank chain and the rank the row shows.
local function load(includeUnbound)
  Wow.reset()
  Wow.flavor("retail")
  _G["CraftAlertDB"] = { settings = { includeUnbound = includeUnbound } }
  Fresh.require("Core.FlavorCompat")
  Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  Fresh.require("UI.Settings.RecipeMute")
  return Fresh.require("UI.RecipeMarkers.MarkerState")
end

local function testHiddenWithoutChain()
  Assert.equal(load(false).Of({}, nil), "hidden")
end

local function testMutedWinsOverUntracked()
  local MarkerState = load(false)
  local chain = { { muted = true }, { muted = true } }
  Assert.equal(MarkerState.Of(chain, chain[2]), "muted")
  chain[2].bind = 0
  Assert.equal(MarkerState.Of(chain, chain[2]), "muted")
end

local function testUntrackedFollowsSetting()
  local chain = { { bind = 0 } }
  Assert.equal(load(false).Of(chain, chain[1]), "untracked")
  Assert.equal(load(true).Of(chain, chain[1]), "on")
  chain = { { bind = 4 } }
  Assert.equal(load(false).Of(chain, chain[1]), "on")
end

local function testPartlyMutedChainFollowsShownRank()
  local MarkerState = load(false)
  local chain = { { muted = true, bind = 4 }, { bind = 4 } }
  Assert.equal(MarkerState.Of(chain, chain[2]), "on")
  chain[2].bind = 0
  Assert.equal(MarkerState.Of(chain, chain[2]), "untracked")
end

return function()
  testHiddenWithoutChain()
  testMutedWinsOverUntracked()
  testUntrackedFollowsSetting()
  testPartlyMutedChainFollowsShownRank()
  Wow.reset()
end
