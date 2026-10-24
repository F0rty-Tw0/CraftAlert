local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")

-- Spec §6.3 step 5: which of the characters that know the matched recipe answers the
-- customer. Runs on matched lines only, so it may call the friend-list API and allocate.
local CrafterRank = {}

local pairs = pairs
local type = type

-- Tier, lower is better: the profession's primary crafter, the current character, other
-- characters of this account, imported characters.
local PRIMARY, CURRENT, SAME_ACCOUNT, IMPORTED = 0, 1, 2, 3

function CrafterRank.IsIgnored(name)
  local api = _G["C_FriendList"]
  if type(api) == "table" and type(api.IsIgnored) == "function" then
    return api.IsIgnored(name) == true
  end
  local legacy = _G["IsIgnored"]
  return type(legacy) == "function" and legacy(name) == true
end

local function tierOf(character, key, prof)
  local profession = character and character.professions and character.professions[prof]
  if profession and profession.primary == true then
    return PRIMARY
  end
  if key == PlayerName.Own() then
    return CURRENT
  end
  return character and character.source == "import" and IMPORTED or SAME_ACCOUNT
end

-- Whether a character takes profession-word leads (step 4.6) for `prof`: not when it stores
-- recipes of that profession and has muted every one; muting says "no leads for these". A
-- profession not read yet has no recipes and still counts. Index.Build notes the muted
-- professions, so this is a lookup, not a walk over the recipes.
local function listensFor(key, prof)
  local index = Index.Current()
  local muted = index and index.mutedProfessions[key]

  return not (muted and muted[prof])
end

-- Concentration `key` can spend on currency `id` now. The current character reads the live
-- currency; another one projects its saved snapshot by the recharge cycles since `at`. No
-- snapshot, no API: 0, so concentration does not count.
local function available(db, key, id)
  if key == PlayerName.Own() then
    local api = _G["C_CurrencyInfo"]
    local info = type(api) == "table" and type(api.GetCurrencyInfo) == "function" and api.GetCurrencyInfo(id)
    return type(info) == "table" and type(info.quantity) == "number" and info.quantity or 0
  end
  local character = db.characters[key]
  local saved = character and character.concentration and character.concentration[id]
  if not saved then
    return 0
  end
  local cycles = math.max(0, math.floor((_G["time"]() - saved.at) * 1000 / saved.cycleMs))

  return math.min(saved.max, saved.amount + cycles * saved.perCycle)
end

-- The quality rank `key` can reach for one recipe → rank, top, byConc; nil without reach data or
-- `ranks`. One rank more when concentration pays for it. Reads the db, not the index, so a
-- finished reach is seen at once.
local function effectiveRank(db, key, recipeKey)
  local character = db.characters[key]
  local recipe = character and character.recipes and character.recipes[recipeKey]
  local reached = recipe and recipe.reachRank
  local top = recipe and recipe.ranks and #recipe.ranks
  if not (reached and top and top > 0) then
    return nil
  end
  local cost = recipe.reachCost or 0
  local canGoHigher = cost > 0 and reached < top
  local byConc = canGoHigher and available(db, key, recipe.reachConc) >= cost

  return byConc and reached + 1 or reached, top, byConc
end

-- Whether entry `a` ranks above `b` (nil: nothing yet). Best first: can order, higher rank /
-- #ranks (no rank last), the rank reached without concentration, tier, name. Equal entries of one
-- character keep the first.
local function better(a, b)
  if b == nil then
    return true
  end
  if a.cannot ~= b.cannot then
    return a.cannot < b.cannot
  end
  if a.fraction ~= b.fraction then
    return a.fraction > b.fraction
  end
  if a.conc ~= b.conc then
    return a.conc < b.conc
  end
  if a.tier ~= b.tier then
    return a.tier < b.tier
  end
  return a.key < b.key
end

-- Fills `probe` in full with one character's entry for `better`; reused, so it allocates nothing.
local function fill(probe, db, key, prof, recipeKey, rank, top, byConc, cannot)
  probe.key = key
  probe.cannot = cannot and 1 or 0
  probe.fraction = rank and rank / top or -1
  probe.conc = byConc and 1 or 0
  probe.tier = tierOf(db.characters[key], key, prof)
  probe.rank = rank
  probe.top = top
  probe.byConc = byConc
  probe.recipeKey = recipeKey
  probe.prof = prof
end

-- A lookup of RealmTag.CannotOrder for one customer, asked once per character: an entry per
-- recipe names the same few characters again and again. → function(key) → true, false or nil.
local function cannotOrderFor(db, customerKey)
  local cannotOrderBy, asked = {}, {}
  return function(key)
    if not asked[key] then
      asked[key] = true
      cannotOrderBy[key] = RealmTag.CannotOrder(db, key, customerKey)
    end
    return cannotOrderBy[key]
  end
end

-- → characterKey, cannotOrder, rank, byConc, recipeKey, candidates; nil when the customer is on
-- Blizzard's ignore list (unless opts.skipIgnore, which only the Settings Test page passes) or no
-- character qualifies. Order of `better`. A character is judged by its best entry; rank, byConc
-- and recipeKey come from the winning entry (nil for a profession word). `candidates` is one
-- { key, rank, byConc, top, recipeKey, prof } per qualifying character, its best entry, in no set
-- order; CrafterRank.Repick judges them again. `result` is the Matcher's reused result: only read
-- here. A match without entries (a profession word) is answered by every enabled character with
-- that profession that still listens for it.
function CrafterRank.Pick(result, customerKey, db, opts)
  if not (opts and opts.skipIgnore) and CrafterRank.IsIgnored(customerKey) then
    return nil
  end
  local cannotOrder = cannotOrderFor(db, customerKey)
  -- Each entry is judged in `probe`, which every call fills in full. A winner keeps its table and
  -- the one it beat becomes the next probe, so a character's many entries allocate nothing.
  local bestBy, probe = {}, {}
  local function consider(key, prof, recipeKey)
    local rank, top, byConc = effectiveRank(db, key, recipeKey)
    fill(probe, db, key, prof, recipeKey, rank, top, byConc, cannotOrder(key) == true)
    local held = bestBy[key]
    if better(probe, held) then
      bestBy[key] = probe
      probe = held or {}
    end
  end
  if result.entryCount > 0 then
    for i = 1, result.entryCount do
      local entry = result.entries[i]
      consider(entry.character, entry.prof or result.prof, entry.recipeKey)
    end
  else
    for key, character in pairs(db.characters) do
      local candidate = character.enabled ~= false and character.professions[result.prof] ~= nil
      if candidate and listensFor(key, result.prof) then
        consider(key, result.prof, nil)
      end
    end
  end
  local best
  local candidates = {}
  for key, entry in pairs(bestBy) do
    candidates[#candidates + 1] = {
      key = key,
      rank = entry.rank,
      byConc = entry.byConc,
      top = entry.top,
      recipeKey = entry.recipeKey,
      prof = entry.prof,
    }
    if better(entry, best) then
      best = entry
    end
  end
  if best == nil then
    return nil
  end

  return best.key, cannotOrder(best.key), best.rank, best.byConc, best.recipeKey, candidates
end

-- Pick again over the candidates a lead kept, with the db as it is now (the main crafter may
-- have moved). Rank, top and byConc are the ones Pick found; the tier and can-order are read
-- anew. → characterKey, cannotOrder, rank, byConc, recipeKey; nil without candidates. No
-- ignore-list check: the lead exists.
function CrafterRank.Repick(lead, db)
  local candidates = lead.crafters
  if type(candidates) ~= "table" then
    return nil
  end
  local cannotOrder = cannotOrderFor(db, lead.customer)
  local best, probe = nil, {}
  for i = 1, #candidates do
    local c = candidates[i]
    fill(probe, db, c.key, c.prof, c.recipeKey, c.rank, c.top, c.byConc, cannotOrder(c.key) == true)
    if better(probe, best) then
      best, probe = probe, best or {}
    end
  end
  if best == nil then
    return nil
  end

  return best.key, cannotOrder(best.key), best.rank, best.byConc, best.recipeKey
end

ns.CrafterRank = CrafterRank
return CrafterRank
