local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function load()
  Wow.reset()
  return Fresh.require("Model.ClassArmor")
end

local EXPECTED = {
  WARRIOR = "plate",
  PALADIN = "plate",
  DEATHKNIGHT = "plate",
  HUNTER = "mail",
  SHAMAN = "mail",
  EVOKER = "mail",
  ROGUE = "leather",
  DRUID = "leather",
  MONK = "leather",
  DEMONHUNTER = "leather",
  MAGE = "cloth",
  PRIEST = "cloth",
  WARLOCK = "cloth",
}

-- Every token maps; the why label is "<armor> (<lowercase token>)"; anything else gives nil, nil.
local function testTable()
  local ClassArmor = load()
  for token, armor in pairs(EXPECTED) do
    local got, why = ClassArmor.For(token)
    Assert.equal(got, armor, token)
    Assert.equal(why, armor .. " (" .. string.lower(token) .. ")", token)
  end
  for _, other in ipairs({ "warrior", "", "ADVENTURER", "Warrior" }) do
    Assert.equal(ClassArmor.For(other), nil, other)
  end
  Assert.equal(ClassArmor.For(nil), nil)
  Assert.equal(ClassArmor.For(5), nil)
end

return function()
  testTable()
  Wow.reset()
end
