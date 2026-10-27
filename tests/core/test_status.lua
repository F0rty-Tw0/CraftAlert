local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function listening(overrides)
  local state = { active = true, channels = { "Trade", "Services" }, recipeCount = 214, crafterCount = 3 }
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end
  return state
end

local function paused(reason, unreadProfession)
  return { active = false, reason = reason, channels = { "Trade" }, recipeCount = 0, crafterCount = 0, unreadProfession = unreadProfession }
end

return function()
  Wow.reset()
  -- Pure: loads and answers with nothing but its own file (no ScanGate, no WoW API).
  local Status = Fresh.require("Core.Status")

  -- §7.6: the listening line names the channels and the index size.
  Assert.equal(Status.Text(listening()), "Listening in Trade, Services — 214 recipes, 3 crafters")
  Assert.equal(Status.Text(listening({ channels = { "Trade" }, recipeCount = 1, crafterCount = 1 })), "Listening in Trade — 1 recipe, 1 crafter")
  Assert.equal(Status.Text(listening({ channels = {} })), "Listening in no channel — 214 recipes, 3 crafters")

  -- Paused: no Trade chat, no profession read yet (names the one to open), and the other reasons.
  Assert.equal(Status.Text(paused("noTrade")), "Paused — no Trade chat here")
  Assert.equal(Status.Text(paused("empty", "Tailoring")), "Paused — no profession read yet: open Tailoring once")
  Assert.equal(Status.Text(paused("empty")), "Paused — no recipes to listen for")
  Assert.equal(Status.Text(paused("disabled")), "Paused — Craft Alert is turned off")
  Assert.equal(Status.Text(paused("notStarted")), "Paused — Craft Alert did not start; /reload to try again")
  Assert.equal(Status.Text(paused("instance")), "Paused — off in instances")
  -- The first index of the session is still being built: a warm-up, not a pause.
  Assert.equal(Status.Text(paused("building")), "Starting — loading recipes")
  Assert.equal(Status.PausedText({ reason = "building" }), "Starting — loading recipes")

  -- PausedText is the paused line on its own, for callers that already know the gate is paused.
  Assert.equal(Status.PausedText({ reason = "noTrade" }), "Paused — no Trade chat here")
end
