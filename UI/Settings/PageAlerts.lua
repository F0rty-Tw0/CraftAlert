local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LeadsWindow = ns.LeadsWindow or require("CraftAlert.UI.LeadsWindow")
local Launcher = ns.Launcher or require("CraftAlert.UI.Launcher")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 Alerts: sound + test, taskbar flash, toast duration, lead timeout, launcher "Hide
-- when no leads", opacity. Nothing here touches the index or the scan gate. Sound, flash and
-- duration are read when an alert fires; a new lead timeout re-arms the expiry timer
-- (Leads.Rearm); the launcher and the leads window repaint at once (the toast takes the
-- opacity when it next shows). Ranges are Schema's.
local PageAlerts = { id = "alerts", title = Localization.Text("Alerts") }

local SOUND_CHANNEL = "Master" -- as AlertToast plays it

local function settings()
  return _G["CraftAlertDB"].settings
end

local function soundOptions()
  local options = { { value = 0, text = Localization.Text("None") } }
  for i, kit in ipairs(Constants.flavors[FlavorCompat.flavorKey].soundKits) do
    options[#options + 1] = { value = kit, text = Localization.Text("Sound %d", i) }
  end
  return options
end

local function playSound()
  local kit = settings().sound
  local play = _G["PlaySound"]
  if kit ~= 0 and type(play) == "function" then
    play(kit, SOUND_CHANNEL)
  end
end

local function addSound(column, add)
  local choice = Controls.Choice(column, Localization.Text("Alert sound"), soundOptions(), function(value)
    settings().sound = value
  end)
  -- Under the label, Play first and the dropdown in the rest of the line; the 20 px button sits
  -- 2 px up, in the middle of the dropdown's 24.
  local layout = Theme.LAYOUT
  local play = Controls.Button(choice.row, Localization.Text("Play"), 48, playSound)
  play:SetPoint("BOTTOMLEFT", choice.row, "BOTTOMLEFT", 0, 2)
  choice.input:ClearAllPoints()
  choice.input:SetPoint("BOTTOMLEFT", play, "BOTTOMRIGHT", layout.PADDING, -2)
  choice.input:SetPoint("BOTTOMRIGHT", choice.row, "BOTTOMRIGHT", 0, 0)
  add(function()
    choice.Set(settings().sound)
  end)
end

local function percent(value)
  return Localization.Text("%d%%", math.floor(value * 100 + 0.5))
end

local function seconds(value)
  return Localization.Text("%d s", value)
end

local function minutes(value)
  return Localization.Text("%d min", value)
end

-- spec as Controls.Slider without onChange; writes settings()[key], then after().
local function addSlider(column, add, spec, key, after)
  spec.onChange = function(value)
    settings()[key] = value
    after()
  end
  local slider = Controls.Slider(column, spec)
  add(function()
    slider.Set(settings()[key])
  end)
end

local function nothing() end

local function rearm()
  Leads.Rearm()
end

local function refreshLauncher()
  Launcher.Refresh()
end

local function refreshLeadsWindow()
  LeadsWindow.Refresh()
end

function PageAlerts.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local add, refresh = Controls.Refresher()
  Controls.Section(column, Localization.Text("When a request arrives"))
  addSound(column, add)
  add(Controls.BoundToggle(column, Localization.Text("Flash the taskbar icon"), settings, "flash", nothing))
  local toast = { label = Localization.Text("Toast duration"), min = 5, max = 120, step = 5, format = seconds }
  addSlider(column, add, toast, "toastDuration", nothing)
  Controls.Section(column, Localization.Text("Leads"))
  local timeout = { label = Localization.Text("Lead timeout"), min = 1, max = 60, step = 1, format = minutes }
  addSlider(column, add, timeout, "leadTimeoutMin", rearm)
  local hideLabel = Localization.Text("Hide the launcher when there are no leads")
  add(Controls.BoundToggle(column, hideLabel, settings, "hideLauncherWhenNoLeads", refreshLauncher))
  local opacity = { label = Localization.Text("Opacity"), min = 0.3, max = 1, step = 0.05, format = percent }
  addSlider(column, add, opacity, "opacity", refreshLeadsWindow)
  return { Refresh = refresh }
end

ns.PageAlerts = PageAlerts
return PageAlerts
