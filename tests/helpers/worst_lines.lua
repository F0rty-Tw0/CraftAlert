-- Worst-case chat lines for the §4.4 per-line max (plan A4), built against a synthetic index
-- (tests/helpers/synthetic_index.lua). Each line targets one step's per-token work.
--   local WorstLines = require("tests.helpers.worst_lines")
--   for _, case in ipairs(WorstLines.cases(index)) do ... case[1] (name), case[2] (line)
local WorstLines = {}

-- prefix, then unit repeated (joined by sep, default " ") while the line fits 255 bytes.
function WorstLines.fill(prefix, unit, sep)
  sep = sep or " "
  local parts, length = { prefix }, #prefix
  while length + #sep + #unit <= 255 do
    parts[#parts + 1] = unit
    length = length + #sep + #unit
  end
  return table.concat(parts, sep)
end

-- Number of typo targets a token of this first byte and length is compared with (§6.2 item
-- 5: length within 1).
local function candidateCount(byLength, length)
  local total = 0
  for targetLength = length - 1, length + 1 do
    for _ in pairs(byLength[targetLength] or {}) do
      total = total + 1
    end
  end
  return total
end

-- Near misses of a target: its last 3 bytes replaced (5-9 letters), or with keepEnds its
-- middle (7-12 letters: first 3 and last 2 bytes kept, so both TypoPass byte filters pass).
local function nearMiss(word, keepEnds)
  local length = #word
  if keepEnds and length >= 7 and length <= 12 then
    return string.sub(word, 1, 3) .. string.rep("q", length - 5) .. string.sub(word, -2)
  elseif not keepEnds and length >= 5 and length <= 9 then
    return string.sub(word, 1, length - 3) .. "qqq"
  end
end

-- A 255-char intent line of near-miss tokens (each 2+ edits from a target with the same first
-- byte and length), densest buckets first, so the typo pass compares as many targets as
-- possible as deep as possible and never matches.
function WorstLines.typo(index, keepEnds)
  local tokens = {}
  for _, byLength in pairs(index.typoBuckets) do
    for targetLength, bucket in pairs(byLength) do
      for word in pairs(bucket) do
        local token = nearMiss(word, keepEnds)
        if token then
          tokens[#tokens + 1] = { token = token, cost = candidateCount(byLength, targetLength) }
        end
      end
    end
  end
  table.sort(tokens, function(a, b)
    if a.cost ~= b.cost then
      return a.cost > b.cost
    end
    return a.token < b.token
  end)
  local parts, length = { "lf" }, 2
  for k = 1, 255 do
    local token = tokens[(k - 1) % #tokens + 1].token
    if length + #token + 1 > 255 then
      break
    end
    parts[#parts + 1] = token
    length = length + #token + 1
  end
  return table.concat(parts, " ")
end

-- "lf" (+ prefix) + every distinct wordIndex word, biggest lists first, up to 255 chars:
-- step 4.4 with the most lists to intersect.
local function allWordsLine(index, prefix)
  local words = {}
  for word, list in pairs(index.wordIndex) do
    words[#words + 1] = { word, #list }
  end
  table.sort(words, function(a, b)
    if a[2] ~= b[2] then
      return a[2] > b[2]
    end
    return a[1] < b[1]
  end)
  local parts = { "lf", prefix }
  local length = #table.concat(parts, " ")
  for _, item in ipairs(words) do
    if length + #item[1] + 1 <= 255 then
      parts[#parts + 1] = item[1]
      length = length + #item[1] + 1
    end
  end
  return table.concat(parts, " ")
end

-- A reviewer's search result (PR 3): many distinct tokens across steps 4.2-4.5.
local SEARCH_LINE = "lf aa int ha ba cloth of ea ca rakufabq na 8x ribicaq ja int rudebabq renedaq rakufabq ea "
  .. "plate enchant of 8x of ca ca int storm green ribagababaq ribagababaq rigadabq da renugababaq "
  .. "ruvadababaq ribagababaq ribagababaq renedaq iron na rupagaq storm"

-- Two slot words (so the inferred armor word empties the intersection) then 3 typo near
-- misses: the lookup, the append, the empty intersection and the typo pass.
function WorstLines.inferredEmpty(index)
  local misses = string.match(WorstLines.typo(index), "^lf (%S+ %S+ %S+)")
  return "lf belt boots " .. misses
end

WorstLines.UNION = "lf ring neck cloak"

-- → { { name, line }, ... }
function WorstLines.cases(index)
  local fill = WorstLines.fill
  return {
    { "typo", WorstLines.typo(index) },
    { "typo_ends", WorstLines.typo(index, true) }, -- 4.5: past both byte filters
    { "plate", fill("lf", "plate") }, -- 4.4: one big wordIndex list, repeated
    { "enchant", fill("lf", "enchant") }, -- 4.2: 200 records under one first word
    { "chest1x", fill("lf", "chest 1x") }, -- 4.3: slot words without a stat word
    { "enchantchest", fill("lf", "enchant chest") }, -- 4.2: many records of one shape
    { "alldistinct", allWordsLine(index) }, -- 4.4: every distinct wordIndex word
    { "enchantwords", allWordsLine(index, "enchant") }, -- 4.4 narrowed to Enchanting
    { "pipes", fill("lf", "||", "") }, -- step 2: an escape every 2 bytes
    { "pipes509", "lf " .. string.rep("||", 253) }, -- step 2: a 509-byte raw line
    { "resets509", "lf " .. string.rep("|r", 253) }, -- step 2: 253 escapes back to back
    { "join_ca", fill("lf", "ca") }, -- 4.2: a join left side shared by many records
    { "digits", fill("lf", "8") }, -- 4.3: digit-only tokens
    { "a", fill("lf", "a") }, -- the most tokens a line can hold
    { "8x", fill("lf", "8x") }, -- 4.3: digits then letters, no stat word
    { "search", SEARCH_LINE },
    { "bareslot", fill("lf", "belt") }, -- 4.4: a bare slot word, so the armor word is inferred
    { "admit", fill("lf crafter", "head") }, -- 4.4: an ambiguous word counted through its cue word
    -- 4.4: an uncounted ambiguous word repeated, each next to filler words (§6.4 cue adjacency)
    { "legs_for", fill("lf", "legs for") },
    { "fillers", fill("lf", "for my the a some me legs") },
    { "back", fill("lf", "back") }, -- 4.4 only: no companion, no stat + slot word
    { "cue_break", fill("lf crafter.", "head a for my") }, -- punctuation ends the cue's reach
    { "inferred_empty", WorstLines.inferredEmpty(index) }, -- 4.4: lookup, append, empty, typo
    -- 4.4: slot words of different slots, no armor slot (so no armor word): the union
    { "union", WorstLines.UNION },
    -- 4.4 R3: a buyer word directly before an ambiguous armor slot word, class known
    { "buyer_legs", fill("wtb", "legs wtb") },
  }
end

return WorstLines
