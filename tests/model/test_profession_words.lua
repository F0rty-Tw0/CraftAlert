local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")

local function load()
  return Fresh.require("Model.ProfessionWords")
end

-- name -> Retail base skill-line ID (the Htrade link ids in tools/captures/retail_report.md
-- confirm 164, 165, 755, 202, 197, 773; Alchemy and Enchanting are the known base ids).
local SKILL_LINES = {
  blacksmithing = 164,
  leatherworking = 165,
  tailoring = 197,
  jewelcrafting = 755,
  enchanting = 333,
  alchemy = 171,
  engineering = 202,
  inscription = 773,
}

local function testEntries()
  local ProfessionWords = load()
  local seen = {}
  for _, entry in ipairs(ProfessionWords.entries) do
    Assert.equal(SKILL_LINES[entry.englishName], entry.skillLineID, entry.englishName)
    seen[entry.englishName] = true
    Assert.truthy(#entry.words > 0, entry.englishName)
  end
  for name in pairs(SKILL_LINES) do
    Assert.truthy(seen[name], "missing " .. name)
  end
  Assert.equal(#ProfessionWords.entries, 8, "crafting professions only: no gathering, cooking, fishing, first aid")
end

-- Spec §6.4 examples plus the slang in docs/knowledge/trade-requests-forever.md.
local function testSlangResolvesPerFlavor()
  local ProfessionWords = load()
  local cases = {
    { "bs", 164, "blacksmithing" },
    { "smith", 164, "blacksmithing" },
    { "blacksmith", 164, "blacksmithing" },
    { "blacksmithing", 164, "blacksmithing" },
    { "lw", 165, "leatherworking" },
    { "lwer", 165, "leatherworking" },
    { "leatherworker", 165, "leatherworking" },
    { "tailor", 197, "tailoring" },
    { "tailoring", 197, "tailoring" },
    { "jc", 755, "jewelcrafting" },
    { "jewelcrafter", 755, "jewelcrafting" },
    { "enchanter", 333, "enchanting" },
    { "enchanting", 333, "enchanting" },
    { "ench", 333, "enchanting" },
    { "alch", 171, "alchemy" },
    { "alchemist", 171, "alchemy" },
    { "alchemy", 171, "alchemy" },
    { "engineer", 202, "engineering" },
    { "engi", 202, "engineering" },
    { "engineering", 202, "engineering" },
    { "scribe", 773, "inscription" },
    { "inscription", 773, "inscription" },
    -- plurals appear in real chat ("any enchanters")
    { "enchanters", 333, "enchanting" },
    { "tailors", 197, "tailoring" },
  }
  for _, case in ipairs(cases) do
    Assert.equal(ProfessionWords.KeyFor(case[1], false), case[2], case[1] .. " retail")
    Assert.equal(ProfessionWords.KeyFor(case[1], true), case[3], case[1] .. " classic")
  end
end

local function testNotProfessionWords()
  local ProfessionWords = load()
  -- "enchant" is what a request names ("lf enchant mangoose"), not who is asked for.
  for _, word in ipairs({ "enchant", "mining", "cooking", "skinning", "herbalism", "fishing", "belt", "", "BS" }) do
    Assert.equal(ProfessionWords.KeyFor(word, false), nil, word)
    Assert.equal(ProfessionWords.KeyFor(word, true), nil, word)
  end
end

-- A word listed under two professions would resolve by table order; none may repeat.
local function testWordsAreUniqueAndLowercase()
  local ProfessionWords = load()
  local owner = {}
  for _, entry in ipairs(ProfessionWords.entries) do
    for _, word in ipairs(entry.words) do
      Assert.equal(word, string.lower(word), word)
      Assert.equal(owner[word], nil, word .. " listed twice")
      owner[word] = entry.englishName
    end
  end
end

return function()
  testEntries()
  testSlangResolvesPerFlavor()
  testNotProfessionWords()
  testWordsAreUniqueAndLowercase()
end
