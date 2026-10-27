local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local RecipeMute = ns.RecipeMute or require("CraftAlert.UI.Settings.RecipeMute")

local MarkerState = {}

-- The look of a recipe row's mute switch. `chain` is the recipe's stored rank records, `shown` the
-- record of the rank the row shows (or nil). Muted when every rank is muted; otherwise the shown
-- rank decides between untracked and on. → "hidden" | "muted" | "untracked" | "on"
function MarkerState.Of(chain, shown)
  if #chain == 0 then
    return "hidden"
  end
  local allMuted = true
  for _, recipe in ipairs(chain) do
    allMuted = allMuted and recipe.muted == true
  end
  if allMuted then
    return "muted"
  end
  if shown and RecipeMute.Untracked(shown) then
    return "untracked"
  end
  return "on"
end

ns.MarkerState = MarkerState
return MarkerState
