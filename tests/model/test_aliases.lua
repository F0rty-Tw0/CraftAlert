local Assert = require("tests.helpers.assert")
local Fixture = require("tests.helpers.matcher_fixture")

local ENCH, BS, TAILOR = Fixture.ENCH, Fixture.BS, Fixture.TAILOR

-- Phrases of every record in nameIndex, as a set: phrase -> record.
local function records(index)
  local byPhrase = {}
  for first, list in pairs(index.nameIndex) do
    for _, record in ipairs(list) do
      Assert.equal(string.match(record.phrase, "^[^ ]+"), first, record.phrase .. " filed under its first word")
      Assert.equal(byPhrase[record.phrase], nil, record.phrase .. " listed once")
      byPhrase[record.phrase] = record
    end
  end
  return byPhrase
end

local function groups(record)
  local list = {}
  for _, entry in ipairs(record.entries) do
    list[#list + 1] = entry.group
  end
  table.sort(list)
  return list
end

-- §6.2 item 1: full names and alias kinds a (enchant suffix), b (edge runs), c (unique 5+ word).
local function testAliasKinds()
  local ns = Fixture.load()
  local index = Fixture.index(ns)
  local byPhrase = records(index)
  local expected = {
    -- full names
    ["enchant weapon fiery weapon"] = true,
    ["enchant weapon mongoose"] = true,
    ["enchant chest lesser stamina"] = true,
    ["enchant chest greater stamina"] = true,
    ["lionheart helm"] = true,
    ["green iron hauberk"] = true,
    ["green iron leggings"] = true,
    ["green iron boots"] = true,
    -- aliases
    ["fiery weapon"] = false, -- a (and b)
    ["enchant weapon fiery"] = false, -- b
    ["weapon fiery weapon"] = false, -- b
    ["fiery"] = false, -- c
    ["mongoose"] = false, -- a and c, one record
    ["weapon mongoose"] = false, -- b
    ["green iron"] = false, -- b, three recipes
    ["iron hauberk"] = false,
    ["iron leggings"] = false,
    ["iron boots"] = false,
    ["lionheart"] = false, -- c
    ["hauberk"] = false,
    ["leggings"] = false,
  }
  for phrase, full in pairs(expected) do
    Assert.truthy(byPhrase[phrase], "missing " .. phrase)
    Assert.equal(byPhrase[phrase].full, full, phrase .. " full")
  end
  for phrase in pairs(byPhrase) do
    Assert.truthy(expected[phrase] ~= nil, "unexpected alias " .. phrase)
  end
  Assert.same(groups(byPhrase["green iron"]), { "green iron boots", "green iron hauberk", "green iron leggings" })
  Assert.same(groups(byPhrase.mongoose), { "enchant weapon - mongoose" })
  Assert.equal(byPhrase["green iron hauberk"].wordCount, 3)
  Assert.equal(byPhrase.lionheart.wordCount, 1)
end

-- §6.2 item 2: all-guard aliases are never made (stop, slang, weapon, stat, profession words).
local function testGuard()
  local ns = Fixture.load()
  local byPhrase = records(Fixture.index(ns))
  for _, phrase in ipairs({ "enchant weapon", "enchant chest", "greater stamina", "lesser stamina", "lesser", "greater", "boots", "helm" }) do
    Assert.equal(byPhrase[phrase], nil, phrase)
  end
  -- An intent word in a name guards too; green and iron are allowed.
  local db = Fixture.db(ns)
  db.characters["Smith-Realm"].recipes[25] = { name = "Need Iron Spike", prof = BS }
  byPhrase = records(Fixture.index(ns, db))
  Assert.truthy(byPhrase["iron spike"])
  Assert.truthy(byPhrase["need iron"], "need guarded alone, iron is not")
  Assert.truthy(byPhrase.spike)
end

-- phraseSet holds full names only; records are shared by every character that knows the recipe.
local function testPhraseSetAndSharing()
  local ns = Fixture.load()
  local db = Fixture.db(ns)
  db.characters["Alt-Realm"] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = { [BS] = { name = "BS", primary = false, read = true } },
    recipes = { [22] = { name = "Green Iron Hauberk", prof = BS } },
  }
  local index = Fixture.index(ns, db)
  Assert.equal(index.phraseSet["green iron"], nil)
  Assert.equal(index.phraseSet.mongoose, nil)
  local record = index.phraseSet["green iron hauberk"]
  Assert.equal(record.full, true)
  Assert.equal(#record.entries, 2)
  Assert.truthy(rawequal(record, records(index)["green iron hauberk"]))
  Assert.truthy(rawequal(record.entries[1], index.phraseSet["green iron hauberk"].entries[1]))
  -- An alias record lists every character too.
  Assert.equal(#records(index).hauberk.entries, 2)
  -- A full name that is also another recipe's alias holds the full-name recipe only.
  db.characters["Smith-Realm"].recipes[25] = { name = "Heavy Green Iron Boots", prof = BS }
  index = Fixture.index(ns, db)
  Assert.same(groups(index.phraseSet["green iron boots"]), { "green iron boots" })
  Assert.same(groups(records(index)["iron boots"]), { "green iron boots", "heavy green iron boots" })
end

-- joinIndex[left] is one record or a list of records whose phrase starts with left: the
-- record that left .. right spells, or nil.
local function joined(index, left, right)
  local found = index.joinIndex[left]
  if found == nil then
    return nil
  end
  for _, record in ipairs(found.phrase and { found } or found) do
    if record.phrase == left .. right then
      return record
    end
  end
  return nil
end

-- §6.2 item 3: one-word records of 6+ letters split into every 2+|2+ pair.
local function testJoinIndex()
  local ns = Fixture.load()
  local index = Fixture.index(ns)
  local lionheart = records(index).lionheart
  Assert.truthy(rawequal(joined(index, "lion", "heart"), lionheart))
  Assert.truthy(rawequal(joined(index, "li", "onheart"), lionheart))
  Assert.truthy(rawequal(joined(index, "lionhea", "rt"), lionheart))
  Assert.truthy(rawequal(index.joinIndex.lion, lionheart), "a left with one record holds it directly")
  Assert.equal(index.joinIndex.l, nil)
  Assert.equal(index.joinIndex.lionhear, nil)
  Assert.truthy(joined(index, "mon", "goose"))
  Assert.equal(joined(index, "mon", "goo"), nil)
  Assert.equal(index.joinIndex.fi, nil, "fiery has 5 letters")
  -- Two records under one left: a list.
  local db = Fixture.db(ns)
  db.characters["Smith-Realm"].recipes[25] = { name = "Lionmane Helm", prof = BS }
  index = Fixture.index(ns, db)
  Assert.equal(#index.joinIndex.lion, 2)
  Assert.equal(joined(index, "lion", "mane").phrase, "lionmane")
  Assert.equal(joined(index, "lion", "heart").phrase, "lionheart")
end

-- §6.2 item 4: slot word after "enchant", expanded through Slang.slots; best enchant first.
local function testStatSlotIndex()
  local ns = Fixture.load()
  local index = Fixture.index(ns)
  local chest = index.statSlotIndex.chest.stamina
  Assert.equal(chest[1].group, "enchant chest - greater stamina", "greater beats lesser")
  Assert.equal(chest[2].group, "enchant chest - lesser stamina")
  Assert.truthy(rawequal(index.statSlotIndex.robe.stamina, chest) or index.statSlotIndex.robe.stamina[1] == chest[1])
  Assert.equal(index.statSlotIndex.weapon, nil, "no stat word in the weapon enchants")
  Assert.equal(index.wordIndex.weapon, nil, "weapon is never a wordIndex word")

  local db = Fixture.db(ns)
  db.characters["Ench-Realm"].recipes = {
    [40] = { name = "Enchant Bracer - Minor Health", prof = ENCH },
    [41] = { name = "Enchant Bracer - Health", prof = ENCH },
    [42] = { name = "Enchant Bracer - Superior Health", prof = ENCH },
    [43] = { name = "Enchant 2H Weapon - Agility", prof = ENCH },
    [44] = { name = "Enchant 2H Weapon - Major Agility", prof = ENCH },
    [45] = { name = "Enchant 2H Weapon - Major Agility", prof = ENCH },
    [46] = { name = "Enchant Cloak - Lesser Agility", prof = ENCH },
  }
  index = Fixture.index(ns, db)
  for _, slot in ipairs({ "bracers", "bracer", "wrist" }) do
    local list = index.statSlotIndex[slot].health
    Assert.equal(#list, 3, slot)
    Assert.equal(list[1].recipeKey, 42, slot .. ": superior first")
    Assert.equal(list[2].recipeKey, 41, slot .. ": no tier word beats minor")
    Assert.equal(list[3].recipeKey, 40)
  end
  -- Same tier: the larger numeric recipeKey wins.
  Assert.equal(index.statSlotIndex["2h"].agility[1].recipeKey, 45)
  Assert.equal(index.statSlotIndex.cape.agility[1].recipeKey, 46)

  -- Mixed key types (numeric keys next to Classic name keys): numbers first, larger first,
  -- then names. Numbers carry names that sort against them, which a name-only compare
  -- between a number and a string turned into cycles (an intransitive sort order).
  db = ns.Defaults.Db()
  local numbered, named, want = {}, {}, {}
  for k = 1, 12 do
    numbered[k] = { name = string.format("Enchant Chest - Stamina %02d", 25 - 2 * k), prof = ENCH }
    local name = string.format("enchant chest - stamina %02d", 2 * k)
    named[name] = { name = name, prof = ENCH }
  end
  for k = 12, 1, -1 do
    want[#want + 1] = k
  end
  for k = 1, 12 do
    want[#want + 1] = string.format("enchant chest - stamina %02d", 2 * k)
  end
  db.characters["A-Realm"] = Fixture.character({ ENCH }, numbered)
  db.characters["B-Realm"] = Fixture.character({ ENCH }, named)
  local got = {}
  for _, entry in ipairs(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }).statSlotIndex.chest.stamina) do
    got[#got + 1] = entry.recipeKey
  end
  Assert.same(got, want)
end

-- §6.2 item 5: one-word records and profession words of 5+ letters, by first byte and length.
local function testTypoBuckets()
  local ns = Fixture.load()
  local index = Fixture.index(ns)
  local byPhrase = records(index)
  local function bucket(word)
    local byLength = index.typoBuckets[string.byte(word)]
    return byLength and byLength[#word] and byLength[#word][word]
  end
  Assert.truthy(rawequal(bucket("mongoose"), byPhrase.mongoose))
  Assert.truthy(rawequal(bucket("fiery"), byPhrase.fiery))
  Assert.truthy(rawequal(bucket("lionheart"), byPhrase.lionheart))
  Assert.equal(bucket("tailor"), TAILOR)
  Assert.equal(bucket("enchanters"), ENCH)
  Assert.equal(bucket("smith"), BS)
  -- 4-letter slang is exact-only (step 4.6); professions with no crafter are absent.
  Assert.equal(bucket("ench"), nil)
  Assert.equal(bucket("leatherworker"), nil)
  Assert.equal(bucket("green iron"), nil, "multi-word records are not typo targets")
end

-- §5.3: a Classic session learn gets its full-name record only and does not count for kind c.
local function testPendingLearns()
  local ns = Fixture.load("tbc")
  local db = ns.Defaults.Db()
  db.characters["Me-Realm"] = {
    source = "local",
    enabled = true,
    realms = {},
    professions = { blacksmithing = { name = "Blacksmithing", primary = false, read = true } },
    recipes = { ["lionheart helm"] = { name = "lionheart helm", prof = "blacksmithing" } },
  }
  local index = ns.Index.Build(db, db.settings, {
    ownKey = "Me-Realm",
    pending = { "lionheart helm", "lionheart gauntlets of fire" },
  })
  local byPhrase = records(index)
  Assert.equal(#byPhrase["lionheart helm"].entries, 1, "stored recipe wins over the same pending name")
  Assert.truthy(byPhrase["lionheart gauntlets of fire"].full)
  Assert.equal(byPhrase["lionheart gauntlets"], nil, "no aliases for a session learn")
  Assert.equal(byPhrase.gauntlets, nil)
  Assert.truthy(byPhrase.lionheart, "pending names do not make lionheart shared")
end

return function()
  testAliasKinds()
  testGuard()
  testPhraseSetAndSharing()
  testJoinIndex()
  testStatSlotIndex()
  testTypoBuckets()
  testPendingLearns()
  require("tests.helpers.wow").reset()
end
