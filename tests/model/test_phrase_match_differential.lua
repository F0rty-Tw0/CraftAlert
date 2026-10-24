local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Differential check on seeded random indexes and lines: step 4.2 in PhraseMatch (shape
-- keys, byte compare) against plain find of " phrase " in the padded line, join pairs by
-- concatenation and link names through phraseSet (§6.3 4.2), and the second-word rule (§6.2
-- item 1).

local SYLLABLES = { "ab", "lion", "heart", "mane", "o'", "9x", "\195\169t", "ir", "on", "green", "a", "zz", "1", "ka" }
local rand, pick = require("tests.helpers.lcg")(1)

local function randomWord()
  local word = ""
  for _ = 1, rand(1, 3) do
    word = word .. pick(SYLLABLES)
  end
  return word
end

-- §6.2 item 4: an enchant's slot words are the Slang.slots lists holding its slot word, or the
-- word alone.
local function addSlotWords(slots, Slang, slot)
  slots[slot] = true
  for _, list in pairs(Slang.slots) do
    for _, word in ipairs(list) do
      if word == slot then
        for _, other in ipairs(list) do
          slots[other] = true
        end
      end
    end
  end
end

-- → index, vocab, the enchant slot words of its names (word -> true).
local function randomPhraseIndex(ns)
  local db, vocab, recipes, slots = ns.Defaults.Db(), {}, {}, {}
  for k = 1, rand(3, 15) do
    local words = {}
    for j = 1, rand(1, 4) do
      words[j] = (rand(1, 3) == 1 and #vocab > 0) and pick(vocab) or randomWord()
      vocab[#vocab + 1] = words[j]
    end
    local name = table.concat(words, " ")
    if rand(1, 5) == 1 then
      name = "Enchant " .. words[1] .. " - " .. table.concat(words, " ", 2)
      addSlotWords(slots, ns.Slang, words[1])
    end
    recipes[k] = { name = name, prof = 164 }
  end
  db.characters["A-Realm"] = { source = "local", enabled = true, realms = {}, professions = {}, recipes = recipes }
  return ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }), vocab, slots
end

local function randomLine(records, vocab)
  local seps, line = { " ", "  ", "-", ", ", "!" }, ""
  for k = 1, rand(1, 8) do
    local kind = rand(1, 4)
    local part
    if kind == 1 then
      part = pick(records).phrase
    elseif kind == 2 then
      local phrase = pick(records).phrase
      local cut = rand(1, #phrase)
      part = phrase:sub(1, cut) .. " " .. phrase:sub(cut + 1) .. (rand(1, 3) == 1 and "x" or "")
    else
      part = kind == 3 and pick(vocab) or randomWord()
    end
    line = line .. (k > 1 and pick(seps) or "") .. part
  end
  if rand(1, 6) == 1 then
    line = line .. " |cff00ff00|Henchant:0|h[" .. pick(records).phrase .. "]|h|r" -- ID 0: no stored recipe
  end
  return line
end

-- Reference step 4.2: the sorted why tokens of the longest hits; none when the only hit is a
-- kind-c alias (Aliases' set, checked in test_aliases) or a one-word full name, matched by one
-- token and not by a link name, and no token is a wordIndex word or an enchant slot word
-- (→ "", "alias" | "full"); else the why tokens and whether only a slot word kept the hit.
local function reference42(index, records, slots, Tokenizer, count)
  local padded, best, hits = " " .. Tokenizer.normalized .. " ", 0, {}
  local function add(record, length, why)
    if length > best then
      best, hits = length, {}
    end
    if length == best and hits[record] == nil then
      hits[record] = why
    end
  end
  for _, record in ipairs(records) do
    if string.find(padded, " " .. record.phrase .. " ", 1, true) then
      add(record, record.wordCount, { record.phrase })
    end
  end
  for i = 1, count - 1 do
    local a, b = Tokenizer.tokens[i], Tokenizer.tokens[i + 1]
    for _, record in ipairs(records) do
      if record.wordCount == 1 and #record.phrase >= 6 and #a >= 2 and #b >= 2 and record.phrase == a .. b then
        add(record, 2, { a, b })
      end
    end
  end
  local linked = {}
  for k = 1, Tokenizer.linkNameCount do
    local record = index.phraseSet[Tokenizer.linkNames[k]]
    if record then
      add(record, record.wordCount, { record.phrase })
      linked[record] = true
    end
  end
  local only, keptBySlot = next(hits), false
  local kind = only and (only.full and only.wordCount == 1 and "full" or not only.full and index.needsSecondWord[only] and "alias")
  if best == 1 and next(hits, only) == nil and kind and not linked[only] then
    local wordIndexToken, slotToken = false, false
    for i = 1, count do
      local token = Tokenizer.tokens[i]
      wordIndexToken = wordIndexToken or index.wordIndex[token] ~= nil
      slotToken = slotToken or slots[token] == true
    end
    if not wordIndexToken and not slotToken then
      return "", kind
    end
    keptBySlot = not wordIndexToken
  end
  local whys = {}
  for _, why in pairs(hits) do
    for _, token in ipairs(why) do
      whys[#whys + 1] = token
    end
  end
  table.sort(whys)
  return table.concat(whys, "|"), nil, keptBySlot
end

local function testPhraseMatchDifferential()
  local ns = Fixture.load()
  local Tokenizer, PhraseMatch = ns.Tokenizer, ns.PhraseMatch
  local hitLines, slotLines, drops = 0, 0, { alias = 0, full = 0 }
  for _ = 1, 60 do
    local index, vocab, slots = randomPhraseIndex(ns)
    ns.Matcher.SetIndex(index)
    local records = {}
    for _, list in pairs(index.nameIndex) do
      for _, record in ipairs(list) do
        records[#records + 1] = record
      end
    end
    for _ = 1, 30 do
      local line = randomLine(records, vocab)
      local count = Tokenizer.Tokenize(string.lower(line))
      local want, dropped, keptBySlot = reference42(index, records, slots, Tokenizer, count)
      slotLines = slotLines + (keptBySlot and 1 or 0)
      PhraseMatch.Run(index, count, "lf")
      local got = {}
      for k = 1, PhraseMatch.whyCount do
        got[k] = PhraseMatch.why[k]
      end
      table.sort(got)
      Assert.equal(table.concat(got, "|"), want, line)
      hitLines = hitLines + (want ~= "" and 1 or 0)
      if dropped then
        drops[dropped] = drops[dropped] + 1
      end
    end
  end
  Assert.truthy(hitLines > 500, "lines with phrase hits: " .. hitLines)
  Assert.truthy(drops.alias > 20, "lines with a dropped kind-c hit: " .. drops.alias)
  Assert.truthy(drops.full > 20, "lines with a dropped one-word full name: " .. drops.full)
  Assert.truthy(slotLines > 10, "lines kept by an enchant slot word only: " .. slotLines)
end

return function()
  testPhraseMatchDifferential()
  Wow.reset()
end
