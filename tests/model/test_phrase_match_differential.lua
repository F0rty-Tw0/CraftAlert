local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Differential check on seeded random indexes and lines: step 4.2 in PhraseMatch (shape
-- keys, byte compare) against plain find of " phrase " in the padded line, join pairs by
-- concatenation and link names through phraseSet (§6.3 4.2), and the kind-c rule (§6.2 item 1).

local SYLLABLES = { "ab", "lion", "heart", "mane", "o'", "9x", "\195\169t", "ir", "on", "green", "a", "zz", "1", "ka" }
local rand, pick = require("tests.helpers.lcg")(1)

local function randomWord()
  local word = ""
  for _ = 1, rand(1, 3) do
    word = word .. pick(SYLLABLES)
  end
  return word
end

local function randomPhraseIndex(ns)
  local db, vocab, recipes = ns.Defaults.Db(), {}, {}
  for k = 1, rand(3, 15) do
    local words = {}
    for j = 1, rand(1, 4) do
      words[j] = (rand(1, 3) == 1 and #vocab > 0) and pick(vocab) or randomWord()
      vocab[#vocab + 1] = words[j]
    end
    local name = table.concat(words, " ")
    if rand(1, 5) == 1 then
      name = "Enchant " .. words[1] .. " - " .. table.concat(words, " ", 2)
    end
    recipes[k] = { name = name, prof = 164 }
  end
  db.characters["A-Realm"] = { source = "local", enabled = true, realms = {}, professions = {}, recipes = recipes }
  return ns.Index.Build(db, db.settings, { ownKey = "Me-Realm" }), vocab
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
    line = line .. " |cff00ff00|Henchant:1|h[" .. pick(records).phrase .. "]|h|r"
  end
  return line
end

-- Reference step 4.2: the sorted why tokens of the longest hits; none when the only hit is a
-- kind-c alias matched by one token and no token is a wordIndex word (→ "", true).
local function reference42(index, records, Tokenizer, count)
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
  for k = 1, Tokenizer.linkNameCount do
    local record = index.phraseSet[Tokenizer.linkNames[k]]
    if record then
      add(record, record.wordCount, { record.phrase })
    end
  end
  local only = next(hits)
  if best == 1 and next(hits, only) == nil and index.kindC[only] then
    local wordIndexToken = false
    for i = 1, count do
      wordIndexToken = wordIndexToken or index.wordIndex[Tokenizer.tokens[i]] ~= nil
    end
    if not wordIndexToken then
      return "", true
    end
  end
  local whys = {}
  for _, why in pairs(hits) do
    for _, token in ipairs(why) do
      whys[#whys + 1] = token
    end
  end
  table.sort(whys)
  return table.concat(whys, "|")
end

local function testPhraseMatchDifferential()
  local ns = Fixture.load()
  local Tokenizer, PhraseMatch = ns.Tokenizer, ns.PhraseMatch
  local hitLines, kindCDrops = 0, 0
  for _ = 1, 60 do
    local index, vocab = randomPhraseIndex(ns)
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
      local want, dropped = reference42(index, records, Tokenizer, count)
      PhraseMatch.Run(index, count, "lf")
      local got = {}
      for k = 1, PhraseMatch.whyCount do
        got[k] = PhraseMatch.why[k]
      end
      table.sort(got)
      Assert.equal(table.concat(got, "|"), want, line)
      hitLines = hitLines + (want ~= "" and 1 or 0)
      kindCDrops = kindCDrops + (dropped and 1 or 0)
    end
  end
  Assert.truthy(hitLines > 500, "lines with phrase hits: " .. hitLines)
  Assert.truthy(kindCDrops > 20, "lines with a dropped kind-c hit: " .. kindCDrops)
end

return function()
  testPhraseMatchDifferential()
  Wow.reset()
end
