local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Slang = ns.Slang or require("CraftAlert.Model.Slang")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")
local StatSlot = ns.StatSlot or require("CraftAlert.Model.StatSlot")

-- Spec §6.2 item 5 and §6.3 step 4.5: typo targets (typoBuckets, built with the index) and
-- the per-line search. Targets are one-word phrase records and profession words of 5+
-- letters; a token is compared only with targets of its first byte and a length within 1.
-- Allowed distance is 1 for every length (one edit or one neighbour swap). The search is hot
-- path: module-level buffers, no table or closure per line.
local TypoPass = {}

local byte = string.byte
local next = next
local pairs = pairs
local ipairs = ipairs
local type = type
local ProfessionKeyFor = ProfessionWords.KeyFor
local statWords, slangWords = StatSlot.statWords, Slang.wordSet

local MIN_LETTERS = 5
local MAX_TOKENS = 3 -- bounds the per-line worst case (§4.4)
local OVER = 2 -- distance() result for "more than one edit"

-- Results of the last Run: alias records (step 4.5), profession keys with the token that hit
-- each (step 4.6), and the tokens that hit anything, in line order.
TypoPass.records, TypoPass.recordCount = {}, 0
TypoPass.profs, TypoPass.profTokens, TypoPass.profCount = {}, {}, 0
TypoPass.why, TypoPass.whyCount = {}, 0

local tokenHits, tokenHitCount = {}, 0

-- New index: drop the buffers that hold the old index's records.
function TypoPass.Reset()
  TypoPass.records, TypoPass.recordCount = {}, 0
  TypoPass.profs, TypoPass.profTokens, TypoPass.profCount = {}, {}, 0
  tokenHits, tokenHitCount = {}, 0
end

local function addTarget(index, word, value)
  local first, length = byte(word, 1), #word
  local byLength = index.typoBuckets[first] or {}
  index.typoBuckets[first] = byLength
  local bucket = byLength[length] or {}
  byLength[length] = bucket
  bucket[word] = value
end

-- Index build: typoBuckets[firstByte][length][word] = record | professionKey. A record wins
-- over a profession word of the same spelling.
function TypoPass.Build(index)
  index.typoBuckets = {}
  for word, key in pairs(index.professionWords) do
    if #word >= MIN_LETTERS then
      addTarget(index, word, key)
    end
  end
  for _, list in pairs(index.nameIndex) do
    for _, record in ipairs(list) do
      if record.wordCount == 1 and #record.phrase >= MIN_LETTERS then
        addTarget(index, record.phrase, record)
      end
    end
  end
end

-- Restricted Damerau-Levenshtein (optimal string alignment) distance of a[i..la] and
-- b[j..lb] when it is 0 or 1, else OVER. Equal leading and trailing bytes are skipped (OSA is
-- the same on reversed strings); what is left is nothing, one edit, a swap ("ab" / "ba") or
-- more than one edit.
local function distance(a, i, la, b, j, lb)
  local gap = (la - i) - (lb - j)
  if gap > 1 or gap < -1 then
    return OVER -- at least |gap| edits
  end
  while i <= la and j <= lb and byte(a, i) == byte(b, j) do
    i, j = i + 1, j + 1
  end
  while la >= i and lb >= j and byte(a, la) == byte(b, lb) do
    la, lb = la - 1, lb - 1
  end
  local n, m = la - i + 1, lb - j + 1
  if n + m <= 1 or (n == 1 and m == 1) then
    return n + m == 0 and 0 or 1 -- equal, one insertion or deletion, or one substitution
  end
  if n == 2 and m == 2 and byte(a, i) == byte(b, lb) and byte(a, la) == byte(b, j) then
    return 1
  end
  return OVER
end
TypoPass.Distance = distance

-- Cheap filter on bytes 2-3 (byte 1 is equal by bucket): false only when the distance from
-- byte 2 on is surely above 1 (equal byte 2, or the one edit at byte 2: substitution,
-- deletion, insertion or swap), so most targets skip distance(). Bytes past the end are nil,
-- and nil == nil keeps the filter a necessary condition at word ends.
local function mayBeNear(t2, t3, w2, w3)
  return t2 == w2 or t3 == w3 or t3 == w2 or t2 == w3
end

-- Fills tokenHits with the targets nearest to one token; → their count.
local function nearest(token, length, byLength)
  local best = OVER
  local t2, t3 = byte(token, 2, 3)
  tokenHitCount = 0
  for targetLength = length - 1, length + 1 do
    local bucket = byLength[targetLength]
    if bucket then
      for word, value in next, bucket do
        local w2, w3 = byte(word, 2, 3)
        if mayBeNear(t2, t3, w2, w3) then
          -- Same first byte by construction: compare from byte 2.
          local d = distance(token, 2, length, word, 2, targetLength)
          if d < best then
            best, tokenHitCount = d, 0
          end
          if d == best and d < OVER then
            tokenHitCount = tokenHitCount + 1
            tokenHits[tokenHitCount] = value
          end
        end
      end
    end
  end
  return tokenHitCount
end

-- Not an intent, stat, slang or profession word, and 5+ letters.
local function eligible(index, token, length)
  return length >= MIN_LETTERS
    and not index.intentSet[token]
    and not statWords[token]
    and not slangWords[token]
    and not index.wordIndex[token]
    and ProfessionKeyFor(token, false) == nil
end

-- Keeps the token's hits; a kind-c alias or a one-word full name only with a companion (§6.2
-- item 1). The token is a why token when it kept something.
local function keep(token, needsSecondWord, companion)
  local records, profs, profTokens = TypoPass.records, TypoPass.profs, TypoPass.profTokens
  local kept = false
  for k = 1, tokenHitCount do
    local value = tokenHits[k]
    if type(value) ~= "table" then
      TypoPass.profCount = TypoPass.profCount + 1
      profs[TypoPass.profCount] = value
      profTokens[TypoPass.profCount] = token
      kept = true
    elseif companion or not needsSecondWord[value] then
      TypoPass.recordCount = TypoPass.recordCount + 1
      records[TypoPass.recordCount] = value
      kept = true
    end
  end
  if kept then
    TypoPass.whyCount = TypoPass.whyCount + 1
    TypoPass.why[TypoPass.whyCount] = token
  end
end

-- Tries the first MAX_TOKENS eligible tokens of tokens[1..count]; per token only the hits
-- at its smallest distance count. companion: the line has a wordIndex word or a step 4.2
-- hit, so kind-c aliases and one-word full names count. → the number of records hit.
function TypoPass.Run(index, tokens, count, companion)
  TypoPass.recordCount, TypoPass.profCount, TypoPass.whyCount = 0, 0, 0
  local typoBuckets = index.typoBuckets
  local tried = 0
  for i = 1, count do
    local token = tokens[i]
    local length = #token
    if tried < MAX_TOKENS and eligible(index, token, length) then
      tried = tried + 1
      local byLength = typoBuckets[byte(token, 1)]
      if byLength and nearest(token, length, byLength) > 0 then
        keep(token, index.needsSecondWord, companion)
      end
    end
  end
  return TypoPass.recordCount
end

ns.TypoPass = TypoPass
return TypoPass
