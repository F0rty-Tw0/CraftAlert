local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Words that count only beside a second word (user rulings 2026-10-20): kind-c aliases
-- (§6.2 item 1) and the ambiguous slot word "ring" (§6.4), through Matcher.Match.
local BS, TAILOR = Fixture.BS, Fixture.TAILOR
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
  expect(ns, "lf hauberk or leggings", "profession:" .. BS, "two kind-c hits count for each other")
  expect(ns, "lf mongoose", "item:enchant weapon - mongoose", "kind a (also kind c) needs nothing")
  -- Step 4.5: the same rule for a kind-c alias hit by the typo pass ("leather" empties 4.4,
  -- so the typo pass runs with "boots" in the line).
  expect(ns, "lf lionhaert", "stop:nomatch")
  expect(ns, "lf lionhaert boots leather", "item:lionheart helm", "a wordIndex word")
  expect(ns, "lf mongose", "item:enchant weapon - mongoose", "kind a by typo")
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
  expect(ns, "lf |cffffd000|Henchant:1|h[Shadowfang]|h|r", "item:910", "a link name")
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
  -- A phrase: "silver ring" is a kind-b alias (step 4.2).
  expect(ns, "lf silver ring", "item:801")
  -- Another word: "ring" is the wordIndex word the kind-c alias "heavy" needs, and "finger"
  -- is the second wordIndex word "ring" needs (step 4.4).
  expect(ns, "lf heavy ring", "item:801")
  expect(ns, "lf ring for my finger", "item:801")
end

return function()
  testKindCOnSpecFixture()
  testKindCOnTradeWords()
  testRing()
  Wow.reset()
end
