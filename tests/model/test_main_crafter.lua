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
end
