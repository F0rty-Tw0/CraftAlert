local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")

-- The Crafters page's character dropdown rows ({ value, text, key, other, realm, name }).
local CrafterOptions = {}

-- Own realm first, then the other realms in order; within a realm by name. Same realm and name
-- mean the same key, so the name decides last.
local function byRealmThenName(a, b)
  if a.other ~= b.other then
    return b.other
  end
  if a.realm ~= b.realm then
    return a.realm < b.realm
  end
  return a.name < b.name
end

-- The player's realm first, then the other realms by realm and name. This is the one place the
-- realm stays visible: a row on another realm shows the whole key, on every flavor.
function CrafterOptions.Characters(db)
  local ownRealm = PlayerName.RealmOf(PlayerName.Own())
  local options = {}
  for key, character in pairs(db.characters) do
    local imported = character.source == "import"
    local source = key == PlayerName.Own() and "this character" or (imported and "imported" or "same account")
    local realm = PlayerName.RealmOf(key)
    local shown = realm == ownRealm and PlayerName.NameOf(key) or key
    options[#options + 1] = {
      value = key,
      text = Localization.Text("%s (%s)", shown, Localization.Text(source)),
      key = key,
      other = realm ~= ownRealm,
      realm = realm or "",
      name = PlayerName.NameOf(key),
    }
  end
  table.sort(options, byRealmThenName)
  return options
end

ns.CrafterOptions = CrafterOptions
return CrafterOptions
