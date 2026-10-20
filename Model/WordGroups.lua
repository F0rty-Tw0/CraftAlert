local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Slang = ns.Slang or require("CraftAlert.Model.Slang")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")
local Candidates = ns.MatchCandidates or require("CraftAlert.Model.MatchCandidates")

-- Spec §6.3 step 4.4 (wordIndex intersection, distinct groups, profession tie-break) and the
-- structures it reads, built with the index from wordIndex:
--   groupWords[group] = { word = true, ... }: the words whose wordIndex list holds the group,
--     one shared set per distinct word set (a list holds every entry of a group, because a
--     group's words come from its item, so membership is a per-group question);
--   wordSets[word] = { set, ... }: the distinct groupWords sets holding word (a few dozen), so
--     a line whose words no group has together is rejected without walking a list;
--   wordInfo[word] = { groupCount, prof, entries, enchanting }: step 4.4's decision for that
--     word alone, and the same decision over its Enchanting entries only (nil when none).
-- A line that names an armor slot without an armor type or an Enchanting word takes the
-- sender's armor word (docs/specs/2026-10-20-class-armor-design.md §4 rules 2-7, and the
-- 2026-10-20 enchanting ruling in the -notes.md beside it): one class lookup at most, only
-- adding words, never uncounting one that counts today.
-- Every wordIndex list keeps one global entry order (build order), so an intersection walked
-- in any list's order comes out in the first list's order. Match is hot path: module-level
-- buffers only.
local WordGroups = {}

local pairs = pairs
local ipairs = ipairs
local slangWords, ambiguous = Slang.wordSet, Slang.ambiguous
local MAX_WORDS = 6 -- distinct slang words per line (§6.3 step 4.4; bounds the §4.4 max)

-- §6.4 Enchanting profession words: a line holding one narrows step 4.4 to Enchanting.
-- Class-armor §4 rule 2(c) crafting cues: the fixed cue words and every profession word.
local enchantingWords, cueWords = {}, {}
for _, word in ipairs(Constants.craftCueWords) do
  cueWords[word] = true
end
for _, entry in ipairs(ProfessionWords.entries) do
  for _, word in ipairs(entry.words) do
    cueWords[word] = true
    if entry.englishName == "enchanting" then
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
  local groupWords, wordSets, listed = {}, {}, {}
  for group, node in pairs(nodeOf) do
    local set = node.set
    groupWords[group] = set
    if not listed[set] then
      listed[set] = true
      for word in pairs(set) do
        local sets = wordSets[word] or {}
        wordSets[word] = sets
        sets[#sets + 1] = set
      end
    end
  end
  index.groupWords, index.wordSets = groupWords, wordSets
end

-- Per-line marks on groupWords sets (setMark[set] == mark), so an intersection checks one
-- set per entry instead of every word.
local setMark = {}

-- Marks with mark the word sets of words[k] (sets) that hold every words[1..n]. → whether
-- some group has them all.
local function markSetsWithAll(sets, words, n, mark)
  local any = false
  for s = 1, #sets do
    local set, all = sets[s], true
    for w = 1, n do
      if not set[words[w]] then
        all = false
        break
      end
    end
    if all then
      setMark[set], any = mark, true
    end
  end
  return any
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

-- §6.4: an ambiguous word counts only when another wordIndex word, a step 4.2 phrase match
-- (hasSet) or a crafting cue word (cued; user ruling 2026-10-21) is in the line.
local function counts(token, first, other, hasSet, cued)
  if not ambiguous[token] then
    return true
  end
  return hasSet or cued or (first ~= nil and first ~= token) or other ~= nil
end

-- Per-line buffers: the distinct counted words (a repeated word intersects once), found
-- with stamps on the words (each wordIndex word has its own list).
local lineWords, lineLists, lineCount = {}, {}, 0
local wordStamp = {}
local stamp = 0
-- Per-line state collect leaves for inferArmor: whether the sender's armor word may be
-- inferred (class-armor §4 rule 2).
local inferable = false

-- New index: drop the lists the last line kept, the stamps and the set marks.
function WordGroups.Reset()
  lineWords, lineLists, lineCount, wordStamp, setMark = {}, {}, 0, {}, {}
end

-- The first two distinct wordIndex words of the line, and whether it holds a crafting cue
-- word (§6.4: what an ambiguous word needs).
local function firstWords(wordIndex, tokens, count)
  local first, other, cued = nil, nil, false
  for i = 1, count do
    local token = tokens[i]
    cued = cued or cueWords[token] == true
    if wordIndex[token] and first == nil then
      first = token
    elseif wordIndex[token] and other == nil and token ~= first then
      other = token
    end
  end
  return first, other, cued
end

-- Fills lineWords/lineLists (the first MAX_WORDS distinct counted words; later new words
-- are skipped), Candidates.wordWhy and the inferArmor line state. → why count, or nil when a
-- known slang word nobody can craft empties the intersection; and whether the line holds an
-- Enchanting word. inferable (§4 rule 2) is decided on every scanned word, counted or not:
-- a slot without an armor type (an ambiguous slot needs a cue) and no Enchanting word (user
-- ruling 2026-10-20: an enchant ignores the asker's armor). tags: index.armorTags. A repeat
-- of a word already counted (wordStamp) takes the same decision at once, since nothing it
-- depends on changed. The first two wordIndex words and the cue are found only when an
-- ambiguous word needs them (most lines have none).
local function collect(wordIndex, tokens, count, hasSet, tags)
  local first, other, cued, scanned, enchanting, cue = nil, nil, false, false, false, false
  local sawType, sawPlainSlot, sawAmbiguousSlot = false, false, false
  local why, whyCount = Candidates.wordWhy, 0
  lineCount, stamp = 0, stamp + 1
  for i = 1, count do
    local token = tokens[i]
    if wordStamp[token] == stamp then
      whyCount = whyCount + 1
      why[whyCount] = token
    else
      enchanting = enchanting or enchantingWords[token] == true
      cue = cue or cueWords[token] == true
      local list = wordIndex[token]
      if (list or slangWords[token]) and lineCount < MAX_WORDS then
        local tag, ambiguousSlot = tags[token], false
        if ambiguous[token] then
          if not scanned then
            first, other, cued = firstWords(wordIndex, tokens, count)
            scanned = true
          end
          ambiguousSlot = tag == "slot"
        end
        local counted = counts(token, first, other, hasSet, cued)
        sawType = sawType or tag == "type"
        sawPlainSlot = sawPlainSlot or (tag == "slot" and not ambiguousSlot)
        sawAmbiguousSlot = sawAmbiguousSlot or ambiguousSlot
        if counted then
          if list == nil then
            return nil, enchanting
          end
          wordStamp[token] = stamp
          lineCount = lineCount + 1
          lineWords[lineCount], lineLists[lineCount] = token, list
          whyCount = whyCount + 1
          why[whyCount] = token
        end
      end
    end
  end
  local slotWithoutType = not sawType and (sawPlainSlot or (sawAmbiguousSlot and cue))
  inferable = slotWithoutType and not enchanting
  return whyCount, enchanting
end

-- Class-armor §4 rule 7: the sender's armor word joins the counted words (after the line's
-- own, outside the MAX_WORDS cap) with its "<armor> (<class>)" why label. A cued ambiguous
-- slot word (§4 rule 5) already counts through its cue word (collect).
-- → why count, or nil when the intersection is empty. No class → the line as collected.
local function inferArmor(index, hasSet, classArmor, whyCount)
  local armor, label = classArmor()
  if armor == nil then
    return whyCount
  end
  local list = index.wordIndex[armor]
  if list == nil then -- a recognized slang word with no entries empties the intersection,
    return hasSet and whyCount or nil -- but a step 4.2 set ignores it (see keepSetWords)
  end
  lineCount = lineCount + 1
  lineWords[lineCount], lineLists[lineCount] = armor, list
  Candidates.wordWhy[whyCount + 1] = label
  return whyCount + 1, true
end

-- collect, then the sender's armor word when §4 rule 2 holds. classArmor: nil or a function
-- → armorWord, whyLabel or nil, called at most once per line (§4 rule 8). → why count or
-- nil, enchanting, and whether the armor word was added (last in lineWords and the why).
local function collectLine(index, tokens, count, hasSet, classArmor)
  local whyCount, enchanting = collect(index.wordIndex, tokens, count, hasSet, index.armorTags)
  local inferred = nil
  if whyCount ~= nil and inferable and classArmor ~= nil then
    whyCount, inferred = inferArmor(index, hasSet, classArmor, whyCount)
  end
  return whyCount, enchanting, inferred
end

-- Narrows step 4.2's set by the line's words (and Enchanting). An inferred armor word goes
-- last and only when some recipe is left: a named set never loses to the sender's class
-- (user ruling 2026-10-20), so the word and its why label drop out. → why count.
local function keepSetWords(index, enchanting, whyCount, inferred)
  local groupWords, own = index.groupWords, inferred and lineCount - 1 or lineCount
  for k = 1, own do
    Candidates.KeepWord(groupWords, lineWords[k])
  end
  if enchanting then
    Candidates.KeepProf(index.enchantingKey)
  end
  if inferred and not Candidates.KeepWord(groupWords, lineWords[lineCount], true) then
    return whyCount - 1
  end
  return whyCount
end

-- Step 4.4. hasSet: step 4.2 left several recipes in Candidates (setWhy[1..setWhyCount]).
-- classArmor: the sender's armor word getter (collectLine). → whether it produced a match
-- (left in Candidates' result).
function WordGroups.Match(index, tokens, count, intentToken, hasSet, setWhy, setWhyCount, classArmor)
  local whyCount, enchanting, inferred = collectLine(index, tokens, count, hasSet, classArmor)
  if whyCount == nil then
    return false
  end
  local why = Candidates.wordWhy
  if hasSet then
    whyCount = keepSetWords(index, enchanting, whyCount, inferred)
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
  -- Walk the smallest list; with an Enchanting word, the smallest Enchanting-only list (each
  -- word's precomputed one), so the narrowing never walks a big list of other professions.
  local smallest, smallestList = 0, nil
  for k = 1, lineCount do
    local list = lineLists[k]
    if enchanting then
      local info = index.wordInfo[lineWords[k]].enchanting
      if info == nil then
        return false -- a word with no Enchanting entry empties the narrowed intersection
      end
      list = info.entries
    end
    if smallestList == nil or #list < #smallestList then
      smallest, smallestList = k, list
    end
  end
  if not markSetsWithAll(index.wordSets[lineWords[smallest]], lineWords, lineCount, stamp) then
    return false
  end
  Candidates.FromListMarked(smallestList, index.groupWords, setMark, stamp)
  return Candidates.count > 0 and Candidates.Decide(intentToken, nil, 0, why, whyCount)
end

ns.WordGroups = WordGroups
return WordGroups
