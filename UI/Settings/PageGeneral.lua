local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local ModernRows = ns.ModernRows or require("CraftAlert.UI.RecipeMarkers.ModernRows")
local ClassicRows = ns.ClassicRows or require("CraftAlert.UI.RecipeMarkers.ClassicRows")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 General: enable, only where Trade chat exists, channels, profession-word alerts,
-- recipe markers, track unbound items. Enable and "Only where Trade chat
-- exists" (saved as onlyResting) re-evaluate the scan gate
-- (§6.1); channels, profession-word alerts and unbound items rebuild the index (§6.2), and a
-- channel also re-evaluates the gate, which owns the registered chat events. A channel the
-- flavor does not have is not shown (§6.1).
local PageGeneral = { id = "general", title = Localization.Text("General") }

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

-- Both marker variants; the one this flavor did not install is a no-op.
local function refreshMarkers()
  ModernRows.Refresh()
  ClassicRows.Refresh()
end

function PageGeneral.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local add, refresh = Controls.Refresher()
  local function toggle(label, owner, key, after, tip)
    add(Controls.BoundToggle(column, Localization.Text(label), owner, key, after, tip and Localization.Text(tip)))
  end
  Controls.Section(column, Localization.Text("Scanning"))
  toggle("Enable Craft Alert", settings, "enable", evaluate, "Turns scanning on or off. Off, Craft Alert reads no chat and shows no alerts.")
  toggle(
    "Only where Trade chat exists",
    settings,
    "onlyResting",
    evaluate,
    "Scans only while a Trade channel is available to you, as in a major city. Elsewhere scanning pauses and resumes on its own."
  )
  Controls.Section(column, Localization.Text("Channels"))
  local available = Constants.flavors[FlavorCompat.flavorKey].channels
  for _, channel in ipairs(ScanGate.CHANNELS) do
    if available[channel.key] then
      toggle(channel.label, channels, channel.key, rebuildChannels)
    end
  end
  Controls.Section(column, Localization.Text("Matching"))
  toggle(
    "Profession-word alerts",
    settings,
    "professionWordAlerts",
    rebuild("professionWordAlerts"),
    'Also alerts when a line names only a profession, such as "LF blacksmith", with no item. Off, only requests for an item you can craft alert.'
  )
  toggle(
    "Bell markers on recipe rows",
    settings,
    "recipeMarkers",
    refreshMarkers,
    "Draws a mute switch on each recipe in the profession window. Click it to mute or unmute that recipe."
  )
  toggle(
    "Track unbound items (materials, potions, gems)",
    settings,
    "includeUnbound",
    rebuild("includeUnbound"),
    "Also alerts for items that are not bound, such as materials, potions and gems. Off, those recipes never alert, muted or not."
  )
  return { Refresh = refresh }
end

ns.PageGeneral = PageGeneral
return PageGeneral
