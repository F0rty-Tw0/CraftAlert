local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Spec §4.4 budgets and §13 "Performance proxy" (plan A4), against a synthetic 10-character /
-- 2,000-recipe index. Every line is generated before any measurement; lines are synthetic
-- (request-like and non-request shapes with unique suffixes), so this test needs no corpus.
--   python scripts/run_test.py --jit tests/perf/test_hot_path_perf.lua   (lupa.luajit21)
--   python scripts/run_test.py tests/perf/test_hot_path_perf.lua         (lupa.lua51; CI lua5.1)
local IS_JIT = rawget(_G, "jit") ~= nil
local MEAN_US = IS_JIT and 20 or 60
local WORST_US = 200 -- §4.4 per-line max, every runtime
local GROWTH_KB = IS_JIT and 8 or 1
local RETAINED_KB = 50
local BUILD_MS = 80
local INDEX_KB = 3072 -- §4.4 idle memory, 3 MB
local LINES = 10000
local RUNS = 3
local WORST_REPS = 300
local SENDER = "Customer-Other"

local Synthetic = require("tests.helpers.synthetic_index")
local build = Synthetic.build
local function pick(list, n)
  return list[(n % #list) + 1]
end

local function median(values)
  table.sort(values)
  return values[math.floor((#values + 1) / 2)]
end

local NON_REQUESTS = {
  "WTS |cff1eff00|Hitem:2575::::::::60:::::|h[Red Linen Shirt]|h|r %dg cheap",
  "LFM RFC 2 dps then go %d",
  "<Guild %d> recruiting for raids, pst for info",
  "selling portals to all cities %d",
  "LFG Deadmines healer %d",
  "what a lovely day in Orgrimmar %d",
  "is the auction house down again %d",
  "WTS Runecloth stacks %d",
  "anyway gonna log off soon %d",
}

local REQUESTS = {
  "LF plate belt crafter %d",
  "LF Blacksmith %d",
  "WTB |cnIQ3:|Hitem:100001::::::::30:1488|h[Item]|h|r %d",
  "lf korvoral boots pls %d",
  "LF enchanter +8stam to chest %d",
  "need Green Iron Belt %d",
  "LF someone to make stuff %d",
}

-- About 90% non-requests; each line unique through its number.
local function mixedLines(count)
  local lines = {}
  for n = 1, count do
    local templates = (n % 10 == 0) and REQUESTS or NON_REQUESTS
    lines[n] = string.format(pick(templates, math.floor(n / 10)), n)
  end
  return lines
end

local function nonMatchingLines(count, offset)
  local lines = {}
  for n = 1, count do
    lines[n] = string.format(pick(NON_REQUESTS, n), offset + n)
  end
  return lines
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

-- A 255-char intent line of near-miss 5-9 letter tokens (each 3 edits from a target with the
-- same first byte and length), densest buckets first, so the typo pass compares deep prefixes
-- against as many targets as possible and never matches.
local function typoWorstLine(index)
  local tokens = {}
  for _, byLength in pairs(index.typoBuckets) do
    for targetLength, bucket in pairs(byLength) do
      if targetLength >= 5 and targetLength <= 9 then
        for word in pairs(bucket) do
          local token = string.sub(word, 1, targetLength - 3) .. "qqq"
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

-- "lf <unit> <unit> ..." up to 255 chars: one word (or pair) repeated, the worst case of a
-- step that does work per token (4.2 phrase scan, 4.3 stat + slot, 4.4 intersection).
local function repeatedLine(unit)
  local parts, length = { "lf" }, 2
  while length + #unit + 1 <= 255 do
    parts[#parts + 1] = unit
    length = length + #unit + 1
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

-- Median of RUNS passes over lines; → mean microseconds per line.
local function meanMicros(Matcher, lines, repeats)
  local runs = {}
  for r = 1, RUNS do
    local started = os.clock()
    for _ = 1, repeats or 1 do
      for i = 1, #lines do
        Matcher.Match("trade", lines[i], SENDER)
      end
    end
    runs[r] = os.clock() - started
  end
  return median(runs) * 1e6 / (#lines * (repeats or 1))
end

local function pass(Matcher, lines)
  for i = 1, #lines do
    Matcher.Match("trade", lines[i], SENDER)
  end
end

-- KB growth of a warm pass with the GC stopped: tables and closures only, since the first
-- pass already interned every string the matcher makes. The smaller of two warm passes: a
-- table per line grows every pass, while a one-off VM resize (Lua stack, string table) seen
-- under lupa.lua51 shows up in one pass only.
local function warmGrowthKB(Matcher, lines)
  collectgarbage("collect")
  collectgarbage("stop")
  pass(Matcher, lines)
  local before = collectgarbage("count")
  pass(Matcher, lines)
  local middle = collectgarbage("count")
  pass(Matcher, lines)
  local after = collectgarbage("count")
  collectgarbage("restart")
  return math.min(middle - before, after - middle)
end

-- KB still held after passes over lines and a full collect: catches a buffer that grows on
-- every line (a missing count reset), which a single warm-pass delta can miss.
local function retainedKB(Matcher, lines, passes)
  collectgarbage("collect")
  local before = collectgarbage("count")
  for _ = 1, passes or 1 do
    pass(Matcher, lines)
  end
  collectgarbage("collect")
  return collectgarbage("count") - before
end

-- Median build time; each build starts after a full collect, so garbage of the run before
-- (an earlier build's whole index) is not collected on this one's clock.
local function buildMs(ns, db)
  local runs = {}
  for r = 1, RUNS do
    collectgarbage("collect")
    local started = os.clock()
    build(ns, db)
    runs[r] = (os.clock() - started) * 1000
  end
  return median(runs)
end

return function()
  local ns = Fixture.load()
  local db, items = Synthetic.db(ns)
  Synthetic.stubItems(items)
  local ms = buildMs(ns, db)
  -- Idle index memory, after a full collect.
  collectgarbage("collect")
  collectgarbage("collect")
  local idleBefore = collectgarbage("count")
  local index = build(ns, db)
  collectgarbage("collect")
  collectgarbage("collect")
  local indexKB = collectgarbage("count") - idleBefore
  ns.Matcher.SetIndex(index)
  local Matcher = ns.Matcher

  local mixed = mixedLines(LINES)
  local quiet = nonMatchingLines(LINES, LINES)
  local worst = typoWorstLine(index)
  Assert.equal(Matcher.Match("trade", worst, SENDER), nil, "worst line must not match")
  Assert.equal(Matcher.lastStop, "nomatch")
  Assert.truthy(#worst > 240 and #worst <= 255, "worst line length " .. #worst)
  Assert.truthy(Matcher.Match("trade", mixed[10], SENDER), "requests in the mix do match")
  local worstCases = {
    { "typo", worst },
    { "plate", repeatedLine("plate") }, -- 4.4: one big wordIndex list, repeated
    { "enchant", repeatedLine("enchant") }, -- 4.2: 200 records under one first word
    { "chest1x", repeatedLine("chest 1x") }, -- 4.3: slot words without a stat word
    { "enchantchest", repeatedLine("enchant chest") }, -- 4.2: many records of one shape
    { "alldistinct", allWordsLine(index) }, -- 4.4: every distinct wordIndex word
    { "enchantwords", allWordsLine(index, "enchant") }, -- 4.4 narrowed to Enchanting
  }
  local worstLines, worstText = {}, {}
  local worstMean = 0
  for k, case in ipairs(worstCases) do
    local micros = meanMicros(Matcher, { case[2] }, WORST_REPS)
    worstMean = math.max(worstMean, micros)
    worstLines[k] = case[2]
    worstText[k] = string.format("%s=%.0f", case[1], micros)
  end
  worstLines[#worstLines + 1] = mixed[10]

  local mean = meanMicros(Matcher, mixed)
  local retained = retainedKB(Matcher, quiet)
  local retainedMatching = retainedKB(Matcher, mixed, 5)
  local growth = warmGrowthKB(Matcher, mixed)
  local worstGrowth = warmGrowthKB(Matcher, worstLines)

  print(
    string.format(
      "perf: runtime=%s size=%d mean=%.2fus worst=%.2fus (%s) retained=%.2fKB retainedMixed=%.2fKB growth=%.3fKB worstGrowth=%.3fKB build=%.1fms index=%.0fKB",
      IS_JIT and "luajit" or "lua51",
      index.size,
      mean,
      worstMean,
      table.concat(worstText, " "),
      retained,
      retainedMatching,
      growth,
      worstGrowth,
      ms,
      indexKB
    )
  )
  Assert.equal(index.size, 2000)
  -- Every budget is checked, then all breaches are reported together.
  local breaches = {}
  local function within(value, budget, what)
    if value > budget then
      breaches[#breaches + 1] = string.format("%s %.3f > %d", what, value, budget)
    end
  end
  within(mean, MEAN_US, "mean us/line")
  within(worstMean, WORST_US, "worst case us/line")
  within(retained, RETAINED_KB, "retained KB")
  within(retainedMatching, RETAINED_KB, "retained KB after 5 passes over the mixed lines")
  within(growth, GROWTH_KB, "warm-pass growth KB")
  within(worstGrowth, GROWTH_KB, "typo warm-pass growth KB")
  within(ms, BUILD_MS, "index build ms")
  within(indexKB, INDEX_KB, "idle index KB")
  Assert.equal(#breaches, 0, "over budget: " .. table.concat(breaches, "; "))
  Wow.reset()
end
