local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- Fresh PlayerName on a flavor, own character "Hero" on OwnRealm (UnitName's second return is
-- nil on Retail; Forever returns the surname there, spec §10).
local function load(flavorKey, ownName, ownSurname)
  Wow.reset()
  Wow.flavor(flavorKey or "retail")
  Wow.stub("UnitName", function()
    return ownName or "Hero", ownSurname
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "OwnRealm"
  end)
  Fresh.require("Core.FlavorCompat")
  local PlayerName = Fresh.require("Core.PlayerName")
  PlayerName.Init()
  return PlayerName
end

local function testNormalize()
  local PlayerName = load()
  Assert.equal(PlayerName.Normalize("Bob"), "Bob-OwnRealm")
  Assert.equal(PlayerName.Normalize("Bob-OwnRealm"), "Bob-OwnRealm")
  Assert.equal(PlayerName.Normalize("Bob-Area 52"), "Bob-Area52")
  Assert.equal(PlayerName.Normalize("Bob-Area52"), "Bob-Area52")
  -- Hyphenated realms lose the hyphen; only the first hyphen separates name from realm.
  Assert.equal(PlayerName.Normalize("Bob-Azjol-Nerub"), "Bob-AzjolNerub")
  -- An empty realm means "no realm".
  Assert.equal(PlayerName.Normalize("Bob-"), "Bob-OwnRealm")
  Assert.equal(PlayerName.Normalize(nil), nil)
  Assert.equal(PlayerName.Normalize(""), nil)
  Assert.equal(PlayerName.Normalize("-Realm"), nil)
  Assert.equal(PlayerName.Normalize(42), nil)
end

-- Review Focus 2: one lead per person, correct realm tag.
local function testNonAsciiAndApostrophes()
  local PlayerName = load()
  Assert.equal(PlayerName.Normalize("Zoë-Kel'Thuzad"), "Zoë-Kel'Thuzad")
  Assert.equal(PlayerName.Normalize("Zoë"), "Zoë-OwnRealm")
  Assert.equal(PlayerName.Normalize("Name-Area52"), "Name-Area52")
  Assert.equal(PlayerName.Normalize("Bob-Mal'Ganis"), "Bob-Mal'Ganis")
  -- Idempotent: a key normalizes to itself, so the same person never gets two keys.
  for _, raw in ipairs({ "Bob", "Zoë-Kel'Thuzad", "Bob-Area 52", "Bob-Azjol-Nerub" }) do
    local key = PlayerName.Normalize(raw)
    Assert.equal(PlayerName.Normalize(key), key, raw)
  end
  Assert.equal(PlayerName.Normalize("Bob"), PlayerName.Normalize("Bob-OwnRealm"))
  Assert.equal(PlayerName.RealmOf("Zoë-Kel'Thuzad"), "Kel'Thuzad")
  Assert.equal(PlayerName.StripApostrophes("Zoë-Kel'Thuzad"), "Zoë-KelThuzad")
  Assert.equal(PlayerName.StripApostrophes("Bob-Area52"), "Bob-Area52")
end

-- Forever names are "First Last" with a space and carry no realm: spaces stay, realm is appended.
local function testForeverNames()
  local PlayerName = load("forever", "First", "Last")
  Assert.equal(PlayerName.Own(), "First Last-OwnRealm")
  Assert.equal(PlayerName.Normalize("Mary Jane"), "Mary Jane-OwnRealm")
  Assert.equal(PlayerName.Normalize("Mary Jane-OwnRealm"), "Mary Jane-OwnRealm")
  Assert.equal(PlayerName.RealmOf("Mary Jane-OwnRealm"), "OwnRealm")
end

local function testOwnAndRealmOf()
  local PlayerName = load()
  Assert.equal(PlayerName.Own(), "Hero-OwnRealm")
  Assert.equal(PlayerName.RealmOf("Bob-Area52"), "Area52")
  Assert.equal(PlayerName.RealmOf("Bob"), "OwnRealm", "no realm means the own realm")
  Assert.equal(PlayerName.RealmOf(nil), nil)

  -- Retail names on a realm that UnitName reports are not mistaken for surnames.
  local retailWithRealm = load("retail", "Hero", "SomeRealm")
  Assert.equal(retailWithRealm.Own(), "Hero-OwnRealm")
end

-- /ca test and the Test page send as "Test" on the player's own realm (spec §7.3).
local function testTestCustomer()
  Assert.equal(load().TestCustomer(), "Test-OwnRealm")
  local unset = Fresh.require("Core.PlayerName")
  Assert.equal(unset.TestCustomer(), "Test-", "before Init there is no realm")
end

local function testNoApiCallsAfterInit()
  local PlayerName = load()
  local function boom()
    error("API called after Init")
  end
  Wow.stub("UnitName", boom)
  Wow.stub("UnitFullName", boom)
  Wow.stub("GetNormalizedRealmName", boom)
  Wow.stub("GetRealmName", boom)
  Assert.equal(PlayerName.Normalize("Bob"), "Bob-OwnRealm")
  Assert.equal(PlayerName.Normalize("Bob-Area 52"), "Bob-Area52")
  Assert.equal(PlayerName.Own(), "Hero-OwnRealm")
  Assert.equal(PlayerName.RealmOf("Bob"), "OwnRealm")
end

-- GetNormalizedRealmName is nil at ADDON_LOADED on TBC; Init runs at PLAYER_LOGIN, but falls
-- back to GetRealmName, and never produces a trailing hyphen when no realm is known.
local function testRealmFallbacks()
  Wow.reset()
  Wow.flavor("tbc")
  Wow.stub("UnitName", function()
    return "Hero"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return nil
  end)
  Wow.stub("GetRealmName", function()
    return "Area 52"
  end)
  Fresh.require("Core.FlavorCompat")
  local fromRealmName = Fresh.require("Core.PlayerName")
  fromRealmName.Init()
  Assert.equal(fromRealmName.Own(), "Hero-Area52")
  Assert.equal(fromRealmName.Normalize("Bob"), "Bob-Area52")

  Wow.stub("GetRealmName", function()
    return nil
  end)
  local unknown = Fresh.require("Core.PlayerName")
  unknown.Init()
  Assert.equal(unknown.Normalize("Bob"), "Bob")
  Assert.equal(unknown.Normalize("Bob-Area 52"), "Bob-Area52")
end

return function()
  testNormalize()
  testNonAsciiAndApostrophes()
  testForeverNames()
  testOwnAndRealmOf()
  testTestCustomer()
  testNoApiCallsAfterInit()
  testRealmFallbacks()
  Wow.reset()
end
