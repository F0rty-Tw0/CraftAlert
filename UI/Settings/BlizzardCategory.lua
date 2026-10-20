local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")
local SettingsWindow = ns.SettingsWindow or require("CraftAlert.UI.Settings.SettingsWindow")

-- Spec §9: one category in Blizzard's Settings (Esc → Options → AddOns) holding one button
-- that opens Craft Alert's own window, registered through the public Settings API (§4.3
-- rule 3). Its small unnamed canvas frame is the only settings frame made at login (§4.4
-- rule 5); Blizzard parents and shows it. A client without RegisterCanvasLayoutCategory gets
-- no category (`/ca config` still opens the window).
local BlizzardCategory = {}

local BUTTON_WIDTH = 200

local category = nil

local function hasApi(settings)
  if type(settings) ~= "table" then
    return false
  end
  return type(settings.RegisterCanvasLayoutCategory) == "function" and type(settings.RegisterAddOnCategory) == "function"
end

local function createCanvas()
  local layout = Theme.LAYOUT
  local frame = _G["CreateFrame"]("Frame")
  local title = FrameKit.Text(frame, "GameFontNormalLarge", nil)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 2 * layout.PADDING, -2 * layout.PADDING)
  title:SetText(Localization.Text("Craft Alert"))
  local button = Controls.Button(frame, Localization.Text("Open Craft Alert settings"), BUTTON_WIDTH, function()
    SettingsWindow.Open()
  end)
  button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -layout.PADDING)
  return frame
end

-- Bootstrap, at login. → the category, or nil when the client has no canvas-layout API.
function BlizzardCategory.Register()
  local settings = _G["Settings"]
  if category or not hasApi(settings) then
    return category
  end
  category = settings.RegisterCanvasLayoutCategory(createCanvas(), Localization.Text("Craft Alert"))
  settings.RegisterAddOnCategory(category)
  return category
end

ns.BlizzardCategory = BlizzardCategory
return BlizzardCategory
