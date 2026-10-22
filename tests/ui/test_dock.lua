local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

return function()
  local ns = UiFixture.load()
  local function anchor(...)
    return { ns.Dock.Anchor(...) }
  end
  Assert.same(anchor(100, 900, 960, 540), { "TOPLEFT", "TOPRIGHT", 8, 0 })
  Assert.same(anchor(100, 100, 960, 540), { "BOTTOMLEFT", "BOTTOMRIGHT", 8, 0 })
  Assert.same(anchor(1800, 900, 960, 540), { "TOPRIGHT", "TOPLEFT", -8, 0 })
  Assert.same(anchor(1800, 100, 960, 540), { "BOTTOMRIGHT", "BOTTOMLEFT", -8, 0 })
  -- Exactly on the centre lines: right half, upper half.
  Assert.same(anchor(960, 540, 960, 540), { "TOPRIGHT", "TOPLEFT", -8, 0 })
  -- Unknown centres (a launcher never shown) use the left/upper row.
  Assert.same(anchor(nil, nil, 960, 540), { "TOPLEFT", "TOPRIGHT", 8, 0 })
  Assert.same(anchor(1800, 100, nil, nil), { "TOPLEFT", "TOPRIGHT", 8, 0 })
  Assert.same(anchor(nil, nil, nil, nil), { "TOPLEFT", "TOPRIGHT", 8, 0 })
  Wow.reset()
end
