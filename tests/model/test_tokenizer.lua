local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")

local Constants = Fresh.require("Core.Constants")

local function load()
  local Tokenizer = Fresh.require("Model.Tokenizer")
  Tokenizer.Configure(Constants.intentWords)
  return Tokenizer
end

local function tokensOf(Tokenizer, count)
  return { unpack(Tokenizer.tokens, 1, count) }
end

-- §4.4 rule 2: one lowercase, then a plain-substring reject before any tokenizing.
local function testScan()
  local Tokenizer = load()
  Assert.equal(Tokenizer.Scan("LF [Enchant Bracer - Minor Health]"), "lf [enchant bracer - minor health]")
  Assert.equal(Tokenizer.Scan("WTS cheap stuff"), nil)
  -- Plain find: a pattern character in an intent word is literal.
  Tokenizer.Configure({ "+5" })
  Assert.equal(Tokenizer.Scan("need +5 stam"), "need +5 stam")
  Assert.equal(Tokenizer.Scan("need 55 stam"), nil)
  -- The list is replaced, not merged, and lowercased once at configure time.
  Tokenizer.Configure({ "WTS" })
  Assert.equal(Tokenizer.Scan("WTS cheap stuff"), "wts cheap stuff")
  Assert.equal(Tokenizer.Scan("LF belt"), nil)
  -- An empty word would pass every line; no words passes none.
  Tokenizer.Configure({ "" })
  Assert.equal(Tokenizer.Scan("LF belt"), nil)
  Tokenizer.Configure({})
  Assert.equal(Tokenizer.Scan("LF belt"), nil)
end

local function testTypedBrackets()
  local Tokenizer = load()
  local count = Tokenizer.Tokenize(Tokenizer.Scan("LF [Enchant Bracer - Minor Health]"))
  Assert.equal(count, 5)
  Assert.same(tokensOf(Tokenizer, count), { "lf", "enchant", "bracer", "minor", "health" })
  Assert.equal(Tokenizer.normalized, "lf enchant bracer minor health")
  Assert.equal(Tokenizer.itemCount, 0)
  Assert.equal(Tokenizer.linkNameCount, 0)
end

-- Review Focus 1: several links, `|cnIQ` and `|cff` colors, bonus IDs, a Retail quality atlas
-- inside the name, and a battle-pet link. Item links give IDs and normalized names in order;
-- link text and link data never become tokens; other link types leave nothing behind.
local function testLinkShapes()
  local Tokenizer = load()
  local line = "WTB |cnIQ4:|Hitem:19019:0:0:0:0:0:0:0:60:::::2:1234:5678|h[Thunderfury, Blessed Blade]|h|r"
    .. " and |cff1eff00|Hitem:2575::::::::60:::::|h[Red Linen Shirt |A:Professions-ChatIcon-Quality-Tier3:17:17::1|a]|h|r"
    .. " or |cff0070dd|Hbattlepet:1387:25:3:1000:300:300:0x0000000000000000|h[Lil' Ragnaros]|h|r"
    .. " or |cff71d5ff|Hspell:7418|h[Enchant Bracer - Minor Health]|h|r pst"
  local count = Tokenizer.Tokenize(Tokenizer.Scan(line))
  Assert.same(tokensOf(Tokenizer, count), { "wtb", "and", "or", "or", "pst" })
  Assert.equal(Tokenizer.normalized, "wtb and or or pst")
  Assert.equal(Tokenizer.itemCount, 2)
  Assert.same({ unpack(Tokenizer.itemIDs, 1, Tokenizer.itemCount) }, { 19019, 2575 })
  Assert.equal(Tokenizer.linkNameCount, 2)
  Assert.same({ unpack(Tokenizer.linkNames, 1, Tokenizer.linkNameCount) }, { "thunderfury blessed blade", "red linen shirt" })
end

-- A link with no color code, and a crafted world drop typed next to a link: the typed name stays text.
local function testBareLinkAndText()
  local Tokenizer = load()
  local count = Tokenizer.Tokenize(string.lower("LF LWer |Hitem:18948|h[Barbaric Bracers]|h pattern, also Iron Shield Spike"))
  Assert.same(tokensOf(Tokenizer, count), { "lf", "lwer", "pattern", "also", "iron", "shield", "spike" })
  Assert.same({ unpack(Tokenizer.itemIDs, 1, Tokenizer.itemCount) }, { 18948 })
  Assert.same({ unpack(Tokenizer.linkNames, 1, Tokenizer.linkNameCount) }, { "barbaric bracers" })
end

-- Bytes >= 128 and apostrophes are word characters, so UTF-8 words and realm names stay whole.
local function testNonAscii()
  local Tokenizer = load()
  local count = Tokenizer.Tokenize(string.lower("LF Verzauberer für Brust, ask Zoë-Kel'Thuzad"))
  Assert.same(tokensOf(Tokenizer, count), { "lf", "verzauberer", "für", "brust", "ask", "zoë", "kel'thuzad" })
  Assert.equal(Tokenizer.normalized, "lf verzauberer für brust ask zoë kel'thuzad")
end

-- Escapes that are not links: textures, raw pipes, newlines; digits stay in words.
local function testOtherEscapes()
  local Tokenizer = load()
  local count = Tokenizer.Tokenize(string.lower("LF |TInterface\\Icons\\INV_Misc_Bell_01:0|t +8stam to chest || 1h|nsword"))
  Assert.same(tokensOf(Tokenizer, count), { "lf", "8stam", "to", "chest", "1h", "sword" })
  Assert.equal(Tokenizer.Tokenize("!!! ..."), 0)
  Assert.equal(Tokenizer.normalized, "")
end

-- No table per line: the same buffers every call, and a shorter line clears the old tail.
local function testBuffersReused()
  local Tokenizer = load()
  local tokens, itemIDs, linkNames = Tokenizer.tokens, Tokenizer.itemIDs, Tokenizer.linkNames
  Tokenizer.Tokenize("lf |hitem:1|h[a b]|h |hitem:2|h[c]|h one two three")
  Assert.equal(Tokenizer.Tokenize("lf belt"), 2)
  Assert.truthy(rawequal(Tokenizer.tokens, tokens))
  Assert.truthy(rawequal(Tokenizer.itemIDs, itemIDs))
  Assert.truthy(rawequal(Tokenizer.linkNames, linkNames))
  Assert.equal(tokens[3], nil)
  Assert.equal(Tokenizer.itemCount, 0)
  Assert.equal(itemIDs[1], nil)
  Assert.equal(Tokenizer.linkNameCount, 0)
  Assert.equal(linkNames[1], nil)
  Assert.equal(Tokenizer.normalized, "lf belt")
end

-- Real Forever request shapes (docs/knowledge/trade-requests-forever.md).
local function testRealLines()
  local Tokenizer = load()
  local cases = {
    { "Any Blacksmith 150+?", "any blacksmith 150" },
    { "LF BS w/ Green Iron Hauberk recipe PST", "lf bs w green iron hauberk recipe pst" },
    { "LF Engineer for 9-60 Battery Pack", "lf engineer for 9 60 battery pack" },
    { "225 Enchant have ALL WEAPON and NECK LFW!!! DM if need!!!", "225 enchant have all weapon and neck lfw dm if need" },
  }
  for _, case in ipairs(cases) do
    Tokenizer.Tokenize(string.lower(case[1]))
    Assert.equal(Tokenizer.normalized, case[2])
  end
end

return function()
  testScan()
  testTypedBrackets()
  testLinkShapes()
  testBareLinkAndText()
  testNonAscii()
  testOtherEscapes()
  testBuffersReused()
  testRealLines()
end
