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

return function()
  testWordIndex()
  testBackIsCloak()
  testProfessionTieBreak()
  testSixWordCap()
  testEnchantingNarrowing()
  Wow.reset()
end
