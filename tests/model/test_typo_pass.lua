local Assert = require("tests.helpers.assert")
local Fixture = require("tests.helpers.matcher_fixture")

-- Reference optimal-string-alignment distance (full table), for checking the bounded one.
local function reference(a, b)
  local d = {}
  for i = 0, #a do
    d[i] = { [0] = i }
  end
  for j = 0, #b do
    d[0][j] = j
  end
  for i = 1, #a do
    for j = 1, #b do
      local cost = string.byte(a, i) == string.byte(b, j) and 0 or 1
      local v = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
      if i > 1 and j > 1 and string.byte(a, i) == string.byte(b, j - 1) and string.byte(a, i - 1) == string.byte(b, j) then
        v = math.min(v, d[i - 2][j - 2] + 1)
      end
      d[i][j] = v
    end
  end
  return d[#a][#b]
end

-- Deterministic words over a small alphabet, so near pairs are common.
local function words(count, seed)
  local list, state = {}, seed
  for n = 1, count do
    local length = 5 + n % 6
    local letters = { "m" }
    for k = 2, length do
      state = (state * 1103515245 + 12345) % 2147483648
      letters[k] = string.sub("aenost", state % 6 + 1, state % 6 + 1)
    end
    list[n] = table.concat(letters)
  end
  return list
end

-- §6.2 item 5: Distance(a, 2, #a, b, 2, #b) is the OSA distance from byte 2 on when it is
-- 0 or 1, else 2 (distance 1 only: one edit or one neighbour swap).
local function testDistance()
  local ns = Fixture.load()
  local Distance = ns.TypoPass.Distance
  Assert.equal(Distance("mongoose", 2, 8, "mangoose", 2, 8), 1)
  Assert.equal(Distance("mnogoose", 2, 8, "mongoose", 2, 8), 1, "a swap counts 1")
  Assert.equal(Distance("mongoose", 2, 8, "mongoose", 2, 8), 0)
  Assert.equal(Distance("mangoosee", 2, 9, "mongoose", 2, 8), 2, "two edits are over")
  Assert.equal(Distance("mangose", 2, 7, "mongoose", 2, 8), 2)
  local list = words(60, 7)
  for _, a in ipairs(list) do
    for _, b in ipairs(list) do
      local want = reference(string.sub(a, 2), string.sub(b, 2))
      Assert.equal(Distance(a, 2, #a, b, 2, #b), math.min(want, 2), a .. " " .. b)
    end
  end
end

-- The byte prefilter never drops a target within the allowed distance, and only the hits at
-- a token's smallest distance count.
local function testRunFindsEveryNearTarget()
  local ns = Fixture.load()
  local targets = words(40, 3)
  local index = { professionWords = {}, nameIndex = {}, intentSet = {}, wordIndex = {} }
  for _, word in ipairs(targets) do
    local record = { phrase = word, entries = {}, full = false, wordCount = 1 }
    index.nameIndex[word] = { record }
  end
  ns.TypoPass.Build(index)
  local hitTokens = 0
  for _, token in ipairs(words(120, 11)) do
    local allowed = 1 -- every length (§6.2 item 5)
    local best = allowed + 1
    for _, word in ipairs(targets) do
      best = math.min(best, reference(token, word))
    end
    local want = {}
    for _, word in ipairs(targets) do
      if best <= allowed and reference(token, word) == best then
        want[word] = true
      end
    end
    ns.TypoPass.Run(index, { token }, 1)
    local got = {}
    for k = 1, ns.TypoPass.recordCount do
      got[ns.TypoPass.records[k].phrase] = true
    end
    Assert.same(got, want, token)
    hitTokens = hitTokens + (next(want) and 1 or 0)
  end
  Assert.truthy(hitTokens >= 10, "the generated tokens exercise hits, not only misses")
end

return function()
  testDistance()
  testRunFindsEveryNearTarget()
  require("tests.helpers.wow").reset()
end
