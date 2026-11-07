local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- A wide host under the details' minimum (asked before the host's mode is re-decided) gives the
-- list no width, never a negative one.
local function testListNeverGoesNegative()
  local ns = UiFixture.load()
  Assert.equal(ns.BridgeWidths.List(330, 300, false), 0)
end

return function()
  testListNeverGoesNegative()
  Wow.reset()
end
