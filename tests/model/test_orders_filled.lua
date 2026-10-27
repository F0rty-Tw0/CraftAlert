local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- Spec §8 and §13 "Realm tag and orders filled": an order filled for a customer in recentGreeted
-- counts one "filled". Phase 0 (docs/knowledge/in-game-facts.md row 18) saw the event's
-- playerName without a realm, so a bare name matches the name part of a greeted key; a name with
-- a realm matches the whole key. NPC customers never match.
local EVENT = "CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG"
local NOON = os.time({ year = 2026, month = 10, day = 27, hour = 12 })
-- Names the stubbed issecretvalue reports as secret (a real secret string still has type
-- "string", so only a plain string stub proves the guard comes before any use of it).
local secretNames = {}
local MODULES = {
  "Core.FlavorCompat",
  "Core.EventRouter",
  "Core.PlayerName",
  "Persistence.Defaults",
  "Model.Leads",
  "Model.Ledger",
  "Model.OrdersFilled",
}

-- Fresh modules on Retail, Me-Realm playing; Bob on Area52 and Cy on the own realm were greeted.
-- → ns, db.
local function setup()
  Wow.reset()
  Wow.flavor("retail")
  Wow.clock.time = NOON
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("issecretvalue", function(value)
    return secretNames[value] == true
  end)
  local ns = {}
  for _, path in ipairs(MODULES) do
    ns[string.match(path, "%.(%w+)$")] = Fresh.require(path)
  end
  ns.PlayerName.Init()
  local db = ns.Defaults.Db()
  db.recentGreeted["Bob-Area52"] = NOON - 60
  db.recentGreeted["Cy-Realm"] = NOON - 60
  ns.Ledger.Install(db)
  ns.OrdersFilled.Install(db)
  return ns, db
end

local function fulfilled(playerName)
  Wow.fireEvent(EVENT, 0, "Plate Belt", playerName, 0, 1)
end

local function filled(ns)
  return ns.Ledger.Today().filled
end

local function testNameMatches()
  local ns = setup()
  fulfilled("Bob")
  Assert.equal(filled(ns), 1, "a bare name matches the greeted key's name")
  fulfilled("Cy")
  Assert.equal(filled(ns), 2)
  fulfilled("Bob-Area 52")
  Assert.equal(filled(ns), 3, "a name with a realm matches the normalized key")
  fulfilled("Bob-OtherRealm")
  Assert.equal(filled(ns), 3, "the realm must match when the event gives one")
  fulfilled("Stranger")
  fulfilled("Stocky Merchant")
  Assert.equal(filled(ns), 3, "never greeted (an NPC order too): nothing")
end

-- A secret, missing or non-string playerName is ignored before any comparison.
local function testUnusableNames()
  local ns = setup()
  secretNames["Bob"] = true
  fulfilled("Bob")
  secretNames["Bob"] = nil
  fulfilled(nil)
  fulfilled(42)
  fulfilled("")
  Assert.equal(filled(ns), 0)
end

-- Two greeted customers sharing a name on different realms count one fill, not two.
local function testOncePerEvent()
  local ns, db = setup()
  db.recentGreeted["Bob-Realm"] = NOON - 30
  local changes = 0
  ns.Ledger.OnChange(function()
    changes = changes + 1
  end)
  fulfilled("Bob")
  Assert.same({ filled(ns), changes }, { 1, 1 })
end

return function()
  testNameMatches()
  testUnusableNames()
  testOncePerEvent()
  Wow.reset()
end
