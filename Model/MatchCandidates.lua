local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The candidate entries of one chat line (§6.3 steps 4.1-4.6), their distinct recipes
-- (groups), the profession decision of step 4.4 and the one reused match result. Hot path:
-- no table is created per line. Sets are kept with stamps (entry -> number of the current
-- operation), so nothing needs clearing between lines; Reset drops them on each new index.
local MatchCandidates = {}

local ipairs = ipairs
local HUGE = math.huge

-- The Matcher's result, reused on every call: callers copy what they keep.
local result = { kind = nil, entries = {}, entryCount = 0, group = nil, prof = nil, why = {}, whyCount = 0 }
MatchCandidates.result = result
MatchCandidates.wordWhy = {} -- step 4.4 why tokens, filled by WordGroups (collect, inferArmor)
MatchCandidates.count = 0

local candidates = {}
local count = 0
local groupFirst, groupCount = {}, 0
local stampOf, groupStamp, profStamp, profCount, profRank = {}, {}, {}, {}, {}
local stamp = 0
local entryCount, whyCount = 0, 0
local lastEntryCount, lastWhyCount = 0, 0

-- New index: drop every buffer that holds the old index's entries (stamps, candidates, the
-- last result), so the old index can be collected, and rank professions by order.
function MatchCandidates.Reset(professionOrder)
  stampOf, groupStamp, profStamp, profCount, profRank = {}, {}, {}, {}, {}
  for i, key in ipairs(professionOrder or {}) do
    profRank[key] = i
  end
  candidates, groupFirst = {}, {}
  count, groupCount = 0, 0
  MatchCandidates.count = 0
  for k = 1, lastEntryCount do
    result.entries[k] = nil
  end
  for k = 1, lastWhyCount do
    result.why[k] = nil
  end
  result.kind, result.group, result.prof = nil, nil, nil
  entryCount, whyCount, lastEntryCount, lastWhyCount = 0, 0, 0, 0
  result.entryCount, result.whyCount = 0, 0
end

local function nextStamp()
  stamp = stamp + 1
  return stamp
end

local function addUnique(entry, current)
  if stampOf[entry] ~= current then
    stampOf[entry] = current
    count = count + 1
    candidates[count] = entry
  end
end

function MatchCandidates.FromList(list)
  local current = nextStamp()
  count = 0
  for k = 1, #list do
    addUnique(list[k], current)
  end
  MatchCandidates.count = count
end

-- The entries of records[1..n] (phrase records), each once.
function MatchCandidates.FromRecords(records, n)
  local current = nextStamp()
  count = 0
  for r = 1, n do
    local entries = records[r].entries
    for k = 1, #entries do
      addUnique(entries[k], current)
    end
  end
  MatchCandidates.count = count
end

-- R4 (slot-words spec): whether an entry stays under a slot word. A group without a word set
-- (an enchant, an itemless recipe, an item nobody wears) stays; any other stays when its item
-- has the word, so worn profession gear (an empty set, WordGroups) goes.
local function entryKept(entry, slot, groupWords)
  local words = groupWords[entry.group]
  return words == nil or words[slot] == true
end

-- Whether any entry of a phrase record stays under the slot word.
function MatchCandidates.AnyKept(record, slot, groupWords)
  local entries = record.entries
  for k = 1, #entries do
    if entryKept(entries[k], slot, groupWords) then
      return true
    end
  end
  return false
end

-- FromRecords, but a record r with slotTokens[r] set adds only the entries that stay under it.
function MatchCandidates.FromRecordsFiltered(records, n, slotTokens, groupWords)
  local current = nextStamp()
  count = 0
  for r = 1, n do
    local entries, slot = records[r].entries, slotTokens[r]
    for k = 1, #entries do
      if not slot or entryKept(entries[k], slot, groupWords) then
        addUnique(entries[k], current)
      end
    end
  end
  MatchCandidates.count = count
end

-- The entries of lists[1..n], each once (§6.3 step 4.4: slot words of different slots).
function MatchCandidates.FromLists(lists, n)
  local current = nextStamp()
  count = 0
  for l = 1, n do
    local list = lists[l]
    for k = 1, #list do
      addUnique(list[k], current)
    end
  end
  MatchCandidates.count = count
end

-- The entries of the best enchant: a statSlotIndex list is sorted best first.
function MatchCandidates.FromBest(list)
  local group = list[1].group
  count = 0
  for k = 1, #list do
    if list[k].group == group then
      count = count + 1
      candidates[count] = list[k]
    end
  end
  MatchCandidates.count = count
end

-- Keeps the candidates whose group has word (groupWords: WordGroups); the same as
-- intersecting with wordIndex[word], since a wordIndex list holds whole groups. soft: when no
-- group has word, keep every candidate (nothing was moved) → false.
function MatchCandidates.KeepWord(groupWords, word, soft)
  local kept = 0
  for k = 1, count do
    local entry = candidates[k]
    local words = groupWords[entry.group]
    if words and words[word] then
      kept = kept + 1
      candidates[kept] = entry
    end
  end
  if kept == 0 and soft then
    return false
  end
  count = kept
  MatchCandidates.count = count
  return true
end

-- Keeps the candidates of profession prof (§6.3 step 4.4: a line naming a profession). soft:
-- when no candidate has prof, keep every candidate (nothing was moved) → false.
function MatchCandidates.KeepProf(prof, soft)
  local kept = 0
  for k = 1, count do
    local entry = candidates[k]
    if entry.prof == prof then
      kept = kept + 1
      candidates[kept] = entry
    end
  end
  if kept == 0 and soft then
    return false
  end
  count = kept
  MatchCandidates.count = count
  return true
end

-- The entries of list whose group's word set is marked (marks[set] == mark, WordGroups).
function MatchCandidates.FromListMarked(list, groupWords, marks, mark)
  count = 0
  for k = 1, #list do
    local entry = list[k]
    if marks[groupWords[entry.group]] == mark then
      count = count + 1
      candidates[count] = entry
    end
  end
  MatchCandidates.count = count
end

-- → the number of distinct recipes among the candidates.
function MatchCandidates.GroupCount()
  local current = nextStamp()
  groupCount = 0
  for k = 1, count do
    local group = candidates[k].group
    if groupStamp[group] ~= current then
      groupStamp[group] = current
      groupCount = groupCount + 1
      groupFirst[groupCount] = candidates[k]
    end
  end
  return groupCount
end

local function pushWhy(token)
  whyCount = whyCount + 1
  result.why[whyCount] = token
end
MatchCandidates.Why = pushWhy

function MatchCandidates.WhyList(list, n)
  for k = 1, n do
    pushWhy(list[k])
  end
end

local function begin(kind, group, prof, intentToken)
  result.kind, result.group, result.prof = kind, group, prof
  entryCount, whyCount = 0, 0
  pushWhy(intentToken)
end

-- Item match on the candidates (all of one recipe).
function MatchCandidates.Item(intentToken)
  begin("item", candidates[1].group, candidates[1].prof, intentToken)
  for k = 1, count do
    result.entries[k] = candidates[k]
  end
  entryCount = count
end

function MatchCandidates.Profession(intentToken, prof, token)
  begin("profession", nil, prof, intentToken)
  pushWhy(token)
end

-- Step 4.4 tie-break over firstOfGroup[1..n] (one entry per distinct recipe): the profession
-- with the most distinct recipes, then rank (ProfessionList order). → key or nil.
local function bestProfession(firstOfGroup, n, rank)
  local current = nextStamp()
  for g = 1, n do
    local prof = firstOfGroup[g].prof
    if prof ~= nil then
      if profStamp[prof] ~= current then
        profStamp[prof], profCount[prof] = current, 0
      end
      profCount[prof] = profCount[prof] + 1
    end
  end
  local best, bestCount, bestRank = nil, 0, HUGE
  for g = 1, n do
    local prof = firstOfGroup[g].prof
    if prof ~= nil then
      local seen, order = profCount[prof], rank[prof] or HUGE
      if seen > bestCount or (seen == bestCount and order < bestRank) then
        best, bestCount, bestRank = prof, seen, order
      end
    end
  end
  return best
end
MatchCandidates.BestProfession = bestProfession

-- The same tie-break over recipes already counted per profession: of profs[1..n], the one
-- with the most (counts[prof]), then rank. → key or nil.
function MatchCandidates.BestCounted(profs, n, counts)
  local best, bestCount, bestRank = nil, 0, HUGE
  for k = 1, n do
    local prof = profs[k]
    local seen, order = counts[prof], profRank[prof] or HUGE
    if seen > bestCount or (seen == bestCount and order < bestRank) then
      best, bestCount, bestRank = prof, seen, order
    end
  end
  return best
end

-- One recipe → item match; several → profession match (§6.3 step 4.4). Why: the intent
-- token, then list1[1..n1], then list2[1..n2]. → false when no candidate has a profession.
function MatchCandidates.Decide(intentToken, list1, n1, list2, n2)
  if MatchCandidates.GroupCount() == 1 then
    MatchCandidates.Item(intentToken)
  else
    local prof = bestProfession(groupFirst, groupCount, profRank)
    if prof == nil then
      return false
    end
    begin("profession", nil, prof, intentToken)
    for k = 1, count do
      if candidates[k].prof == prof then
        entryCount = entryCount + 1
        result.entries[entryCount] = candidates[k]
      end
    end
  end
  MatchCandidates.WhyList(list1, n1)
  MatchCandidates.WhyList(list2, n2)
  return true
end

-- Profession match on every candidate, all of prof, when the caller counted several recipes
-- (WordGroups' union). Why: the intent token, then why[1..n].
function MatchCandidates.DecideProfession(intentToken, prof, why, n)
  begin("profession", nil, prof, intentToken)
  for k = 1, count do
    result.entries[k] = candidates[k]
  end
  entryCount = count
  MatchCandidates.WhyList(why, n)
end

local function copyEntries(list)
  for k = 1, #list do
    result.entries[k] = list[k]
  end
  entryCount = #list
end

-- Decide on one word alone, from its precomputed WordGroups info (same outcome as FromList +
-- Decide on its list). → false when no candidate has a profession.
function MatchCandidates.DecideWord(intentToken, info, why, n)
  local entries = info.entries
  if info.groupCount == 1 then
    begin("item", entries[1].group, entries[1].prof, intentToken)
  elseif info.prof == nil then
    return false
  else
    begin("profession", nil, info.prof, intentToken)
  end
  copyEntries(entries)
  MatchCandidates.WhyList(why, n)
  return true
end

-- Among the keys hit by the first token (tokensOf[k] == tokensOf[1]), the one first in
-- ProfessionList order. → key, token.
function MatchCandidates.FirstByOrder(keys, tokensOf, n)
  local token = tokensOf[1]
  local best, bestRank = keys[1], profRank[keys[1]] or HUGE
  for k = 2, n do
    if tokensOf[k] ~= token then
      break
    end
    local rank = profRank[keys[k]] or HUGE
    if rank < bestRank then
      best, bestRank = keys[k], rank
    end
  end
  return best, token
end

-- Publishes the counts and clears what the previous match left past them.
function MatchCandidates.Finish()
  for k = entryCount + 1, lastEntryCount do
    result.entries[k] = nil
  end
  for k = whyCount + 1, lastWhyCount do
    result.why[k] = nil
  end
  lastEntryCount, lastWhyCount = entryCount, whyCount
  result.entryCount, result.whyCount = entryCount, whyCount
end

ns.MatchCandidates = MatchCandidates
return MatchCandidates
