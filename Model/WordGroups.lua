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
--   wordInfo[word] = { groupCount, prof, entries, byProf }: step 4.4's decision for that word
--     alone, and byProf[key] the same decision over one profession's entries only (absent
--     when it has none), for a line that names a profession; byProf is nil when one
--     profession has every entry (narrowedInfo).
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

-- §6.4 profession words: a line holding one narrows step 4.4 to that profession, Enchanting
-- before any other, else the first named (user ruling 2026-10-21).
-- Class-armor §4 rule 2(c) crafting cues: the fixed cue words and every profession word;
-- fillers may sit between a cue word and the ambiguous word it partners.
local enchantingWords, cueWords, fillerWords = {}, {}, {}
for _, word in ipairs(Constants.craftCueWords) do
  cueWords[word] = true
end
for _, word in ipairs(Constants.cueFillerWords) do
  fillerWords[word] = true
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

-- info.byProf for list: the entries of each profession, then their infoFor in place. nil when
-- one profession has every entry (most words), so the index holds no table for it.
local function byProfession(list, rank, seenIn)
  local only = list[1] and list[1].prof
  for _, entry in ipairs(list) do
    if entry.prof ~= only then
      only = nil
      break
    end
  end
  if only ~= nil then
    return nil
  end
  local byProf = {}
  for _, entry in ipairs(list) do
    local prof = entry.prof
    if prof ~= nil then
      local entries = byProf[prof] or {}
      byProf[prof] = entries
      entries[#entries + 1] = entry
    end
  end
  for prof, entries in pairs(byProf) do
    byProf[prof] = infoFor(entries, rank, seenIn)
  end
  return byProf
end

-- A word's step 4.4 decision over profession prof's entries only, or nil when it has none.
local function narrowedInfo(info, prof)
  local byProf = info.byProf
  if byProf == nil then
    return info.prof == prof and info or nil
  end
  return byProf[prof]
end

-- Index build (also after a test adds wordIndex words): fills groupWords, wordInfo and the
-- profession key of every profession word (professionKeys).
function WordGroups.Build(index)
  buildGroupWords(index)
  local rank = {}
  for i, key in ipairs(index.professionOrder or {}) do
    rank[key] = i
  end
  local isClassic = FlavorCompat.isClassic
  index.enchantingKey = ProfessionWords.KeyFor("enchanting", isClassic)
  index.professionKeys = {}
  for _, entry in ipairs(ProfessionWords.entries) do
    for _, word in ipairs(entry.words) do
      index.professionKeys[word] = ProfessionWords.KeyFor(word, isClassic)
    end
  end
  local seenIn = {}
  index.wordInfo = {}
  for word, list in pairs(index.wordIndex) do
    local info, byProf = infoFor(list, rank, seenIn), byProfession(list, rank, seenIn)
    if byProf ~= nil and info.groupCount > 1 and info.prof ~= nil then
      info.entries = byProf[info.prof].entries -- the same entries in the same order, held once
    end
    info.byProf = byProf
    index.wordInfo[word] = info
  end
end

-- §6.4: an ambiguous word counts only when another wordIndex word or a step 4.2 phrase match
-- (hasSet) is in the line, or a crafting cue word is next to it (cued, cuedAt).
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

-- The first two distinct wordIndex words of the line (§6.4: what an ambiguous word needs).
local function firstWords(wordIndex, tokens, count)
  local first, other = nil, nil
  for i = 1, count do
    local token = tokens[i]
    if wordIndex[token] and first == nil then
      first = token
    elseif wordIndex[token] and other == nil and token ~= first then
      other = token
    end
  end
  return first, other
end

-- §6.4, user ruling 2026-10-21: whether a crafting cue word is the token right before or
-- after tokens[i], past filler words but never past punctuation (breakBefore:
-- Tokenizer.BreakBefore).
local function cuedAt(tokens, count, breakBefore, i)
  local k = i
  while k > 1 and not breakBefore(k) do
    k = k - 1
    if cueWords[tokens[k]] then
      return true
    elseif not fillerWords[tokens[k]] then
      break
    end
  end
  k = i
  while k < count and not breakBefore(k + 1) do
    k = k + 1
    if cueWords[tokens[k]] then
      return true
    elseif not fillerWords[tokens[k]] then
      break
    end
  end
  return false
end

-- Fills lineWords/lineLists (the first MAX_WORDS distinct counted words; later new words
-- are skipped), Candidates.wordWhy and the inferArmor line state. → why count, or nil when a
-- known slang word nobody can craft empties the intersection; and the profession key the
-- line narrows to (an Enchanting word first, else the first profession word) or nil.
-- inferable (§4 rule 2) is decided on every scanned word, counted or not: a slot without an
-- armor type (an ambiguous slot needs a cue next to it) and no Enchanting word (user ruling
-- 2026-10-20: an enchant ignores the asker's armor). A repeat of a word already counted
-- (wordStamp) takes the same decision at once, since nothing it depends on changed. The
-- first two wordIndex words and the cue are found only when an ambiguous word needs them
-- (most lines have none).
local function collect(index, tokens, count, breakBefore, hasSet)
  local wordIndex, tags, professionKeys = index.wordIndex, index.armorTags, index.professionKeys
  local first, other, scanned, enchanting, named = nil, nil, false, false, nil
  local sawType, sawPlainSlot, sawCuedSlot = false, false, false
  local why, whyCount = Candidates.wordWhy, 0
  lineCount, stamp = 0, stamp + 1
  for i = 1, count do
    local token = tokens[i]
    if wordStamp[token] == stamp then
      whyCount = whyCount + 1
      why[whyCount] = token
    else
      enchanting = enchanting or enchantingWords[token] == true
      named = named or professionKeys[token]
      local list = wordIndex[token]
      if (list or slangWords[token]) and lineCount < MAX_WORDS then
        local tag, ambiguousSlot, cued = tags[token], false, false
        if ambiguous[token] then
          if not scanned then
            first, other = firstWords(wordIndex, tokens, count)
            scanned = true
          end
          ambiguousSlot, cued = tag == "slot", cuedAt(tokens, count, breakBefore, i)
        end
        local counted = counts(token, first, other, hasSet, cued)
        sawType = sawType or tag == "type"
        sawPlainSlot = sawPlainSlot or (tag == "slot" and not ambiguousSlot)
        sawCuedSlot = sawCuedSlot or (ambiguousSlot and cued)
        if counted then
          if list == nil then
            return nil
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
  local slotWithoutType = not sawType and (sawPlainSlot or sawCuedSlot)
  inferable = slotWithoutType and not enchanting
  return whyCount, enchanting and index.enchantingKey or named
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
-- nil, the narrowing profession key or nil, and whether the armor word was added (last in
-- lineWords and the why).
local function collectLine(index, tokens, count, breakBefore, hasSet, classArmor)
  local whyCount, narrow = collect(index, tokens, count, breakBefore, hasSet)
  local inferred = nil
  if whyCount ~= nil and inferable and classArmor ~= nil then
    whyCount, inferred = inferArmor(index, hasSet, classArmor, whyCount)
  end
  return whyCount, narrow, inferred
end

-- Narrows step 4.2's set by the line's words (and the named profession). An inferred armor
-- word goes last and only when some recipe is left: a named set never loses to the sender's
-- class (user ruling 2026-10-20), so the word and its why label drop out. → why count.
local function keepSetWords(index, narrow, whyCount, inferred)
  local groupWords, own = index.groupWords, inferred and lineCount - 1 or lineCount
  for k = 1, own do
    Candidates.KeepWord(groupWords, lineWords[k])
  end
  if narrow ~= nil then
    Candidates.KeepProf(narrow)
  end
  if inferred and not Candidates.KeepWord(groupWords, lineWords[lineCount], true) then
    return whyCount - 1
  end
  return whyCount
end

local function noBreak()
  return false
end

-- Step 4.4. hasSet: step 4.2 left several recipes in Candidates (setWhy[1..setWhyCount]).
-- classArmor: the sender's armor word getter (collectLine). breakBefore: Tokenizer.BreakBefore
-- for tokens, nil when they hold no punctuation. → whether it produced a match (left in
-- Candidates' result).
function WordGroups.Match(index, tokens, count, intentToken, hasSet, setWhy, setWhyCount, classArmor, breakBefore)
  local whyCount, narrow, inferred = collectLine(index, tokens, count, breakBefore or noBreak, hasSet, classArmor)
  if whyCount == nil then
    return false
  end
  local why = Candidates.wordWhy
  if hasSet then
    whyCount = keepSetWords(index, narrow, whyCount, inferred)
    return Candidates.count > 0 and Candidates.Decide(intentToken, setWhy, setWhyCount, why, whyCount)
  end
  if lineCount == 0 then
    return false
  end
  if lineCount == 1 then
    local info = index.wordInfo[lineWords[1]]
    if narrow ~= nil then
      info = narrowedInfo(info, narrow)
    end
    return info ~= nil and Candidates.DecideWord(intentToken, info, why, whyCount)
  end
  -- Walk the smallest list; with a named profession, the smallest list of that profession only
  -- (each word's precomputed one), so the narrowing never walks a big list of other professions.
  local smallest, smallestList = 0, nil
  for k = 1, lineCount do
    local list = lineLists[k]
    if narrow ~= nil then
      local info = narrowedInfo(index.wordInfo[lineWords[k]], narrow)
      if info == nil then
        return false -- a word with no entry of that profession empties the narrowed intersection
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
