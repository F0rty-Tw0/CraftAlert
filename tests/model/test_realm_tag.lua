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

  -- Strip is what the importers store realms through.
  Assert.equal(RealmTag.Strip("Area 52"), "Area52")
  Assert.equal(RealmTag.Strip("Azjol-Nerub"), "AzjolNerub")
  Assert.equal(RealmTag.Strip("Kel'Thuzad"), "Kel'Thuzad")

  -- Group rules. Characters are built like dbWith: realms = connected list, linkedRealms = the
  -- user's manual links.
  local function groupDb(chars)
    local gdb = dbWith()
    for key, fields in pairs(chars) do
      gdb.characters[key] = fields
    end
    return gdb
  end

  -- Connected: same realm, or either side's realms list holds the other's realm.
  RealmTag = load("retail", {})
  db = groupDb({ ["Alt-Kel'Thuzad"] = {}, ["Far-Other"] = {}, ["Ghost2-Other"] = {} })
  Assert.equal(RealmTag.Connected(db, ME, "Alt-Kel'Thuzad"), true)
  Assert.equal(RealmTag.Connected(db, ME, "Far-Other"), false)
  db.characters[ME].realms = { "Other" }
  Assert.equal(RealmTag.Connected(db, ME, "Far-Other"), true)
  db.characters[ME].realms = {}
  db.characters["Far-Other"].realms = { "Kel'Thuzad" }
  Assert.equal(RealmTag.Connected(db, ME, "Far-Other"), true)
  Assert.equal(RealmTag.Connected(db, "Far-Other", ME), true)
  Assert.equal(RealmTag.Connected(db, ME, "Ghost-Other"), false, "no record")
  Assert.equal(RealmTag.Connected(db, ME, "Ghost2-Other"), false, "record without a list")

  -- SameGroup adds linkedRealms on either side; Connected ignores them.
  db = groupDb({ ["Far-Other"] = {} })
  Assert.equal(RealmTag.SameGroup(db, ME, "Far-Other"), false)
  db.characters["Far-Other"].linkedRealms = { "Kel'Thuzad" }
  Assert.equal(RealmTag.SameGroup(db, ME, "Far-Other"), true)
  Assert.equal(RealmTag.SameGroup(db, "Far-Other", ME), true)
  Assert.equal(RealmTag.Connected(db, ME, "Far-Other"), false)
  Assert.equal(RealmTag.InScope(db, "Far-Other"), true)
  db.characters["Far-Other"].linkedRealms = nil
  db.characters[ME].linkedRealms = { "Other" }
  Assert.equal(RealmTag.SameGroup(db, ME, "Far-Other"), true)

  -- Not transitive: two alts linked from Kel'Thuzad are not a group with each other.
  db = groupDb({
    ["X-RealmB"] = { linkedRealms = { "Kel'Thuzad" } },
    ["Y-RealmC"] = { linkedRealms = { "Kel'Thuzad" } },
  })
  Assert.equal(RealmTag.SameGroup(db, "X-RealmB", "Y-RealmC"), false)

  -- Linked from realm A is out of scope when the player is on unrelated realm C.
  local function loadOn(own, name)
    Wow.reset()
    Wow.flavor("retail")
    Wow.stub("UnitName", function()
      return name or "Me"
    end)
    Wow.stub("GetNormalizedRealmName", function()
      return own
    end)
    Wow.stub("GetRealmName", function()
      return own
    end)
    Fresh.require("Core.FlavorCompat")
    Fresh.require("Core.PlayerName").Init()
    return Fresh.require("Model.RealmTag")
  end
  RealmTag = loadOn("RealmC")
  db = groupDb({ ["Far-Other"] = { linkedRealms = { "Kel'Thuzad" } } })
  Assert.equal(RealmTag.InScope(db, "Far-Other"), false)

  -- The player's own linkedRealms never widen scope: Ann (RealmA) linked to RealmB does not put
  -- the unlinked Bee-RealmB in scope, and Abe, another RealmA character, gets the same answer.
  db = groupDb({
    ["Ann-RealmA"] = { linkedRealms = { "RealmB" } },
    ["Abe-RealmA"] = {},
    ["Bee-RealmB"] = {},
  })
  for _, name in ipairs({ "Ann", "Abe" }) do
    RealmTag = loadOn("RealmA", name)
    Assert.equal(RealmTag.InScope(db, "Bee-RealmB"), false, name)
    Assert.equal(RealmTag.InScope(db, "Abe-RealmA"), true, name)
  end
  -- An alt that links the player's realm is in scope.
  db.characters["Bee-RealmB"].linkedRealms = { "RealmA" }
  Assert.equal(RealmTag.InScope(db, "Bee-RealmB"), true)

  -- Own realm unknown: everything is in scope.
  RealmTag = loadOn(nil)
  Assert.equal(RealmTag.InScope(db, "Far-Other"), true)

  -- SetLinked / IsLinked on the own realm.
  RealmTag = load("retail", {})
  db = groupDb({ ["Far-Other"] = {} })
  RealmTag.SetLinked(db, "Far-Other", true)
  RealmTag.SetLinked(db, "Far-Other", true)
  Assert.same(db.characters["Far-Other"].linkedRealms, { "Kel'Thuzad" })
  Assert.equal(RealmTag.IsLinked(db, "Far-Other"), true)
  db.characters["Far-Other"].linkedRealms = { "Kel'Thuzad", "Kel'Thuzad" }
  RealmTag.SetLinked(db, "Far-Other", false)
  Assert.equal(db.characters["Far-Other"].linkedRealms, nil)
  Assert.equal(RealmTag.IsLinked(db, "Far-Other"), false)
  db.characters["Far-Other"].linkedRealms = { "Other", "Kel'Thuzad" }
  RealmTag.SetLinked(db, "Far-Other", false)
  Assert.same(db.characters["Far-Other"].linkedRealms, { "Other" })

  -- A missing character is left alone.
  RealmTag.SetLinked(db, "Ghost-Other", true)
  Assert.equal(db.characters["Ghost-Other"], nil)
  Assert.equal(RealmTag.IsLinked(db, "Ghost-Other"), false)
end
