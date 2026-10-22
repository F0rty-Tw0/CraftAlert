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

-- Tokens() is the fixed class order, as a fresh array each call.
local function testTokens()
  local ClassArmor = load()
  local expected = {
    "WARRIOR",
    "PALADIN",
    "DEATHKNIGHT",
    "HUNTER",
    "SHAMAN",
    "EVOKER",
    "ROGUE",
    "DRUID",
    "MONK",
    "DEMONHUNTER",
    "MAGE",
    "PRIEST",
    "WARLOCK",
  }
  local tokens = ClassArmor.Tokens()
  Assert.equal(#tokens, #expected, "length")
  for i, token in ipairs(expected) do
    Assert.equal(tokens[i], token, "token " .. i)
  end
  tokens[1] = "CHANGED"
  tokens[#tokens + 1] = "EXTRA"
  local again = ClassArmor.Tokens()
  Assert.equal(again[1], "WARRIOR", "mutation does not leak")
  Assert.equal(#again, #expected, "mutation does not leak")
end

return function()
  testTable()
  testTokens()
  Wow.reset()
end
