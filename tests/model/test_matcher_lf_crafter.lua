local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- "LF crafter" by customer class (spec 2026-10-28-lf-crafter-by-class): a bare "LF crafter"
-- line alerts for the profession that makes the sender's armor type (plate → Blacksmithing,
-- mail and leather → Leatherworking, cloth → Tailoring), behind the profession-word setting.
-- Every row checks the number of GetPlayerInfoByGUID calls: one only when "LF" and "crafter"
-- are both in the line, nothing earlier matched and the line names no want.
local BS, TAILOR, LW = Fixture.BS, Fixture.TAILOR, Fixture.LW
local expect, outcome, why = Fixture.expect, Fixture.outcome, Fixture.why

local W, M, P, H, U = "Player-1-W", "Player-1-M", "Player-1-P", "Player-1-H", "Player-1-U"
local CLASSES = {
  [W] = "WARRIOR",
  [M] = "MAGE",
  [P] = "PRIEST",
  [H] = "HUNTER",
  [U] = function()
    return "Localized", nil
  end,
}

-- Expects the outcome with the sender's GUID; wantCalls / wantWhy are checked when given.
local function check(ns, label, line, guid, want, wantCalls, wantWhy)
  local calls = Fixture.stubClasses(CLASSES)
  local result = expect(ns, line, want, label .. ": " .. line, guid)
  if wantCalls ~= nil then
    Assert.equal(calls.n, wantCalls, label .. ": lookups")
  end
  if wantWhy ~= nil then
    Assert.equal(why(result), wantWhy, label .. ": why")
  end
  return result
end

-- Enchanting, Blacksmithing, Tailoring and Leatherworking crafters (the §6.2 item 6 fixture).
local function fullIndex(settings)
  local ns = Fixture.load()
  local db = Fixture.db(ns)
  db.characters["Lw-Realm"] = Fixture.character({ LW }, {})
  for key, value in pairs(settings or {}) do
    db.settings[key] = value
  end
  ns.Matcher.SetIndex(Fixture.index(ns, db))
  return ns
end

local function testSpecRows()
  local ns = fullIndex()
  check(ns, "priest", "LF crafter", P, "profession:" .. TAILOR, 1, "lf+crafter+cloth (priest)")
  check(ns, "warrior", "LF crafter", W, "profession:" .. BS, 1, "lf+crafter+plate (warrior)")
  check(ns, "hunter", "LF crafters?", H, "profession:" .. LW, 1, "lf+crafters+mail (hunter)")
  check(ns, "mage, filler", "LF a crafter pls", M, "profession:" .. TAILOR, 1)
  check(ns, "unknown class", "LF crafter", U, "stop:nomatch", 1)
  check(ns, "no GUID", "LF crafter", nil, "stop:nomatch", 0)
  check(ns, "profession word first", "LF BS crafter", P, "profession:" .. BS, 0, "lf+bs")
  check(ns, "not bare", "LF crafter for my neck", M, "stop:nomatch", 0)
  check(ns, "only LF", "need crafter", W, "stop:nomatch", 0)
  check(ns, "no LF", "any crafter?", W, "stop:nomatch", 0)
  check(ns, "break between", "LF, crafter", W, "stop:nomatch", 0)
  check(ns, "everyday word after a break", "LF crafter, back in 5", W, "profession:" .. BS, 1)
  local today = outcome(ns, "LF crafter back")
  Assert.equal(today, "stop:nomatch", "crafter cues back today")
  check(ns, "cued everyday word", "LF crafter back", W, today, 0)
  check(ns, "blocker", "WTS crafting, any crafter", W, "stop:blocker", 0)
  check(ns, "blocker", "WTS crafting, LF crafter", W, "stop:blocker", 0)
end

local function testSettingOff()
  local ns = fullIndex({ professionWordAlerts = false })
  for _, guid in ipairs({ W, M, P, H }) do
    check(ns, "setting off", "LF crafter", guid, "stop:nomatch", 0)
  end
end

-- The two words: "crafter" or "crafters" right after "LF", one filler ("a", "any", "some") at
-- most, nothing but spaces between.
local function testWordShape()
  local ns = fullIndex()
  check(ns, "any", "LF any crafter", W, "profession:" .. BS, 1)
  check(ns, "some", "LF some crafters", W, "profession:" .. BS, 1)
  check(ns, "later in the line", "hi all, LF crafter", W, "profession:" .. BS, 1)
  check(ns, "two fillers", "LF a some crafter", W, "stop:nomatch", 0)
  check(ns, "other word between", "LF my crafter", W, "stop:nomatch", 0)
  check(ns, "crafter first", "crafter LF", W, "stop:nomatch", 0)
  check(ns, "break after the filler", "LF a, crafter", W, "stop:nomatch", 0)
  check(ns, "craft is no crafter", "LF craft", W, "stop:nomatch", 0)
  check(ns, "lfc is no LF", "LFC crafter", W, "stop:nomatch", 0)
end

-- .claude/rules/matcher-adjacent-words.md: an everyday word right after "crafter", with and
-- without punctuation. After a break it names no want; next to the cue word it does, and the
-- line keeps today's result.
local function testEverydayWords()
  local ns = fullIndex()
  local today = { back = "stop:nomatch", ring = "stop:nomatch", hand = "stop:nomatch", head = "item:lionheart helm" }
  for _, word in ipairs({ "back", "ring", "hand", "head" }) do
    local cued = "LF crafter " .. word
    Assert.equal(outcome(ns, cued), today[word], "today: " .. cued)
    check(ns, "cued " .. word, cued, W, today[word])
    check(ns, word .. " after a break", "LF crafter, " .. word .. " me", W, "profession:" .. BS, 1)
  end
  -- A cue or buyer word counts an armor slot word (R3): a want, so today's result, and step 4.4's
  -- lookup is the line's only one (no plate legs indexed).
  check(ns, "cued slot word", "LF legs crafter", W, "stop:nomatch", 1)
  check(ns, "LF legs, then LF crafter", "LF legs, LF crafter", W, "stop:nomatch", 1)
  check(ns, "LF legs, then LF crafter", "LF legs, LF crafter", U, "stop:nomatch", 1)
end

-- Any other want in the line keeps today's result: an item link, a profession word you lack, a
-- step 4.2 hit (also one set aside or dropped), a slang word nobody crafts.
local function testWants()
  local ns = fullIndex()
  check(ns, "item link", "LF crafter |cffffffff|Hitem:12345::::|h[Thing]|h|r", W, "stop:nomatch", 0)
  check(ns, "profession you lack", "LF crafter for engineering", W, "stop:nomatch", 0)
  check(ns, "phrase hit", "LF crafter lionheart helm", W, "item:lionheart helm", 0)
  Assert.equal(outcome(ns, "LF crafter lionheart"), "stop:nomatch", "lionheart is set aside today")
  check(ns, "set-aside hit", "LF crafter lionheart", W, "stop:nomatch", 0)
  check(ns, "dropped hit", "LF crafter lionheart legs", W, "stop:nomatch", 0)
  check(ns, "unindexed slang", "LF crafter for a cloak", W, "stop:nomatch", 0)
end

-- User ruling 2026-10-28: the armor guess is for a bare line only; a named want always beats it.
-- "crafter(s)" then for / to / who / that in the same clause names something, even when Craft
-- Alert cannot read what; a word step 4.4 knows anywhere in the line names a want, even one it
-- did not count (an ambiguous word with no cue next to it), and so does an extraSlang key with
-- no recipe indexed. Everyday words (back, ring, hand, head...) after a break still need a cue
-- (testEverydayWords).
local function testNamedSomething()
  local ns = fullIndex()
  check(ns, "for", "LF crafter for flask", W, "stop:nomatch", 0)
  check(ns, "for my", "LF crafter for my weapon", W, "stop:nomatch", 0)
  check(ns, "to", "LF crafter to make ring", W, "stop:nomatch", 0)
  check(ns, "who", "LF crafter who can make", W, "stop:nomatch", 0)
  check(ns, "that", "LF crafters that can", W, "stop:nomatch", 0)
  check(ns, "pst is no naming word", "LF crafter pst", W, "profession:" .. BS, 1)
  check(ns, "break before for", "LF crafter, for a friend", W, "profession:" .. BS, 1)
  check(ns, "uncounted slot word", "LF crafter pls, legs", W, "stop:nomatch", 0)
  check(ns, "uncounted slot word", "LF crafter, feet", W, "stop:nomatch", 0)
  ns = fullIndex({ extraSlang = { zzneck = "neck" } })
  check(ns, "extraSlang key", "LF crafter zzneck", W, "stop:nomatch", 0)
end

-- A step 4.2 set that step 4.4 cannot decide (saved recipes without a profession) is a want too.
local function testUndecidedSet()
  local ns = Fixture.load()
  local db = Fixture.db(ns)
  db.characters["Odd-Realm"] = Fixture.character({}, {
    [91] = { name = "Zorkian Iron Hauberk" },
    [92] = { name = "Zorkian Iron Leggings" },
  })
  ns.Matcher.SetIndex(Fixture.index(ns, db))
  check(ns, "undecided set", "LF crafter zorkian iron", W, "stop:nomatch", 0)
end

-- No character with the profession → no match (step 4.6 alike); the Settings Test page has no
-- GUID; Classic keys a profession by its English name.
local function testNoCrafterUngatedClassic()
  local ns = Fixture.load()
  ns.Matcher.SetIndex(Fixture.index(ns))
  check(ns, "no leatherworker", "LF crafter", H, "stop:nomatch", 1)
  local calls = Fixture.stubClasses(CLASSES)
  Assert.equal(ns.Matcher.MatchUngated("LF crafter"), nil, "Test page: no GUID, no lead")
  Assert.equal(calls.n, 0, "Test page: no lookup")
  ns = Fixture.load("era")
  local db = ns.Defaults.Db()
  db.characters["Smith-Realm"] = Fixture.character({ "blacksmithing" }, {})
  db.characters["Tai-Realm"] = Fixture.character({ "tailoring" }, {})
  ns.Matcher.SetIndex(ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }))
  check(ns, "classic warrior", "LF crafter", W, "profession:blacksmithing", 1, "lf+crafter+plate (warrior)")
  check(ns, "classic priest", "LF crafter", P, "profession:tailoring", 1)
end

return function()
  testSpecRows()
  testSettingOff()
  testWordShape()
  testEverydayWords()
  testWants()
  testNamedSomething()
  testUndecidedSet()
  testNoCrafterUngatedClassic()
  Wow.reset()
end
