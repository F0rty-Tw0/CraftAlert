local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Constants = ns.Constants or require("CraftAlert.Core.Constants")

-- Spec §6.4 slang table: the English words players use for an item's slot, armor type,
-- weapon kind and container. Data only; ItemKeywords maps an item onto it. Other languages
-- add their own tables later. Item class and subclass numbers are the Enum.ItemClass and
-- Enum.Item*Subclass values, which the Classic clients share.
local Slang = {}

Slang.CLASS_CONTAINER = 1
Slang.CLASS_WEAPON = 2
Slang.CLASS_ARMOR = 4

-- itemEquipLoc -> words. Slots with no words (shirt, tabard, thrown, ammo, quiver, relic,
-- profession gear) are left out on purpose: nobody asks for them by slot. Trinkets too (user
-- ruling 2026-10-24): "LF trinket" picked whichever profession knows the most trinkets (old
-- alchemist stones over PvP trinkets), so only a trinket's name matches.
local CHEST = { "chest", "robe", "chestguard", "breastplate", "tunic", "jerkin", "vest" }
local ONE_HAND = { "1h" }
Slang.slots = {
  INVTYPE_FINGER = { "ring", "finger", "band", "signet" },
  INVTYPE_NECK = { "neck", "necklace", "amulet", "choker", "pendant" },
  INVTYPE_WAIST = { "belt", "waist", "girdle", "waistband" },
  INVTYPE_FEET = { "boots", "boot", "feet", "shoes", "sabatons", "treads" },
  INVTYPE_HAND = { "gloves", "glove", "hands", "gauntlets", "hand", "grips", "handguards" },
  INVTYPE_WRIST = { "bracers", "bracer", "wrist", "bindings", "vambraces", "cuffs" },
  INVTYPE_HEAD = { "helm", "helmet", "head", "hood", "cowl" },
  INVTYPE_SHOULDER = { "shoulders", "shoulder", "pauldrons", "mantle", "spaulders" },
  INVTYPE_CLOAK = { "cloak", "cape", "back", "drape" },
  INVTYPE_CHEST = CHEST,
  INVTYPE_ROBE = CHEST,
  INVTYPE_LEGS = { "legs", "leg", "pants", "leggings", "legguards", "legplates", "greaves" },
  INVTYPE_SHIELD = { "shield" },
  INVTYPE_HOLDABLE = { "offhand" },
  INVTYPE_BAG = { "bag" },
  -- Hand count comes from the slot; the weapon kind comes from Slang.weapons.
  INVTYPE_WEAPON = ONE_HAND,
  INVTYPE_WEAPONMAINHAND = ONE_HAND,
  INVTYPE_WEAPONOFFHAND = { "1h", "offhand" },
  INVTYPE_2HWEAPON = { "2h" },
}

-- Armor subclass (class 4) -> words. Misc (0), shield (6) and the class relics add none.
Slang.armor = {
  [1] = { "cloth" },
  [2] = { "leather" },
  [3] = { "mail" },
  [4] = { "plate" },
}

-- Weapon subclass (class 2) -> words.
local AXE, MACE, SWORD = { "axe" }, { "mace" }, { "sword" }
Slang.weapons = {
  [0] = AXE, -- one-handed
  [1] = AXE, -- two-handed
  [2] = { "bow" },
  [3] = { "gun" },
  [4] = MACE,
  [5] = MACE,
  [6] = { "polearm" },
  [7] = SWORD,
  [8] = SWORD,
  [10] = { "staff" },
  [13] = { "fist", "claw" }, -- unarmed / fist weapons
  [15] = { "dagger" },
  [18] = { "crossbow" },
  [19] = { "wand" },
}

-- Every container subclass (class 1) is a bag.
Slang.containers = { "bag" }

-- §6.4: body-part words that count only beside another word-index match.
Slang.ambiguous = {}
for _, word in ipairs(Constants.ambiguousWords) do
  Slang.ambiguous[word] = true
end

-- User ruling 2026-10-22: slot words only step 4.4 (WordGroups) reads. They are no companion
-- word (§6.2 item 1, steps 4.2 and 4.5) and no stat + slot slot word (§6.3 step 4.3), so "be
-- back in 5" never completes an alias or a stat. The other ambiguous words stay companions.
-- User ruling 2026-10-24: "hand", "band", "hood" and "vest" join them, so "need a hand" and
-- "LF hood" never complete an alias or a stat.
Slang.wordGroupsOnly = { back = true, hand = true, band = true, hood = true, vest = true }

-- User ruling 2026-10-24 (R1): "hand" directly after "main", "one" or "two" is no slot word, so
-- no glove crafter hears of a weapon hand. User ruling 2026-10-25: after "off" ("off hand",
-- "off-hand": a hyphen splits tokens) it is the off-hand slot, as "offhand". Only singular
-- "hand": "off hands" is no gear term, and "hands" keeps its meaning.
local OFF_HAND_PREFIX = { off = true, main = true, one = true, two = true }

-- tokens[i] is "hand" → the word it stands for: "offhand" right after "off" (spaces or one
-- hyphen between), nil after "main", "one" or "two", or after "off" across other punctuation
-- ("logged off. hand over": two thoughts, no slot word; breakBefore: Tokenizer.BreakBefore,
-- asked only after "off"), else "hand". Callers check for "hand" first, so other tokens pay no
-- call. Hot path: no allocation.
function Slang.HandWord(tokens, i, breakBefore)
  local before = i > 1 and tokens[i - 1]
  if before == "off" and not breakBefore(i, true) then
    return "offhand"
  end
  return not OFF_HAND_PREFIX[before] and "hand" or nil
end

-- Class-armor spec §4 rule 1: armor slot words -> "slot", armor type words -> "type". Step 4.4
-- reads them (through index.armorTags) to see a slot named without an armor type.
local ARMOR_SLOTS = {
  "INVTYPE_WAIST",
  "INVTYPE_FEET",
  "INVTYPE_HAND",
  "INVTYPE_WRIST",
  "INVTYPE_HEAD",
  "INVTYPE_SHOULDER",
  "INVTYPE_CHEST",
  "INVTYPE_ROBE",
  "INVTYPE_LEGS",
}
Slang.armorTags = {}
for _, equipLoc in ipairs(ARMOR_SLOTS) do
  for _, word in ipairs(Slang.slots[equipLoc]) do
    Slang.armorTags[word] = "slot"
  end
end
for _, words in pairs(Slang.armor) do
  for _, word in ipairs(words) do
    Slang.armorTags[word] = "type"
  end
end

-- Every word above, for the matcher's "recognized slang word with no entries" rule (§6.3 4.4).
Slang.wordSet = {}
local function addWords(words)
  for _, word in ipairs(words) do
    Slang.wordSet[word] = true
  end
end
for _, words in pairs(Slang.slots) do
  addWords(words)
end
for _, words in pairs(Slang.armor) do
  addWords(words)
end
for _, words in pairs(Slang.weapons) do
  addWords(words)
end
addWords(Slang.containers)

ns.Slang = Slang
return Slang
