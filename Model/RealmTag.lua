local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")

-- Spec §7.2 (Retail only; Forever and Classic have no crafting orders): each local character
-- stores its connected realms at login, and a lead is tagged "can't order" when the customer's
-- realm is not among the chosen crafter's. An empty list means "unknown" (Phase 0:
-- GetAutoCompleteRealms returned {} on every probed flavor), never "own realm only".
local RealmTag = {}

local gsub = string.gsub
local ipairs = ipairs
local type = type

-- Realms compare with spaces and hyphens removed.
local function strip(realm)
  return (gsub(realm, "[ %-]", ""))
end

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

ns.RealmTag = RealmTag
return RealmTag
