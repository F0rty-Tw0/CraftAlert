local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Tokenizer = ns.Tokenizer or require("CraftAlert.Model.Tokenizer")
local Candidates = ns.MatchCandidates or require("CraftAlert.Model.MatchCandidates")
local Slang = ns.Slang or require("CraftAlert.Model.Slang")

-- Spec §6.3 step 4.2: full names and aliases (phrase records), join pairs and link names.
-- Build side (Aliases calls Add per new record): phraseIds[firstWord] = id,
-- phraseWordRange[id] and phraseKeys, so a line position costs one lookup per word count.
-- Run is hot path: module-level buffers, no table or closure per line.
local PhraseMatch = {}

local byte = string.byte
local find = string.find

-- phraseKeys key = (((phraseIds[firstWord] * KEY_LENGTHS + #phrase) * KEY_WORDS + wordCount)
-- * KEY_LENGTHS + byte length of the second word, 0 for one word) * KEY_BYTES + last byte of
-- the phrase: a record's "shape". The second word's length splits the shapes that names built
-- on one pattern share ("enchant chest ..." / "enchant bracer ..."), so fewer lookups need a
-- byte compare. Below 2^53 for any id under 2^20.
local KEY_LENGTHS = 256 -- a chat line has at most 255 bytes
local KEY_WORDS = 128
local KEY_BYTES = 256
-- The same key expanded, so Run pays the first-word and second-word terms once per position:
-- id * ID_UNIT + #phrase * LENGTH_UNIT + wordCount * WORDS_UNIT + second * KEY_BYTES + last byte.
local WORDS_UNIT = KEY_LENGTHS * KEY_BYTES
local LENGTH_UNIT = KEY_WORDS * WORDS_UNIT
local ID_UNIT = KEY_LENGTHS * LENGTH_UNIT

local tokens, linkNames = Tokenizer.tokens, Tokenizer.linkNames
local linkIDs, linkTails = Tokenizer.linkIDs, Tokenizer.linkTails
local wordGroupsOnly = Slang.wordGroupsOnly
local BreakBefore = Tokenizer.BreakBefore
local HandWord = Slang.HandWord

-- User ruling 2026-10-25: the slot words that are everyday chat ("back in 5", "hand over", "ring me")
-- never filter an alias hit: Slang.wordGroupsOnly plus ring and head. Not Slang.ambiguous: legs,
-- leg, hands and feet still filter. "hand" is here; "off hand" filters as "offhand" (addHit).
local everydaySlot = { ring = true, head = true }
for word in pairs(wordGroupsOnly) do
  everydaySlot[word] = true
end
---@type table
local index = nil
local tokenCount = 0
local padded = ""
local tokenAt = {} -- tokenAt[i]: position of token i in padded; [tokenCount + 1]: one past the end

-- Hits (longest only) and their why tokens.
local hits, hitCount, hitLength = {}, 0, 0
local hitWhy, hitWhyCount = {}, 0
PhraseMatch.why, PhraseMatch.whyCount = hitWhy, 0
-- R4 (slot-words spec), per hit h: hitSlot[h] = the slot word right after an alias hit's span,
-- else false; hitAt[h] = the hit's first token; hitWhyFrom[h] = the hitWhy index of its first
-- why token (the filter compacts a dropped hit's why tokens out).
local hitSlot, hitAt, hitWhyFrom = {}, {}, {}
-- dropped[i] == dropRun: token i lies in a hit R4 dropped, which the typo pass must not revive.
-- The run counter is bumped per Run, so nothing needs clearing.
local dropped, dropRun = {}, 0
PhraseMatch.dropped, PhraseMatch.dropRun = dropped, 0
-- hitStamp[record] == hitRun: the record is in hits (a new run starts with each line and
-- with each longer hit), so a repeated hit costs one lookup, not a scan of hits.
local hitStamp, hitRun = {}, 0
-- The lone hit the second-word rule set aside on the last line, else nil: it is the typo
-- pass's companion and counts with its hits (§6.2 item 1).
PhraseMatch.setAside = nil

local NO_INDEX = {} -- Run always sets the real one first

-- New index: drop the hits (records) and the index the last Run kept.
function PhraseMatch.Reset()
  index, hits, hitCount, hitLength = NO_INDEX, {}, 0, 0
  hitStamp, PhraseMatch.setAside = {}, nil
end

function PhraseMatch.Begin(newIndex)
  newIndex.phraseIds, newIndex.phraseKeys, newIndex.phraseWordRange = {}, {}, {}
end

-- Files a new record by shape (first word, byte length, word count, last byte), so a chat line
-- position costs one lookup per word count instead of a scan of every record under its first
-- word. phraseWordRange[id] = fewest * KEY_WORDS + most: the fewest and most words of a
-- record with that first word (one number, not two tables).
function PhraseMatch.Add(built, record, firstWord)
  local length, wordCount = #record.phrase, record.wordCount
  if length >= KEY_LENGTHS or wordCount >= KEY_WORDS then
    return -- longer than any chat line
  end
  local range = built.phraseWordRange
  local id = built.phraseIds[firstWord]
  if id == nil then
    id = #range + 1
    built.phraseIds[firstWord], range[id] = id, wordCount * KEY_WORDS + wordCount
  end
  local most = range[id] % KEY_WORDS
  local fewest = (range[id] - most) / KEY_WORDS
  fewest, most = wordCount < fewest and wordCount or fewest, wordCount > most and wordCount or most
  range[id] = fewest * KEY_WORDS + most
  local second = 0 -- byte length of the second word
  if wordCount > 1 then
    local secondEnd = find(record.phrase, " ", #firstWord + 2, true) or length + 1
    second = secondEnd - #firstWord - 2
  end
  local shape = ((id * KEY_LENGTHS + length) * KEY_WORDS + wordCount) * KEY_LENGTHS + second
  local key = shape * KEY_BYTES + byte(record.phrase, length)
  local found = built.phraseKeys[key]
  if found == nil then
    built.phraseKeys[key] = record
  elseif found.phrase then -- a second record of the same shape ("enchant boots ..." / "enchant chest ...")
    built.phraseKeys[key] = { found, record }
  else
    found[#found + 1] = record
  end
end

-- i: the hit's first token, nil for a link name. length: its span in tokens (2 for a join pair).
local function addHit(record, length, why1, why2, i)
  if length < hitLength then
    return
  end
  if length > hitLength then
    hitLength, hitCount, hitWhyCount, hitRun = length, 0, 0, hitRun + 1
  end
  if hitStamp[record] == hitRun then
    return
  end
  hitStamp[record] = hitRun
  hitCount = hitCount + 1
  hits[hitCount] = record
  hitAt[hitCount], hitWhyFrom[hitCount], hitSlot[hitCount] = i, hitWhyCount + 1, false
  -- User ruling 2026-10-24 (R4, bug C26): an alias followed by a slot word is filtered by it.
  -- User ruling 2026-10-25: not by an everyday word ("sim plate back") or across punctuation
  -- ("LF sim plate, back in 5"), which chat does not read as naming the piece.
  -- User ruling 2026-10-25 ("Treat as offhand"): "off hand" there filters as "offhand" does.
  if i and not record.full and i + length <= tokenCount then
    local k = i + length
    local slot = tokens[k]
    if slot == "off" and k < tokenCount and tokens[k + 1] == "hand" then
      slot = HandWord(tokens, k + 1, BreakBefore) or slot
    end
    if index.slotsOf[slot] and not everydaySlot[slot] and not BreakBefore(k) then
      hitSlot[hitCount] = slot
    end
  end
  hitWhyCount = hitWhyCount + 1
  hitWhy[hitWhyCount] = why1
  if why2 then
    hitWhyCount = hitWhyCount + 1
    hitWhy[hitWhyCount] = why2
  end
end

-- Whether padded holds phrase at `at`, given that its first `from - 1` bytes already match
-- (the first word is token i itself). Byte compare: no scan past the first difference.
local function phraseAt(phrase, at, from)
  local offset = at - 1
  for k = from, #phrase do
    if byte(padded, offset + k) ~= byte(phrase, k) then
      return false
    end
  end
  return true
end

-- A record found by its shape when its other bytes match too. One plain find (C) costs less
-- than a byte loop in Lua; a miss scans at most the rest of the line.
local function tryRecord(record, at, wordCount, i)
  local phrase = record.phrase
  if find(padded, phrase, at, true) == at then
    addHit(record, wordCount, phrase, nil, i)
  end
end

-- A joinIndex record (its phrase starts with token and is #token + #right long) that
-- token .. right spells.
local function tryJoin(record, i, token, right)
  local from = #token + 1
  if phraseAt(record.phrase, tokenAt[i + 1] - from + 1, from) then
    addHit(record, 2, token, right, i)
  end
end

-- Full names and aliases starting at token i (one phraseKeys lookup per word count: the words
-- must span exactly #phrase bytes, so only whole words match), then the join pair (i, i + 1).
-- id = phraseIds[token], found = joinIndex[token] (Run looks them up: most tokens have neither).
local function phrasesAt(i, token, id, found)
  if id then
    local phraseKeys = index.phraseKeys
    local at = tokenAt[i]
    local range = index.phraseWordRange[id]
    local most = range % KEY_WORDS
    local fewest = (range - most) / KEY_WORDS
    if most > tokenCount - i + 1 then
      most = tokenCount - i + 1
    end
    -- Key terms but the span's: one word has no second-word term. A span of 2+ words holds the
    -- second word, so a second word of 256+ bytes never reaches a key (the break comes first).
    local oneWord = id * ID_UNIT + (1 - at) * LENGTH_UNIT
    local moreWords = i < tokenCount and oneWord + #tokens[i + 1] * KEY_BYTES or oneWord
    local base = fewest == 1 and oneWord or moreWords
    local limit = at + KEY_LENGTHS - 1
    for wordCount = fewest, most do
      local stop = tokenAt[i + wordCount] - 2 -- last byte of the span
      if stop >= limit then
        break -- longer than any filed phrase (and the key would spill into the next id)
      end
      local keyed = phraseKeys[base + stop * LENGTH_UNIT + wordCount * WORDS_UNIT + byte(padded, stop)]
      base = moreWords -- only the first span can be one word
      if keyed and keyed.phrase then
        tryRecord(keyed, at, wordCount, i)
      elseif keyed then
        for k = 1, #keyed do
          tryRecord(keyed[k], at, wordCount, i)
        end
      end
    end
  end
  local right = tokens[i + 1]
  if found and right then
    -- The length check is inline: a short left side ("ca") is shared by many records, and a
    -- call per record would cost more than the check. A list is sorted shortest phrase first,
    -- so the walk stops at the first longer phrase.
    local total = #token + #right
    if found.phrase then
      if #found.phrase == total then
        tryJoin(found, i, token, right)
      end
    else
      for k = 1, #found do
        local length = #found[k].phrase
        if length > total then
          break
        elseif length == total then
          tryJoin(found[k], i, token, right)
        end
      end
    end
  end
end

-- → boolean, so two answers compare with ~=.
local function isCompanion(wordIndex, enchantSlotWords, token)
  return (wordIndex[token] ~= nil and not wordGroupsOnly[token]) or enchantSlotWords[token] == true
end

-- Whether a token of the last Run's line is a wordIndex word (except a Slang.wordGroupsOnly
-- one) or an enchant slot word, the companions of §6.2 item 1. "off hand" counts as "offhand".
-- HandWord costs a string search per "hand", so it is asked only when "offhand" and "hand"
-- differ as companions in this index; otherwise either reading gives the same answer.
function PhraseMatch.HasCompanionWord()
  local wordIndex, enchantSlotWords = index.wordIndex, index.enchantSlotWords
  local handDiffers = isCompanion(wordIndex, enchantSlotWords, "offhand") ~= isCompanion(wordIndex, enchantSlotWords, "hand")
  for i = 1, tokenCount do
    local token = tokens[i]
    if handDiffers and token == "hand" then
      token = HandWord(tokens, i, BreakBefore) or token
    end
    if (wordIndex[token] and not wordGroupsOnly[token]) or enchantSlotWords[token] then
      return true
    end
  end
  return false
end

-- R4: drops every hit whose slot word (hitSlot) leaves its record no entry, and compacts hits,
-- hitSlot and hitWhy. A dropped hit's tokens are stamped for the typo pass. The hits all span
-- hitLength tokens (a longer hit resets the list), and only hits from the token loop have a slot.
local function dropFiltered()
  local groupWords = index.groupWords
  local kept, keptWhy = 0, 0
  for h = 1, hitCount do
    local slot = hitSlot[h]
    if slot and not Candidates.AnyKept(hits[h], slot, groupWords) then
      for k = hitAt[h], hitAt[h] + hitLength - 1 do
        dropped[k] = dropRun
      end
    else
      kept = kept + 1
      hits[kept], hitSlot[kept] = hits[h], slot
      local last = (h < hitCount and hitWhyFrom[h + 1] or hitWhyCount + 1) - 1
      for k = hitWhyFrom[h], last do
        keptWhy = keptWhy + 1
        hitWhy[keptWhy] = hitWhy[k]
      end
    end
  end
  hitCount, hitWhyCount = kept, keptWhy
end

-- A "match" keeps the slot word that filtered a kept hit in its why tokens, once each.
local function addSlotWhy()
  for h = 1, hitCount do
    local slot = hitSlot[h]
    local seen = false
    for g = 1, h - 1 do
      seen = seen or hitSlot[g] == slot
    end
    if slot and not seen then
      hitWhyCount = hitWhyCount + 1
      hitWhy[hitWhyCount] = slot
    end
  end
end

-- Step 4.2 on the tokenized line (Tokenizer buffers). → "match", "set" (several recipes,
-- left in Candidates; PhraseMatch.why[1..whyCount] holds their why tokens) or nil.
function PhraseMatch.Run(newIndex, count, intentToken)
  index, tokenCount = newIndex, count
  padded = " " .. Tokenizer.normalized .. " "
  hitCount, hitLength, hitWhyCount, hitRun = 0, 0, 0, hitRun + 1
  dropRun = dropRun + 1
  PhraseMatch.dropRun, PhraseMatch.setAside = dropRun, nil
  local at = 2 -- position of token 1 in padded
  for i = 1, tokenCount do
    tokenAt[i] = at
    at = at + #tokens[i] + 1
  end
  tokenAt[tokenCount + 1] = at
  local phraseIds, joinIndex = index.phraseIds, index.joinIndex
  for i = 1, tokenCount do
    local token = tokens[i]
    local id, found = phraseIds[token], joinIndex[token]
    if id or found then
      phrasesAt(i, token, id, found)
    end
  end
  -- A link name hits by its recipe's spell ID, else as a full name, else by the text after a
  -- "Profession:" prefix; the whole text goes first, so "[Transmute: Arcanite]" keeps its name.
  local linked = false
  local phraseSet, recipeRecords = index.phraseSet, index.recipeRecords
  for k = 1, Tokenizer.linkNameCount do
    local record = recipeRecords[linkIDs[k]] or phraseSet[linkNames[k]] or phraseSet[linkTails[k]]
    if record then
      addHit(record, record.wordCount, record.phrase, nil, nil)
      linked = true
    end
  end
  dropFiltered()
  -- §6.2 item 1: a kind-c alias or a one-word full name matched by one token, alone among the
  -- hits, needs a wordIndex or enchant slot word in the line; otherwise it is set aside (the
  -- typo pass may still pair with it). A join pair covers 2 tokens, and a line with a link-name
  -- hit has either that record as its hit, a longer hit, or two hits: never set aside.
  local lone = hitCount == 1 and hitLength == 1 and not linked
  if lone and index.needsSecondWord[hits[1]] and not PhraseMatch.HasCompanionWord() then
    PhraseMatch.setAside, hitCount, hitWhyCount = hits[1], 0, 0
  end
  PhraseMatch.whyCount = hitWhyCount
  if hitCount == 0 then
    return nil
  end
  Candidates.FromRecordsFiltered(hits, hitCount, hitSlot, index.groupWords)
  if Candidates.GroupCount() > 1 then
    return "set"
  end
  addSlotWhy()
  Candidates.Item(intentToken)
  Candidates.WhyList(hitWhy, hitWhyCount)
  return "match"
end

ns.PhraseMatch = PhraseMatch
return PhraseMatch
