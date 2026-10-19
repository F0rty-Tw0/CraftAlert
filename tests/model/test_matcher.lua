local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

local ENCH, BS, TAILOR, LW = Fixture.ENCH, Fixture.BS, Fixture.TAILOR, Fixture.LW
local SENDER = Fixture.SENDER
local character, expect, why = Fixture.character, Fixture.expect, Fixture.why

local function fixture(ns, index)
  ns.Matcher.SetIndex(index or Fixture.index(ns))
end

-- §6.2 item 6: the required lines against the fixture index.
local function testRequiredLines()
  local ns = Fixture.load()
  fixture(ns)
  expect(ns, "lf fiery weapon", "item:enchant weapon - fiery weapon")
  local result = expect(ns, "lf lion heart", "item:lionheart helm")
  Assert.equal(why(result), "lf+lion+heart")
  expect(ns, "lf enchant mangoose pls", "item:enchant weapon - mongoose")
  expect(ns, "Any Enchaters in ORG?", "profession:" .. ENCH)
  result = expect(ns, "LF Enchanter +8stam to chest", "item:enchant chest - greater stamina")
  Assert.equal(why(result), "lf+chest+8stam")
  Assert.equal(result.entryCount, 1)
  Assert.equal(result.entries[1].character, "Ench-Realm")
  result = expect(ns, "LF BS with green iron chest", "item:green iron hauberk")
  Assert.equal(why(result), "lf+green iron+chest")
  expect(ns, "LF a <name> Tailor. Hoping to lend him my name", "profession:" .. TAILOR)
  fixture(ns, Fixture.withLeatherworker(ns))
  expect(ns, "LF healer for Lower Blackrock Spire", "stop:nomatch")
  expect(ns, "LF lwer", "profession:" .. LW, "the leatherworker is enabled")
end

-- §6.3 step 1 gate and lastStop per drop reason.
local function testGate()
  local ns = Fixture.load()
  fixture(ns)
  local Matcher = ns.Matcher
  ns.PlayerName.Init()
  Assert.equal(Matcher.Match("general", "lf fiery weapon", SENDER), nil)
  Assert.equal(Matcher.lastStop, "channel", "disabled channel dropped at step 1")
  Assert.equal(Matcher.Match("trade", Wow.secret("lf fiery weapon"), SENDER), nil)
  Assert.equal(Matcher.lastStop, "secret")
  Assert.equal(Matcher.Match("trade", "lf fiery weapon", Wow.secret(SENDER)), nil)
  Assert.equal(Matcher.lastStop, "secret")
  Assert.equal(Matcher.Match("trade", "lf fiery weapon", "Me-Realm"), nil)
  Assert.equal(Matcher.lastStop, "self")
  local db = Fixture.db(ns)
  db.ignored["Spammer-Realm"] = true
  fixture(ns, Fixture.index(ns, db))
  Assert.equal(Matcher.Match("trade", "lf fiery weapon", "Spammer-Realm"), nil)
  Assert.equal(Matcher.lastStop, "blocked")
  -- MatchUngated runs steps 2-4 only (/ca test).
  Assert.truthy(Matcher.MatchUngated("lf fiery weapon"))
  Assert.equal(Matcher.lastStop, "match")
  expect(ns, "WTS fiery weapon", "stop:prefilter")
  expect(ns, "selfish wolf fiery weapon", "stop:intent")
  expect(ns, "nomatch line lf", "stop:nomatch")
end

-- §6.3 step 3: blockers and ad shapes win over intent; PST alone is no ad.
local function testIntentAndAds()
  local ns = Fixture.load()
  fixture(ns)
  expect(ns, "LF fiery weapon WTS", "stop:blocker", "blocker beats intent")
  expect(ns, "need fiery weapon lfw", "stop:blocker")
  expect(ns, "Crafting fiery weapon, need mats, PST", "stop:blocker", "crafting ... pst")
  expect(ns, "anyone need fiery weapon? /w me", "stop:blocker", "/w me")
  expect(ns, "I can craft fiery weapon if you need, pst", "stop:blocker", "can craft + pst")
  expect(ns, "can craft fiery weapon if you need", "item:enchant weapon - fiery weapon", "can craft without pst")
  expect(ns, "LF fiery weapon PST", "item:enchant weapon - fiery weapon", "pst alone")
  expect(ns, "pst crafting need fiery weapon", "item:enchant weapon - fiery weapon", "pst before crafting")
  -- "/w me" is an ad only as a whole word: not "/w meow" or "/w melissa".
  expect(ns, "LF enchanter /w meow", "profession:" .. ENCH, "/w meow")
  expect(ns, "lf fiery weapon /w melissa", "item:enchant weapon - fiery weapon", "/w melissa")
  expect(ns, "lf fiery weapon /w me.", "stop:blocker", "/w me then punctuation")
  expect(ns, "lf fiery weapon /w melissa or /w me", "stop:blocker", "a later whole /w me")
end

-- §6.3 4.1: the first craftable item link matches; other links and link text are ignored.
local function testItemLinks()
  local ns = Fixture.load()
  local index = Fixture.itemIndex(ns)
  local result = expect(ns, "WTB |Hitem:999|h[Thunderbrow Ring]|h or |cnIQ3:|Hitem:501::::::::30:1488|h[Thick Plate Belt]|h|r", "item:501")
  Assert.equal(result.entryCount, 2, "both crafters")
  Assert.equal(result.prof, BS)
  Assert.equal(why(result), "wtb+501")
  Assert.truthy(rawequal(result.entries[1], index.itemIndex[501][1]))
  -- Enchant link names match full recipe names through phraseSet.
  fixture(ns)
  expect(ns, "LF |cffffd000|Henchant:23800|h[Enchant Weapon - Mongoose]|h|r", "item:enchant weapon - mongoose")
  expect(ns, "LF |cffffd000|Henchant:1|h[Mongoose]|h|r", "stop:nomatch", "link names match full names only")
end

-- §6.3 4.2: longest phrase wins, so a full name beats its own alias; several -> 4.4 set.
local function testPhrases()
  local ns = Fixture.load()
  fixture(ns)
  expect(ns, "lf green iron hauberk", "item:green iron hauberk")
  expect(ns, "lf green iron", "profession:" .. BS, "three recipes, one profession")
  -- §6.4: an ambiguous word counts beside another wordIndex word or a 4.2 phrase match.
  expect(ns, "lf green iron legs", "item:green iron leggings")
  expect(ns, "lf green iron feet", "item:green iron boots")
  expect(ns, "lf green iron mail legs", "item:green iron leggings")
  expect(ns, "lf mongoose", "item:enchant weapon - mongoose")
  expect(ns, "lf greenironhauberk", "stop:nomatch", "only one-word records join")
  expect(ns, "lf hauberk or leggings", "profession:" .. BS)
  -- Keywords with + ( [ % are plain text: no pattern errors, no false hits.
  expect(ns, "LF [Green Iron Hauberk] (+5%) [%s", "item:green iron hauberk")
  expect(ns, "LF %a+ (.*) [green", "stop:nomatch")
  -- Join pairs: two one-word records under the same left side.
  local db = Fixture.db(ns)
  db.characters["Smith-Realm"].recipes[25] = { name = "Lionmane Helm", prof = BS }
  fixture(ns, Fixture.index(ns, db))
  expect(ns, "lf lion mane", "item:lionmane helm")
  expect(ns, "lf lion heart", "item:lionheart helm")
  expect(ns, "lf lion hearts", "stop:nomatch")
end

-- §6.3 4.2: a phrase that is a recipe's full name matches that recipe only, even when it is
-- also another recipe's alias; link names match full names only.
local function testFullNameBeatsAlias()
  local ns = Fixture.load()
  local db = ns.Defaults.Db()
  local ALCH = 171
  db.characters["Alch-Realm"] = character({ ALCH }, {
    [1] = { name = "Healing Potion", prof = ALCH },
    [2] = { name = "Greater Healing Potion", prof = ALCH },
    [3] = { name = "Major Healing Potion", prof = ALCH },
  })
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  expect(ns, "lf healing potion", "item:healing potion")
  expect(ns, "lf greater healing potion", "item:greater healing potion")
  db = Fixture.db(ns)
  db.characters["Smith-Realm"].recipes[25] = { name = "Heavy Green Iron Boots", prof = BS }
  fixture(ns, Fixture.index(ns, db))
  expect(ns, "lf green iron boots", "item:green iron boots")
  expect(ns, "lf |cffffd000|Henchant:1|h[Green Iron Boots]|h|r", "item:green iron boots")
  expect(ns, "lf heavy green iron boots", "item:heavy green iron boots")
end

-- §6.3 4.5 typo pass: 5+ letter tokens, distance 1 only, the first 3 eligible tokens tried.
local function testTypoPass()
  local ns = Fixture.load()
  fixture(ns)
  expect(ns, "lf mongose", "item:enchant weapon - mongoose", "distance 1")
  expect(ns, "lf mnogoose", "item:enchant weapon - mongoose", "a swap counts 1")
  expect(ns, "lf lionhaert", "stop:nomatch", "a kind-c alias by typo needs a second word")
  expect(ns, "lf mangose", "stop:nomatch", "distance 2 on a 7-letter token")
  expect(ns, "lf mangoosee", "stop:nomatch", "distance 2 on 8+ letters too")
  expect(ns, "any tilor can help pls", "profession:" .. TAILOR)
  expect(ns, "lf alpha bravo mangoose", "item:enchant weapon - mongoose", "the 3rd eligible token is tried")
  expect(ns, "lf alpha bravo charl mangoose", "stop:nomatch", "the 4th is not")
end

-- §6.3 4.6: profession words, gated by "Profession-word alerts".
local function testProfessionWords()
  local ns = Fixture.load()
  fixture(ns)
  expect(ns, "Any Blacksmith 150+?", "profession:" .. BS)
  expect(ns, "WTB enchants, your mats", "profession:" .. ENCH)
  expect(ns, "LF Engineer", "stop:nomatch", "no engineer enabled")
  local db = Fixture.db(ns)
  db.settings.professionWordAlerts = false
  fixture(ns, Fixture.index(ns, db))
  expect(ns, "LF Blacksmith", "stop:nomatch")
  expect(ns, "lf fiery weapon", "item:enchant weapon - fiery weapon")
end

-- Classic keys professions by name; the matcher passes them through.
local function testClassicKeys()
  local ns = Fixture.load("tbc")
  local db = ns.Defaults.Db()
  db.characters["Smith-Realm"] = character({ "blacksmithing", "jewelcrafting" }, {})
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  expect(ns, "LF bs", "profession:blacksmithing")
  expect(ns, "LF jc", "profession:jewelcrafting")
end

-- One module-level result table, reused; SetIndex configures the Tokenizer intent list.
-- Weak-keyed probe of an index and everything it owns (records, lists, entries).
local function probeIndex(index)
  local probe = setmetatable({}, { __mode = "k" })
  probe[index] = true
  for _, list in pairs(index.nameIndex) do
    probe[list] = true
    for _, record in ipairs(list) do
      probe[record], probe[record.entries] = true, true
      for _, entry in ipairs(record.entries) do
        probe[entry] = true
      end
    end
  end
  for _, list in pairs(index.wordIndex) do
    probe[list] = true
  end
  return probe
end

-- After SetIndex(B), nothing the matcher kept from index A (its buffers of records, lists and
-- entries, the last result) keeps A alive.
local function testOldIndexReleased()
  local ns = Fixture.load()
  local probe
  do
    local old = Fixture.index(ns)
    probe = probeIndex(old)
    fixture(ns, old)
  end
  for _, line in ipairs({
    "lf green iron hauberk",
    "lf mongose",
    "lf tailr",
    "lf chest 8stam",
    "lf mail feet",
    "lf mail",
    "lf enchanter",
    "lf green iron chest",
  }) do
    Assert.truthy(ns.Matcher.Match("trade", line, SENDER), line)
  end
  fixture(ns, Fixture.index(ns))
  collectgarbage("collect")
  collectgarbage("collect")
  Assert.equal(next(probe), nil, "the old index is collectable")
  Assert.equal(ns.MatchCandidates.result.entryCount, 0, "the last result is cleared")
end

-- A span longer than any phrase key (255+ bytes) never matches a record by shape.
local function testLongSpan()
  local ns = Fixture.load()
  local db = ns.Defaults.Db()
  db.characters["A-Realm"] = character({ BS }, { [1] = { name = "aa cc", prof = BS }, [2] = { name = "bb cc", prof = BS } })
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  expect(ns, "lf aa cc" .. string.rep("x", 255) .. "c", "stop:nomatch")
  expect(ns, "lf aa cc", "item:aa cc")
end

-- A span of a record's shape (first word, length, word count, second word's length, last byte)
-- matches only when the record's phrase starts right there, not somewhere later in the line.
local function testShapeTwinElsewhere()
  local ns = Fixture.load()
  local db = ns.Defaults.Db()
  db.characters["A-Realm"] = character({ BS }, { [1] = { name = "aa cc", prof = BS }, [2] = { name = "bb cc", prof = BS } })
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  expect(ns, "lf aa dc xaa ccx", "stop:nomatch")
end

local function testResultReuseAndConfigure()
  local ns = Fixture.load()
  local db = Fixture.db(ns)
  db.settings.intentWords = { "plz" }
  fixture(ns, Fixture.index(ns, db))
  local first = ns.Matcher.Match("trade", "plz green iron", SENDER)
  Assert.equal(first.entryCount, 3)
  expect(ns, "lf fiery weapon", "stop:prefilter", "intent list replaced")
  local second = ns.Matcher.Match("trade", "mongoose plz", SENDER)
  Assert.truthy(rawequal(first, second))
  Assert.equal(second.group, "enchant weapon - mongoose")
  Assert.equal(second.entries[2], nil, "stale entries cleared")
  Assert.equal(ns.Matcher.Match("trade", "plz chest 8stam", SENDER).whyCount, 3)
  Assert.equal(ns.Matcher.Match("trade", "mongoose plz", SENDER).why[3], nil, "stale why cleared")
end

return function()
  testRequiredLines()
  testGate()
  testIntentAndAds()
  testItemLinks()
  testPhrases()
  testFullNameBeatsAlias()
  testTypoPass()
  testProfessionWords()
  testClassicKeys()
  testResultReuseAndConfigure()
  testOldIndexReleased()
  testLongSpan()
  testShapeTwinElsewhere()
  Wow.reset()
end
