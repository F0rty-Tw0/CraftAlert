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
-- profession gear) are left out on purpose: nobody asks for them by slot.
local CHEST = { "chest", "robe" }
local ONE_HAND = { "1h" }
Slang.slots = {
  INVTYPE_FINGER = { "ring", "finger" },
  INVTYPE_NECK = { "neck", "necklace", "amulet" },
  INVTYPE_WAIST = { "belt", "waist" },
  INVTYPE_FEET = { "boots", "boot", "feet", "shoes" },
  INVTYPE_HAND = { "gloves", "glove", "hands", "gauntlets" },
  INVTYPE_WRIST = { "bracers", "bracer", "wrist" },
  INVTYPE_HEAD = { "helm", "helmet", "head" },
  INVTYPE_SHOULDER = { "shoulders", "shoulder", "pauldrons" },
  INVTYPE_CLOAK = { "cloak", "cape", "back" },
  INVTYPE_CHEST = CHEST,
  INVTYPE_ROBE = CHEST,
  INVTYPE_LEGS = { "legs", "pants" },
  INVTYPE_TRINKET = { "trinket" },
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
Slang.wordGroupsOnly = { back = true }

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
