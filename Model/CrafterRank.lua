local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")

-- Spec §6.3 step 5: which of the characters that know the matched recipe answers the
-- customer. Runs on matched lines only, so it may call the friend-list API and allocate.
local CrafterRank = {}

local pairs = pairs
local type = type

-- Lower is better: current character, the profession's primary crafter, other characters of
-- this account, imported characters. A crafter the customer cannot send an order to (Retail,
-- realm list known) ranks below all of those. Ties are broken by character name.
local CURRENT, PRIMARY, SAME_ACCOUNT, IMPORTED = 0, 1, 2, 3
local CANNOT_ORDER = 10

local function isIgnored(name)
  local api = _G["C_FriendList"]
  if type(api) == "table" and type(api.IsIgnored) == "function" then
    return api.IsIgnored(name) == true
  end
  local legacy = _G["IsIgnored"]
  return type(legacy) == "function" and legacy(name) == true
end

local function tierOf(character, key, prof)
  if key == PlayerName.Own() then
    return CURRENT
  end
  local profession = character and character.professions and character.professions[prof]
  if profession and profession.primary == true then
    return PRIMARY
  end
  return character and character.source == "import" and IMPORTED or SAME_ACCOUNT
end

-- → characterKey, cannotOrder; nil when the customer is on Blizzard's ignore list (unless
-- opts.skipIgnore, which /ca test passes) or no character qualifies. `result` is the
-- Matcher's reused result: only read here. A match without entries (a profession word) is
-- answered by every enabled character with that profession.
function CrafterRank.Pick(result, customerKey, db, opts)
  if not (opts and opts.skipIgnore) and isIgnored(customerKey) then
    return nil
  end
  local bestKey, bestScore = nil, nil
  local function consider(key, prof)
    local score = tierOf(db.characters[key], key, prof)
    if RealmTag.CannotOrder(db, key, customerKey) == true then
      score = score + CANNOT_ORDER
    end
    if bestKey == nil or score < bestScore or (score == bestScore and key < bestKey) then
      bestKey, bestScore = key, score
    end
  end
  if result.entryCount > 0 then
    for i = 1, result.entryCount do
      local entry = result.entries[i]
      consider(entry.character, entry.prof or result.prof)
    end
  else
    for key, character in pairs(db.characters) do
      if character.enabled ~= false and character.professions[result.prof] then
        consider(key, result.prof)
      end
    end
  end
  if bestKey == nil then
    return nil
  end
  return bestKey, RealmTag.CannotOrder(db, bestKey, customerKey)
end

ns.CrafterRank = CrafterRank
return CrafterRank
