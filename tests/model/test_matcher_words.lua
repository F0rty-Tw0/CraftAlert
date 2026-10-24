local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- §6.3 step 4.4 (wordIndex words) and the §6.4 ambiguous words, through Matcher.Match.
local ENCH, BS, TAILOR, LW = Fixture.ENCH, Fixture.BS, Fixture.TAILOR, Fixture.LW
local JC = 755
local character, expect, why = Fixture.character, Fixture.expect, Fixture.why
local Assert = require("tests.helpers.assert")

-- §6.3 4.4 and §13 Matcher extras.
local function testWordIndex()
  local ns = Fixture.load()
  Fixture.itemIndex(ns)
  local result = assert(expect(ns, "LF plate belt crafter", "item:501"))
  Assert.equal(why(result), "lf+plate+belt")
  Assert.equal(result.entryCount, 2, "a recipe known by two characters counts once")
  expect(ns, "LF leather belt", "stop:nomatch", "a slang word with no entries empties the intersection")
  expect(ns, "need legs", "stop:nomatch", "an ambiguous word alone")
  expect(ns, "LF plate legs", "item:502")
  expect(ns, "LF plate", "profession:" .. BS, "two plate recipes, one profession")
  expect(ns, "LF BS", "profession:" .. BS)
  expect(ns, "LF jc", "profession:" .. JC)
end

-- §6.3 4.4: several professions -> most candidates, ties by ProfessionList order.
local function testProfessionTieBreak()
  local ns = Fixture.load()
  local function oneEach(db)
    db.characters["Tai-Realm"] = character({ TAILOR }, { [5] = { item = 601, name = "Silk Sash", prof = TAILOR } })
    db.characters["Lw-Realm"] = character({ LW }, { [6] = { item = 701, name = "Hide Strap", prof = LW } })
  end
  -- belt: Thick Plate Belt (BS, two crafters), Silk Sash (Tailoring), Hide Strap (LW): one
  -- recipe each, so ProfessionList order decides.
  Fixture.itemIndex(ns, oneEach)
  expect(ns, "LF belt", "profession:" .. TAILOR)
  Fixture.itemIndex(ns, oneEach, { LW, BS, TAILOR })
  expect(ns, "LF belt", "profession:" .. LW)
  -- Candidates count per distinct recipe: 3 BS entries are 1 recipe, Tailoring has 2.
  Fixture.itemIndex(ns, function(db)
    local recipes = { [5] = { item = 601, name = "Silk Sash", prof = TAILOR }, [7] = { item = 602, name = "Wool Sash", prof = TAILOR } }
    db.characters["Tai-Realm"] = character({ TAILOR }, recipes)
    db.characters["Smith-Realm"].recipes[3] = { item = 501, name = "Thick Plate Belt", prof = BS }
  end, { BS, TAILOR })
  expect(ns, "LF belt", "profession:" .. TAILOR, "two tailoring recipes beat one plate belt")
end

-- §6.3 4.4: only the first 6 distinct slang words of a line, in line order, take part.
local function testSixWordCap()
  local ns = Fixture.load()
  -- Plate boots answer to boots boot feet shoes plate, plus two extra slang words.
  Fixture.itemIndex(ns, function(db)
    db.settings.extraSlang = { footies = "boots", stompers = "boots" }
    db.characters["Smith-Realm"].recipes[3] = { item = 503, name = "Iron Treads", prof = BS }
  end)
  expect(ns, "lf boots boot feet shoes plate footies leather", "item:503", "the 7th distinct word is not used")
  expect(ns, "lf boots boot feet shoes plate leather footies", "stop:nomatch", "the 6th still empties")
  expect(ns, "lf boots boots boot feet shoes plate footies leather", "item:503", "a repeat is not a new word")
  local result = expect(ns, "lf boots boot feet shoes plate footies stompers", "item:503")
  Assert.equal(why(result), "lf+boots+boot+feet+shoes+plate+footies")
end

-- §6.3 4.4: a line with an Enchanting profession word narrows the candidates to Enchanting
-- entries first, so "lf enchant chest" never reaches a blacksmith's chest piece.
local function testEnchantingNarrowing()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Ench-Realm"] = character({ ENCH }, { [8] = { item = 601, name = "Runed Sash", prof = ENCH } })
    db.characters["Tai-Realm"] = character({ TAILOR }, { [5] = { item = 602, name = "Silk Sash", prof = TAILOR } })
  end)
  expect(ns, "LF belt", "profession:" .. TAILOR, "three professions without an Enchanting word")
  expect(ns, "LF enchanter belt", "item:601", "one word, narrowed")
  expect(ns, "LF ench cloth belt", "item:601", "several words, narrowed")
  expect(ns, "LF enchants plate", "profession:" .. ENCH, "nothing left: step 4.6")
  ns = Fixture.load()
  ns.Matcher.SetIndex(Fixture.index(ns))
  local result = expect(ns, "lf enchant chest", "profession:" .. ENCH, "no Green Iron Hauberk")
  Assert.equal(why(result), "lf+enchant")
  expect(ns, "lf enchant green iron", "profession:" .. ENCH, "a 4.2 set is narrowed too")
  expect(ns, "LF Enchanter +8stam to chest", "item:enchant chest - greater stamina", "step 4.3 first")
end

-- §6.4: "back" names the cloak slot (user ruling 2026-10-20) but is ambiguous (user ruling
-- 2026-10-21): it counts beside another slot/type word or a crafting cue word (a profession
-- word too), never alone or in everyday speech; a line without an intent word still stops at
-- the prefilter.
local function testBackIsCloak()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Tai-Realm"] = character({ TAILOR }, { [9] = { item = 606, name = "Silk Cloak", prof = TAILOR } })
  end)
  expect(ns, "LF back crafter", "item:606", "a cue word partners an ambiguous word")
  expect(ns, "LF cloth back", "item:606")
  expect(ns, "LF tailor back", "item:606", "a profession word is a cue word")
  expect(ns, "LF back", "stop:nomatch", "an ambiguous word alone")
  expect(ns, "LF tank for M+ will be back in 5", "stop:nomatch")
  expect(ns, "LF guild looking to get back into raiding", "stop:nomatch")
  expect(ns, "WTB carry, pay you back", "stop:nomatch")
  expect(ns, "LF someone to get my back", "stop:nomatch")
  expect(ns, "brb, back in 5", "stop:prefilter", "no intent word")
end

-- Cloth, leather and ring pieces beside the smiths' plate belt and plate legs: every
-- ambiguous slot word below has a recipe of its own, so a word that counts alerts an item.
-- withNeck: the jewelcrafter also knows a necklace. extra(db): more settings or recipes.
local function slotIndex(ns, withNeck, extra)
  Fixture.itemIndex(ns, function(db)
    db.characters["Tai-Realm"] = character({ TAILOR }, {
      [9] = { item = 606, name = "Silk Cloak", prof = TAILOR },
      [10] = { item = 603, name = "Silk Hood", prof = TAILOR },
      [11] = { item = 604, name = "Silk Pants", prof = TAILOR },
    })
    db.characters["Lw-Realm"] = character({ LW }, {
      [12] = { item = 702, name = "Hide Cap", prof = LW },
      [13] = { item = 802, name = "Hide Gloves", prof = LW },
      [14] = { item = 703, name = "Hide Pants", prof = LW },
    })
    local jc = { [15] = { item = 801, name = "Gem Band", prof = JC } }
    if withNeck then
      jc[16] = { item = 811, name = "Gem Choker", prof = JC }
    end
    db.characters["Jc-Realm"] = character({ JC }, jc)
    if extra then
      extra(db)
    end
  end)
end

-- User ruling 2026-10-24: the R1 nouns (leggings, grips, hood, ...) are slot words of their slot.
-- An ambiguous one (hand, band, hood, vest) needs a partner, like legs.
local function testR1SlotWords()
  local ns = Fixture.load()
  ns.Matcher.SetIndex(Fixture.index(ns))
  expect(ns, "lf green iron mail leggings", "item:green iron leggings", "the noun narrows like legs")
  ns = Fixture.load()
  slotIndex(ns)
  expect(ns, "LF grips crafter", "item:802")
  expect(ns, "LF hood", "stop:nomatch", "an ambiguous R1 word, no partner, no class")
end

-- User ruling 2026-10-24 (R2): an extraSlang key whose target is a slot word is a slot word of that
-- slot in the different-slots union; a key never ambiguous (today's behavior); a type key is none.
local function testExtraSlangSlotWords()
  local ns = Fixture.load()
  slotIndex(ns, false, function(db)
    db.settings.extraSlang = { footies = "boots", pl8 = "plate" }
    db.characters["Smith-Realm"].recipes[3] = { item = 503, name = "Korvath Treads", prof = BS }
  end)
  local function same(line, with)
    Assert.equal(Fixture.outcome(ns, line), Fixture.outcome(ns, with), line)
  end
  same("LF footies and ring", "LF boots and ring")
  same("LF footies", "LF boots")
  same("LF pl8 belt and ring", "LF plate belt and ring")
end

-- User ruling 2026-10-24: "hand" after off, main, one or two is no slot word anywhere: no count,
-- no partner for another ambiguous word; a plain "hand" is the glove slot.
local function testOffHandIsNoSlotWord()
  local ns = Fixture.load()
  slotIndex(ns, true)
  expect(ns, "LF off hand crafter", "stop:nomatch", "hand after off: no slot word, no cue partner")
  expect(ns, "LF off-hand crafter", "stop:nomatch", "a hyphen splits tokens")
  expect(ns, "LF main hand crafter", "stop:nomatch")
  expect(ns, "LF two hand crafter", "stop:nomatch")
  Assert.truthy(ns.Slang.IsOffHand({ "one", "hand" }, 2))
  Assert.falsy(ns.Slang.IsOffHand({ "hand" }, 1), "no token before")
  Assert.falsy(ns.Slang.IsOffHand({ "off", "hands" }, 2), "only singular hand")
  expect(ns, "LF hand crafter", "item:802", "a plain hand is gloves")
  Assert.equal(Fixture.outcome(ns, "LF hand crafter"), Fixture.outcome(ns, "LF gloves crafter"))
  -- firstWords skips an off-hand hand, so it never partners another ambiguous word.
  Assert.equal(Fixture.outcome(ns, "LF off hand legs"), Fixture.outcome(ns, "LF legs"), "off hand does not count legs")
end

-- User ruling 2026-10-24 ("either slot counts"): a line whose counted words are all slot
-- words of different slots matches the recipes of any of them; a type word in the line, or
-- words of one slot only, keep the intersection. An ambiguous slot word joins the union only
-- with a cue word next to it.
local function testEitherSlotCounts()
  local ns = Fixture.load()
  slotIndex(ns, true)
  local result = assert(expect(ns, "LF neck and ring crafter", "profession:" .. JC, "ring has a cue word"))
  Assert.equal(why(result), "lf+neck+ring")
  Assert.equal(result.entryCount, 2, "the necklace and the ring")
  result = assert(expect(ns, "LF craft neck ring on public rn", "item:811", "the trade line: ring has no cue word"))
  Assert.equal(why(result), "lf+neck")
  expect(ns, "LF neck ring", "item:811", "ring has no cue word")
  expect(ns, "LF neck ring, need a ring crafter", "profession:" .. JC, "a cue next to a repeat")
  expect(ns, "LF jc neck ring", "item:811", "narrowed, then the union")
  expect(ns, "LF lw neck ring", "profession:" .. LW, "nothing narrowed: step 4.6")
  expect(ns, "LF neck", "item:811", "one slot")
  expect(ns, "LF craft ring", "item:801", "one slot")
  expect(ns, "LF ring finger", "item:801", "two words of one slot")
  expect(ns, "LF cloth hands", "stop:nomatch", "a type word keeps the intersection")
  expect(ns, "LF lw cloth legs", "profession:" .. LW, "a type word keeps the intersection")
end

-- User ruling 2026-10-24: an ambiguous word in everyday speech counts beside a slot word
-- (§6.4) but never widens the union of different slots.
local function testUnionSkipsUncuedWords()
  local ns = Fixture.load()
  slotIndex(ns)
  expect(ns, "LF ring, be back in 5", "stop:nomatch", "no Silk Cloak")
  expect(ns, "WTB ring, will pay you back", "stop:nomatch", "no Silk Cloak")
  local result = assert(expect(ns, "LF ring crafter, my hands are full", "item:801", "no Hide Gloves"))
  Assert.equal(why(result), "lf+ring")
  expect(ns, "LF belt, back in 5", "item:501", "the belt alone")
  -- One belt, one cloak: ProfessionList order puts Tailoring first.
  expect(ns, "LF belt, back crafter", "profession:" .. TAILOR, "back joins through its cue word")
end

-- User ruling 2026-10-24: the union skips a slot word nobody crafts; the intersection of one
-- slot's words does not.
local function testUnionSkipsEmptySlots()
  local ns = Fixture.load()
  slotIndex(ns)
  local result = assert(expect(ns, "LF craft ring and boots", "item:801", "no boots recipe"))
  Assert.equal(why(result), "lf+ring")
  expect(ns, "LF craft boots and shield", "stop:nomatch", "nobody crafts either")
  expect(ns, "LF craft boots and plate", "stop:nomatch", "a type word: the intersection empties")
  expect(ns, "LF craft boots and shoes", "stop:nomatch", "one slot: the intersection empties")
  -- A warrior's plate joins boots, a type word: the intersection again, empty without boots.
  local warrior = "Player-1-W"
  Fixture.stubClasses({ [warrior] = "WARRIOR" })
  expect(ns, "LF craft ring and boots", "stop:nomatch", "the sender's plate keeps the intersection", warrior)
end

-- Words of one slot ("1h offhand": an off-hand weapon is both) keep the intersection.
local function testOneSlotWordsIntersect()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 910, name = "Iron Sword", prof = BS }
    db.characters["Smith-Realm"].recipes[4] = { item = 912, name = "Iron Dirk", prof = BS }
    db.characters["Smith-Realm"].recipes[5] = { item = 913, name = "Iron Lantern", prof = BS }
  end)
  expect(ns, "LF 1h offhand", "item:912", "only the off-hand dagger has both")
end

-- The union picks its profession from each word's recipe count, which counts a recipe twice
-- when two of the words hold it, or when two professions craft it; those lines count the
-- recipes of the whole union, as the intersection's tie-break does.
local function testUnionCountsRecipesOnce()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 910, name = "Iron Sword", prof = BS }
    db.characters["Smith-Realm"].recipes[4] = { item = 912, name = "Iron Dirk", prof = BS }
    db.characters["Tai-Realm"] = character({ TAILOR }, { [5] = { item = 913, name = "Silk Lantern", prof = TAILOR } })
    local necks = { [6] = { item = 811, name = "Gem Choker", prof = JC }, [7] = { item = 814, name = "Gem Torc", prof = JC } }
    db.characters["Jc-Realm"] = character({ JC }, necks)
  end, { JC, BS, TAILOR })
  -- Sword and dirk (1h), dirk and lantern (offhand): 2 smith recipes, not 3, tie the 2 necks.
  expect(ns, "LF 1h offhand neck", "profession:" .. JC, "the dirk counts once")
  -- offhand shares only the dirk with 1h, so its lanterns stay in the union: 2 tie the 2
  -- smith recipes and win on order.
  ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 910, name = "Iron Sword", prof = BS }
    db.characters["Smith-Realm"].recipes[4] = { item = 912, name = "Iron Dirk", prof = BS }
    db.characters["Tai-Realm"] = character({ TAILOR }, {
      [5] = { item = 913, name = "Silk Lantern", prof = TAILOR },
      [8] = { item = 915, name = "Wool Lantern", prof = TAILOR },
    })
    db.characters["Jc-Realm"] = character({ JC }, { [6] = { item = 811, name = "Gem Choker", prof = JC } })
  end, { TAILOR, BS, JC })
  expect(ns, "LF 1h offhand neck", "profession:" .. TAILOR, "offhand is not covered by 1h")
  ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Aa-Realm"] = character({ JC }, { [6] = { item = 811, name = "Gem Choker", prof = JC } })
    db.characters["Zz-Realm"] = character({ BS }, { [7] = { item = 811, name = "Gem Choker", prof = BS } })
    db.characters["Tai-Realm"] = character({ TAILOR }, {
      [5] = { item = 601, name = "Silk Sash", prof = TAILOR },
      [8] = { item = 605, name = "Wool Sash", prof = TAILOR },
    })
  end, { BS, TAILOR, JC })
  -- The choker counts for its first crafter's profession only: Tailoring's 2 sashes beat 1
  -- plate belt, where 2 for the smiths (belt and choker) would tie and win on order.
  expect(ns, "LF neck and belt", "profession:" .. TAILOR, "the choker counts once")
end

-- A tie between professions outside ProfessionList order goes to the first candidate's, in
-- the union as for one word.
local function testUnionTieFollowsCandidates()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Lw-Realm"] = character({ LW }, { [6] = { item = 811, name = "Gem Choker", prof = LW } })
    db.characters["Tai-Realm"] = character({ TAILOR }, { [7] = { item = 814, name = "Gem Torc", prof = TAILOR } })
    db.characters["Jc-Realm"] = character({ JC }, { [8] = { item = 815, name = "Gem Chain", prof = JC } })
  end, {})
  local alone = Fixture.outcome(ns, "LF neck")
  expect(ns, "LF neck and belt", alone, "the first neck's profession")
  expect(ns, "LF belt and neck", "profession:" .. BS, "the belt first")
end

-- §6.3 4.4: any profession word narrows the candidates to that profession, as an Enchanting
-- word does (user ruling 2026-10-21); with several, the first that still has a candidate,
-- Enchanting before the others in line order (user ruling 2026-10-22); nothing left falls
-- through to step 4.6.
local function testNamedProfessionNarrowing()
  local ns = Fixture.load()
  slotIndex(ns)
  expect(ns, "LF legs crafter", "profession:" .. TAILOR, "three legs without a profession word")
  expect(ns, "LF bs legs", "item:502", "one word, narrowed")
  expect(ns, "LF bs pants", "item:502")
  expect(ns, "LF lw head", "item:702")
  expect(ns, "LF cloth legs", "item:604")
  expect(ns, "LF lw cloth legs", "profession:" .. LW, "several words, nothing left: step 4.6")
  expect(ns, "LF blacksmith, back in 10 min", "profession:" .. BS, "never a Tailoring cloak")
  expect(ns, "LF lw bs legs", "item:703", "two professions, both with a candidate: the first named")
  expect(ns, "LF tailor or bs for plate legs", "item:502", "Tailoring has no plate legs: the next named")
  expect(ns, "LF jc and bs plate legs", "item:502", "Jewelcrafting has no plate legs: the next named")
  expect(ns, "LF bs enchanter belt", "item:501", "Enchanting first, but it has no belt: Blacksmithing")
  expect(ns, "LF lw jc plate legs", "profession:" .. LW, "no named profession has one: step 4.6")
end

-- §6.4, user ruling 2026-10-21: a crafting cue word partners an ambiguous word only as the
-- token right before or after it (filler words between are skipped, punctuation is not).
local function testCueAdjacency()
  local ns = Fixture.load()
  slotIndex(ns)
  expect(ns, "LF back crafter", "item:606")
  expect(ns, "LF tailor back", "item:606")
  expect(ns, "LF bs for legs", "item:502")
  expect(ns, "LF ring crafter", "item:801")
  expect(ns, "LF crafter hands", "item:802")
  expect(ns, "LF legs crafter", "profession:" .. TAILOR)
  expect(ns, "LF crafter for my legs", "profession:" .. TAILOR, "filler words between")
  expect(ns, "LF crafter to make my legs", "stop:nomatch", "a non-filler word between")
  expect(ns, "LF crafter, be back in 5", "stop:nomatch")
  expect(ns, "LF engineer, got your back", "stop:nomatch")
  expect(ns, "LF alchemist for flasks, back soon", "stop:nomatch")
  expect(ns, "LF scribe, ring me when ready", "stop:nomatch")
  expect(ns, "LF crafter, hands down best tip", "stop:nomatch", "punctuation ends the neighbourhood")
  expect(ns, "LF legs, crafter for legs", "profession:" .. TAILOR, "an uncued word counts where it is cued")
  -- Corpus misses (2026-10-23): recraft cue words, singular "leg".
  expect(ns, "lf recraft ring", "item:801")
  expect(ns, "LF recrafter hands", "item:802")
  expect(ns, "lf recrafting for my legs", "profession:" .. TAILOR)
  expect(ns, "will recraft legs for tips", "stop:nomatch", "the intent word is never its own cue")
  expect(ns, "recraft ring", "stop:nomatch")
  expect(ns, "lf CRAFTER LEG", "profession:" .. TAILOR, "leg is legs")
  expect(ns, "LF bs leg", "item:502")
  expect(ns, "LF tank, break a leg", "stop:nomatch", "leg is ambiguous like legs")
  local result = expect(ns, "LF tailor, will pay you back", "profession:" .. TAILOR)
  Assert.equal(why(result), "lf+tailor", "the profession word alone")
  result = expect(ns, "LF bs crafter, back from afk", "profession:" .. BS)
  Assert.equal(why(result), "lf+bs", "the profession word alone")
end

-- User ruling 2026-10-24: "trinket" is no slot word (old alchemist stones outvoted PvP
-- trinkets); a trinket matches by its name only.
local function testTrinketByNameOnly()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Tai-Realm"] = character({ TAILOR }, { [9] = { item = 950, name = "Silk Charm", prof = TAILOR } })
  end)
  expect(ns, "LF trinket crafter", "stop:nomatch")
  expect(ns, "LF tailor trinket", "profession:" .. TAILOR, "the profession word alone")
  expect(ns, "LF silk charm", "item:950")
end

return function()
  testWordIndex()
  testBackIsCloak()
  testTrinketByNameOnly()
  testNamedProfessionNarrowing()
  testCueAdjacency()
  testR1SlotWords()
  testExtraSlangSlotWords()
  testOffHandIsNoSlotWord()
  testEitherSlotCounts()
  testUnionSkipsUncuedWords()
  testUnionSkipsEmptySlots()
  testOneSlotWordsIntersect()
  testUnionCountsRecipesOnce()
  testUnionTieFollowsCandidates()
  testProfessionTieBreak()
  testSixWordCap()
  testEnchantingNarrowing()
  Wow.reset()
end
