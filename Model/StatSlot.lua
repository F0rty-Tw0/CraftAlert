local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Slang = ns.Slang or require("CraftAlert.Model.Slang")

-- Spec §6.2 item 4 and §6.3 step 4.3: enchants found by stat + slot ("+8stam to chest").
-- Build side (inside Index.Build): statSlotIndex[slotWord][statKey] = { entry, ... }, best
-- enchant first. Find is hot path: no table or closure per line.
local StatSlot = {}

local pairs = pairs
local ipairs = ipairs
local type = type
local sub = string.sub
local byte = string.byte
local sort = table.sort

local DIGIT_0, DIGIT_9 = 48, 57
local DEFAULT_TIER = 3

-- Stat word -> stat key.
StatSlot.statWords = {
  stamina = "stamina",
  stam = "stamina",
  sta = "stamina",
  intellect = "intellect",
  int = "intellect",
  agility = "agility",
  agi = "agility",
  strength = "strength",
  str = "strength",
  spirit = "spirit",
  spi = "spirit",
  defense = "defense",
  def = "defense",
  health = "health",
  hp = "health",
  mana = "mana",
  mp = "mana",
}
local statWords = StatSlot.statWords

-- Best enchant order: minor < lesser < (none) < greater < superior < major.
local TIERS = { minor = 1, lesser = 2, greater = 4, superior = 5, major = 6 }

local ranks = {} -- entry -> { tier, name } while a build runs

local slotCache = {} -- Slang is static data, so the merged lists never change

-- Slang.slots lists holding the slot word, merged, without the Slang.wordGroupsOnly words
-- (user ruling 2026-10-22); just the word when none does ("weapon").
local function slotWords(slot)
  if slotCache[slot] then
    return slotCache[slot]
  end
  local words, seen = {}, {}
  for _, list in pairs(Slang.slots) do
    for _, word in ipairs(list) do
      if word == slot then
        for _, other in ipairs(list) do
          if not seen[other] and not Slang.wordGroupsOnly[other] then
            seen[other] = true
            words[#words + 1] = other
          end
        end
      end
    end
  end
  if #words == 0 then
    words[1] = slot
  end
  sort(words)
  slotCache[slot] = words
  return words
end

-- The highest tier word in the name; DEFAULT_TIER when it has none.
local function tierOf(words)
  local tier = nil
  for _, word in ipairs(words) do
    local rank = TIERS[word]
    if rank and (tier == nil or rank > tier) then
      tier = rank
    end
  end
  return tier or DEFAULT_TIER
end

function StatSlot.Begin(index)
  index.statSlotIndex, index.enchantSlotWords = {}, {}
  ranks = {}
end

-- An "enchant <slot> ... <stat>" name (normalized words) adds its entry under every slot
-- word of that slot and every stat in the name. Every "enchant <slot>" name, stat or not,
-- adds the slot words to enchantSlotWords (companions, §6.2 item 1).
function StatSlot.Add(index, name, words, entry)
  if words[1] ~= "enchant" or words[2] == nil then
    return
  end
  for _, slot in ipairs(slotWords(words[2])) do
    index.enchantSlotWords[slot] = true
  end
  for k = 3, #words do
    local stat = statWords[words[k]]
    if stat then
      ranks[entry] = { tier = tierOf(words), name = name }
      for _, slot in ipairs(slotWords(words[2])) do
        local byStat = index.statSlotIndex[slot] or {}
        index.statSlotIndex[slot] = byStat
        local list = byStat[stat] or {}
        byStat[stat] = list
        if list[#list] ~= entry then
          list[#list + 1] = entry
        end
      end
    end
  end
end

-- Best enchant first: tier, then numeric recipeKeys before name keys (Classic), the larger
-- number first, then name, then character. Ranking the key type first keeps the order
-- transitive when both kinds of key meet (sort raises "invalid order function" otherwise).
local function better(a, b)
  local ra, rb = ranks[a], ranks[b]
  if ra.tier ~= rb.tier then
    return ra.tier > rb.tier
  end
  local ka, kb = a.recipeKey, b.recipeKey
  local na, nb = type(ka) == "number", type(kb) == "number"
  if na ~= nb then
    return na
  end
  if na and ka ~= kb then
    return ka > kb
  end
  if ra.name ~= rb.name then
    return ra.name < rb.name
  end
  return a.character < b.character
end

-- pause = fn(weight) from Aliases.Build: a comparator can't yield, so it runs between sorts,
-- weighed by the sorted list's length.
function StatSlot.Finish(index, pause)
  for _, byStat in pairs(index.statSlotIndex) do
    for _, list in pairs(byStat) do
      sort(list, better)
      pause(#list)
    end
  end
  ranks = {}
end

-- A stat key for a token, also for "8stam"-style tokens (digits, then the stat word).
local function statOf(token)
  local key = statWords[token]
  local first = byte(token, 1)
  if key == nil and first >= DIGIT_0 and first <= DIGIT_9 then
    -- A byte walk, not find(token, "^%d+"): the pattern matcher costs more per token (§4.4).
    local after = 2
    local b = byte(token, after)
    while b and b >= DIGIT_0 and b <= DIGIT_9 do
      after = after + 1
      b = byte(token, after)
    end
    if b == nil then
      return nil -- all digits: no stat word left
    end
    key = statWords[sub(token, after)]
  end
  return key
end

-- Per-line buffers of Find: the line's distinct stat keys in line order, each with the first
-- token that gave it, and the slot tables already tried (stamped, weak keys).
local lineKeys, lineKeyTokens, lineKeyCount = {}, {}, 0
local triedStamp = setmetatable({}, { __mode = "k" })
local stamp = 0

local function collectStatKeys(tokens, count)
  lineKeyCount = 0
  for j = 1, count do
    local key = statOf(tokens[j])
    if key then
      local known = false
      for k = 1, lineKeyCount do
        known = known or lineKeys[k] == key
      end
      if not known then
        lineKeyCount = lineKeyCount + 1
        lineKeys[lineKeyCount], lineKeyTokens[lineKeyCount] = key, tokens[j]
      end
    end
  end
  return lineKeyCount
end

-- Step 4.3: the first slot word with entries, with the first stat word that has some for
-- it. → the best-first entry list, the slot token and the stat token; nil when none. Each
-- token's stat key is read once and each slot word tried once, so a line costs O(tokens).
function StatSlot.Find(index, tokens, count)
  if collectStatKeys(tokens, count) == 0 then
    return nil
  end
  stamp = stamp + 1
  local statSlotIndex = index.statSlotIndex
  for i = 1, count do
    local byStat = statSlotIndex[tokens[i]]
    if byStat and triedStamp[byStat] ~= stamp then
      triedStamp[byStat] = stamp
      for k = 1, lineKeyCount do
        local list = byStat[lineKeys[k]]
        if list then
          return list, tokens[i], lineKeyTokens[k]
        end
      end
    end
  end
  return nil
end

ns.StatSlot = StatSlot
return StatSlot
