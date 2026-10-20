local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Class-armor spec §4 rule 4: the armor type a class wears, keyed by the class token
-- GetPlayerInfoByGUID returns. Data only. Every flavor uses this table: on Forever and the
-- Classic flavors it is the max-level armor (hunters and shamans wear leather, warriors and
-- paladins mail, before level 40). Tokens a flavor lacks never occur.
local ClassArmor = {}

local ARMOR = {
  WARRIOR = "plate",
  PALADIN = "plate",
  DEATHKNIGHT = "plate",
  HUNTER = "mail",
  SHAMAN = "mail",
  EVOKER = "mail",
  ROGUE = "leather",
  DRUID = "leather",
  MONK = "leather",
  DEMONHUNTER = "leather",
  MAGE = "cloth",
  PRIEST = "cloth",
  WARLOCK = "cloth",
}

-- The why-line label per token, "plate (warrior)", built once so no string is made per line.
local WHY = {}
for token, armor in pairs(ARMOR) do
  WHY[token] = armor .. " (" .. string.lower(token) .. ")"
end

-- Armor word and why label for a class token, or nil, nil for any other value.
function ClassArmor.For(classToken)
  return ARMOR[classToken], WHY[classToken]
end

ns.ClassArmor = ClassArmor
return ClassArmor
