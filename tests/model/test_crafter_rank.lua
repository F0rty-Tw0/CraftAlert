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

-- The default settings, so the index can be built from `data`.
local function withSettings(data)
  data.settings = require("CraftAlert.Persistence.Defaults").Db().settings
  return data
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

  -- A character whose recipes of that profession are all muted wants no leads for it; one with
  -- no recipe of it stored yet (never read) still answers, and so does one unmuted recipe, even
  -- an unbound one the index leaves out. Pick reads this from the index, so each change rebuilds.
  local Index = require("CraftAlert.Model.Index")
  data = withSettings(db())
  data.characters["Me-Realm"].recipes = {
    [1] = { name = "belt", prof = BS, muted = true },
    [2] = { name = "helm", prof = BS, muted = true, bind = 0 },
    [3] = { name = "enchant", prof = ENCH },
  }
  for _, key in ipairs({ "Prim-Realm", "Alt-Realm", "Zed-Realm", "Imp-Realm" }) do
    data.characters[key].professions[BS] = nil
  end
  Index.Configure(data, { ownKey = "Me-Realm" })
  Index.Rebuild()
  Assert.equal(CrafterRank.Pick(profession, CUSTOMER, data), nil, "all muted: no crafter, no lead")
  data.characters["Alt-Realm"].professions[BS] = { name = "Blacksmithing", primary = false, read = false }
  Index.Rebuild()
  Assert.equal((CrafterRank.Pick(profession, CUSTOMER, data)), "Alt-Realm", "the muted current character is passed over")
  data.characters["Me-Realm"].recipes[2].muted = nil
  Index.Rebuild()
  Assert.equal((CrafterRank.Pick(profession, CUSTOMER, data)), "Me-Realm", "one unmuted unbound recipe is enough")

  -- Pick looks the muted state up in the index (§4.4): a character with thousands of recipes is
  -- not walked on every profession-word match.
  local reads = 0
  local function counted(fields)
    return setmetatable({}, {
      __index = function(_, field)
        reads = reads + 1
        return fields[field]
      end,
    })
  end
  data = withSettings(db())
  for _, key in ipairs({ "Prim-Realm", "Alt-Realm", "Zed-Realm", "Imp-Realm" }) do
    data.characters[key] = nil
  end
  for i = 1, 3000 do
    data.characters["Me-Realm"].recipes[i] = counted({ name = "recipe " .. i, prof = BS, muted = true })
  end
  Index.Configure(data, { ownKey = "Me-Realm" })
  Index.Rebuild()
  reads = 0
  Assert.equal(CrafterRank.Pick(profession, CUSTOMER, data), nil)
  Assert.equal(reads, 0, "no stored recipe is read")

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

  -- IsIgnored is the one ignore check: Leads asks it too.
  Wow.stub("C_FriendList", {
    IsIgnored = function()
      return true
    end,
  })
  Assert.equal(CrafterRank.IsIgnored("Bob-Draenor"), true)
  Wow.stub("C_FriendList", nil)
  Assert.equal(CrafterRank.IsIgnored("Bob-Draenor"), false, "no API, no legacy global: not ignored")

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

  -- One Pick asks about each character once, however many entries name it and for the winner too
  -- (Pick runs per matched line; a long realm list times many entries is the cost to avoid).
  local RealmTag = require("CraftAlert.Model.RealmTag")
  local cannotOrderOf = RealmTag.CannotOrder
  local function pickCounting(keys)
    local questions = {}
    rawset(RealmTag, "CannotOrder", function(db2, crafter, customer)
      questions[crafter] = (questions[crafter] or 0) + 1
      return cannotOrderOf(db2, crafter, customer)
    end)
    local winner, tag = CrafterRank.Pick(result(keys), CUSTOMER, data)
    rawset(RealmTag, "CannotOrder", cannotOrderOf)
    return winner, tag, questions
  end
  local winner, tag, counts = pickCounting({ "Me-Realm", "Alt-Realm", "Zed-Realm", "Alt-Realm", "Me-Realm" })
  Assert.same({ winner, tag }, { "Alt-Realm", false })
  Assert.same(counts, { ["Me-Realm"] = 1, ["Alt-Realm"] = 1, ["Zed-Realm"] = 1 })
  winner, tag, counts = pickCounting({ "Imp-Realm", "Imp-Realm" })
  Assert.same({ winner, tag }, { "Imp-Realm", nil })
  Assert.same(counts, { ["Imp-Realm"] = 1 }, "an unknown answer (nil) is remembered too")

  -- A crafter with no realm list is unknown, not "cannot": never demoted, never tagged.
  picked, cannotOrder = CrafterRank.Pick(result({ "Me-Realm", "Imp-Realm" }), CUSTOMER, data)
  Assert.equal(picked, "Imp-Realm")
  Assert.equal(cannotOrder, nil)
  picked, cannotOrder = CrafterRank.Pick(result({ "Prim-Realm", "Imp-Realm" }), CUSTOMER, db())
  Assert.equal(picked, "Prim-Realm")
  Assert.equal(cannotOrder, nil)

  -- Quality rank (spec §4.4): after can-order, before the tier. An entry is { crafter, recipeKey }.
  local function rankedResult(...)
    local entries = {}
    for i, pair in ipairs({ ... }) do
      entries[i] = { character = pair[1], recipeKey = pair[2], group = 501, prof = BS }
    end
    return { kind = "item", entries = entries, entryCount = #entries, group = 501, prof = BS, why = { "lf" }, whyCount = 1 }
  end
  local function learn(key, recipeKey, fields)
    fields.name, fields.prof = "recipe " .. recipeKey, BS
    data.characters[key].recipes[recipeKey] = fields
  end
  local function ranked(...)
    return CrafterRank.Pick(rankedResult(...), CUSTOMER, data)
  end
  local CYCLE_MS = 345600
  local rank, byConc, recipeKey, _
  local function snapshot(amount, max)
    return { [3168] = { amount = amount, at = 0, cycleMs = CYCLE_MS, perCycle = 1, max = max or 1000 } }
  end

  CrafterRank = load("retail")
  data = db()
  learn("Me-Realm", 10, { ranks = { 1, 2 }, reachRank = 1, reachCost = 0, reachConc = 3168 })
  learn("Alt-Realm", 10, { ranks = { 1, 2 }, reachRank = 2, reachCost = 0, reachConc = 3168 })
  picked, _, rank, byConc, recipeKey = ranked({ "Me-Realm", 10 }, { "Alt-Realm", 10 })
  Assert.same({ picked, rank, byConc, recipeKey }, { "Alt-Realm", 2, false, 10 }, "the higher rank beats the current character")

  -- Alt concentration is projected from its snapshot: amount + whole recharge cycles, up to max.
  data = db()
  learn("Alt-Realm", 10, { ranks = { 1, 2 }, reachRank = 1, reachCost = 376, reachConc = 3168 })
  data.characters["Alt-Realm"].concentration = snapshot(300)
  Wow.clock.time = 27648
  picked, _, rank, byConc = ranked({ "Alt-Realm", 10 })
  Assert.same({ picked, rank, byConc }, { "Alt-Realm", 2, true }, "380 projected covers the 376 cost")
  Wow.clock.time = 24192
  picked, _, rank, byConc = ranked({ "Alt-Realm", 10 })
  Assert.same({ picked, rank, byConc }, { "Alt-Realm", 1, false }, "370 projected does not")
  Wow.clock.time = 1728000
  data.characters["Alt-Realm"].concentration = snapshot(300, 350)
  rank, byConc = select(3, ranked({ "Alt-Realm", 10 }))
  Assert.same({ rank, byConc }, { 1, false }, "the projection stops at max")
  data.characters["Alt-Realm"].concentration = nil
  rank, byConc = select(3, ranked({ "Alt-Realm", 10 }))
  Assert.same({ rank, byConc }, { 1, false }, "no snapshot counts as 0")
  data.characters["Alt-Realm"].recipes[10].reachRank = 2
  rank, byConc = select(3, ranked({ "Alt-Realm", 10 }))
  Assert.same({ rank, byConc }, { 2, false }, "top rank reached: concentration is not asked")
  Wow.clock.time = 0

  -- The current character reads its live currency.
  data = db()
  learn("Me-Realm", 10, { ranks = { 1, 2 }, reachRank = 1, reachCost = 376, reachConc = 3168 })
  local quantity = 400
  Wow.stub("C_CurrencyInfo", {
    GetCurrencyInfo = function(id)
      Assert.equal(id, 3168)
      return { quantity = quantity }
    end,
  })
  rank, byConc = select(3, ranked({ "Me-Realm", 10 }))
  Assert.same({ rank, byConc }, { 2, true }, "400 live covers 376")
  quantity = 10
  rank, byConc = select(3, ranked({ "Me-Realm", 10 }))
  Assert.same({ rank, byConc }, { 1, false }, "10 live does not")
  Wow.stub("C_CurrencyInfo", {
    GetCurrencyInfo = function()
      return nil
    end,
  })
  rank, byConc = select(3, ranked({ "Me-Realm", 10 }))
  Assert.same({ rank, byConc }, { 1, false }, "no currency answer counts as 0")
  Wow.stub("C_CurrencyInfo", nil)
  rank, byConc = select(3, ranked({ "Me-Realm", 10 }))
  Assert.same({ rank, byConc }, { 1, false }, "no currency API (Classic) counts as 0")

  -- Can-order stays the first key.
  data = db()
  data.characters["Me-Realm"].realms = { "Realm", "Draenor" }
  data.characters["Alt-Realm"].realms = { "Realm" }
  learn("Me-Realm", 10, { ranks = { 1, 2 }, reachRank = 1, reachCost = 0, reachConc = 3168 })
  learn("Alt-Realm", 10, { ranks = { 1, 2 }, reachRank = 2, reachCost = 0, reachConc = 3168 })
  picked, cannotOrder, rank = ranked({ "Me-Realm", 10 }, { "Alt-Realm", 10 })
  Assert.same({ picked, cannotOrder, rank }, { "Me-Realm", false, 1 }, "a crafter who cannot be ordered loses despite a higher rank")

  -- The key is rank / #ranks; nil ranks below any number.
  data = db()
  learn("Alt-Realm", 10, { ranks = { 1, 2, 3, 4, 5 }, reachRank = 1, reachCost = 0, reachConc = 3168 })
  learn("Me-Realm", 10, { ranks = { 1, 2 }, reachCost = 0 })
  Assert.equal((ranked({ "Me-Realm", 10 }, { "Alt-Realm", 10 })), "Alt-Realm", "1 of 5 beats no rank")
  learn("Zed-Realm", 10, { ranks = { 1, 2 }, reachRank = 2, reachCost = 0, reachConc = 3168 })
  data.characters["Alt-Realm"].recipes[10].reachRank = 4
  Assert.equal((ranked({ "Alt-Realm", 10 }, { "Zed-Realm", 10 })), "Zed-Realm", "2 of 2 beats 4 of 5")

  -- An imported character has no rank, so a ranked alt beats it; unranked ties fall to the tier.
  data = db()
  learn("Alt-Realm", 10, { ranks = { 1, 2 }, reachRank = 1, reachCost = 0, reachConc = 3168 })
  Assert.equal((ranked({ "Imp-Realm", 10 }, { "Alt-Realm", 10 })), "Alt-Realm")
  Assert.equal((ranked({ "Imp-Realm", 10 }, { "Zed-Realm", 10 })), "Zed-Realm", "nobody ranked: the tier decides")

  -- Review Focus 2: reach fields on a recipe without `ranks` mean no rank, and no error.
  data = db()
  learn("Alt-Realm", 10, { reachRank = 1, reachCost = 376, reachConc = 3168 })
  picked, _, rank, byConc, recipeKey = ranked({ "Alt-Realm", 10 })
  Assert.same({ picked, rank, byConc, recipeKey }, { "Alt-Realm", nil, nil, 10 })
  picked, _, rank, byConc, recipeKey = ranked({ "Alt-Realm", 99 })
  Assert.same({ picked, rank, byConc, recipeKey }, { "Alt-Realm", nil, nil, 99 }, "an entry the db does not hold has no rank")

  -- A character with several entries is judged by its best one, in either entry order.
  data = db()
  learn("Alt-Realm", 10, { ranks = { 1, 2 }, reachRank = 1, reachCost = 0, reachConc = 3168 })
  learn("Alt-Realm", 11, { ranks = { 1, 2 }, reachRank = 2, reachCost = 0, reachConc = 3168 })
  picked, _, rank, _, recipeKey = ranked({ "Alt-Realm", 10 }, { "Alt-Realm", 11 })
  Assert.same({ picked, rank, recipeKey }, { "Alt-Realm", 2, 11 })
  picked, _, rank, _, recipeKey = ranked({ "Alt-Realm", 11 }, { "Alt-Realm", 10 })
  Assert.same({ picked, rank, recipeKey }, { "Alt-Realm", 2, 11 })

  -- A profession-word match has no recipe: no rank, no recipeKey.
  _, _, rank, byConc, recipeKey = CrafterRank.Pick({ kind = "profession", entries = {}, entryCount = 0, prof = BS }, CUSTOMER, data)
  Assert.same({ rank, byConc, recipeKey }, {})

  -- Forever has no crafting orders, so realms never reorder anything.
  CrafterRank = load("forever")
  picked, cannotOrder = CrafterRank.Pick(result({ "Me-Realm", "Alt-Realm" }), CUSTOMER, data)
  Assert.equal(picked, "Me-Realm")
  Assert.equal(cannotOrder, nil)
end
