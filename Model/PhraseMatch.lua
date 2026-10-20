local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Tokenizer = ns.Tokenizer or require("CraftAlert.Model.Tokenizer")
local Candidates = ns.MatchCandidates or require("CraftAlert.Model.MatchCandidates")

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
---@type table
local index = nil
local tokenCount = 0
local padded = ""
local tokenAt = {} -- tokenAt[i]: position of token i in padded; [tokenCount + 1]: one past the end

-- Hits (longest only) and their why tokens.
local hits, hitCount, hitLength = {}, 0, 0
local hitWhy, hitWhyCount = {}, 0
PhraseMatch.why, PhraseMatch.whyCount = hitWhy, 0
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

local function addHit(record, length, why1, why2)
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
local function tryRecord(record, at, wordCount)
  local phrase = record.phrase
  if find(padded, phrase, at, true) == at then
    addHit(record, wordCount, phrase, nil)
  end
end

-- A joinIndex record (its phrase starts with token and is #token + #right long) that
-- token .. right spells.
local function tryJoin(record, i, token, right)
  local from = #token + 1
  if phraseAt(record.phrase, tokenAt[i + 1] - from + 1, from) then
    addHit(record, 2, token, right)
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
        tryRecord(keyed, at, wordCount)
      elseif keyed then
        for k = 1, #keyed do
          tryRecord(keyed[k], at, wordCount)
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

-- Whether a token of the last Run's line is a wordIndex word or an enchant slot word, the
-- companions of §6.2 item 1.
function PhraseMatch.HasCompanionWord()
  local wordIndex, enchantSlotWords = index.wordIndex, index.enchantSlotWords
  for i = 1, tokenCount do
    local token = tokens[i]
    if wordIndex[token] or enchantSlotWords[token] then
      return true
    end
  end
  return false
end

-- Step 4.2 on the tokenized line (Tokenizer buffers). → "match", "set" (several recipes,
-- left in Candidates; PhraseMatch.why[1..whyCount] holds their why tokens) or nil.
function PhraseMatch.Run(newIndex, count, intentToken)
  index, tokenCount = newIndex, count
  padded = " " .. Tokenizer.normalized .. " "
  hitCount, hitLength, hitWhyCount, hitRun = 0, 0, 0, hitRun + 1
  PhraseMatch.setAside = nil
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
  local linked = false
  for k = 1, Tokenizer.linkNameCount do
    local record = index.phraseSet[linkNames[k]]
    if record then
      addHit(record, record.wordCount, record.phrase, nil)
      linked = true
    end
  end
  -- §6.2 item 1: a kind-c alias or a one-word full name matched by one token, alone among the
  -- hits, needs a wordIndex word in the line. A join pair covers 2 tokens, and a line with a
  -- link-name hit has either that record as its hit, a longer hit, or two hits: never dropped.
  local lone = hitCount == 1 and hitLength == 1 and not linked
  if lone and index.needsSecondWord[hits[1]] and not PhraseMatch.HasCompanionWord() then
    PhraseMatch.setAside, hitCount, hitWhyCount = hits[1], 0, 0
  end
  PhraseMatch.whyCount = hitWhyCount
  if hitCount == 0 then
    return nil
  end
  Candidates.FromRecords(hits, hitCount)
  if Candidates.GroupCount() > 1 then
    return "set"
  end
  Candidates.Item(intentToken)
  Candidates.WhyList(hitWhy, hitWhyCount)
  return "match"
end

ns.PhraseMatch = PhraseMatch
return PhraseMatch
