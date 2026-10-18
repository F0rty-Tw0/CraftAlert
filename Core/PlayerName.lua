local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")

-- One normalizer for every character and customer key (spec §10): "Name-Realm", realm
-- without spaces or hyphens, a missing realm replaced by the player's own. Init caches
-- the own name and realm; after that no WoW API is called, so the hot path may use it.
-- The name part is never split on spaces (Forever names are "First Last").
local PlayerName = {}

local find = string.find
local gsub = string.gsub
local match = string.match
local sub = string.sub

local DEFAULT_SURNAME_SEPARATOR = " "

local ownRealm = nil
local ownKey = nil

local function callGlobal(name, ...)
  local fn = _G[name]
  if type(fn) == "function" then
    return fn(...)
  end
  return nil
end

-- Strips spaces and hyphens; nil for an empty realm.
local function normalizeRealm(realm)
  if type(realm) ~= "string" or realm == "" then
    return nil
  end
  if find(realm, "[ %-]") then
    realm = gsub(realm, "[ %-]", "")
  end
  if realm == "" then
    return nil
  end
  return realm
end

-- nil for anything that is not a usable name. Without a known own realm a bare name stays bare.
function PlayerName.Normalize(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local name = raw
  local realm = nil
  local dash = find(raw, "-", 1, true)
  if dash then
    name = sub(raw, 1, dash - 1)
    realm = normalizeRealm(sub(raw, dash + 1))
  end
  if name == "" then
    return nil
  end
  realm = realm or ownRealm
  if realm == nil then
    return name
  end
  return name .. "-" .. realm
end

-- Forever's UnitName returns (firstName, surname); everywhere else the second value is a realm.
local function ownName()
  local first, second = callGlobal("UnitName", "player")
  if FlavorCompat.isForever and type(first) == "string" and type(second) == "string" and second ~= "" then
    return first .. (_G["CHARACTERNAME_SURNAME_SEPARATOR"] or DEFAULT_SURNAME_SEPARATOR) .. second
  end
  return first
end

-- Call at PLAYER_LOGIN: GetNormalizedRealmName() is still nil at ADDON_LOADED on TBC.
function PlayerName.Init()
  ownRealm = normalizeRealm(callGlobal("GetNormalizedRealmName")) or normalizeRealm(callGlobal("GetRealmName"))
  ownKey = PlayerName.Normalize(ownName())
end

function PlayerName.Own()
  return ownKey
end

function PlayerName.RealmOf(key)
  if type(key) ~= "string" then
    return nil
  end
  return match(key, "^[^-]*%-(.+)$") or ownRealm
end

-- For comparisons across sources that drop the apostrophe (CraftScan, spec §10.2).
function PlayerName.StripApostrophes(key)
  return (gsub(key, "'", ""))
end

ns.PlayerName = PlayerName
return PlayerName
