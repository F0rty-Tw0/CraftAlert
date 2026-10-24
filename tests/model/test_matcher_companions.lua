local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Words that count only beside a second word (user rulings 2026-10-20): kind-c aliases
-- (§6.2 item 1) and the ambiguous slot word "ring" (§6.4), through Matcher.Match.
local BS, ENCH, TAILOR = Fixture.BS, Fixture.ENCH, Fixture.TAILOR
local JC = 755
local character, expect, why = Fixture.character, Fixture.expect, Fixture.why

-- §6.2 item 1 (c): a kind-c alias hit by one token counts beside a wordIndex word or another
-- step 4.2 hit; a join pair counts on its own; kinds a and b and full names need nothing.
local function testKindCOnSpecFixture()
  local ns = Fixture.load()
  ns.Matcher.SetIndex(Fixture.index(ns))
  expect(ns, "lf lionheart", "stop:nomatch")
  expect(ns, "lf fiery", "stop:nomatch")
  expect(ns, "lf lionheart lionheart", "stop:nomatch", "the same alias twice is one hit")
  expect(ns, "lf lion heart", "item:lionheart helm", "a join pair")
  local result = expect(ns, "lf lionheart plate", "item:lionheart helm", "a wordIndex word")
  Assert.equal(why(result), "lf+lionheart")
  expect(ns, "lf hauberk or leggings", "item:green iron hauberk") -- leggings is a slot word, no kind-c alias (user ruling 2026-10-24)
  expect(ns, "lf mongoose", "item:enchant weapon - mongoose", "kind a (also kind c) needs nothing")
  -- Step 4.5: the same rule for a kind-c alias hit by the typo pass ("leather" empties 4.4,
  -- so the typo pass runs with "boots" in the line).
  expect(ns, "lf lionhaert", "stop:nomatch")
  expect(ns, "lf lionhaert boots leather", "item:lionheart helm", "a wordIndex word")
  expect(ns, "lf mongose", "item:enchant weapon - mongoose", "kind a by typo")
  -- An enchant slot word (§6.2 item 4) is a companion too, for an exact or a typo hit (user
  -- ruling 2026-10-20). A misspelled slot word is none: slot words are no typo targets.
  expect(ns, "lf fiery for my weapon", "item:enchant weapon - fiery weapon", "a slot word")
  expect(ns, "lf fierry weapon", "item:enchant weapon - fiery weapon", "a slot word, by typo")
  expect(ns, "lf fiery weapn", "stop:nomatch", "a misspelled slot word")
  -- A lone hit the rule set aside is a typo hit's companion and counts with it, so a typo line
  -- behaves like its exact line (user ruling 2026-10-20).
  expect(ns, "lf lionheart hauberk", "profession:" .. BS)
  result = expect(ns, "lf lionhaert hauberk", "profession:" .. BS)
  Assert.equal(why(result), "lf+lionhaert+hauberk")
  expect(ns, "lf mongoose hauberk", "profession:" .. ENCH)
  expect(ns, "lf mongose hauberk", "profession:" .. ENCH)
  expect(ns, "lf lionheart lionhaert", "stop:nomatch", "the same alias twice is one hit")
  -- "leggings" is a slot word, no kind-c alias (user ruling 2026-10-24): "hauberk" matches alone.
  result = expect(ns, "lf hauberk leggings enchant lionhaert", "item:green iron hauberk")
  Assert.equal(why(result), "lf+hauberk")
  -- A token whose hits were all set aside is no why token.
  result = expect(ns, "lf lionhaert mongose", "item:enchant weapon - mongoose")
  Assert.equal(why(result), "lf+mongose")
end

-- The reviewer's probe index (PR 3): one-word names of other things in Trade. Shadowfang is a
-- sword (item 910: class 2, subclass 7).
local function testKindCOnTradeWords()
  local ns = Fixture.load()
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      if itemID == 910 then
        return itemID, "type", "subtype", "INVTYPE_WEAPON", 0, 2, 7
      end
    end,
  })
  local db = ns.Defaults.Db()
  db.characters["Tailor-Realm"] = character({ TAILOR }, {
    [1] = { name = "Black Mageweave Vest", prof = TAILOR },
    [2] = { name = "Shadoweave Mask", prof = TAILOR },
    [3] = { name = "Runecloth Bag", prof = TAILOR },
  })
  db.characters["Smith-Realm"] = character({ BS }, {
    [4] = { item = 910, name = "Shadowfang", prof = BS },
    [5] = { name = "Heavy Copper Maul", prof = BS },
  })
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  for _, line in ipairs({
    "LF black lotus",
    "lf copper ore",
    "need heavy hitters for raid",
    "lf runecloth, paying well",
    "who wants to go black temple",
  }) do
    expect(ns, line, "stop:nomatch")
  end
  expect(ns, "lf black mageweave", "item:black mageweave vest", "kind b")
  expect(ns, "lf heavy copper maul", "item:heavy copper maul")
  expect(ns, "lf copper maul", "item:heavy copper maul")
  -- A one-word full name follows the same rule (§6.2 item 1); link names and item links don't.
  expect(ns, "LF tank for Shadowfang Keep", "stop:nomatch")
  expect(ns, "lf shadowfang", "stop:nomatch")
  expect(ns, "lf shadowfnag", "stop:nomatch", "by typo")
  local result = expect(ns, "lf shadowfang sword", "item:910", "a wordIndex word")
  Assert.equal(why(result), "lf+shadowfang")
  expect(ns, "lf |cffffd000|Henchant:0|h[Shadowfang]|h|r", "item:910", "a link name") -- ID 0: no stored recipe
  expect(ns, "LF |cff0070dd|Hitem:910::::::::60:::::|h[Shadowfang]|h|r", "item:910", "an item link")
end

-- §6.4: "ring" is ambiguous. Ring items (class 4 subclass 0) carry no armor word; item 802
-- (a setting) has no item words.
local function testRing()
  local ns = Fixture.load()
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      if itemID == 801 then
        return itemID, "type", "subtype", "INVTYPE_FINGER", 0, 4, 0
      end
    end,
  })
  local db = ns.Defaults.Db()
  db.characters["Jc-Realm"] = character({ JC }, {
    [1] = { item = 801, name = "Heavy Silver Ring", prof = JC },
    [2] = { item = 802, name = "Thorium Setting", prof = JC },
  })
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  expect(ns, "LF tank, ring me when ready", "stop:nomatch")
  expect(ns, "anyone want to go to the ring of blood", "stop:nomatch")
  expect(ns, "LF ring", "stop:nomatch", "an ambiguous word alone")
  expect(ns, "LF ring crafter", "item:801", "a crafting cue word partners it (user ruling 2026-10-21)")
  -- A phrase: "silver ring" is a kind-b alias (step 4.2).
  expect(ns, "lf silver ring", "item:801")
  -- Another word: "ring" is the wordIndex word the kind-c alias "heavy" needs, and "finger"
  -- is the second wordIndex word "ring" needs (step 4.4).
  expect(ns, "lf heavy ring", "item:801")
  expect(ns, "lf ring for my finger", "item:801")
end

-- User ruling 2026-10-22: "back" names a cloak in step 4.4 only. It is no companion of a lone
-- step 4.2 or 4.5 hit and no stat + slot slot word (step 4.3), so "be back in 5" completes
-- nothing; "cloak" and the other ambiguous words ("legs") keep both roles.
local function testBackIsNoCompanion()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Tai-Realm"] = character({ TAILOR }, { [9] = { item = 606, name = "Silk Cloak", prof = TAILOR } })
    db.characters["Smith2-Realm"] = character({ BS }, {
      [4] = { item = 910, name = "Shadowfang", prof = BS },
      [5] = { name = "Heavy Copper Maul", prof = BS },
      [6] = { item = 802, name = "Hide Gloves", prof = BS },
    })
    db.characters["Ench-Realm"] = character({ ENCH }, {
      [11] = { name = "Enchant Cloak - Greater Agility", prof = ENCH },
      [12] = { name = "Enchant Cloak - Superior Mana", prof = ENCH },
    })
  end)
  expect(ns, "need heavy hitters for raid, be back in 5", "stop:nomatch", "step 4.2: a kind-c alias")
  expect(ns, "LF shadowfang run, back in 10", "stop:nomatch", "step 4.2: a one-word full name")
  expect(ns, "LF shadowfnag run, back in 10", "stop:nomatch", "step 4.5: by typo")
  expect(ns, "LF healer w mana, back in 5", "stop:nomatch", "step 4.3: no stat + slot")
  -- With "back" no stat + slot word, step 4.4 counts it through its cue word "enchant" and
  -- narrows to Enchanting, which has no cloak item: step 4.6 alerts Enchanting (the ruling
  -- accepts this over the cloak agility enchant).
  expect(ns, "LF agi back enchant", "profession:" .. ENCH)
  expect(ns, "LF agi cloak enchant", "item:enchant cloak - greater agility", "cloak is a stat + slot word")
  expect(ns, "LF shadowfang cloak", "item:910", "cloak is a companion")
  expect(ns, "LF shadowfang legs", "item:910", "another ambiguous word is a companion")
  expect(ns, "LF shadowfang, need a hand", "stop:nomatch", "hand is no companion (user ruling 2026-10-24)")
  expect(ns, "LF tailor back", "item:606", "step 4.4 still reads back")
end

return function()
  testKindCOnSpecFixture()
  testKindCOnTradeWords()
  testRing()
  testBackIsNoCompanion()
  Wow.reset()
end
