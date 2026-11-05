local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")

-- Spec §7.2 (Retail only; Forever and Classic have no crafting orders): each local character
-- stores its connected realms at login, and a lead is tagged "Can't send an order (other
-- realm)" when the customer's realm is not among the chosen crafter's. An empty list means
-- "unknown" (Phase 0: GetAutoCompleteRealms returned {} on every probed flavor), never "own
-- realm only" -- for that warning. InScope treats an empty list as no connection. SameGroup
-- and InScope also read a character's manual linkedRealms.
local RealmTag = {}

local gsub = string.gsub
local ipairs = ipairs
local type = type

-- Realms compare with spaces and hyphens removed. Public for the importers (ExportString,
-- CraftScanImport), whose realms CannotOrder compares as stored.
function RealmTag.Strip(realm)
  return (gsub(realm, "[ %-]", ""))
end

local strip = RealmTag.Strip

-- Call at PLAYER_LOGIN, after PlayerName.Init. Writes nothing when the list is unknown or the
-- character is not in the db.
function RealmTag.Store(db, charKey)
  local character = db.characters[charKey]
  local list = FlavorCompat.isRetail and FlavorCompat.GetAutoCompleteRealms() or nil
  if character == nil or type(list) ~= "table" or #list == 0 then
    return
  end
  local realms, seen = {}, {}
  local function add(realm)
    if type(realm) == "string" and realm ~= "" then
      realm = strip(realm)
      if realm ~= "" and not seen[realm] then
        seen[realm] = true
        realms[#realms + 1] = realm
      end
    end
  end
  for _, realm in ipairs(list) do
    add(realm)
  end
  add(PlayerName.RealmOf(charKey))
  character.realms = realms
end

-- → true when the customer cannot send the crafter an order, false when they can, nil when
-- unknown (not Retail, no realm list stored for the crafter, no customer realm). Stored realms
-- are already stripped (Store, and Schema for a hand-edited db), so they compare as they are.
function RealmTag.CannotOrder(db, crafterKey, customerKey)
  if not FlavorCompat.isRetail then
    return nil
  end
  local character = db.characters[crafterKey]
  local realms = character and character.realms
  local customerRealm = PlayerName.RealmOf(customerKey)
  if type(realms) ~= "table" or #realms == 0 or customerRealm == nil then
    return nil
  end
  customerRealm = strip(customerRealm)
  for i = 1, #realms do
    if realms[i] == customerRealm then
      return false
    end
  end
  return true
end

local function holds(list, realm)
  if type(list) ~= "table" or realm == nil then
    return false
  end
  for i = 1, #list do
    if list[i] == realm then
      return true
    end
  end
  return false
end

-- Same realm (two unknown realms count as the same), or either character's connected-realms
-- list holds the other's realm. A missing record or list is no match.
function RealmTag.Connected(db, a, b)
  local realmA, realmB = PlayerName.RealmOf(a), PlayerName.RealmOf(b)
  if realmA == realmB then
    return true
  end
  local charA, charB = db.characters[a], db.characters[b]
  return holds(charA and charA.realms, realmB) or holds(charB and charB.realms, realmA)
end

-- Connected, or either character's manual linkedRealms holds the other's realm. Not
-- transitive: two alts linked from one realm are not SameGroup with each other.
function RealmTag.SameGroup(db, a, b)
  if RealmTag.Connected(db, a, b) then
    return true
  end
  local realmA, realmB = PlayerName.RealmOf(a), PlayerName.RealmOf(b)
  local charA, charB = db.characters[a], db.characters[b]
  return holds(charA and charA.linkedRealms, realmB) or holds(charB and charB.linkedRealms, realmA)
end

-- True when the key is in the player's group: connected to the player's realm, or linked to it
-- (IsLinked, the key's own linkedRealms). The player's own linkedRealms are left out on purpose:
-- they say who may see the player, and reading them would put every alt on a linked realm in
-- scope whenever that character is logged in. With the own realm unknown nothing can be
-- filtered, so everything is in scope.
function RealmTag.InScope(db, key)
  local own = PlayerName.Own()
  if PlayerName.RealmOf(own) == nil then
    return true
  end
  return RealmTag.Connected(db, own, key) or RealmTag.IsLinked(db, key)
end

-- Links or unlinks the own realm on a character's linkedRealms. Does nothing when the
-- character or own realm is unknown.
function RealmTag.SetLinked(db, key, on)
  local character = db.characters[key]
  local ownRealm = PlayerName.RealmOf(PlayerName.Own())
  if character == nil or ownRealm == nil then
    return
  end
  if on then
    if not holds(character.linkedRealms, ownRealm) then
      local list = character.linkedRealms or {}
      list[#list + 1] = ownRealm
      character.linkedRealms = list
    end
    return
  end
  local list = character.linkedRealms
  if type(list) ~= "table" then
    return
  end
  local kept = {}
  for i = 1, #list do
    if list[i] ~= ownRealm then
      kept[#kept + 1] = list[i]
    end
  end
  character.linkedRealms = #kept > 0 and kept or nil
end

function RealmTag.IsLinked(db, key)
  local character = db.characters[key]
  return holds(character and character.linkedRealms, PlayerName.RealmOf(PlayerName.Own()))
end

ns.RealmTag = RealmTag
return RealmTag
