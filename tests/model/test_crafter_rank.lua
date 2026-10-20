local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local BS, ENCH = 164, 333
local CUSTOMER = "Bob-Draenor"

-- Fresh modules for one flavor; the player is Me-Realm.
local function load(flavor)
  Wow.reset()
  Wow.flavor(flavor)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.PlayerName").Init()
  Fresh.require("Model.RealmTag")
  return Fresh.require("Model.CrafterRank")
end

local function character(source, primaryProf, realms)
  local professions = { [BS] = { name = "Blacksmithing", primary = primaryProf == BS, read = true } }
  professions[ENCH] = { name = "Enchanting", primary = primaryProf == ENCH, read = true }
  return { source = source, enabled = true, realms = realms, professions = professions, recipes = {} }
end

-- Me (current), Prim (primary Blacksmith, primary nothing else), Alt and Zed (same account),
-- Imp (imported). No realm lists, so the realm tier stays out of the way.
local function db()
  return {
    characters = {
      ["Me-Realm"] = character("local", nil, {}),
      ["Prim-Realm"] = character("local", BS, {}),
      ["Alt-Realm"] = character("local", nil, {}),
      ["Zed-Realm"] = character("local", nil, {}),
      ["Imp-Realm"] = character("import", nil, {}),
    },
  }
end

-- A Matcher result naming the given characters as crafters of one recipe.
local function result(keys, prof)
  local entries = {}
  for i, key in ipairs(keys) do
    entries[i] = { character = key, recipeKey = 1, group = 501, prof = prof or BS }
  end
  return { kind = "item", entries = entries, entryCount = #entries, group = 501, prof = prof or BS, why = { "lf" }, whyCount = 1 }
end

return function()
  local CrafterRank = load("retail")
  local data = db()

  -- Current character > primary for the profession > same account > imported > name.
  local function pick(keys, prof)
    return (CrafterRank.Pick(result(keys, prof), CUSTOMER, data))
  end
  Assert.equal(pick({ "Imp-Realm", "Zed-Realm", "Alt-Realm" }), "Alt-Realm", "name breaks the tie among same-account alts")
  Assert.equal(pick({ "Zed-Realm", "Imp-Realm" }), "Zed-Realm", "same account beats imported")
  Assert.equal(pick({ "Imp-Realm" }), "Imp-Realm")
  Assert.equal(pick({ "Alt-Realm", "Prim-Realm", "Zed-Realm" }), "Prim-Realm", "the profession's primary crafter beats alts")
  Assert.equal(pick({ "Prim-Realm", "Me-Realm", "Alt-Realm" }), "Me-Realm", "the current character comes first")
  Assert.equal(pick({ "Alt-Realm", "Prim-Realm" }, ENCH), "Alt-Realm", "primary counts for its own profession only")
  Assert.equal(pick({ "Prim-Realm", "Prim-Realm", "Alt-Realm" }), "Prim-Realm", "a crafter listed twice is one candidate")

  -- Primary is judged by the profession of the entry; a pending learn has none and takes the result's.
  local mixed = result({ "Prim-Realm", "Alt-Realm" })
  mixed.entries[1].prof, mixed.entries[2].prof = ENCH, ENCH
  Assert.equal((CrafterRank.Pick(mixed, CUSTOMER, data)), "Alt-Realm")
  mixed.entries[1].prof = nil
  Assert.equal((CrafterRank.Pick(mixed, CUSTOMER, data)), "Prim-Realm")

  -- Eight alts know the recipe (Review Focus 3): one crafter comes back.
  data = db()
  local alts = {}
  for i = 1, 8 do
    local key = "Alt" .. i .. "-Realm"
    data.characters[key] = character("local", nil, {})
    alts[i] = key
  end
  Assert.equal(pick(alts), "Alt1-Realm")

  -- A pending Classic learn names the current character, which the db may not hold yet.
  Assert.equal(pick({ "Me-Realm", "Alt-Realm" }), "Me-Realm")
  data = {}
  data.characters = {}
  Assert.equal(pick({ "Me-Realm" }), "Me-Realm")

  -- No candidate, no crafter.
  Assert.equal(CrafterRank.Pick({ kind = "profession", entries = {}, entryCount = 0, prof = 999 }, CUSTOMER, db()), nil)

  -- Profession matches that name no entries (step 4.6) use the characters with the profession.
  data = db()
  data.characters["Prim-Realm"].enabled = false
  data.characters["Alt-Realm"].professions[BS] = nil
  data.characters["Zed-Realm"].professions[BS] = nil
  data.characters["Imp-Realm"].professions[BS] = nil
  local profession = { kind = "profession", entries = {}, entryCount = 0, prof = BS, why = { "lf" }, whyCount = 1 }
  Assert.equal((CrafterRank.Pick(profession, CUSTOMER, data)), "Me-Realm", "a disabled crafter is skipped")
  data.characters["Me-Realm"].professions[BS] = nil
  Assert.equal(CrafterRank.Pick(profession, CUSTOMER, data), nil)
  data.characters["Prim-Realm"].enabled = true
  Assert.equal((CrafterRank.Pick(profession, CUSTOMER, data)), "Prim-Realm")

  -- Blizzard's ignore list: the customer is dropped unless /ca test skips the check.
  local asked = {}
  Wow.stub("C_FriendList", {
    IsIgnored = function(name)
      asked[#asked + 1] = name
      return name == CUSTOMER
    end,
  })
  data = db()
  Assert.equal(CrafterRank.Pick(result({ "Alt-Realm" }), CUSTOMER, data), nil)
  Assert.same(asked, { CUSTOMER })
  Assert.equal((CrafterRank.Pick(result({ "Alt-Realm" }), CUSTOMER, data, { skipIgnore = true })), "Alt-Realm")
  Assert.equal((CrafterRank.Pick(result({ "Alt-Realm" }), "Carl-Draenor", data)), "Alt-Realm")
  Assert.equal(#asked, 2, "skipIgnore does not ask")
  Wow.stub("C_FriendList", nil)

  -- Retail: crafters who can receive the customer's order rank above those who cannot.
  data = db()
  data.characters["Me-Realm"].realms = { "Realm" }
  data.characters["Prim-Realm"].realms = { "Realm" }
  data.characters["Alt-Realm"].realms = { "Realm", "Draenor" }
  data.characters["Zed-Realm"].realms = { "Realm", "Draenor" }
  local picked, cannotOrder = CrafterRank.Pick(result({ "Me-Realm", "Zed-Realm", "Alt-Realm" }), CUSTOMER, data)
  Assert.equal(picked, "Alt-Realm", "can-receive beats the current character")
  Assert.equal(cannotOrder, false)
  Assert.equal((CrafterRank.Pick(result({ "Prim-Realm", "Zed-Realm" }), CUSTOMER, data)), "Zed-Realm", "can-receive beats the primary crafter")
  picked, cannotOrder = CrafterRank.Pick(result({ "Prim-Realm", "Me-Realm" }), CUSTOMER, data)
  Assert.equal(picked, "Me-Realm", "nobody can receive: the usual order")
  Assert.equal(cannotOrder, true)
  picked, cannotOrder = CrafterRank.Pick(result({ "Prim-Realm", "Me-Realm" }), "Bob-Realm", data)
  Assert.equal(picked, "Me-Realm")
  Assert.equal(cannotOrder, false)

  -- A crafter with no realm list is unknown, not "cannot": never demoted, never tagged.
  picked, cannotOrder = CrafterRank.Pick(result({ "Me-Realm", "Imp-Realm" }), CUSTOMER, data)
  Assert.equal(picked, "Imp-Realm")
  Assert.equal(cannotOrder, nil)
  picked, cannotOrder = CrafterRank.Pick(result({ "Prim-Realm", "Imp-Realm" }), CUSTOMER, db())
  Assert.equal(picked, "Prim-Realm")
  Assert.equal(cannotOrder, nil)

  -- Forever has no crafting orders, so realms never reorder anything.
  CrafterRank = load("forever")
  picked, cannotOrder = CrafterRank.Pick(result({ "Me-Realm", "Alt-Realm" }), CUSTOMER, data)
  Assert.equal(picked, "Me-Realm")
  Assert.equal(cannotOrder, nil)
end
