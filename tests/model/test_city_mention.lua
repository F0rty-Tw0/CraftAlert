local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")

local function load()
  local Tokenizer = Fresh.require("Model.Tokenizer")
  local CityMention = Fresh.require("Model.CityMention")
  return Tokenizer, CityMention
end

-- Spec §7: each row tokenizes the line, then asks OnlyOther (ownKey = undercity unless given).
local ROWS = {
  -- R2a/R2b: full names anywhere.
  { "LF BS orgrimmar", true },
  { "LF ench thunder bluff", true },
  { "LF ench thunder, bluff", false },
  { "LF ench thunderbluff", true },
  { "WTB orgri summon", true },
  -- R2c: short names after a cue word or a lone @.
  { "LF BS in org", true },
  { "LF ench @SW", true },
  { "LF ench @ sw", true },
  { "LF ench at tb", true },
  { "LF ench from og", true },
  { "LF ench near smc", true },
  { "@exo LF ench", true },
  -- Short names without a cue: everyday words and abbreviations.
  { "if anyone can craft", false },
  { "darn no one", false },
  { "LF tb", false },
  { "LF ench in, if anyone", false },
  { "LF ench in , if anyone", false },
  { "LF ench @@sw", false },
  -- R3: the player's own capital keeps the line.
  { "LF BS in uc", false },
  { "LF BS in org or uc", false },
  { "LF BS, uc later", false },
  { "LF BS in org, uc later", false },
  { "LF BS in org, tb later", true },
  { "LF ench in tb, if anyone", false, "ironforge" },
  { "LF BS in uc or org", false },
  { "LF BS undercity, orgrimmar", false },
  { "LF BS in org", false, "orgrimmar" },
  { "LF ench in tb", true, "orgrimmar" },
  -- Adjacent-words rule: a cue word before a non-city token, everyday words around a hit.
  { "LF thick plate, back in 5", false },
  { "LF thick plate back", false },
  { "LF thick plate back in org", true },
  { "LF thick plate in org, back in 5", true },
}

local function testRows()
  local Tokenizer, CityMention = load()
  for _, row in ipairs(ROWS) do
    local line, expected, own = row[1], row[2], row[3] or "undercity"
    Tokenizer.Tokenize(string.lower(line))
    Assert.equal(CityMention.OnlyOther(own), expected, line .. " (own " .. own .. ")")
  end
end

local function testForMap()
  local _, CityMention = load()
  Assert.equal(CityMention.ForMap(1458), "undercity")
  Assert.equal(CityMention.ForMap(90), "undercity")
  Assert.equal(CityMention.ForMap(1454), "orgrimmar")
  Assert.equal(CityMention.ForMap(1453), "stormwind")
  Assert.equal(CityMention.ForMap(1954), "silvermoon")
  Assert.equal(CityMention.ForMap(1415), nil, "a zone, not a capital")
  Assert.equal(CityMention.ForMap(999999), nil)
  Assert.equal(CityMention.ForMap(nil), nil)
end

local function testForZoneName()
  local _, CityMention = load()
  Assert.equal(CityMention.ForZoneName("Stormwind City"), "stormwind")
  Assert.equal(CityMention.ForZoneName("the exodar"), "exodar")
  Assert.equal(CityMention.ForZoneName("Thunder Bluff"), "thunderbluff")
  Assert.equal(CityMention.ForZoneName("UNDERCITY"), "undercity")
  Assert.equal(CityMention.ForZoneName("Tirisfal Glades"), nil)
  Assert.equal(CityMention.ForZoneName(""), nil)
  Assert.equal(CityMention.ForZoneName(nil), nil)
end

-- Outside oracle: real Forever Trade lines. OnlyOther reads tokens only, so unmatched lines count too.
local CORPUS_OTHER = {
  ["LF Enchanter located in ORG"] = true,
  ["in org looking for enchanter"] = true,
  ["LF enchanter in TB"] = true,
  ["Any Enchaters in ORG?"] = true,
  ["LF Tailor in ORG"] = true,
  ["LF Blacksmith to attach [Iron Shield Spike] in ORG"] = true,
  ["|cffffd000|Htrade:<guid>:7413:333|h[Enchanting]|h|r 225 LFW in ORG. Tips Appreciated (:"] = true,
  ["LF summon to TB"] = true,
  ["WTB summon to TB 1g"] = true,
  ["any Lock in TB that can summon me?"] = true,
  ["Any rogue in TB open |cnIQ2:|Hitem:4633::::::::29:1487::1::1:28:5246:::::|h[Heavy Bronze Lockbox]|h|r plz?"] = true,
  ["at TB need money for the bus to org"] = true,
}

local function testCorpus()
  local Tokenizer, CityMention = load()
  local corpus = dofile("tests/fixtures/trade_corpus.lua")
  local seen = 0
  for _, entry in ipairs(corpus) do
    Tokenizer.Tokenize(string.lower(entry.text))
    local expected = CORPUS_OTHER[entry.text] == true
    Assert.equal(CityMention.OnlyOther("undercity"), expected, entry.text)
    if expected then
      seen = seen + 1
    end
  end
  Assert.equal(seen, 12, "every listed corpus line is in the fixture")
end

return function()
  testRows()
  testForMap()
  testForZoneName()
  testCorpus()
end
