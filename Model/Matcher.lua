local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Tokenizer = ns.Tokenizer or require("CraftAlert.Model.Tokenizer")
local PhraseMatch = ns.PhraseMatch or require("CraftAlert.Model.PhraseMatch")
local StatSlot = ns.StatSlot or require("CraftAlert.Model.StatSlot")
local TypoPass = ns.TypoPass or require("CraftAlert.Model.TypoPass")
local Candidates = ns.MatchCandidates or require("CraftAlert.Model.MatchCandidates")
local WordGroups = ns.WordGroups or require("CraftAlert.Model.WordGroups")

-- Hot path, spec §6.3 steps 1-4: gate, prefilter + tokenize, intent, match. Reads only the
-- index (never CraftAlertDB or settings), calls no Blizzard API but issecretvalue, and
-- creates no table or closure per line: buffers are module-level and reused. A match fills
-- the one module-level `result`; callers copy what they keep.
local Matcher = {}

local find = string.find
local byte = string.byte
local type = type
local issecretvalue = FlavorCompat.issecretvalue
local Normalize = PlayerName.Normalize
local Scan, Tokenize = Tokenizer.Scan, Tokenizer.Tokenize
local tokens, itemIDs = Tokenizer.tokens, Tokenizer.itemIDs

local result = Candidates.result
---@type table
local index = nil
local tokenCount = 0
local intentToken = nil

Matcher.lastStop = "nomatch"

-- Stores the index and hands its intent list to the Tokenizer (an Index.OnRebuilt callback).
function Matcher.SetIndex(newIndex)
  index = newIndex
  Tokenizer.Configure(newIndex.intentList)
  Candidates.Reset(newIndex.professionOrder)
  PhraseMatch.Reset()
  WordGroups.Reset()
  TypoPass.Reset()
end

local function stop(reason)
  Matcher.lastStop = reason
  return nil
end

local WHISPER_ME = "/w me"
local WHISPER_ME_END = #WHISPER_ME

-- A byte of Tokenizer.WORD (letters, digits, apostrophe, bytes 128-255) in lowercase text.
local function isWordByte(b)
  return (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or b == 39 or b >= 128
end

-- "/w me" as a whole word ("/w me", "/w me." but not "/w meow").
local function whisperMe(lower)
  local at = find(lower, WHISPER_ME, 1, true)
  while at do
    local after = byte(lower, at + WHISPER_ME_END)
    if after == nil or not isWordByte(after) then
      return true
    end
    at = find(lower, WHISPER_ME, at + 1, true)
  end
  return false
end

-- Step 3: an intent token, then no blocker token and no ad shape. → stop reason or nil.
local function intentStop(lower)
  local intentSet, blockerSet = index.intentSet, index.blockerSet
  local blocked, crafting, pst, ad, canCraft = false, false, false, false, false
  intentToken = nil
  for i = 1, tokenCount do
    local token = tokens[i]
    if intentToken == nil and intentSet[token] then
      intentToken = token
    end
    if blockerSet[token] then
      blocked = true
    elseif token == "crafting" then
      crafting = true
    elseif token == "pst" then
      pst = true
      ad = ad or crafting -- "crafting ... pst"
    elseif token == "craft" and tokens[i - 1] == "can" then
      canCraft = true
    end
  end
  if intentToken == nil then
    return "intent"
  end
  if blocked or ad or (canCraft and pst) or whisperMe(lower) then
    return "blocker"
  end
  return nil
end

-- Step 4.1: the first item link whose ID is indexed.
local function matchItemLink()
  for k = 1, Tokenizer.itemCount do
    local list = index.itemIndex[itemIDs[k]]
    if list then
      Candidates.FromList(list)
      Candidates.Item(intentToken)
      Candidates.Why(itemIDs[k])
      return true
    end
  end
  return false
end

-- Step 4.3: stat + slot names the best enchant.
local function matchStatSlot()
  local list, slot, stat = StatSlot.Find(index, tokens, tokenCount)
  if list == nil then
    return false
  end
  Candidates.FromBest(list)
  Candidates.Item(intentToken)
  Candidates.Why(slot)
  Candidates.Why(stat)
  return true
end

-- Step 4.4 (WordGroups). hasSet: step 4.2 left several recipes in Candidates.
local function matchWords(hasSet)
  return WordGroups.Match(index, tokens, tokenCount, intentToken, hasSet, PhraseMatch.why, PhraseMatch.whyCount)
end

-- Step 4.5: the typo pass, only after steps 4.1-4.4 found nothing. hasPhrase: step 4.2 kept
-- a hit, which (like a wordIndex word) lets kind-c aliases and one-word full names count
-- (§6.2 item 1).
local function matchTypos(hasPhrase)
  if TypoPass.Run(index, tokens, tokenCount, hasPhrase or PhraseMatch.HasIndexWord()) == 0 then
    return false
  end
  Candidates.FromRecords(TypoPass.records, TypoPass.recordCount)
  return Candidates.Decide(intentToken, nil, 0, TypoPass.why, TypoPass.whyCount)
end

-- Step 4.6: the first profession word, else the first typo hit on a profession word.
local function matchProfessionWord()
  if not index.professionWordAlerts then
    return false
  end
  local professionWords = index.professionWords
  for i = 1, tokenCount do
    local key = professionWords[tokens[i]]
    if key ~= nil then
      Candidates.Profession(intentToken, key, tokens[i])
      return true
    end
  end
  if TypoPass.profCount == 0 then
    return false
  end
  local key, token = Candidates.FirstByOrder(TypoPass.profs, TypoPass.profTokens, TypoPass.profCount)
  Candidates.Profession(intentToken, key, token)
  return true
end

local function matchTokens()
  if matchItemLink() then
    return true
  end
  local phrases = PhraseMatch.Run(index, tokenCount, intentToken)
  if phrases == "match" then
    return true
  end
  local hasSet = phrases == "set"
  return matchStatSlot() or matchWords(hasSet) or matchTypos(hasSet) or matchProfessionWord()
end

-- Steps 2-4 without the gate (/ca test). → result or nil; lastStop says why.
function Matcher.MatchUngated(text)
  if index == nil or type(text) ~= "string" then
    return stop("nomatch")
  end
  local lower = Scan(text)
  if lower == nil then
    return stop("prefilter")
  end
  tokenCount = Tokenize(lower)
  local reason = intentStop(lower)
  if reason then
    return stop(reason)
  end
  if not matchTokens() then
    return stop("nomatch")
  end
  Candidates.Finish()
  Matcher.lastStop = "match"
  return result
end

-- Steps 1-4. channelKey: a ScanGate.ChannelKey value ("trade", "services", ...).
function Matcher.Match(channelKey, text, sender)
  if index == nil or not index.channelEnabled[channelKey] then
    return stop("channel")
  end
  if issecretvalue(text) or issecretvalue(sender) then
    return stop("secret")
  end
  local key = Normalize(sender)
  if key ~= nil and key == index.ownName then
    return stop("self")
  end
  if key ~= nil and index.blockSet[key] then
    return stop("blocked")
  end
  return Matcher.MatchUngated(text)
end

ns.Matcher = Matcher
return Matcher
