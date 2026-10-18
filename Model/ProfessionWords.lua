local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Spec §6.4 profession words: what players call each crafting profession, with the
-- professionKey each resolves to. Retail and Forever key a profession by its base skill-line
-- ID; Classic keys it by the lowercase localized name, which equals englishName on English
-- clients only (§11). Words are lowercase tokens, as the Tokenizer produces them. Gathering,
-- cooking, fishing and first aid are not listed (spec §5.1). English only in v1.
local ProfessionWords = {}

ProfessionWords.entries = {
  {
    words = { "blacksmithing", "blacksmith", "blacksmiths", "bs", "smith", "smiths" },
    skillLineID = 164,
    englishName = "blacksmithing",
  },
  {
    words = { "leatherworking", "leatherworker", "leatherworkers", "lw", "lwer", "lwers" },
    skillLineID = 165,
    englishName = "leatherworking",
  },
  {
    words = { "tailoring", "tailor", "tailors" },
    skillLineID = 197,
    englishName = "tailoring",
  },
  {
    words = { "jewelcrafting", "jewelcrafter", "jewelcrafters", "jc", "jcer" },
    skillLineID = 755,
    englishName = "jewelcrafting",
  },
  {
    words = { "enchanting", "enchanter", "enchanters", "ench" },
    skillLineID = 333,
    englishName = "enchanting",
  },
  {
    words = { "alchemy", "alchemist", "alchemists", "alch" },
    skillLineID = 171,
    englishName = "alchemy",
  },
  {
    words = { "engineering", "engineer", "engineers", "engi" },
    skillLineID = 202,
    englishName = "engineering",
  },
  {
    words = { "inscription", "scribe", "scribes" },
    skillLineID = 773,
    englishName = "inscription",
  },
}

local entryByWord = {}
for _, entry in ipairs(ProfessionWords.entries) do
  for _, word in ipairs(entry.words) do
    entryByWord[word] = entry
  end
end

-- word must already be lowercase. → professionKey (skill-line ID, or the lowercase English
-- name when isClassic), or nil when the word names no crafting profession.
function ProfessionWords.KeyFor(word, isClassic)
  local entry = entryByWord[word]
  if not entry then
    return nil
  end
  if isClassic then
    return entry.englishName
  end
  return entry.skillLineID
end

ns.ProfessionWords = ProfessionWords
return ProfessionWords
