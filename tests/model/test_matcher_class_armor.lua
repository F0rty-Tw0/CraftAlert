local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Class-armor spec §7 rows 1-18 and the plan's Review Focus cases: step 4.4 takes the
-- sender's armor word when a line names an armor slot without an armor type (§4 rules 2-7).
-- Every row checks the outcome against "today" (the same line with no GUID) where the spec
-- says "as today", and the number of GetPlayerInfoByGUID calls.
local BS, TAILOR, LW, ENCH = Fixture.BS, Fixture.TAILOR, Fixture.LW, Fixture.ENCH
local expect, outcome, why = Fixture.expect, Fixture.outcome, Fixture.why

local W, M, P, U = "Player-1-W", "Player-1-M", "Player-1-P", "Player-1-U"
local RAISES, SECRET_CLASS, ADVENTURER = "Player-1-R", "Player-1-S", "Player-1-A"
local CLASSES = {
  [W] = "WARRIOR",
  [M] = "MAGE",
  [P] = "PALADIN",
  [U] = function()
    return "Localized", nil
  end,
  [RAISES] = function()
    error("GetPlayerInfoByGUID raised")
  end,
  [SECRET_CLASS] = function()
    return "Localized", Wow.secret("WARRIOR")
  end,
  [ADVENTURER] = "ADVENTURER",
}

-- { itemID, recipe name, only with opts.greenIron }. No name holds a slot, armor or profession
-- word, or a word of any test line, so step 4.2 matches nothing but row 18's "green iron" set.
local REALMS = {
  {
    key = "Smith-Realm",
    prof = BS,
    recipes = {
      { 501, "Korvath Cinch" },
      { 504, "Korvath Visor" },
      { 502, "Korvath Greaves" },
      { 503, "Korvath Treads" },
      { 505, "Green Iron Girdle", true },
      { 506, "Green Iron Hauberk", true },
    },
  },
  { key = "Lw-Realm", prof = LW, recipes = { { 701, "Hidemaw Strap" }, { 702, "Hidemaw Cowl" }, { 703, "Hidemaw Breeches" } } },
  {
    key = "Tai-Realm",
    prof = TAILOR,
    recipes = {
      { 601, "Silkveil Sash" },
      { 603, "Silkveil Hood" },
      { 604, "Silkveil Trousers" },
      { 606, "Silkveil Drape" },
      { 605, "Green Iron Cord", true },
    },
  },
}

local function setOf(list)
  local set = {}
  for _, value in ipairs(list or {}) do
    set[value] = true
  end
  return set
end

local function recipesOf(realm, opts, dropped)
  local recipes = {}
  for _, recipe in ipairs(realm.recipes) do
    local itemID, name, greenIron = recipe[1], recipe[2], recipe[3]
    if not dropped[itemID] and (not greenIron or opts.greenIron) then
      recipes[itemID] = { item = itemID, name = name, prof = realm.prof }
    end
  end
  return recipes
end

-- Plate, leather and cloth pieces from enabled crafters, profession order BS, LW, Tailoring.
-- opts: only (realm keys kept), disable (realm keys disabled), drop (item IDs left out),
-- extraSlang, greenIron (adds Green Iron Girdle and Green Iron Cord). Set on the Matcher.
local function armorIndex(ns, opts)
  opts = opts or {}
  Fixture.stubItems()
  local db = ns.Defaults.Db()
  local kept, disabled, dropped = setOf(opts.only), setOf(opts.disable), setOf(opts.drop)
  for _, realm in ipairs(REALMS) do
    if opts.only == nil or kept[realm.key] then
      local character = Fixture.character({ realm.prof }, recipesOf(realm, opts, dropped))
      character.enabled = not disabled[realm.key]
      db.characters[realm.key] = character
    end
  end
  db.settings.extraSlang = opts.extraSlang or {}
  local index = ns.Index.Build(db, db.settings, {
    ownKey = "Me-Realm",
    professionOrder = function()
      return { BS, LW, TAILOR }
    end,
  })
  ns.Matcher.SetIndex(index)
  return index
end

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

local function fullIndex(opts)
  local ns = Fixture.load()
  armorIndex(ns, opts)
  return ns
end

-- Today's outcomes on the full index: the guards the "as today" rows lean on.
local function testBaselines()
  local ns = fullIndex()
  Assert.equal(outcome(ns, "LF belt"), "profession:" .. BS, "baseline: three belts, profession order")
  -- §6.4, user ruling 2026-10-21: a crafting cue word partners an ambiguous word.
  Assert.equal(outcome(ns, "LF head crafter"), "profession:" .. BS, "baseline: head counts through the cue word")
  Assert.equal(outcome(ns, "LF bs for legs"), "item:502", "baseline: legs counts through bs, narrowed to Blacksmithing")
  Assert.equal(outcome(ns, "LF belt and head"), "stop:nomatch", "baseline: head counts through belt")
end

local function testRows1To3()
  local ns = fullIndex()
  check(ns, "row 1", "LF belt", W, "item:501", 1, "lf+belt+plate (warrior)")
  check(ns, "row 2", "LF belt", M, "item:601")
  ns = fullIndex({ only = { "Tai-Realm" } })
  check(ns, "row 3", "LF belt", W, "stop:nomatch")
end

local function testRows4To5()
  local ns = fullIndex({ only = { "Smith-Realm", "Tai-Realm" }, drop = { 603, 604, 606 } })
  check(ns, "row 4", "LF bs for legs", M, "profession:" .. BS)
  ns = fullIndex({ extraSlang = { pl8 = "plate" } })
  Assert.equal(outcome(ns, "LF leather belt"), "item:701", "row 5 today")
  Assert.equal(outcome(ns, "LF pl8 belt"), "item:501", "row 5 today")
  check(ns, "row 5", "LF leather belt", W, "item:701", 0)
  check(ns, "row 5", "LF pl8 belt", M, "item:501", 0)
end

local function testRows6To10()
  local ns = fullIndex()
  check(ns, "row 6", "LF head crafter", W, "item:504", nil, "lf+head+plate (warrior)")
  check(ns, "row 6 repeated", "LF head crafter head", W, "item:504", 1, "lf+head+head+plate (warrior)")
  -- The cued word belongs to its own line: the next line does not intersect with it.
  check(ns, "cued word is per line", "LF belt crafter", W, "item:501", 1, "lf+belt+plate (warrior)")
  check(ns, "row 7", "LF bs for legs", P, "item:502", nil, "lf+legs+plate (paladin)")
  check(ns, "row 9", "LF healer, head to Deadmines", P, "stop:nomatch", 0)
  check(ns, "row 10", "need legs", W, "stop:nomatch", 0)
  -- User ruling 2026-10-21: a named profession wins; no enabled crafter of it → no alert.
  ns = fullIndex({ disable = { "Tai-Realm" } })
  check(ns, "row 8", "LF tailor for head", W, "stop:nomatch")
end

local function testRows11To12()
  local ns = fullIndex()
  check(ns, "row 11", "LF head crafter", U, "profession:" .. BS, 1, "lf+head")
  check(ns, "row 12", "LF belt and boots", W, "stop:nomatch", 1)
end

-- Row 13: every unknown-class case leaves "LF belt" as today.
local function testRow13()
  local ns = fullIndex()
  local today = outcome(ns, "LF belt")
  check(ns, "row 13 nil GUID", "LF belt", nil, today, 0)
  check(ns, "row 13 secret GUID", "LF belt", Wow.secret(W), today, 0)
  check(ns, "row 13 number GUID", "LF belt", 42, today, 0)
  check(ns, "row 13 API raises", "LF belt", RAISES, today, 1)
  check(ns, "row 13 class nil", "LF belt", U, today, 1)
  check(ns, "row 13 secret class", "LF belt", SECRET_CLASS, today, 1)
  check(ns, "row 13 unknown class", "LF belt", ADVENTURER, today, 1)
  Wow.stub("GetPlayerInfoByGUID", nil)
  expect(ns, "LF belt", today, "row 13 no API", W)
end

local function testRows14To15()
  local ns = fullIndex()
  Assert.equal(outcome(ns, "LF ring"), "stop:nomatch", "row 14 today")
  Assert.equal(outcome(ns, "LF cloak"), "item:606", "row 14 today")
  check(ns, "row 14", "LF ring", W, "stop:nomatch", 0)
  check(ns, "row 14 cued", "LF ring crafter", W, "stop:nomatch", 0)
  check(ns, "row 14", "LF cloak", W, "item:606", 0)
  local today = outcome(ns, "LF belt")
  local calls = Fixture.stubClasses(CLASSES)
  expect(ns, "LF belt", "item:501", "row 15: the real line", W)
  local result = ns.Matcher.MatchUngated("LF belt")
  Assert.equal(result and result.kind .. ":" .. tostring(result.prof), today, "row 15: /ca test as today")
  Assert.equal(calls.n, 1, "row 15: no lookup for the ungated line")
end

local function testRows16To18()
  local ns = Fixture.load("era")
  armorIndex(ns)
  check(ns, "row 16", "LF belt", W, "item:501", 1, "lf+belt+plate (warrior)")
  ns = Fixture.load("forever")
  armorIndex(ns)
  check(ns, "row 17", "LF belt", W, "item:501")
  ns = fullIndex({ greenIron = true })
  check(ns, "row 18", "LF green iron belt", W, "item:505", nil, "lf+green iron+belt+plate (warrior)")
end

-- User ruling 2026-10-20 (trade corpus #25): when the inferred word would empty a step 4.2
-- set, it is ignored and the line keeps today's item match and why line.
local function testSetKeptOverClass()
  local ns = fullIndex({ greenIron = true })
  local line = "LF BS with green iron chest"
  local today, todayResult = outcome(ns, line)
  Assert.equal(today, "item:506", "set ruling today")
  local todayWhy = why(todayResult)
  check(ns, "set ruling", line, W, "item:506", 1, todayWhy)
  Assert.falsy(string.find(todayWhy, "warrior", 1, true), "set ruling: no class in the why line")
  ns = fullIndex({ greenIron = true, only = { "Smith-Realm" } })
  check(ns, "set ruling, no cloth indexed", line, M, "item:506", 1, todayWhy)
end

-- User ruling 2026-10-20 (supersedes Review Focus 1): a line with an Enchanting word infers
-- no armor word and looks up no class, since an enchant does not depend on the asker's armor,
-- unless Enchanting has no candidate and a profession named after it falls through (user
-- ruling 2026-10-22).
local function testEnchantingLines()
  local ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Ench-Realm"] = Fixture.character({ ENCH }, { [8] = { item = 601, name = "Runed Sash", prof = ENCH } })
    db.characters["Tai-Realm"] = Fixture.character({ TAILOR }, { [5] = { item = 602, name = "Silk Sash", prof = TAILOR } })
  end)
  local today, todayResult = outcome(ns, "LF enchanter belt")
  Assert.equal(today, "item:601", "enchanting today")
  local todayWhy = why(todayResult)
  check(ns, "enchanting", "LF enchanter belt", W, "item:601", 0, todayWhy)
  ns = Fixture.load()
  ns.Matcher.SetIndex(Fixture.index(ns))
  Assert.equal(outcome(ns, "LF enchant chest"), "profession:" .. ENCH, "enchanting today")
  check(ns, "enchanting", "LF enchant chest", W, "profession:" .. ENCH, 0)
  -- User ruling 2026-10-22: an Enchanting word with no candidate falls through to the next
  -- named profession, and that one takes the sender's armor word (a plate and a leather belt).
  ns = Fixture.load()
  Fixture.itemIndex(ns, function(db)
    db.characters["Smith-Realm"].recipes[3] = { item = 701, name = "Hide Strap", prof = BS }
  end)
  check(ns, "enchanting", "LF bs belt", W, "item:501", 1)
  check(ns, "enchanting", "LF ench or bs belt", W, "item:501", 1)
  check(ns, "enchanting", "LF bs or ench belt", W, "item:501", 1)
  -- The same on a step 4.2 set ("green iron"): Enchanting is tried on the set first, without
  -- the armor word and the class lookup; the professions named after it get the armor word.
  local function greenIron(enchanting)
    ns = Fixture.load()
    Fixture.itemIndex(ns, function(db)
      db.characters["Smith-Realm"].recipes[3] = { item = 505, name = "Green Iron Girdle", prof = BS }
      db.characters["Tai-Realm"] = Fixture.character({ TAILOR }, { [5] = { item = 605, name = "Green Iron Cord", prof = TAILOR } })
      db.characters["Ench-Realm"] = Fixture.character({ ENCH }, { [44] = enchanting })
    end)
  end
  greenIron({ name = "Green Iron Sigil", prof = ENCH })
  check(ns, "enchanting set", "LF ench or bs green iron belt", W, "item:505", 1)
  check(ns, "enchanting set", "LF ench or tailor green iron belt", W, "item:605", 1)
  check(ns, "enchanting set", "LF ench green iron belt", W, "profession:" .. ENCH, 0)
  greenIron({ item = 602, name = "Green Iron Sash", prof = ENCH })
  check(ns, "enchanting set", "LF ench or bs green iron belt", W, "item:602", 0)
end

-- Review Focus 2: inference never removes a word that counts today (§4 rule 5).
local function testPartneredWordsStay()
  local ns = fullIndex()
  check(ns, "RF2", "LF belt and head", W, "stop:nomatch", 1)
  ns = fullIndex({ greenIron = true })
  check(ns, "RF2", "LF green iron head", W, outcome(ns, "LF green iron head"), 0)
end

-- Review Focus 3 and 5: seven buffer slots leave nothing stale; extra slang onto a slot word.
local function testSevenWordsAndExtraSlang()
  local ns = fullIndex()
  check(ns, "RF3", "LF belt waist helm helmet pants legs crafter", W, "stop:nomatch", 1)
  check(ns, "RF3", "LF belt", M, "item:601", 1, "lf+belt+cloth (mage)")
  ns = fullIndex({ extraSlang = { britches = "legs" } })
  check(ns, "RF5", "LF britches", W, "item:502", 1)
end

return function()
  testBaselines()
  testRows1To3()
  testRows4To5()
  testRows6To10()
  testRows11To12()
  testRow13()
  testRows14To15()
  testRows16To18()
  testSetKeptOverClass()
  testEnchantingLines()
  testPartneredWordsStay()
  testSevenWordsAndExtraSlang()
  Wow.reset()
end
