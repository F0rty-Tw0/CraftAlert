local Wow = require("tests.helpers.wow")

-- A synthetic 10-character / 2,000-recipe db for the §4.4 budgets (plan A4): 8 professions,
-- 200 recipes each; Enchanting gets "Enchant <slot> - <tier> <stat>" names, the rest armor
-- items, half with a made-up word unique to the recipe, half with shared adjectives.
--   local Synthetic = require("tests.helpers.synthetic_index")
--   local db, items = Synthetic.db(ns)
--   Synthetic.stubItems(items)
--   local index = Synthetic.build(ns, db)
local Synthetic = {}

local CLASS_ARMOR = 4
Synthetic.PROFESSIONS = { 164, 165, 197, 333, 755, 171, 202, 773 }
local PROFESSIONS = Synthetic.PROFESSIONS
local ENCH = 333
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
  items[itemID] = { slot[1], CLASS_ARMOR, (n % 4) + 1 }
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
      recipes[n] = recipeAt(n, prof, items)
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

return Synthetic
