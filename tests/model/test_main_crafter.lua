local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local BS, ENCH = 164, 333

local function character(...)
  local professions = {}
  for _, prof in ipairs({ ... }) do
    professions[prof] = { name = "Prof" .. prof, primary = false, read = true }
  end
  return { source = "local", enabled = true, realms = {}, professions = professions, recipes = {} }
end

-- A-Realm and B-Realm are both Blacksmiths; C-Realm only enchants.
return function()
  Wow.reset()
  local MainCrafter = Fresh.require("Model.MainCrafter")
  local db = {
    characters = {
      ["A-Realm"] = character(BS),
      ["B-Realm"] = character(BS),
      ["C-Realm"] = character(ENCH),
    },
  }
  local function prim(key)
    return db.characters[key].professions[BS].primary
  end
  local function setRaw(key, on)
    db.characters[key].professions[BS].primary = on
  end

  MainCrafter.Set(db, "A-Realm", BS, true)
  Assert.same({ prim("A-Realm"), prim("B-Realm") }, { true, false })
  Assert.equal(MainCrafter.Of(db, BS), "A-Realm")

  MainCrafter.Set(db, "B-Realm", BS, true) -- moves the flag
  Assert.same({ prim("A-Realm"), prim("B-Realm") }, { false, true })
  Assert.equal(db.characters["C-Realm"].professions[BS], nil, "no profession, untouched")
  Assert.equal(db.characters["C-Realm"].professions[ENCH].primary, false, "another profession, untouched")

  MainCrafter.Set(db, "B-Realm", BS, false)
  Assert.equal(MainCrafter.Of(db, BS), nil)
  Assert.same({ prim("A-Realm"), prim("B-Realm") }, { false, false })

  -- Old data, two flagged: Of reads the lowest key; Clear leaves none.
  setRaw("A-Realm", true)
  setRaw("B-Realm", true)
  Assert.equal(MainCrafter.Of(db, BS), "A-Realm")
  MainCrafter.Clear(db, BS)
  Assert.same({ prim("A-Realm"), prim("B-Realm") }, { false, false })
  Assert.equal(MainCrafter.Of(db, BS), nil)

  -- Turning the flag off on a character that does not hold it leaves the holder alone.
  MainCrafter.Set(db, "A-Realm", BS, true)
  MainCrafter.Set(db, "B-Realm", BS, false)
  Assert.equal(MainCrafter.Of(db, BS), "A-Realm")

  -- One main per group: the player is Me-RealmA; X and Y are linked to RealmA, so both are in scope
  -- without being SameGroup with each other; Far-RealmZ and Far2-RealmZ are another group.
  Wow.reset()
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "RealmA"
  end)
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.PlayerName").Init()
  Fresh.require("Model.RealmTag")
  MainCrafter = Fresh.require("Model.MainCrafter")
  db = {
    characters = {
      ["Near-RealmA"] = character(BS),
      ["Far-RealmZ"] = character(BS),
      ["Far2-RealmZ"] = character(BS),
      ["X-RealmB"] = character(BS),
      ["Y-RealmC"] = character(BS),
    },
  }
  db.characters["X-RealmB"].linkedRealms = { "RealmA" }
  db.characters["Y-RealmC"].linkedRealms = { "RealmA" }

  MainCrafter.Set(db, "Far-RealmZ", BS, true)
  MainCrafter.Set(db, "Near-RealmA", BS, true)
  Assert.equal(prim("Far-RealmZ"), true, "another group keeps its main")
  Assert.equal(MainCrafter.Of(db, BS), "Near-RealmA")
  Assert.equal(MainCrafter.Of(db, BS, "Far-RealmZ"), "Far-RealmZ")

  MainCrafter.Set(db, "X-RealmB", BS, true)
  MainCrafter.Set(db, "Y-RealmC", BS, true)
  Assert.same({ prim("X-RealmB"), prim("Y-RealmC"), prim("Near-RealmA") }, { false, true, false })
  Assert.equal(MainCrafter.Of(db, BS, "X-RealmB"), "Y-RealmC")

  MainCrafter.Clear(db, BS)
  Assert.equal(prim("Y-RealmC"), false)
  Assert.equal(prim("Far-RealmZ"), true, "out of scope, kept")

  -- Off touches only that character; an out-of-scope main clears only its own group.
  MainCrafter.Set(db, "Y-RealmC", BS, true)
  MainCrafter.Set(db, "Near-RealmA", BS, false)
  Assert.equal(prim("Y-RealmC"), true)
  MainCrafter.Set(db, "Far2-RealmZ", BS, true)
  Assert.same({ prim("Far-RealmZ"), prim("Far2-RealmZ"), prim("Y-RealmC") }, { false, true, true })
end
