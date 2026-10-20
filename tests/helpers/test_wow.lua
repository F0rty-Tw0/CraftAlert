local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")

-- The stub layer the tests and tools/sim.lua share: a reset leaves nothing of the last run.
return function()
  Wow.reset()
  local frame = _G["CreateFrame"]("Frame", "CraftAlertResetProbe")
  Assert.equal(rawget(_G, "CraftAlertResetProbe"), frame, "a named frame is a global, as in the client")
  _G["CreateFrame"]("Frame", nil)
  Assert.equal(#Wow.frames, 2)
  Wow.reset()
  Assert.equal(rawget(_G, "CraftAlertResetProbe"), nil, "the named frame is gone")
  Assert.same(Wow.frames, {})
end
