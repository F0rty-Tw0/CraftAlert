local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Hot path §6.3 steps 2: the cheap intent prefilter, then tokenizing of surviving lines.
-- No table or closure is created per line: results go into the module buffers below,
-- valid until the next Tokenize call, and the string is walked with string.find (never gmatch).
-- Item links (`|Hitem:<id>...|h[Name]|h`) give their ID and normalized name; enchant links
-- (`|Henchant:<spellID>|h[Name]|h`: Classic enchants, and every recipe link on Retail and
-- Forever, named "[Profession: Name]") give their normalized name plus, per link name, the
-- spell ID (linkIDs) and the text after the first colon (linkTails). Link data and link text
-- never become tokens, so a linked "[Thunderbrow Ring]" does not read as "ring". Other link
-- types (battle pets, spells, ...) and other escapes leave nothing behind.
local Tokenizer = {}

local find = string.find
local strLower = string.lower
local byte = string.byte
local concat = table.concat
local tonumber = tonumber
local ipairs = ipairs
local type = type

-- Word characters: ASCII letters and digits, the apostrophe, and every byte >= 128 (UTF-8).
-- Byte ranges, not %w: a class calls the C library's isalnum per byte, which made this search
-- most of Tokenize's cost (§4.4). Lowercase first, since Tokenize reads lowercase text.
local WORD = "[a-z0-9'\128-\255A-Z]+"
local WORD_CAPTURE = "(" .. WORD .. ")" -- find hands back the token: no sub call per token
local SPACES = "^%s*" -- anchored, so BreakBefore reads only the gap between two tokens
local HYPHEN_SPACES = "^%-?%s*" -- always matches: one optional hyphen, then spaces
local ITEM_LINK = "^|hitem:(%d+)"
local ENCHANT_LINK = "^|henchant:(%d*)"
local ANY_LINK = "^|h%a+:"
local MAX_TOKENS = 64 -- word tokens kept per line (§6.3 step 2; bounds the §4.4 per-line max)
local HUGE = math.huge

local BYTE_A, BYTE_C, BYTE_H, BYTE_K = 97, 99, 104, 107
local BYTE_N, BYTE_R, BYTE_T, BYTE_BAR = 110, 114, 116, 124
-- Escapes that span to a closing code of the same letter: textures, atlases, protected names.
local PAIRED_CLOSER = { [BYTE_T] = "|t", [BYTE_A] = "|a", [BYTE_K] = "|k" }
-- Two-byte escapes: color reset, newline, a literal pipe.
local TWO_BYTE = { [BYTE_R] = true, [BYTE_N] = true, [BYTE_BAR] = true }

local intents = {}
local intentCount = 0

local tokens = {}
local starts = {} -- starts[k]: where token k begins in the line (BreakBefore)
local itemIDs = {}
local linkNames = {}
local linkIDs = {} -- linkIDs[k]: the enchant link's spell ID, or false
local linkTails = {} -- linkTails[k]: an enchant link name's words after its first colon, or false
Tokenizer.WORD = WORD -- Index normalizes recipe phrases with the same word class
Tokenizer.tokens = tokens
Tokenizer.itemIDs = itemIDs
Tokenizer.linkNames = linkNames
Tokenizer.linkIDs = linkIDs
Tokenizer.linkTails = linkTails
Tokenizer.itemCount = 0
Tokenizer.linkNameCount = 0
Tokenizer.normalized = ""

-- Per-call state, module-level so the helpers below need no closures.
local count, items, names = 0, 0, 0
local lastCount, lastItems, lastNames = 0, 0, 0
local linkEnd = nil -- position of the open named link's closing `|h`
local linkFirst = 0 -- first token index of the open named link's text
---@type number|false
local linkID = false -- the open enchant link's spell ID
local linkColon = nil -- position of the first colon in the open enchant link's text
local line = "" -- the lowercase text of the last Tokenize call (BreakBefore)

-- Replaces the intent list (lowercased here, once, so Scan never lowercases a word).
function Tokenizer.Configure(intentWords)
  local n = 0
  for _, word in ipairs(intentWords) do
    if type(word) == "string" and word ~= "" then
      n = n + 1
      intents[n] = strLower(word)
    end
  end
  for k = n + 1, intentCount do
    intents[k] = nil
  end
  intentCount = n
end

-- Lowercases once; the lowercase text when some intent word occurs in it as a plain substring.
function Tokenizer.Scan(text)
  local lower = strLower(text)
  for k = 1, intentCount do
    if find(lower, intents[k], 1, true) then
      return lower
    end
  end
  return nil
end

-- The open link's words after linkColon ("[Tailoring: Silk Bag]" -> "silk bag"), or false.
local function tail()
  if linkColon then
    for k = linkFirst, count do
      if starts[k] > linkColon then
        return k > linkFirst and concat(tokens, " ", k, count)
      end
    end
  end
  return false
end

-- The named link's text tokens become one normalized link name and leave the token buffer.
local function closeLink(p)
  if count >= linkFirst then
    names = names + 1
    linkNames[names] = concat(tokens, " ", linkFirst, count)
    linkIDs[names] = linkID
    linkTails[names] = tail()
    for k = linkFirst, count do
      tokens[k] = nil
    end
    count = linkFirst - 1
  end
  linkEnd = nil
  return p + 2
end

-- At a `|h`: closes the open named link, opens an item or enchant link, or skips a whole
-- other link.
local function link(s, p)
  if p == linkEnd then
    return closeLink(p)
  end
  if not find(s, ANY_LINK, p) then
    return p + 2
  end
  local dataEnd = find(s, "|h", p + 2, true)
  if not dataEnd then
    return #s + 1
  end
  local textEnd = find(s, "|h", dataEnd + 2, true) or #s + 1
  local _, _, id = find(s, ITEM_LINK, p)
  linkID, linkColon = false, nil
  if id then
    items = items + 1
    itemIDs[items] = tonumber(id)
  else
    local _, _, spellID = find(s, ENCHANT_LINK, p)
    if not spellID then
      return textEnd + 2
    end
    linkID = tonumber(spellID) or false
    local colon = find(s, ":", dataEnd + 2, true)
    linkColon = colon and colon < textEnd and colon or nil
  end
  linkEnd = textEnd
  linkFirst = count + 1
  return dataEnd + 2
end

-- Position after the escape sequence starting with the `|` at p; code is the byte after it.
-- Tokenize skips the two-byte escapes itself.
local function escape(s, p, code)
  if code == BYTE_H then
    return link(s, p)
  end
  if code == BYTE_C then
    if byte(s, p + 2) == BYTE_N then -- named color, `|cnIQ4:`
      local colon = find(s, ":", p + 3, true)
      return colon and colon + 1 or p + 3
    end
    return p + 10 -- `|cAARRGGBB`
  end
  local closer = PAIRED_CLOSER[code]
  if closer then
    local close = find(s, closer, p + 2, true)
    return close and close + 2 or #s + 1
  end
  return p + 1
end

-- Clears what the previous line left past this line's counts, then publishes the counts.
local function finish()
  for k = count + 1, lastCount do
    tokens[k], starts[k] = nil, nil
  end
  for k = items + 1, lastItems do
    itemIDs[k] = nil
  end
  for k = names + 1, lastNames do
    linkNames[k], linkIDs[k], linkTails[k] = nil, nil, nil
  end
  lastCount, lastItems, lastNames = count, items, names
  Tokenizer.itemCount = items
  Tokenizer.linkNameCount = names
  Tokenizer.normalized = concat(tokens, " ", 1, count)
end

-- Fills the buffers from lowercase text; returns the token count. `normalized` is the tokens
-- joined by one space: every run of non-word characters collapsed, no edge spaces.
function Tokenizer.Tokenize(lower)
  count, items, names, linkEnd, line = 0, 0, 0, nil, lower
  local afterEnd = #lower + 1
  local i = 1
  local bar = find(lower, "|", 1, true) or afterEnd
  -- The next word match is kept across escapes and searched again only when an escape ran
  -- past its start and no escape starts right at i: a search per escape would rescan the rest
  -- of the line each time (O(n^2) on "||||..."), and escapes back to back ("|r|r...") need none.
  local first, last, word = find(lower, WORD_CAPTURE, 1)
  while true do
    if first and first < i and bar ~= i then
      first, last, word = find(lower, WORD_CAPTURE, i)
    end
    if bar == i or bar < (first or afterEnd) then
      local code = byte(lower, bar + 1)
      if code == BYTE_BAR then -- a run of "||" (literal pipes): one search
        local run = (find(lower, "[^|]", bar) or afterEnd) - bar
        i = bar + run - run % 2 -- an odd last "|" starts the next escape
      elseif TWO_BYTE[code] then -- inline: a line can hold hundreds of "|r"
        i = bar + 2
      else
        i = escape(lower, bar, code)
      end
      bar = find(lower, "|", i, true) or afterEnd
    elseif first and (count < MAX_TOKENS or linkEnd) then -- link text leaves the buffer at its |h
      -- The words before the next escape, without the escape checks above. The loop runs per
      -- token, so it keeps the count and buffers in locals (no upvalue access); linkEnd stays
      -- as it is until the next escape, so the cap is fixed here.
      local n, cap = count, linkEnd and HUGE or MAX_TOKENS
      local tokenBuf, startBuf = tokens, starts
      repeat
        n = n + 1
        tokenBuf[n], startBuf[n] = word, first
        i = last + 1
        first, last, word = find(lower, WORD_CAPTURE, i)
      until not first or first > bar or n >= cap
      count = n
    elseif first and bar < afterEnd then
      i = bar -- full: skip the words up to the next escape, whose links still count
    else
      break
    end
  end
  if linkEnd then
    closeLink(linkEnd)
  end
  finish()
  return count
end

-- §6.4 cue adjacency: whether anything but spaces (punctuation, an escape, a link) sits
-- between tokens k - 1 and k of the last line; never before the first. Asked only for the few
-- tokens an ambiguous word needs, so Tokenize pays one store per token, not a search.
-- hyphenJoins: one hyphen in the gap is no break either ("off-hand", Slang.HandWord).
function Tokenizer.BreakBefore(k, hyphenJoins)
  if k <= 1 or k > count then
    return false
  end
  local _, gapEnd = find(line, SPACES, starts[k - 1] + #tokens[k - 1])
  if hyphenJoins and gapEnd + 1 < starts[k] then
    _, gapEnd = find(line, HYPHEN_SPACES, gapEnd + 1)
  end
  return gapEnd + 1 < starts[k]
end

ns.Tokenizer = Tokenizer
return Tokenizer
