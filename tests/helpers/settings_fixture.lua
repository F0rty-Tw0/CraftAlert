-- The settings pane in the leads window over UiFixture, with the refreshes a setting may trigger recorded instead
-- of run: Index.RequestRebuild(reason) → "rebuild:<reason>", Index.RequestRebuildSoon(reason) →
-- "rebuildSoon:<reason>", ScanGate.Evaluate → "evaluate",
-- Leads.Rearm → "rearm", Launcher.Refresh → "launcher", LeadsWindow.Refresh → "leadsWindow",
-- ModernRows.Refresh → "markers", ClassicRows.Refresh → "classicMarkers". The Alerts page calls
-- launcher and leadsWindow as Bootstrap wires them (PageAlerts.SetOnLauncherToggle, SetOnOpacity).
--   local ns, db, refreshes = SettingsFixture.load(opts)   -- opts as UiFixture.load
--   SettingsFixture.open(ns, "Alerts")                     -- opens the window on that page
--   SettingsFixture.row("Lead timeout").input              -- the shown control with that label
--   SettingsFixture.take(refreshes)                        -- what was triggered since last take
--   SettingsFixture.pageBar(box)                           -- the scroll bar of a page's box
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local SettingsFixture = {}

SettingsFixture.WINDOW = "CraftAlertLeadsWindow"

local function spy(module, name, record)
  module[name] = function(...)
    record(...)
  end
end

function SettingsFixture.load(opts)
  local ns, db, calls = UiFixture.load(opts)
  local refreshes = {}
  spy(ns.Index, "RequestRebuild", function(reason)
    refreshes[#refreshes + 1] = "rebuild:" .. tostring(reason)
  end)
  spy(ns.Index, "RequestRebuildSoon", function(reason)
    refreshes[#refreshes + 1] = "rebuildSoon:" .. tostring(reason)
  end)
  local names = {
    { ns.ScanGate, "Evaluate", "evaluate" },
    { ns.Leads, "Rearm", "rearm" },
    { ns.Launcher, "Refresh", "launcher" },
    { ns.LeadsWindow, "Refresh", "leadsWindow" },
    { ns.ModernRows, "Refresh", "markers" },
    { ns.ClassicRows, "Refresh", "classicMarkers" },
  }
  for _, entry in ipairs(names) do
    spy(entry[1], entry[2], function()
      refreshes[#refreshes + 1] = entry[3]
    end)
  end
  ns.PageAlerts.SetOnLauncherToggle(ns.Launcher.Refresh)
  ns.PageAlerts.SetOnOpacity(ns.LeadsWindow.Refresh)
  return ns, db, refreshes, calls
end

-- The recorded refreshes, emptied.
function SettingsFixture.take(refreshes)
  local taken = {}
  for i = 1, #refreshes do
    taken[i] = refreshes[i]
    refreshes[i] = nil
  end
  return taken
end

function SettingsFixture.window()
  return rawget(_G, SettingsFixture.WINDOW)
end

-- Whether the frame and every parent up to UIParent are shown.
function SettingsFixture.visible(frame)
  while frame do
    if frame.IsShown and not frame:IsShown() then
      return false
    end
    frame = frame.parent
  end
  return true
end

function SettingsFixture.navButton(title)
  for _, frame in ipairs(Wow.frames) do
    if frame.pageId and frame.label and frame.label:GetText() == title then
      return frame
    end
  end
  error("no nav button " .. title)
end

-- Opens the window on the settings pane if needed and selects the page with that title.
function SettingsFixture.open(ns, title)
  local window = SettingsFixture.window()
  if window == nil or not window:IsShown() or window:GetTitleText():GetText() ~= "Craft Alert — Settings" then
    ns.LeadsWindow.ToggleSettings()
  end
  Widgets.click(SettingsFixture.navButton(title), "LeftButton")
end

-- The visible row labelled `label` (row.input is its control).
function SettingsFixture.row(label)
  for _, frame in ipairs(Wow.frames) do
    if frame.settingsLabel == label and SettingsFixture.visible(frame) then
      return frame
    end
  end
  error("no visible row " .. label)
end

-- The visible button labelled `label` under `parent` (any depth).
function SettingsFixture.button(parent, label)
  for _, frame in ipairs(Wow.frames) do
    if frame.label and frame.label:GetText() == label and SettingsFixture.visible(frame) then
      local node = frame
      while node and node ~= parent do
        node = node.parent
      end
      if node == parent then
        return frame
      end
    end
  end
  error("no visible button " .. label)
end

-- The scroll bar of the page whose box is `box` (UI/ScrollView.lua puts it on the box).
function SettingsFixture.pageBar(box)
  for _, frame in ipairs(Wow.frames) do
    if frame.frameType == "Slider" and frame.parent == box then
      return frame
    end
  end
  error("no scroll bar on the page's box")
end

-- The shown texts of the window's visible frames (so of the selected page), joined by " / ".
function SettingsFixture.texts()
  local visibleFrames = {}
  for _, frame in ipairs(Wow.frames) do
    if SettingsFixture.visible(frame) then
      visibleFrames[#visibleFrames + 1] = frame
    end
  end
  return table.concat(Widgets.texts(SettingsFixture.window(), visibleFrames), " / ")
end

return SettingsFixture
