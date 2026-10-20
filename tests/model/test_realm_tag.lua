local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local ME = "Me-Kel'Thuzad"

-- Fresh modules for one flavor; the player is Me on Kel'Thuzad and `realms` is what
-- C_AutoComplete.GetAutoCompleteRealms() returns.
local function load(flavor, realms)
  Wow.reset()
  Wow.flavor(flavor)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Kel'Thuzad"
  end)
  Wow.stub("C_AutoComplete", {
    GetAutoCompleteRealms = function()
      return realms
    end,
  })
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.PlayerName").Init()
  return Fresh.require("Model.RealmTag")
end

local function dbWith(realms)
  local db = { characters = {} }
  db.characters[ME] = { source = "local", enabled = true, realms = realms or {}, professions = {}, recipes = {} }
  return db
end

return function()
  -- Store: connected realms plus the own realm, spaces and hyphens removed, no duplicates.
  local RealmTag = load("retail", { "Area 52", "Kel'Thuzad", "Twisting-Nether" })
  local db = dbWith()
  RealmTag.Store(db, ME)
  Assert.same(db.characters[ME].realms, { "Area52", "Kel'Thuzad", "TwistingNether" })

  -- The own realm is added when the client's list leaves it out.
  RealmTag = load("retail", { "Area 52" })
  db = dbWith()
  RealmTag.Store(db, ME)
  Assert.same(db.characters[ME].realms, { "Area52", "Kel'Thuzad" })

  -- An empty or missing list means "unknown", never "own realm only" (Phase 0): nothing is
  -- written, and a list stored earlier stays.
  RealmTag = load("retail", {})
  db = dbWith()
  RealmTag.Store(db, ME)
  Assert.same(db.characters[ME].realms, {})
  db = dbWith({ "Area52" })
  RealmTag.Store(db, ME)
  Assert.same(db.characters[ME].realms, { "Area52" })
  RealmTag = load("retail", nil)
  RealmTag.Store(db, ME)
  Assert.same(db.characters[ME].realms, { "Area52" })

  -- A character the db does not hold is not created.
  RealmTag = load("retail", { "Area 52" })
  db = { characters = {} }
  RealmTag.Store(db, ME)
  Assert.equal(db.characters[ME], nil)

  -- Retail only: Forever and Classic have no crafting orders.
  for _, flavor in ipairs({ "forever", "tbc" }) do
    RealmTag = load(flavor, { "Area 52" })
    db = dbWith()
    RealmTag.Store(db, ME)
    Assert.same(db.characters[ME].realms, {}, flavor)
    db = dbWith({ "Area52" })
    Assert.equal(RealmTag.CannotOrder(db, ME, "Bob-Draenor"), nil, flavor)
  end

  -- CannotOrder: true only when a realm list exists and excludes the customer's realm.
  RealmTag = load("retail", {})
  db = dbWith({ "Area52", "Kel'Thuzad" })
  Assert.equal(RealmTag.CannotOrder(db, ME, "Bob-Area52"), false)
  Assert.equal(RealmTag.CannotOrder(db, ME, "Zoë-Kel'Thuzad"), false)
  Assert.equal(RealmTag.CannotOrder(db, ME, "Bob-Draenor"), true)
  Assert.equal(RealmTag.CannotOrder(db, ME, "Bob"), false, "a bare name is on the player's own realm")

  -- The customer's realm is stripped on every call; stored realms are compared as stored (Store
  -- and the load-time Schema check strip them), so a hand-edited "Area 52" never gets here.
  db = dbWith({ "Area52" })
  Assert.equal(RealmTag.CannotOrder(db, ME, "Bob-Area 52"), false)
  Assert.equal(RealmTag.CannotOrder(db, ME, "Bob-Area-52"), false)
  Assert.equal(RealmTag.CannotOrder(dbWith({ "Area 52" }), ME, "Bob-Area52"), true)

  -- No list known (empty, absent), unknown crafter, unusable customer → no tag.
  Assert.equal(RealmTag.CannotOrder(dbWith({}), ME, "Bob-Draenor"), nil)
  Assert.equal(RealmTag.CannotOrder(dbWith(), "Ghost-Realm", "Bob-Draenor"), nil)
  Assert.equal(RealmTag.CannotOrder(db, ME, nil), nil)
  db.characters[ME].realms = nil
  Assert.equal(RealmTag.CannotOrder(db, ME, "Bob-Draenor"), nil)
end
