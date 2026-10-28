local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local TableKit = ns.TableKit or require("CraftAlert.Core.TableKit")

-- Default settings (spec §9) and an empty account DB (spec §10). Every call builds new
-- tables, so a caller may edit the result freely.
local Defaults = {}

Defaults.schemaVersion = 1

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
    templates = TableKit.CopyMap(Constants.templates[flavorKey]),
    notes = {},
    intentWords = TableKit.CopyList(Constants.intentWords),
    blockerWords = TableKit.CopyList(Constants.blockerWords),
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
    ui = {},
  }
end

-- A new record for one of this account's characters, before any profession is read.
function Defaults.Character()
  return { source = "local", enabled = true, realms = {}, professions = {}, recipes = {} }
end

ns.Defaults = Defaults
return Defaults
