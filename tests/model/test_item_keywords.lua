local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local CLASS_CONTAINER, CLASS_WEAPON, CLASS_ARMOR = 1, 2, 4

-- itemID -> { equipLoc, classID, subclassID }, served through the C_Item stub.
local function load(items)
  Wow.reset()
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      local item = items[itemID]
      if not item then
        return nil
      end
      -- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
      return itemID, "type", "subtype", item[1], 0, item[2], item[3]
    end,
  })
  Fresh.require("Core.Constants")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Model.Slang")
  return Fresh.require("Model.ItemKeywords")
end

-- Spec §6.4: every slot, armor type, weapon subclass and container -> its words.
-- Words come slot first, then type; subclass numbers are the Enum.Item*Subclass values.
local CASES = {
  -- Slots (armor class, subclass 0 = misc unless it is the real armor type)
  { "INVTYPE_FINGER", CLASS_ARMOR, 0, { "ring", "finger" } },
  { "INVTYPE_NECK", CLASS_ARMOR, 0, { "neck", "necklace", "amulet" } },
  { "INVTYPE_WAIST", CLASS_ARMOR, 4, { "belt", "waist", "plate" } },
  { "INVTYPE_FEET", CLASS_ARMOR, 2, { "boots", "boot", "feet", "shoes", "leather" } },
  { "INVTYPE_HAND", CLASS_ARMOR, 3, { "gloves", "glove", "hands", "gauntlets", "mail" } },
  { "INVTYPE_WRIST", CLASS_ARMOR, 1, { "bracers", "bracer", "wrist", "cloth" } },
  { "INVTYPE_HEAD", CLASS_ARMOR, 4, { "helm", "helmet", "head", "plate" } },
  { "INVTYPE_SHOULDER", CLASS_ARMOR, 2, { "shoulders", "shoulder", "pauldrons", "leather" } },
  { "INVTYPE_CLOAK", CLASS_ARMOR, 1, { "cloak", "cape", "cloth" } },
  { "INVTYPE_CHEST", CLASS_ARMOR, 3, { "chest", "robe", "mail" } },
  { "INVTYPE_ROBE", CLASS_ARMOR, 1, { "chest", "robe", "cloth" } },
  { "INVTYPE_LEGS", CLASS_ARMOR, 4, { "legs", "pants", "plate" } },
  { "INVTYPE_TRINKET", CLASS_ARMOR, 0, { "trinket" } },
  { "INVTYPE_SHIELD", CLASS_ARMOR, 6, { "shield" } },
  { "INVTYPE_HOLDABLE", CLASS_ARMOR, 0, { "offhand" } },
  -- Weapons: hand count comes from the equip location, the kind from the subclass
  { "INVTYPE_WEAPON", CLASS_WEAPON, 0, { "1h", "axe" } },
  { "INVTYPE_2HWEAPON", CLASS_WEAPON, 1, { "2h", "axe" } },
  { "INVTYPE_WEAPONMAINHAND", CLASS_WEAPON, 7, { "1h", "sword" } },
  { "INVTYPE_2HWEAPON", CLASS_WEAPON, 8, { "2h", "sword" } },
  { "INVTYPE_WEAPONOFFHAND", CLASS_WEAPON, 15, { "1h", "offhand", "dagger" } },
  { "INVTYPE_WEAPON", CLASS_WEAPON, 4, { "1h", "mace" } },
  { "INVTYPE_2HWEAPON", CLASS_WEAPON, 5, { "2h", "mace" } },
  { "INVTYPE_WEAPON", CLASS_WEAPON, 13, { "1h", "fist", "claw" } },
  { "INVTYPE_2HWEAPON", CLASS_WEAPON, 10, { "2h", "staff" } },
  { "INVTYPE_2HWEAPON", CLASS_WEAPON, 6, { "2h", "polearm" } },
  { "INVTYPE_RANGED", CLASS_WEAPON, 2, { "bow" } },
  { "INVTYPE_RANGEDRIGHT", CLASS_WEAPON, 3, { "gun" } },
  { "INVTYPE_RANGEDRIGHT", CLASS_WEAPON, 18, { "crossbow" } },
  { "INVTYPE_RANGEDRIGHT", CLASS_WEAPON, 19, { "wand" } },
  -- Containers: any container subclass is a bag
  { "INVTYPE_BAG", CLASS_CONTAINER, 0, { "bag" } },
  { "", CLASS_CONTAINER, 3, { "bag" } },
  -- No words: shirt, tabard, thrown, ammo, quiver, relic, profession gear, non-equipment
  { "INVTYPE_BODY", CLASS_ARMOR, 0, {} },
  { "INVTYPE_TABARD", CLASS_ARMOR, 0, {} },
  { "INVTYPE_THROWN", CLASS_WEAPON, 16, {} },
  { "INVTYPE_AMMO", 6, 2, {} },
  { "INVTYPE_QUIVER", 11, 2, {} },
  { "INVTYPE_RELIC", CLASS_ARMOR, 7, {} },
  { "INVTYPE_PROFESSION_TOOL", 19, 0, {} },
  { "INVTYPE_PROFESSION_GEAR", 19, 0, {} },
  { "", 0, 1, {} },
}

local function testEverySlotAndType()
  local items = {}
  for index, case in ipairs(CASES) do
    items[index] = { case[1], case[2], case[3] }
  end
  local ItemKeywords = load(items)
  for index, case in ipairs(CASES) do
    local label = string.format("%s class %d sub %d", case[1], case[2], case[3])
    Assert.same(ItemKeywords.WordsFor(index), case[4], label)
  end
end

local function testUnknownItem()
  local ItemKeywords = load({})
  Assert.same(ItemKeywords.WordsFor(99), {})
  Assert.same(ItemKeywords.WordsFor(nil), {})
end

local function testMissingApi()
  Wow.reset()
  Wow.stub("C_Item", nil)
  Wow.stub("GetItemInfoInstant", nil)
  Fresh.require("Core.Constants")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Model.Slang")
  Assert.same(Fresh.require("Model.ItemKeywords").WordsFor(5), {})
end

-- extraSlang maps a player word to an existing slot/type word (§9 Keywords page).
local function testExtraSlang()
  local ItemKeywords = load({
    [1] = { "INVTYPE_WRIST", CLASS_ARMOR, 2 },
    [2] = { "INVTYPE_HEAD", CLASS_ARMOR, 4 },
  })
  local extra = { cuffs = "bracers", hat = "head", Lid = "HELM", nothing = "wand", [""] = "head" }
  Assert.same(ItemKeywords.WordsFor(1, extra), { "bracers", "bracer", "wrist", "leather", "cuffs" })
  Assert.same(ItemKeywords.WordsFor(2, extra), { "helm", "helmet", "head", "plate", "hat", "lid" })
  -- Several matches come out in sorted order; a word already present is not repeated.
  Assert.same(ItemKeywords.WordsFor(1, { zz = "wrist", aa = "wrist", wrist = "bracers" }), { "bracers", "bracer", "wrist", "leather", "aa", "zz" })
  -- Without extras, and with an empty table, nothing is added.
  Assert.same(ItemKeywords.WordsFor(1, {}), { "bracers", "bracer", "wrist", "leather" })
end

-- The extra table is read per call and never stored: a later call without it is unchanged.
local function testExtraSlangNotRemembered()
  local ItemKeywords = load({ [1] = { "INVTYPE_TRINKET", CLASS_ARMOR, 0 } })
  Assert.same(ItemKeywords.WordsFor(1, { bauble = "trinket" }), { "trinket", "bauble" })
  Assert.same(ItemKeywords.WordsFor(1), { "trinket" })
end

local function testResultIsFresh()
  local ItemKeywords = load({ [1] = { "INVTYPE_TRINKET", CLASS_ARMOR, 0 } })
  local first = ItemKeywords.WordsFor(1)
  first[#first + 1] = "mutated"
  Assert.same(ItemKeywords.WordsFor(1), { "trinket" })
end

local function testAmbiguousFlags()
  load({})
  local Slang = Fresh.require("Model.Slang")
  for _, word in ipairs({ "legs", "head", "hands", "feet" }) do
    Assert.truthy(Slang.ambiguous[word], word)
  end
  Assert.falsy(Slang.ambiguous.belt)
  Assert.falsy(Slang.ambiguous.plate)
end

-- Matcher step 4.4: a recognized slang word with no index entries still counts.
local function testWordSet()
  load({})
  local Slang = Fresh.require("Model.Slang")
  for _, word in ipairs({ "belt", "plate", "legs", "2h", "wand", "bag", "offhand" }) do
    Assert.truthy(Slang.wordSet[word], word)
  end
  Assert.falsy(Slang.wordSet.cuffs)
  -- Every ambiguous word is also a slang word.
  for word in pairs(Slang.ambiguous) do
    Assert.truthy(Slang.wordSet[word], word)
  end
end

-- Class-armor spec §4 rule 1: armor slot words are tagged "slot", armor types "type"; a player's
-- extra slang word takes the tag of the word it maps to.
local function testArmorTags()
  load({})
  local Slang = Fresh.require("Model.Slang")
  local ItemKeywords = Fresh.require("Model.ItemKeywords")
  local slots = {
    "belt",
    "waist",
    "boots",
    "boot",
    "feet",
    "shoes",
    "gloves",
    "glove",
    "hands",
    "gauntlets",
    "bracers",
    "bracer",
    "wrist",
    "helm",
    "helmet",
    "head",
    "shoulders",
    "shoulder",
    "pauldrons",
    "chest",
    "robe",
    "legs",
    "pants",
  }
  local expected = { cloth = "type", leather = "type", mail = "type", plate = "type" }
  for _, word in ipairs(slots) do
    expected[word] = "slot"
  end
  Assert.same(Slang.armorTags, expected)
  -- Non-armor slots carry no tag.
  for _, word in ipairs({ "ring", "cloak", "neck", "trinket", "shield", "offhand", "bag", "1h", "sword" }) do
    Assert.equal(Slang.armorTags[word], nil, word)
  end
  local tags = ItemKeywords.ArmorTags({ pl8 = "plate", Britches = "LEGS", junk = "wand", plate = "belt", [""] = "head" })
  Assert.equal(tags.pl8, "type")
  Assert.equal(tags.britches, "slot")
  Assert.equal(tags.junk, nil)
  Assert.equal(tags.plate, "type", "a static word keeps its tag")
  Assert.equal(tags[""], nil)
  Assert.equal(Slang.armorTags.pl8, nil, "the static table is not written")
  Assert.same(ItemKeywords.ArmorTags(nil), expected)
end

return function()
  testEverySlotAndType()
  testUnknownItem()
  testMissingApi()
  testExtraSlang()
  testExtraSlangNotRemembered()
  testResultIsFresh()
  testAmbiguousFlags()
  testWordSet()
  testArmorTags()
end
