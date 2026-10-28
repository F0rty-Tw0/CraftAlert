local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local BindLookup = ns.BindLookup or require("CraftAlert.Professions.BindLookup")

-- Spec §5.2 stored recipe: how every window reader (ModernReader, ClassicReader) merges one
-- recipe into a character's `recipes`. A merge only adds; the player's mute and a known bind
-- survive it. Also ranks a profession's expansion lines by median recipe ID, names the newest,
-- looks up a line's expansion name, and applies the only-newest rule (OnlyNewest), which does
-- overwrite mutes.
local RecipeStore = {}

local pairs, type = pairs, type
local floor = math.floor
local sort = table.sort

local function sameList(a, b)
  if a == nil or b == nil then
    return a == b
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- Adds the recipe or updates it in place (mute and bind survive; a read with no line keeps the
-- stored one) → whether storage changed.
function RecipeStore.Merge(recipes, recipeKey, fields, professionKey)
  local old = recipes[recipeKey]
  if old == nil then
    fields.prof = professionKey
    recipes[recipeKey] = fields
    return true
  end
  local lineChanged = fields.line ~= nil and old.line ~= fields.line
  local changed = old.item ~= fields.item
    or old.name ~= fields.name
    or old.prof ~= professionKey
    or not sameList(old.ranks, fields.ranks)
    or lineChanged
  if changed then
    if old.item ~= fields.item then
      old.bind = nil
    end
    old.item, old.name, old.prof, old.ranks = fields.item, fields.name, professionKey, fields.ranks
    old.line = fields.line or old.line
  end
  return changed
end

-- Merges the recipe (Merge) → changed, and queues the bind lookup when the output item's bind
-- is unknown.
function RecipeStore.Store(recipes, recipeKey, fields, professionKey)
  local changed = RecipeStore.Merge(recipes, recipeKey, fields, professionKey)
  local recipe = recipes[recipeKey]
  if recipe.item and recipe.bind == nil then
    BindLookup.Queue(recipe.item)
    return changed, true
  end
  return changed, false
end

-- Number keys (spell IDs) of the profession's recipes, grouped by line, each list sorted.
-- Name keys (Classic) and lineless recipes are skipped. `only` limits the pass to one line.
local function keysByLine(recipes, prof, only)
  local byLine = {}
  for key, recipe in pairs(recipes) do
    local line = recipe.line
    if type(key) == "number" and recipe.prof == prof and line ~= nil and (only == nil or line == only) then
      local keys = byLine[line] or {}
      byLine[line] = keys
      keys[#keys + 1] = key
    end
  end
  for _, keys in pairs(byLine) do
    sort(keys)
  end
  return byLine
end

local function median(keys)
  local count = #keys
  local middle = floor(count / 2)
  if count % 2 == 1 then
    return keys[middle + 1]
  end
  return (keys[middle] + keys[middle + 1]) / 2
end

-- Median recipe ID of the profession's recipes in the line, or nil when it has none. The
-- median keeps one stray patched-in recipe from moving a line.
function RecipeStore.LineRank(recipes, prof, line)
  local keys = keysByLine(recipes, prof, line)[line]
  return keys and median(keys) or nil
end

-- The profession's newest line: the highest LineRank (line IDs were renumbered in 8.0, recipe
-- IDs only grow); a tie goes to the higher line ID. Nil when no recipe has a line.
function RecipeStore.NewestLine(recipes, prof)
  local best, bestRank
  for line, keys in pairs(keysByLine(recipes, prof)) do
    local rank = median(keys)
    if bestRank == nil or rank > bestRank or (rank == bestRank and line > best) then
      best, bestRank = line, rank
    end
  end
  return best
end

-- Mutes every lined recipe of the profession outside `line`, unmutes those in it (never
-- writes false) → how many changed. Lineless recipes are untouched.
function RecipeStore.OnlyNewest(recipes, prof, line)
  local changed = 0
  for _, recipe in pairs(recipes) do
    if recipe.prof == prof and recipe.line ~= nil then
      local muted = recipe.line ~= line or nil
      if recipe.muted ~= muted then
        recipe.muted = muted
        changed = changed + 1
      end
    end
  end
  return changed
end

-- The line's expansion name, or nil: an empty name and a client without the call give none.
function RecipeStore.ExpansionName(line)
  local api = _G["C_TradeSkillUI"]
  if type(api) ~= "table" or type(api.GetProfessionInfoBySkillLineID) ~= "function" then
    return nil
  end
  local info = api.GetProfessionInfoBySkillLineID(line)
  local name = type(info) == "table" and info.expansionName
  return type(name) == "string" and name ~= "" and name or nil
end

ns.RecipeStore = RecipeStore
return RecipeStore
