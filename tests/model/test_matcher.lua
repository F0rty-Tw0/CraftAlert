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
  result = assert(expect(ns, "LF Enchanter +8stam to chest", "item:enchant chest - greater stamina"))
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
  local Matcher = ns.Matcher
  -- No index yet (login stopped early or the build raised): /ca test says so, not "nomatch".
  Assert.equal(Matcher.MatchUngated("lf fiery weapon"), nil)
  Assert.equal(Matcher.lastStop, "noIndex")
  fixture(ns)
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
  fixture(ns, Fixture.index(ns, db))
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
  expect(ns, "WTC fiery weapon", "item:enchant weapon - fiery weapon", "wtc is a default intent word")
  expect(ns, "LFRC fiery weapon", "item:enchant weapon - fiery weapon", "lfrc is a default intent word")
  expect(ns, "TANK LF FOR ENCHS ORG", "profession:" .. ENCH, "enchs is an Enchanting word")
  expect(ns, "pst crafting need fiery weapon", "item:enchant weapon - fiery weapon", "pst before crafting")
  -- "/w me" is an ad only as a whole word: not "/w meow" or "/w melissa".
  expect(ns, "LF enchanter /w meow", "profession:" .. ENCH, "/w meow")
  expect(ns, "lf fiery weapon /w melissa", "item:enchant weapon - fiery weapon", "/w melissa")
  expect(ns, "need fiery weapon /w me.", "stop:blocker", "/w me then punctuation")
  expect(ns, "need fiery weapon /w melissa or /w me", "stop:blocker", "a later whole /w me")
  -- A buyer's word (lf, lfc, lfrc, wtb, wtc) makes "/w me" a request, not an ad.
  expect(ns, "lf fiery weapon /w me.", "item:enchant weapon - fiery weapon", "lf + /w me")
  expect(ns, "anyone lfc fiery weapon? /w me", "item:enchant weapon - fiery weapon", "any buyer word in the line")
  expect(ns, "WTB fiery weapon /w me", "item:enchant weapon - fiery weapon")
  expect(ns, "LF fiery weapon WTS /w me", "stop:blocker", "a blocker word still wins")
  expect(ns, "WTC fiery weapon /w me", "item:enchant weapon - fiery weapon", "wtc is a buyer word")
  expect(ns, "LFRC fiery weapon /w me", "item:enchant weapon - fiery weapon", "lfrc is a buyer word")
  -- "LF work" is a crafter's ad, whatever else the line says.
  expect(ns, "Enchanter LF work /w me", "stop:blocker")
  expect(ns, "Max enchanter LF work, fiery weapon", "stop:blocker")
  expect(ns, "LF fiery weapon, will work for tips", "item:enchant weapon - fiery weapon", "work not right after lf")
  expect(ns, "LF work order fiery weapon", "item:enchant weapon - fiery weapon", "a work order is a buyer's request")
  expect(ns, "LF Work-Order fiery weapon", "item:enchant weapon - fiery weapon", "hyphenated work order")
end

-- §6.3 4.1: the first craftable item link matches; other links and link text are ignored.
local function testItemLinks()
  local ns = Fixture.load()
  local index = Fixture.itemIndex(ns)
  local result = assert(expect(ns, "WTB |Hitem:999|h[Thunderbrow Ring]|h or |cnIQ3:|Hitem:501::::::::30:1488|h[Thick Plate Belt]|h|r", "item:501"))
  Assert.equal(result.entryCount, 2, "both crafters")
  Assert.equal(result.prof, BS)
  Assert.equal(why(result), "wtb+501")
  Assert.truthy(rawequal(result.entries[1], index.itemIndex[501][1]))
  -- Enchant link names match full recipe names through phraseSet.
  fixture(ns)
  expect(ns, "LF |cffffd000|Henchant:23800|h[Enchant Weapon - Mongoose]|h|r", "item:enchant weapon - mongoose")
  expect(ns, "LF |cffffd000|Henchant:1|h[Mongoose]|h|r", "stop:nomatch", "link names match full names only")
end

-- §6.3 4.2: a recipe link's ID names a stored recipe whatever its text; else the text after a
-- "Profession:" prefix matches when the whole text does not.
local function testRecipeLinkIDs()
  local ns = Fixture.load()
  local db = Fixture.db(ns)
  db.characters["Tailor-Realm"].recipes[1228943] = { name = "Martyr's Gloves", prof = TAILOR }
  db.characters["Tailor-Realm"].recipes[17187] = { name = "Transmute: Arcanite", prof = TAILOR }
  db.characters["Tailor-Realm"].recipes[17188] = { name = "Arcanite", prof = TAILOR }
  db.characters["Tailor-Realm"].recipes["Bolt of Silk"] = { name = "Bolt of Silk", prof = TAILOR }
  fixture(ns, Fixture.index(ns, db))
  local result = expect(ns, "LF |cnIQ4:|Henchant:1228943|h[Midnight Tailoring: Martyr's Gloves]|h|r craftere", "item:martyr's gloves")
  Assert.equal(assert(result).entries[1].character, "Tailor-Realm")
  expect(ns, "LF |Henchant:12|h[Enchanting: Renamed]|h", "item:enchant weapon - mongoose", "the ID wins over the text")
  expect(ns, "LF |Henchant:9|h[Enchanting: Enchant Weapon - Mongoose]|h", "item:enchant weapon - mongoose", "prefix stripped")
  expect(ns, "LF |Henchant:9|h[Transmute: Arcanite]|h", "item:transmute: arcanite", "a colon in the name itself")
  expect(ns, "LF |Henchant:9|h[Tailoring: Bolt of Silk]|h", "item:bolt of silk", "name-keyed recipe")
  expect(ns, "LF |Henchant:9|h[Tailoring: Mongoose]|h", "stop:nomatch", "the stripped text matches full names only")
  -- Only enchant links carry IDs: an item ID equal to a recipe key is not that recipe.
  expect(ns, "LF |Hitem:12|h[Something]|h", "stop:nomatch")
  db.characters["Ench-Realm"].recipes[12].muted = true
  fixture(ns, Fixture.index(ns, db))
  expect(ns, "LF |Henchant:12|h[Enchanting: Renamed]|h", "stop:nomatch", "a muted recipe")
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
  expect(ns, "lf hauberk or leggings", "item:green iron hauberk") -- leggings is a slot word, no kind-c alias (user ruling 2026-10-24)
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

-- User ruling 2026-10-24 (R4, bug C26): an alias followed by a slot word keeps only the recipes
-- of that slot; a dropped alias is gone for the typo pass and the shorter hits it displaced.
local function testSlotNameGuard()
  local ns = Fixture.load()
  local db = Fixture.db(ns)
  db.characters["Smith-Realm"].recipes = { [22] = { name = "Green Iron Hauberk", prof = BS } }
  fixture(ns, Fixture.index(ns, db))
  expect(ns, "LF green iron helm", "stop:nomatch")
  local result = expect(ns, "LF green iron chest", "item:green iron hauberk")
  Assert.equal(why(result), "lf+green iron+chest", "the slot word that filtered stays in the why")
  expect(ns, "LF green iron", "item:green iron hauberk")
  -- User ruling 2026-10-25 ("Treat as offhand"): "off hand" after an alias filters as "offhand"
  -- does; punctuation before "off" or between the two words leaves the hit alone.
  expect(ns, "LF green iron offhand", "stop:nomatch")
  expect(ns, "LF green iron off hand", "stop:nomatch", "off hand filters as offhand")
  expect(ns, "LF green iron off-hand", "stop:nomatch", "off-hand filters as offhand")
  expect(ns, "LF green iron, off hand", "item:green iron hauberk", "punctuation before off")
  expect(ns, "LF green iron off, hand over", "item:green iron hauberk", "punctuation inside off hand")
  Fixture.itemIndex(ns, function(itemDb)
    itemDb.characters["Smith-Realm"].recipes[3] = { item = 915, name = "Zorgblade Frostmourne Tome", prof = BS }
  end)
  result = expect(ns, "LF zorgblade frostmourne off hand", "item:915", "an off-hand item stays")
  Assert.equal(why(result), "lf+zorgblade frostmourne+offhand")
  expect(ns, "LF zorgblade frostmourne gloves", "stop:nomatch")
  -- The typo pass skips the tokens of the dropped hit (it matches "thick", kind c, at distance 0).
  Fixture.itemIndex(ns)
  expect(ns, "LF thick plate helm", "stop:nomatch")
  expect(ns, "LF thick plate belt", "item:501")
  -- User ruling 2026-10-25: an everyday slot word (back, hand, ring, head, band, hood, vest) or
  -- punctuation before the slot word leaves the alias hit alone, as before R4.
  for _, word in ipairs({ "back", "hand", "ring", "head", "band", "hood", "vest" }) do
    expect(ns, "LF thick plate " .. word, "item:501", "everyday word: " .. word)
  end
  expect(ns, "LF thick plate, back in 5", "item:501", "punctuation, then back")
  expect(ns, "LF thick plate - hand over", "item:501", "dash, then hand")
  -- Punctuation alone also frees a slot word that is no everyday word ("helm" drops the hit when adjacent).
  expect(ns, "LF thick plate, helm", "item:501", "punctuation, then helm")
  expect(ns, "LF thick plate legs", "item:502", "legs is no everyday word: the belt is dropped")
  expect(ns, "LF thick plate hands", "stop:nomatch", "hands is no everyday word")
  -- The displaced shorter hit ("charged", kind c) does not come back after the drop.
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 802, name = "Charged Scrapmaster's Gauntlets", prof = BS }
  end)
  expect(ns, "LF Charged Scrapmaster's Helm", "stop:nomatch")
  expect(ns, "LF Charged Scrapmaster's Gloves", "item:802")
  -- The typo pass skips every token of a dropped multi-token hit, not only its first: "frostmourne"
  -- (the 2nd token, a kind c alias) is not revived as a typo target of itself.
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 802, name = "Zorgblade Frostmourne Gloves", prof = BS }
  end)
  expect(ns, "LF zorgblade frostmourne legs", "stop:nomatch")
  expect(ns, "LF zorgblade frostmourne gloves", "item:802")
  -- Two kept alias hits followed by the same slot word put it in the why once.
  Fixture.items[505] = { "INVTYPE_WAIST", 4, 4 }
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 505, name = "Alpha Beta Gamma Delta", prof = BS }
  end)
  result = expect(ns, "LF alpha beta belt gamma delta belt", "item:505")
  Assert.equal(why(result), "lf+alpha beta+gamma delta+belt", "the slot word once")
  Fixture.items[505] = nil
  -- Two kind-b hits on "thick plate": the belt entry goes, the treads stay (also by slang).
  Fixture.items[508] = { "INVTYPE_CHEST", 4, 4 }
  local function treads(db)
    db.settings.extraSlang = { footies = "boots" }
    db.characters["Smith-Realm"].recipes[3] = { item = 503, name = "Thick Plate Treads", prof = BS }
    db.characters["Smith-Realm"].recipes[4] = { item = 508, name = "Green Iron Hauberk", prof = BS }
  end
  Fixture.itemIndex(ns, treads)
  expect(ns, "LF thick plate boots", "item:503")
  expect(ns, "LF thick plate footies", "item:503")
  -- Only the hit followed by a slot word is filtered: both groups stay, a "set" (step 4.4).
  result = expect(ns, "LF thick plate boots or green iron", "item:503")
  Assert.equal(why(result), "lf+thick plate+green iron+plate+boots")
  -- The set path applies R4 too: the hit "thick plate" followed by "helm" is dropped, so it is
  -- no set member and its words are not in the why ("green iron boots" has no recipe: no match).
  result = expect(ns, "LF thick plate helm or green iron", "item:508")
  Assert.equal(why(result), "lf+green iron")
  expect(ns, "LF thick plate helm or green iron boots", "stop:nomatch")
  Fixture.items[508] = nil
  -- Enchants have no item words: they stay under a slot word.
  fixture(ns)
  db = Fixture.db(ns)
  db.characters["Ench-Realm"].recipes[15] = { name = "Enchant Boots - Minor Speed", prof = ENCH }
  db.characters["Ench-Realm"].recipes[16] = { name = "Enchant Bracer - Sim Health", prof = ENCH }
  fixture(ns, Fixture.index(ns, db))
  expect(ns, "LF minor speed boots", "item:enchant boots - minor speed")
  expect(ns, "LF sim health bracers", "item:enchant bracer - sim health")
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
  -- Leaves a set-aside record behind, which SetIndex must clear too.
  Assert.equal(ns.Matcher.Match("trade", "lf hauberk", SENDER), nil, "lf hauberk")
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
  -- The longest filed phrase (255 bytes) still matches.
  local long = "aa " .. string.rep("c", 252)
  db.characters["A-Realm"].recipes[3] = { name = long, prof = BS }
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  expect(ns, "lf " .. long, "item:" .. long)
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

-- The getter Matcher hands to step 4.4. WordGroups.Match is replaced so only this test calls it.
local function testClassGetter()
  local CLASS_ARMOR_ARG = 8 -- WordGroups.Match(index, tokens, count, intent, hasSet, setWhy, setWhyCount, classArmor)
  local function capture(flavor)
    local ns = Fixture.load(flavor)
    Fixture.itemIndex(ns)
    local seen = {}
    ns.WordGroups.Match = function(...)
      seen.getter = select(CLASS_ARMOR_ARG, ...)
      return false
    end
    return ns, seen
  end
  local ns, seen = capture()
  local calls = Fixture.stubClasses({ ["Player-1-W"] = "WARRIOR" })
  ns.Matcher.Match("trade", "LF belt", SENDER, "Player-1-W")
  Assert.equal(type(seen.getter), "function")
  local first = seen.getter
  Assert.same({ seen.getter() }, { "plate", "plate (warrior)" })
  ns.Matcher.Match("trade", "LF belt", SENDER, nil)
  Assert.equal(seen.getter, first, "one function value for every line")
  Assert.equal(seen.getter(), nil, "a line without a GUID has no class")
  ns.Matcher.Match("trade", "LF belt", SENDER, "Player-1-W")
  ns.Matcher.MatchUngated("LF belt")
  Assert.equal(seen.getter(), nil, "/ca test never reuses the last sender's GUID")
  Assert.equal(calls.n, 1, "only the first getter call reached the API")
  ns, seen = capture("era")
  calls = Fixture.stubClasses({ ["Player-1-W"] = "WARRIOR" })
  ns.Matcher.Match("trade", "LF belt", SENDER, "Player-1-W")
  Assert.same({ seen.getter() }, { "plate", "plate (warrior)" }, "a Classic flavor infers too")
  Assert.equal(calls.n, 1, "Classic: one API call")
  ns.Matcher.MatchUngated("LF belt")
  Assert.equal(seen.getter(), nil, "Classic: /ca test never uses a GUID")
  Assert.equal(calls.n, 1, "Classic: no call for the ungated line")
end

return function()
  testRequiredLines()
  testGate()
  testIntentAndAds()
  testItemLinks()
  testRecipeLinkIDs()
  testPhrases()
  testSlotNameGuard()
  testFullNameBeatsAlias()
  testTypoPass()
  testProfessionWords()
  testClassicKeys()
  testResultReuseAndConfigure()
  testOldIndexReleased()
  testLongSpan()
  testShapeTwinElsewhere()
  testClassGetter()
  Wow.reset()
end
