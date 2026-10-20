-- The settings window over UiFixture, with the refreshes a setting may trigger recorded instead
-- of run: Index.RequestRebuild(reason) → "rebuild:<reason>", ScanGate.Evaluate → "evaluate",
-- Leads.Rearm → "rearm", Launcher.Refresh → "launcher", LeadsWindow.Refresh → "leadsWindow".
--   local ns, db, refreshes = SettingsFixture.load(opts)   -- opts as UiFixture.load
--   SettingsFixture.open(ns, "Alerts")                     -- opens the window on that page
--   SettingsFixture.row("Lead timeout").input              -- the shown control with that label
--   SettingsFixture.take(refreshes)                        -- what was triggered since last take
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local SettingsFixture = {}

SettingsFixture.WINDOW = "CraftAlertSettingsWindow"

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
  local names = {
    { ns.ScanGate, "Evaluate", "evaluate" },
    { ns.Leads, "Rearm", "rearm" },
    { ns.Launcher, "Refresh", "launcher" },
    { ns.LeadsWindow, "Refresh", "leadsWindow" },
  }
  for _, entry in ipairs(names) do
    spy(entry[1], entry[2], function()
      refreshes[#refreshes + 1] = entry[3]
    end)
  end
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

-- Opens the window if needed and selects the page with that title.
function SettingsFixture.open(ns, title)
  local window = SettingsFixture.window()
  if window == nil or not window:IsShown() then
    ns.SettingsWindow.Toggle()
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
