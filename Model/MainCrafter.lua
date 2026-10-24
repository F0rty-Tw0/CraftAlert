local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The main crafter of a profession: the one character whose `professions[prof].primary` is
-- set. This module is the only writer, so there is one flag per profession (spec §1). Reads
-- are by CrafterRank (§6.3 step 5); nothing here rebuilds the index.
local MainCrafter = {}

local pairs = pairs

-- Setting the flag clears every other character's; turning it off touches only `charKey`.
function MainCrafter.Set(db, charKey, prof, on)
  for key, character in pairs(db.characters) do
    local profession = character.professions[prof]
    if profession and (key == charKey or on) then
      profession.primary = key == charKey and on
    end
  end
end

function MainCrafter.Clear(db, prof)
  for _, character in pairs(db.characters) do
    local profession = character.professions[prof]
    if profession then
      profession.primary = false
    end
  end
end

-- Old data can flag several characters; the lowest key counts as the main, so the answer
-- never depends on pairs() order.
function MainCrafter.Of(db, prof)
  local main
  for key, character in pairs(db.characters) do
    local profession = character.professions[prof]
    if profession and profession.primary == true and (main == nil or key < main) then
      main = key
    end
  end
  return main
end

ns.MainCrafter = MainCrafter
return MainCrafter
