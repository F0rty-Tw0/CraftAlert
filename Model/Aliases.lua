local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Tokenizer = ns.Tokenizer or require("CraftAlert.Model.Tokenizer")
local Slang = ns.Slang or require("CraftAlert.Model.Slang")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")
local StatSlot = ns.StatSlot or require("CraftAlert.Model.StatSlot")
local PhraseMatch = ns.PhraseMatch or require("CraftAlert.Model.PhraseMatch")

-- Spec §6.2 "Short names, typos and stat + slot": the phrase records behind nameIndex and the
-- structures built from them (phraseSet, needsSecondWord, joinIndex; PhraseMatch files each
-- record by shape, StatSlot fills statSlotIndex, and TypoPass builds typoBuckets from the same
-- records).
-- Runs inside Index.Build only, never per chat line, so it may allocate freely.
local Aliases = {}

local pairs = pairs
local ipairs = ipairs
local find = string.find
local sub = string.sub
local gmatch = string.gmatch
local concat = table.concat
local sort = table.sort

local MIN_UNIQUE_LETTERS = 5 -- kind c words
local MIN_JOIN_LETTERS = 6
local MIN_SPLIT_SIDE = 2

-- "enchant bracer - minor health" -> "enchant bracer minor health", { words }; the form
-- Tokenizer.normalized uses. nil for a name without word characters.
function Aliases.Normalize(name)
  local words = {}
  for word in gmatch(name, Tokenizer.WORD) do
    words[#words + 1] = word
  end
  if #words == 0 then
    return nil
  end
  return concat(words, " "), words
end

local function addAll(set, list)
  for _, word in ipairs(list) do
    set[word] = true
  end
end

-- §6.2 item 2: words that cannot make an alias on their own.
local function guardSet(index)
  local guard = { weapon = true }
  addAll(guard, Constants.aliasStopWords)
  for word in pairs(Slang.wordSet) do
    guard[word] = true
  end
  for word in pairs(StatSlot.statWords) do
    guard[word] = true
  end
  for _, entry in ipairs(ProfessionWords.entries) do
    addAll(guard, entry.words)
  end
  for _, set in ipairs({ index.intentSet, index.blockerSet }) do
    for word in pairs(set) do
      guard[word] = true
    end
  end
  return guard
end

-- word -> the one group whose names hold it, or false when several do (kind c).
local function uniqueWords(parsed, names)
  local owner = {}
  for _, item in ipairs(names) do
    local info = parsed[item.name]
    if info and not item.pending then
      for _, word in ipairs(info.words) do
        local seen = owner[word]
        if seen == nil then
          owner[word] = item.entry.group
        elseif seen ~= item.entry.group then
          owner[word] = false
        end
      end
    end
  end
  return owner
end

local function guarded(guard, words, first, last)
  for k = first, last do
    if not guard[words[k]] then
      return false
    end
  end
  return true
end

-- Appends words[first..last] to list as (phrase, first word, word count, kind c) when it is a
-- new, unguarded alias.
local function addAlias(list, seen, guard, words, first, last, kindC)
  if guarded(guard, words, first, last) then
    return
  end
  local phrase = first == last and words[first] or concat(words, " ", first, last)
  if not seen[phrase] then
    seen[phrase] = true
    local n = #list
    list[n + 1], list[n + 2], list[n + 3], list[n + 4] = phrase, words[first], last - first + 1, kindC
  end
end

-- → alias quads of one recipe name (kinds a, b, c), guarded and without the full name; a
-- phrase of two kinds is listed once, as the first.
local function aliasesOf(name, info, group, owner, guard)
  local list, seen, words = {}, { [info.phrase] = true }, info.words
  local dash = find(name, " - ", 1, true)
  if dash then
    local _, suffix = Aliases.Normalize(sub(name, dash + 3))
    if suffix then
      addAlias(list, seen, guard, suffix, 1, #suffix, false) -- kind a
    end
  end
  local n = #words
  if n > 2 then -- kind b: the first two and the last two words (a 2-word name is its full name)
    addAlias(list, seen, guard, words, 1, 2, false)
    addAlias(list, seen, guard, words, n - 1, n, false)
  end
  for k, word in ipairs(words) do -- kind c
    if #word >= MIN_UNIQUE_LETTERS and owner[word] == group then
      addAlias(list, seen, guard, words, k, k, true)
    end
  end
  return list
end

local function addEntry(record, entry)
  local entries = record.entries
  if entries[#entries] ~= entry then
    entries[#entries + 1] = entry
  end
end

-- One record per phrase; a phrase that is some recipe's full name is a full record.
local function recordFor(index, records, phrase, firstWord, wordCount, full)
  local record = records[phrase]
  if record == nil then
    record = { phrase = phrase, entries = {}, full = false, wordCount = wordCount }
    records[phrase] = record
    local list = index.nameIndex[firstWord] or {}
    index.nameIndex[firstWord] = list
    list[#list + 1] = record
    PhraseMatch.Add(index, record, firstWord)
  end
  if full and not record.full then
    record.full = true
    index.phraseSet[phrase] = record
  end
  return record
end

local function shorterPhrase(a, b)
  if #a.phrase ~= #b.phrase then
    return #a.phrase < #b.phrase
  end
  return a.phrase < b.phrase
end

-- §6.2 item 3: every one-word record of 6+ letters, split with 2+ letters on each side.
-- joinIndex[left] = the record, or a list of the records (shortest phrase first), whose phrase
-- starts with left (the Matcher checks the right side's bytes): no table and no string per
-- right side.
local function addJoins(index, records)
  local joinIndex = index.joinIndex
  for phrase, record in pairs(records) do
    local length = #phrase
    if record.wordCount == 1 and length >= MIN_JOIN_LETTERS then
      for split = MIN_SPLIT_SIDE, length - MIN_SPLIT_SIDE do
        local left = sub(phrase, 1, split)
        local found = joinIndex[left]
        if found == nil then
          joinIndex[left] = record
        elseif found.phrase then
          joinIndex[left] = { found, record }
        else
          found[#found + 1] = record
        end
      end
    end
  end
  for _, found in pairs(joinIndex) do
    if not found.phrase then
      sort(found, shorterPhrase)
    end
  end
end

-- Records and itemIndex lists that hold the same entries in the same order share one list:
-- most aliases list exactly their recipe's entries, so this saves a table per alias (§4.4
-- index memory). A list is compared with the first list seen that starts with the same entry
-- (no key strings: the build budget is tight). Every list is read-only once the index is built.
local function sameEntries(a, b)
  if #a ~= #b then
    return false
  end
  for k = 2, #a do
    if a[k] ~= b[k] then
      return false
    end
  end
  return true
end

-- byFirst is a parameter: a LuaJIT trace keeps a called closure, so its upvalues, alive.
local function canonical(byFirst, list)
  local found = byFirst[list[1]]
  if found == nil then
    byFirst[list[1]] = list
    return list
  end
  return sameEntries(found, list) and found or list
end

local function shareEntryLists(index, records)
  local byFirst, itemIndex = {}, index.itemIndex
  for itemID, list in pairs(itemIndex) do
    itemIndex[itemID] = canonical(byFirst, list)
  end
  for _, record in pairs(records) do
    record.entries = canonical(byFirst, record.entries)
  end
end

-- needsSecondWord[record] = true: one token matching the record counts only beside a second
-- word in the line (§6.2 item 1, user rulings 2026-10-20). Holds one-word full names, and
-- aliases that every name made as kind c. A set, not a record field: a fifth field would
-- double the hash part of each such record.
local function markKind(needsSecondWord, notKindC, record, isKindC)
  if not isKindC then
    needsSecondWord[record], notKindC[record] = nil, true
  elseif not notKindC[record] then
    needsSecondWord[record] = true
  end
end

-- names = { { name = lowercase recipe name, entry = entry, pending = true|nil }, ... } in
-- build order. Fills index.nameIndex, phraseSet, needsSecondWord, phraseIds, phraseKeys,
-- phraseWordRange, joinIndex and statSlotIndex; intentSet and blockerSet must already be set.
function Aliases.Build(index, names)
  index.phraseSet, index.needsSecondWord, index.joinIndex = {}, {}, {}
  local notKindC = {}
  PhraseMatch.Begin(index)
  StatSlot.Begin(index)
  local parsed, fullNames = {}, {}
  for _, item in ipairs(names) do
    if parsed[item.name] == nil then
      local phrase, words = Aliases.Normalize(item.name)
      parsed[item.name] = phrase and { phrase = phrase, words = words } or false
      if phrase then
        fullNames[phrase] = true
      end
    end
  end
  local owner, guard = uniqueWords(parsed, names), guardSet(index)
  local records = {}
  for _, item in ipairs(names) do
    local info = parsed[item.name]
    if info then
      local words, entry = info.words, item.entry
      local full = recordFor(index, records, info.phrase, words[1], #words, true)
      addEntry(full, entry)
      if #words == 1 then
        index.needsSecondWord[full] = true -- a one-word full name ("Shadowfang")
      end
      if not item.pending then
        if info.aliasGroup ~= entry.group then -- aliases depend on the group (kind c)
          info.aliases, info.aliasGroup = aliasesOf(item.name, info, entry.group, owner, guard), entry.group
        end
        local aliases = info.aliases
        for k = 1, #aliases, 4 do
          -- §6.3 4.2: a full name beats its own alias, so a phrase that is some recipe's full
          -- name holds full-name entries only.
          if not fullNames[aliases[k]] then
            local record = recordFor(index, records, aliases[k], aliases[k + 1], aliases[k + 2], false)
            addEntry(record, entry)
            markKind(index.needsSecondWord, notKindC, record, aliases[k + 3])
          end
        end
        StatSlot.Add(index, item.name, words, entry)
      end
    end
  end
  StatSlot.Finish(index)
  addJoins(index, records)
  shareEntryLists(index, records)
end

ns.Aliases = Aliases
return Aliases
