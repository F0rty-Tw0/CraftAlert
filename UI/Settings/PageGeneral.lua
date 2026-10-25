local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 General: enable, only where Trade chat exists, channels, profession-word alerts,
-- recipe markers (unbound items are on the Crafters page). Enable and "Only where Trade chat
-- exists" (saved as onlyResting) re-evaluate the scan gate
-- (§6.1); channels and profession-word alerts rebuild the index (§6.2), and a
-- channel also re-evaluates the gate, which owns the registered chat events. A channel the
-- flavor does not have is not shown (§6.1).
local PageGeneral = { id = "general", title = Localization.Text("General") }

local CHANNELS = {
  { key = "trade", label = "Trade" },
  { key = "services", label = "Services" },
  { key = "general", label = "General" },
  { key = "lfg", label = "LookingForGroup" },
  { key = "guild", label = "Guild" },
  { key = "communities", label = "Communities" },
}

local function settings()
  return _G["CraftAlertDB"].settings
end

local function channels()
  return settings().channels
end

local function evaluate()
  ScanGate.Evaluate()
end

local function rebuild(reason)
  return function()
    Index.RequestRebuild(reason)
  end
end

local function rebuildChannels()
  Index.RequestRebuild("channels")
  ScanGate.Evaluate()
end

-- Recipe markers (Phase 3) read the flag when they draw.
local function nothing() end

function PageGeneral.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local add, refresh = Controls.Refresher()
  local function toggle(label, owner, key, after)
    add(Controls.BoundToggle(column, Localization.Text(label), owner, key, after))
  end
  Controls.Section(column, Localization.Text("Scanning"))
  toggle("Enable Craft Alert", settings, "enable", evaluate)
  toggle("Only where Trade chat exists", settings, "onlyResting", evaluate)
  Controls.Section(column, Localization.Text("Channels"))
  local available = Constants.flavors[FlavorCompat.flavorKey].channels
  for _, channel in ipairs(CHANNELS) do
    if available[channel.key] then
      toggle(channel.label, channels, channel.key, rebuildChannels)
    end
  end
  Controls.Section(column, Localization.Text("Matching"))
  toggle("Profession-word alerts", settings, "professionWordAlerts", rebuild("professionWordAlerts"))
  toggle("Bell markers on recipe rows", settings, "recipeMarkers", nothing)
  return { Refresh = refresh }
end

ns.PageGeneral = PageGeneral
return PageGeneral
