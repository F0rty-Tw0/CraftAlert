local Wow = require("tests.helpers.wow")

-- A synthetic 10-character / 2,000-recipe db for the §4.4 budgets (plan A4): 8 professions,
-- 200 recipes each; Enchanting gets "Enchant <slot> - <tier> <stat>" names, the rest armor
-- items, half with a made-up word unique to the recipe, half with shared adjectives. Off-hand
-- items (held-in-off-hand armor, off-hand daggers) put "offhand" in the word index, as any real
-- index with one does, so the "off hand" reads pay their full cost here.
--   local Synthetic = require("tests.helpers.synthetic_index")
--   local db, items = Synthetic.db(ns)
--   Synthetic.stubItems(items)
--   local index = Synthetic.build(ns, db)
local Synthetic = {}

local CLASS_ARMOR, CLASS_WEAPON = 4, 2
local SUBCLASS_MISC, SUBCLASS_DAGGER = 0, 15
Synthetic.PROFESSIONS = { 164, 165, 197, 333, 755, 171, 202, 773 }
local PROFESSIONS = Synthetic.PROFESSIONS
local ENCH = 333
-- { equipLoc, noun, class, subclass }: the class and subclass a real item of the slot has; an
-- entry without them is armor of subclass (n % 4) + 1 (cloth to plate).
local SLOTS = {
  { "INVTYPE_WAIST", "Belt" },
  { "INVTYPE_FEET", "Boots" },
  { "INVTYPE_HAND", "Gloves" },
  { "INVTYPE_WRIST", "Bracers" },
  { "INVTYPE_HEAD", "Helm" },
  { "INVTYPE_SHOULDER", "Shoulders" },
  { "INVTYPE_CHEST", "Chestguard" },
  { "INVTYPE_LEGS", "Leggings" },
  { "INVTYPE_CLOAK", "Cloak" },
  { "INVTYPE_FINGER", "Ring" },
  { "INVTYPE_NECK", "Necklace" },
  { "INVTYPE_HOLDABLE", "Orb", CLASS_ARMOR, SUBCLASS_MISC },
  { "INVTYPE_WEAPONOFFHAND", "Parrying Dagger", CLASS_WEAPON, SUBCLASS_DAGGER },
}
local ADJECTIVES = { "Green", "Blue", "Ornate", "Imperial", "Dark", "Bright", "Shadow", "Storm", "Frost", "Flame", "Earthen", "Radiant" }
local MATERIALS = { "Iron", "Steel", "Mithril", "Thorium", "Copper", "Bronze", "Silk", "Linen", "Rugged", "Thick", "Heavy", "Felsteel" }
local ENCHANT_SLOTS = { "Chest", "Bracer", "Boots", "Gloves", "Cloak", "Weapon", "Shield", "2H Weapon" }
local TIERS = { "Minor", "Lesser", "", "Greater", "Superior", "Major" }
local STATS = { "Stamina", "Intellect", "Agility", "Strength", "Spirit", "Defense", "Health", "Mana" }
local CONSONANTS = "bcdfghklmnprstvz"
local VOWELS = "aeiou"
local function pick(list, n)
  return list[(n % #list) + 1]
end

-- A made-up word unique to n < 6400, 5-11 letters, any first letter (like "Lionheart" or
-- "Mongoose"): the kind c alias and typo target of its recipe. Bytes 2-5 spell n in base
-- 5/16/5/16, so no two words share them.
local function uniqueWord(n)
  local letters, rest = { string.char(65 + (math.floor(n / 2) * 7) % 26) }, n
  for k = 1, 4 + n % 7 do
    local alphabet = (k % 2 == 1) and VOWELS or CONSONANTS
    local at = rest % #alphabet
    rest = math.floor(rest / #alphabet)
    letters[k + 1] = string.sub(alphabet, at + 1, at + 1)
  end
  return table.concat(letters)
end

local function recipeAt(n, prof, items)
  if prof == ENCH then
    local tier = pick(TIERS, math.floor(n / 8))
    local stat = (tier ~= "" and tier .. " " or "") .. pick(STATS, math.floor(n / 48))
    return { name = "Enchant " .. pick(ENCHANT_SLOTS, n) .. " - " .. stat, prof = prof }
  end
  local slot = pick(SLOTS, n)
  local itemID = 100000 + n
  items[itemID] = { slot[1], slot[3] or CLASS_ARMOR, slot[4] or (n % 4) + 1 }
  local name
  if n % 2 == 0 then
    name = uniqueWord(n) .. " " .. slot[2]
  else
    name = pick(ADJECTIVES, n) .. " " .. pick(MATERIALS, math.floor(n / 12)) .. " " .. slot[2]
  end
  return { item = itemID, name = name, prof = prof, bind = 1 }
end

-- 10 characters x 200 recipes; returns the db and the item table for the C_Item stub.
function Synthetic.db(ns)
  local db, items = ns.Defaults.Db(), {}
  for c = 1, 10 do
    local prof = PROFESSIONS[(c - 1) % #PROFESSIONS + 1]
    local recipes = {}
    for k = 1, 200 do
      local n = (c - 1) * 200 + k
      recipes[200000 + n * 131] = recipeAt(n, prof, items) -- sparse, like real recipe spell IDs
    end
    db.characters["Char" .. c .. "-Realm"] = {
      source = "local",
      enabled = true,
      realms = {},
      professions = { [prof] = { name = tostring(prof), primary = false, read = true } },
      recipes = recipes,
    }
  end
  return db, items
end

function Synthetic.stubItems(items)
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      local item = items[itemID]
      if item then
        return itemID, "Armor", "Plate", item[1], 0, item[2], item[3]
      end
    end,
  })
end

function Synthetic.build(ns, db)
  return ns.Index.Build(db, db.settings, {
    ownKey = "Me-Realm",
    professionOrder = function()
      return PROFESSIONS
    end,
  })
end

-- Pairs each table of a with the table at the same place in b, reached through non-table keys
-- only; the first place a table is reached wins.
local function pairTables(a, b, pairOf)
  if type(a) ~= "table" or type(b) ~= "table" or pairOf[a] ~= nil then
    return
  end
  pairOf[a] = b
  for key, value in pairs(a) do
    if type(key) ~= "table" then
      pairTables(value, b[key], pairOf)
    end
  end
end

local function firstDifference(a, b, path, pairOf, seen)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a ~= b and path or nil
  end
  if pairOf[a] ~= b then
    return path .. " (a different table, or one shared differently)"
  end
  if seen[a] then
    return nil
  end
  seen[a] = true
  local count = 0
  for key, value in pairs(a) do
    local keyB = type(key) == "table" and pairOf[key] or key
    local where = path .. "." .. (type(key) == "table" and tostring(key.phrase or key) or tostring(key))
    if keyB == nil then
      return where .. " (a key table with no match)"
    end
    local found = firstDifference(value, b[keyB], where, pairOf, seen)
    if found then
      return found
    end
    count = count + 1
  end
  for _ in pairs(b) do
    count = count - 1
  end
  return count ~= 0 and path .. " (b has other keys)" or nil
end

-- → nil when two builds are equal: same values in the same order, the same tables shared, and
-- table-keyed sets (needsSecondWord holds records) matched through the paired tables; else the
-- path of the first difference. Assert.same can't compare two builds: their record keys differ.
-- Checked both ways, so a list shared in b but not in a counts too.
local function oneWay(a, b)
  local pairOf = {}
  pairTables(a, b, pairOf)
  return firstDifference(a, b, "index", pairOf, {})
end

function Synthetic.difference(a, b)
  return oneWay(a, b) or oneWay(b, a)
end

return Synthetic
