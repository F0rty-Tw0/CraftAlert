local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- The main crafter of a profession: the one character whose `professions[prof].primary` is
-- set. This module is the only writer, so there is one flag per profession (spec §1). Reads
-- are by CrafterRank (§6.3 step 5); nothing here rebuilds the index.
local MainCrafter = {}

local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")

local pairs = pairs

-- One main per group of realms (RealmTag.SameGroup is not transitive, so two in-scope alts linked
-- from one realm count as together too). Whether `key` shares a main with `anchor`; a nil anchor
-- means the player's scope.
local function reaches(db, anchor, key)
  if anchor == nil then
    return RealmTag.InScope(db, key)
  end
  return RealmTag.SameGroup(db, anchor, key) or (RealmTag.InScope(db, anchor) and RealmTag.InScope(db, key))
end

-- Setting the flag clears every other character's it reaches; turning it off touches only `charKey`.
function MainCrafter.Set(db, charKey, prof, on)
  for key, character in pairs(db.characters) do
    local profession = character.professions[prof]
    if profession then
      if key == charKey then
        profession.primary = on
      elseif on and reaches(db, charKey, key) then
        profession.primary = false
      end
    end
  end
end

-- Clears only the characters in the player's scope; other groups keep their main.
function MainCrafter.Clear(db, prof)
  for key, character in pairs(db.characters) do
    local profession = character.professions[prof]
    if profession and RealmTag.InScope(db, key) then
      profession.primary = false
    end
  end
end

-- Old data can flag several characters; the lowest key counts as the main, so the answer
-- never depends on pairs() order. Only characters `anchor` reaches count (nil: the player's scope).
function MainCrafter.Of(db, prof, anchor)
  local main
  for key, character in pairs(db.characters) do
    local profession = character.professions[prof]
    if profession and profession.primary == true and (main == nil or key < main) and reaches(db, anchor, key) then
      main = key
    end
  end
  return main
end

ns.MainCrafter = MainCrafter
return MainCrafter
