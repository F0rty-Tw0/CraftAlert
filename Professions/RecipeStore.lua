local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Spec §5.2 stored recipe: how every window reader (ModernReader, ClassicReader) merges one
-- recipe into a character's `recipes`. Reads only add; the player's mute and a known bind survive.
local RecipeStore = {}

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

ns.RecipeStore = RecipeStore
return RecipeStore
