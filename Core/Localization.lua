local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- English only in v1 (spec §11): the English string is the key and is returned as is,
-- so a locale catalog can be added later without touching call sites.
local Localization = {}

function Localization.Text(text, ...)
  if select("#", ...) == 0 then
    return text
  end
  return string.format(text, ...)
end

-- `one` for a count of 1, else `other`, each formatted with the count: ("%d recipe", "%d recipes").
function Localization.Plural(count, one, other)
  return Localization.Text(count == 1 and one or other, count)
end

ns.Localization = Localization
return Localization
