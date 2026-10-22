local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Differential check on seeded random indexes and lines: step 4.4 in WordGroups
-- (group-level, precomputed) against an entry-level reference that follows the spec text
-- (§6.3 4.4: intersection, the 6-word cap, profession narrowing, grouping, the profession
-- tie-break; §6.4 ambiguous words and their neighbouring cue words).

local ENCH = 333
local PROFS = { 164, 165, 197, ENCH }
local ORDER = { 333, 164, 197, 165 }
local LOCS =
  { "INVTYPE_WAIST", "INVTYPE_FEET", "INVTYPE_HAND", "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_LEGS", "INVTYPE_2HWEAPON", "INVTYPE_FINGER" }
local WORDS = {
  "belt",
  "boots",
  "feet",
  "gloves",
  "head",
  "helm",
  "chest",
  "robe",
  "legs",
  "2h",
  "sword",
  "plate",
  "mail",
  "leather",
  "cloth",
  "ring",
  "chesty",
  "lf",
  "x",
  "shield",
  "enchant",
  "ench",
  "boot",
  "shoes",
  "waist",
  "bs",
  "tailor",
  "crafter",
  "for",
  "my",
}
local rand, pick = require("tests.helpers.lcg")(1)

local function entryText(entries, n)
  local parts = {}
  for k = 1, n do
    parts[k] = entries[k].character .. "/" .. tostring(entries[k].recipeKey)
  end
  return table.concat(parts, ",")
end

local function randomItemDb(ns)
  local items = {}
  local itemCount = rand(3, 12)
  for id = 1, itemCount do
    items[1000 + id] = { pick(LOCS), 4, rand(1, 4) }
  end
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      local item = items[itemID]
      if item then
        return itemID, "A", "B", item[1], 0, item[2], item[3]
      end
    end,
  })
  local db = ns.Defaults.Db()
  db.settings.extraSlang = { chesty = "chest", footies = "boots", stompers = "boots", kicks = "boots", girdle = "belt", sash = "belt" }
  for c = 1, rand(1, 4) do
    local recipes = {}
    for k = 1, rand(2, 8) do
      local id = 1000 + rand(1, itemCount)
      local hasItem = rand(1, 5) ~= 1
      recipes[100 + rand(1, 20)] = { name = "Recipe " .. (hasItem and id or ("n" .. k)), prof = pick(PROFS), item = hasItem and id or nil, bind = 1 }
    end
    db.characters["C" .. c .. "-Realm"] = { source = "local", enabled = true, realms = {}, professions = {}, recipes = recipes }
  end
  return db
end

local function isIn(list, word)
  for _, x in ipairs(list) do
    if x == word then
      return true
    end
  end
  return false
end

-- §6.4: a cue word (a craftCueWords word or a profession word) right before or after
-- tokens[i], past cueFillerWords only. The lines hold no punctuation.
local function cuedAt(ns, tokens, i)
  for _, step in ipairs({ -1, 1 }) do
    local k = i + step
    while tokens[k] and isIn(ns.Constants.cueFillerWords, tokens[k]) do
      k = k + step
    end
    local t = tokens[k]
    if t and (isIn(ns.Constants.craftCueWords, t) or ns.ProfessionWords.KeyFor(t, false) ~= nil) then
      return true
    end
  end
  return false
end

-- Reference step 4.4 over tokens (and a 4.2 set of entries, or nil). → outcome text,
-- whether the 6-word cap left a word out, and whether a named profession after the first
-- narrowed (the first had no candidate).
local function reference44(ns, index, tokens, set)
  local wordIndex, Slang = index.wordIndex, ns.Slang
  local first, other, named = nil, nil, {}
  for _, t in ipairs(tokens) do
    if wordIndex[t] and first == nil then
      first = t
    elseif wordIndex[t] and other == nil and t ~= first then
      other = t
    end
    local key = ns.ProfessionWords.KeyFor(t, false)
    if key ~= nil and not isIn(named, key) then
      named[#named + 1] = key -- the named professions in line order
    end
  end
  if isIn(named, ENCH) then
    for k = #named, 1, -1 do
      if named[k] == ENCH then
        table.remove(named, k)
      end
    end
    table.insert(named, 1, ENCH) -- Enchanting before any other
  end
  local lists, taken, takenCount, capped = {}, {}, 0, false
  for i, t in ipairs(tokens) do
    local partnered = set ~= nil or cuedAt(ns, tokens, i) or (first ~= nil and first ~= t) or other ~= nil
    local counted = not Slang.ambiguous[t] or partnered
    if (wordIndex[t] or Slang.wordSet[t]) and counted then
      if not taken[t] and takenCount == 6 then
        capped = true
      else
        if wordIndex[t] == nil then
          return "nil", capped
        end
        if not taken[t] then
          taken[t], takenCount = true, takenCount + 1
        end
        lists[#lists + 1] = wordIndex[t]
      end
    end
  end
  local base = set or lists[1]
  if base == nil then
    return "nil", capped
  end
  local inAll = {}
  for _, e in ipairs(base) do
    local all = true
    for _, list in ipairs(lists) do
      local found = false
      for _, x in ipairs(list) do
        found = found or x == e
      end
      all = all and found
    end
    if all then
      inAll[#inAll + 1] = e
    end
  end
  -- The first named profession that keeps a candidate narrows; none keeps one → nothing.
  local kept, later = #named == 0 and inAll or {}, false
  for n, prof in ipairs(named) do
    for _, e in ipairs(inAll) do
      if e.prof == prof then
        kept[#kept + 1] = e
      end
    end
    if #kept > 0 then
      later = n > 1
      break
    end
  end
  local seen, firstOf = {}, {}
  for _, e in ipairs(kept) do
    if not seen[e.group] then
      seen[e.group] = true
      firstOf[#firstOf + 1] = e
    end
  end
  if #firstOf == 0 then
    return "nil", capped
  elseif #firstOf == 1 then
    return "item " .. tostring(firstOf[1].group) .. " " .. entryText(kept, #kept), capped, later
  end
  local counts, rank = {}, {}
  for i, key in ipairs(ORDER) do
    rank[key] = i
  end
  for _, e in ipairs(firstOf) do
    counts[e.prof] = (counts[e.prof] or 0) + 1
  end
  local best, bestCount, bestRank = nil, 0, math.huge
  for _, e in ipairs(firstOf) do
    local n, r = counts[e.prof], rank[e.prof] or math.huge
    if n > bestCount or (n == bestCount and r < bestRank) then
      best, bestCount, bestRank = e.prof, n, r
    end
  end
  local entries = {}
  for _, e in ipairs(kept) do
    if e.prof == best then
      entries[#entries + 1] = e
    end
  end
  return "profession " .. tostring(best) .. " " .. entryText(entries, #entries), capped, later
end

local AMBIGUOUS, CUES, GAPS = { "legs", "head", "feet", "ring", "hands" }, { "crafter", "bs", "tailor", "ench" }, { "for", "my", "x", "lf" }
local NAMES = { "bs", "tailor", "lw", "ench" }

-- A random line: an ambiguous word and a cue word with 0-2 filler or other words between, 1-4
-- words, or a group's own words in random order with 1-3 random words put in anywhere (so the
-- 6-word cap decides lines that still match), and in some two profession words (so a named
-- profession after the first narrows when the first has no candidate).
local function randomTokens(index, all)
  local tokens = {}
  if rand(1, 5) == 1 then
    tokens = { pick(AMBIGUOUS), pick(CUES) }
    for _ = 1, rand(0, 2) do
      table.insert(tokens, 2, pick(GAPS))
    end
    if rand(1, 2) == 1 then
      tokens[1], tokens[#tokens] = tokens[#tokens], tokens[1]
    end
    return tokens
  end
  if #all == 0 or rand(1, 3) ~= 1 then
    for k = 1, rand(1, 4) do
      tokens[k] = pick(WORDS)
    end
    return tokens
  end
  for word in pairs(index.groupWords[pick(all).group] or {}) do
    tokens[#tokens + 1] = word
  end
  table.sort(tokens)
  for k = #tokens, 2, -1 do
    local j = rand(1, k)
    tokens[k], tokens[j] = tokens[j], tokens[k]
  end
  for _ = 1, rand(1, 3) do
    table.insert(tokens, rand(1, #tokens + 1), pick(WORDS))
  end
  if rand(1, 3) == 1 then
    table.insert(tokens, rand(1, #tokens + 1), pick(NAMES))
    table.insert(tokens, rand(1, #tokens + 1), pick(NAMES))
  end
  return tokens
end

local function testWordGroupsDifferential()
  local ns = Fixture.load()
  local checked, cappedHits, enchantHits, namedHits, laterHits, ambiguousSetHits, ambiguousCueHits = 0, 0, 0, 0, 0, 0, 0
  for _ = 1, 60 do
    local db = randomItemDb(ns)
    local index = ns.Index.Build(db, db.settings, {
      ownKey = "C1-Realm",
      professionOrder = function()
        return ORDER
      end,
    })
    ns.Matcher.SetIndex(index)
    local all, ids = {}, {}
    for id in pairs(index.itemIndex) do
      ids[#ids + 1] = id
    end
    table.sort(ids) -- pairs() order differs between runtimes; the line sequence must not
    for _, id in ipairs(ids) do
      for _, e in ipairs(index.itemIndex[id]) do
        all[#all + 1] = e
      end
    end
    for _ = 1, 40 do
      local tokens = randomTokens(index, all)
      local set = nil
      if #all > 0 and rand(1, 3) == 1 then
        set = {}
        for _ = 1, rand(1, 4) do
          local e = pick(all)
          local dup = false
          for _, x in ipairs(set) do
            dup = dup or x == e
          end
          if not dup then
            set[#set + 1] = e
          end
        end
        ns.MatchCandidates.FromList(set)
      end
      local got = "nil"
      if ns.WordGroups.Match(index, tokens, #tokens, "lf", set ~= nil, {}, 0) then
        ns.MatchCandidates.Finish()
        local r = ns.MatchCandidates.result
        got = r.kind .. " " .. tostring(r.kind == "item" and r.group or r.prof) .. " " .. entryText(r.entries, r.entryCount)
      end
      local want, capped, later = reference44(ns, index, tokens, set)
      Assert.equal(got, want, table.concat(tokens, " "))
      checked = checked + (got ~= "nil" and 1 or 0)
      cappedHits = cappedHits + ((capped and got ~= "nil") and 1 or 0)
      local enchant, named, ambiguousSet, ambiguousCued = false, false, false, false
      for i, t in ipairs(tokens) do
        local key = ns.ProfessionWords.KeyFor(t, false)
        enchant = enchant or key == ENCH
        named = named or (key ~= nil and key ~= ENCH)
        ambiguousSet = ambiguousSet or (set ~= nil and ns.Slang.ambiguous[t] == true)
        ambiguousCued = ambiguousCued or (set == nil and ns.Slang.ambiguous[t] == true and cuedAt(ns, tokens, i))
      end
      enchantHits = enchantHits + ((enchant and got ~= "nil") and 1 or 0)
      namedHits = namedHits + ((named and not enchant and got ~= "nil") and 1 or 0)
      laterHits = laterHits + ((later and got ~= "nil") and 1 or 0)
      ambiguousSetHits = ambiguousSetHits + ((ambiguousSet and got ~= "nil") and 1 or 0)
      ambiguousCueHits = ambiguousCueHits + ((ambiguousCued and got ~= "nil") and 1 or 0)
    end
  end
  -- Each rule decides enough matching lines (317 / 16 / 58 / 54 / 19 / 29 / 56 with this seed).
  Assert.truthy(checked > 150, "lines that match: " .. checked)
  Assert.truthy(cappedHits > 10, "matching lines the 6-word cap decided: " .. cappedHits)
  Assert.truthy(enchantHits > 20, "matching lines with an Enchanting word: " .. enchantHits)
  Assert.truthy(namedHits > 20, "matching lines with another profession word: " .. namedHits)
  Assert.truthy(laterHits > 10, "matching lines a named profession after the first narrowed: " .. laterHits)
  Assert.truthy(ambiguousSetHits > 8, "matching lines with a 4.2 set and an ambiguous word: " .. ambiguousSetHits)
  Assert.truthy(ambiguousCueHits > 30, "matching lines with an ambiguous word next to a cue word: " .. ambiguousCueHits)
end

return function()
  testWordGroupsDifferential()
  Wow.reset()
end
