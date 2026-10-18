local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")

-- Default settings (spec §9) and an empty account DB (spec §10). Every call builds new
-- tables, so a caller may edit the result freely.
local Defaults = {}

Defaults.schemaVersion = 1

local function copyList(list)
  local copy = {}
  for i = 1, #list do
    copy[i] = list[i]
  end
  return copy
end

local function copyMap(map)
  local copy = {}
  for key, value in pairs(map) do
    copy[key] = value
  end
  return copy
end

function Defaults.Settings()
  local flavorKey = FlavorCompat.flavorKey
  return {
    enable = true,
    onlyResting = true,
    channels = { trade = true, services = true, general = false, lfg = false, guild = false, communities = false },
    professionWordAlerts = true,
    includeUnbound = false,
    recipeMarkers = true,
    sound = Constants.flavors[flavorKey].soundKits[1], -- 0 = none
    flash = true,
    toastDuration = 20,
    leadTimeoutMin = 10,
    hideLauncherWhenNoLeads = false,
    opacity = 1.0,
    templates = copyMap(Constants.templates[flavorKey]),
    notes = {},
    intentWords = copyList(Constants.intentWords),
    blockerWords = copyList(Constants.blockerWords),
    extraSlang = {},
    craftScanImported = nil,
    craftScanPrompted = nil,
  }
end

function Defaults.Db()
  return {
    schema = Defaults.schemaVersion,
    settings = Defaults.Settings(),
    characters = {},
    leads = {},
    ledger = {},
    recentGreeted = {},
    ignored = {},
    ui = {},
  }
end

ns.Defaults = Defaults
return Defaults
