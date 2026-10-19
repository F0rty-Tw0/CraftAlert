local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Slang = ns.Slang or require("CraftAlert.Model.Slang")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")
local Candidates = ns.MatchCandidates or require("CraftAlert.Model.MatchCandidates")

-- Spec §6.3 step 4.4 (wordIndex intersection, distinct groups, profession tie-break) and the
-- structures it reads, built with the index from wordIndex:
--   groupWords[group] = { word = true, ... }: the words whose wordIndex list holds the group,
--     one shared set per distinct word set (a list holds every entry of a group, because a
--     group's words come from its item, so membership is a per-group question);
--   wordInfo[word] = { groupCount, prof, entries, enchanting }: step 4.4's decision for that
--     word alone, and the same decision over its Enchanting entries only (nil when none).
-- Every wordIndex list keeps one global entry order (build order), so an intersection walked
-- in any list's order comes out in the first list's order. Match is hot path: module-level
-- buffers only.
local WordGroups = {}

local pairs = pairs
local ipairs = ipairs
local slangWords, ambiguous = Slang.wordSet, Slang.ambiguous
local MAX_WORDS = 6 -- distinct slang words per line (§6.3 step 4.4; bounds the §4.4 max)

-- §6.4 Enchanting profession words: a line holding one narrows step 4.4 to Enchanting.
local enchantingWords = {}
for _, entry in ipairs(ProfessionWords.entries) do
  if entry.englishName == "enchanting" then
    for _, word in ipairs(entry.words) do
      enchantingWords[word] = true
    end
  end
end

-- groupWords by inversion of wordIndex: each group walks a trie of word sets in pairs()
-- order (the same order for every group), so groups with equal word sets end on one node and
-- share its set.
local function buildGroupWords(index)
  local root = { set = {}, children = {} }
  local nodeOf = {}
  for word, list in pairs(index.wordIndex) do
    for _, entry in ipairs(list) do
      local group = entry.group
      local node = nodeOf[group] or root
      if node.word ~= word then -- a group with several entries is listed once per entry
        local child = node.children[word]
        if child == nil then
          local set = { [word] = true }
          for known in pairs(node.set) do
            set[known] = true
          end
          child = { set = set, children = {}, word = word }
          node.children[word] = child
        end
        nodeOf[group] = child
      end
    end
  end
  local groupWords = {}
  for group, node in pairs(nodeOf) do
    groupWords[group] = node.set
  end
  index.groupWords = groupWords
end

-- Step 4.4 on one list: one recipe → its entries; several → the best profession's entries.
-- seenIn[group] == list: the group was already met in this list.
local function infoFor(list, rank, seenIn)
  local firstOfGroup = {}
  for _, entry in ipairs(list) do
    if seenIn[entry.group] ~= list then
      seenIn[entry.group] = list
      firstOfGroup[#firstOfGroup + 1] = entry
    end
  end
  if #firstOfGroup == 1 then
    return { groupCount = 1, prof = list[1].prof, entries = list }
  end
  local prof = Candidates.BestProfession(firstOfGroup, #firstOfGroup, rank)
  local entries = {}
  for _, entry in ipairs(list) do
    if prof ~= nil and entry.prof == prof then
      entries[#entries + 1] = entry
    end
  end
  return { groupCount = #firstOfGroup, prof = prof, entries = entries }
end

-- Index build (also after a test adds wordIndex words): fills groupWords and wordInfo.
function WordGroups.Build(index)
  buildGroupWords(index)
  local rank = {}
  for i, key in ipairs(index.professionOrder or {}) do
    rank[key] = i
  end
  local enchantingKey = ProfessionWords.KeyFor("enchanting", FlavorCompat.isClassic)
  index.enchantingKey = enchantingKey
  local seenIn = {}
  index.wordInfo = {}
  for word, list in pairs(index.wordIndex) do
    local info, enchanting = infoFor(list, rank, seenIn), {}
    for _, entry in ipairs(list) do
      if entry.prof == enchantingKey then
        enchanting[#enchanting + 1] = entry
      end
    end
    info.enchanting = enchanting[1] and infoFor(enchanting, rank, seenIn) or nil
    index.wordInfo[word] = info
  end
end

-- §6.4: an ambiguous word counts only when another wordIndex word or a step 4.2 phrase
-- match (hasSet) is in the line.
local function counts(token, first, other, hasSet)
  if not ambiguous[token] then
    return true
  end
  return hasSet or (first ~= nil and first ~= token) or other ~= nil
end

-- Per-line buffers: the distinct counted words (a repeated word intersects once), found
-- with stamps on the words (each wordIndex word has its own list).
local lineWords, lineLists, lineCount = {}, {}, 0
local wordStamp = {}
local stamp = 0

-- New index: drop the lists the last line kept, and the stamps.
function WordGroups.Reset()
  lineWords, lineLists, lineCount, wordStamp = {}, {}, 0, {}
end

-- The first two distinct wordIndex words of the line, and whether it holds an Enchanting
-- profession word.
local function firstWords(wordIndex, tokens, count)
  local first, other, enchanting = nil, nil, false
  for i = 1, count do
    local token = tokens[i]
    if wordIndex[token] and first == nil then
      first = token
    elseif wordIndex[token] and other == nil and token ~= first then
      other = token
    end
    enchanting = enchanting or enchantingWords[token] == true
  end
  return first, other, enchanting
end

-- Fills lineWords/lineLists (the first MAX_WORDS distinct counted words; later new words
-- are skipped) and Candidates.wordWhy. → why count, or nil when a known slang word nobody can
-- craft empties the intersection; and whether the line holds an Enchanting word.
local function collect(wordIndex, tokens, count, hasSet)
  local first, other, enchanting = firstWords(wordIndex, tokens, count)
  local why, whyCount = Candidates.wordWhy, 0
  lineCount, stamp = 0, stamp + 1
  for i = 1, count do
    local token = tokens[i]
    local list = wordIndex[token]
    local new = wordStamp[token] ~= stamp
    if (list or slangWords[token]) and (not new or lineCount < MAX_WORDS) and counts(token, first, other, hasSet) then
      if list == nil then
        return nil, enchanting
      end
      if new then
        wordStamp[token] = stamp
        lineCount = lineCount + 1
        lineWords[lineCount], lineLists[lineCount] = token, list
      end
      whyCount = whyCount + 1
      why[whyCount] = token
    end
  end
  return whyCount, enchanting
end

-- Step 4.4. hasSet: step 4.2 left several recipes in Candidates (setWhy[1..setWhyCount]).
-- → whether it produced a match (left in Candidates' result).
function WordGroups.Match(index, tokens, count, intentToken, hasSet, setWhy, setWhyCount)
  local whyCount, enchanting = collect(index.wordIndex, tokens, count, hasSet)
  if whyCount == nil then
    return false
  end
  local why = Candidates.wordWhy
  if hasSet then
    for k = 1, lineCount do
      Candidates.KeepWord(index.groupWords, lineWords[k])
    end
    if enchanting then
      Candidates.KeepProf(index.enchantingKey)
    end
    return Candidates.count > 0 and Candidates.Decide(intentToken, setWhy, setWhyCount, why, whyCount)
  end
  if lineCount == 0 then
    return false
  end
  if lineCount == 1 then
    local info = index.wordInfo[lineWords[1]]
    if enchanting then
      info = info.enchanting
    end
    return info ~= nil and Candidates.DecideWord(intentToken, info, why, whyCount)
  end
  local smallest = 1
  for k = 2, lineCount do
    if #lineLists[k] < #lineLists[smallest] then
      smallest = k
    end
  end
  Candidates.FromListWhere(lineLists[smallest], index.groupWords, lineWords, lineCount, smallest)
  if enchanting then
    Candidates.KeepProf(index.enchantingKey)
  end
  return Candidates.count > 0 and Candidates.Decide(intentToken, nil, 0, why, whyCount)
end

ns.WordGroups = WordGroups
return WordGroups
