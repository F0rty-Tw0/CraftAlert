local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 Alerts: sound + test, taskbar flash, toast duration, lead timeout, launcher "Hide
-- when no leads", opacity. Nothing here touches the index or the scan gate. Sound, flash and
-- duration are read when an alert fires; a new lead timeout re-arms the expiry timer
-- (Leads.Rearm); the launcher and the leads window repaint at once (the toast takes the
-- opacity when it next shows). Both repaints come through setters Bootstrap calls
-- (SetOnLauncherToggle, SetOnOpacity): the window needs the settings pane, which lists these
-- pages, and the launcher needs the window, so a page requires neither. Ranges are Schema's.
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
  end, Localization.Text("The sound played with each new lead. Play tries the chosen one; None is silent."))
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

local onLauncherToggle = nothing
local onOpacity = nothing

local function rearm()
  Leads.Rearm()
end

local function launcherToggled()
  onLauncherToggle()
end

local function opacityChanged()
  onOpacity()
end

-- `fn()` runs after every "Hide the launcher when there are no leads" change (Bootstrap passes
-- Launcher.Refresh); nil clears it.
function PageAlerts.SetOnLauncherToggle(fn)
  onLauncherToggle = fn or nothing
end

-- `fn()` runs after every opacity change (Bootstrap passes LeadsWindow.Refresh); nil clears it.
function PageAlerts.SetOnOpacity(fn)
  onOpacity = fn or nothing
end

function PageAlerts.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local add, refresh = Controls.Refresher()
  Controls.Section(column, Localization.Text("When a request arrives"))
  addSound(column, add)
  local flashTip = Localization.Text("Flashes the game's taskbar icon on a new lead while the game is in the background.")
  add(Controls.BoundToggle(column, Localization.Text("Flash the taskbar icon"), settings, "flash", nothing, flashTip))
  local toast = {
    label = Localization.Text("Toast duration"),
    min = 5,
    max = 120,
    step = 5,
    format = seconds,
    tip = Localization.Text("How long the alert toast stays on screen before it hides on its own."),
  }
  addSlider(column, add, toast, "toastDuration", nothing)
  Controls.Section(column, Localization.Text("Leads"))
  local timeout = {
    label = Localization.Text("Lead timeout"),
    min = 1,
    max = 60,
    step = 1,
    format = minutes,
    tip = Localization.Text("How long a lead stays in the list before it expires and is removed."),
  }
  addSlider(column, add, timeout, "leadTimeoutMin", rearm)
  local hideLabel = Localization.Text("Hide the launcher when there are no leads")
  local hideTip = Localization.Text("Hides the launcher button while there are no leads. It returns with the next lead.")
  add(Controls.BoundToggle(column, hideLabel, settings, "hideLauncherWhenNoLeads", launcherToggled, hideTip))
  local opacity = {
    label = Localization.Text("Opacity"),
    min = 0.3,
    max = 1,
    step = 0.05,
    format = percent,
    tip = Localization.Text("How see-through the leads window and the toast are."),
  }
  addSlider(column, add, opacity, "opacity", opacityChanged)
  return { Refresh = refresh }
end

ns.PageAlerts = PageAlerts
return PageAlerts
