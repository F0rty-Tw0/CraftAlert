local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local PageGeneral = ns.PageGeneral or require("CraftAlert.UI.Settings.PageGeneral")
local PageAlerts = ns.PageAlerts or require("CraftAlert.UI.Settings.PageAlerts")
local PageGreetings = ns.PageGreetings or require("CraftAlert.UI.Settings.PageGreetings")
local PageKeywords = ns.PageKeywords or require("CraftAlert.UI.Settings.PageKeywords")
local PageCrafters = ns.PageCrafters or require("CraftAlert.UI.Settings.PageCrafters")
local PageTest = ns.PageTest or require("CraftAlert.UI.Settings.PageTest")

-- Spec §9: Craft Alert's own settings window in the WhisperMessenger look, frame
-- CraftAlertSettingsWindow, created on the first Toggle (§4.4 rule 5). Left navigation, one
-- page at a time. A page is { id, title, Create(parent) → { Refresh() } }: built the first
-- time it is selected, refreshed from the db each time it is shown. Movable, position saved
-- in CraftAlertDB.ui.settings; ESC closes it (UISpecialFrames, the one sanctioned insert).
local SettingsWindow = {}

local FRAME_NAME = "CraftAlertSettingsWindow"
local UI_KEY = "settings"
local FALLBACK_POSITION = { "CENTER", 0, 40 }

local pages = {}
---@type table
local window = nil -- { frame, nav, content = { [id] = { frame, view } }, buttons = { [id] = button }, selected }

local function paintNav()
  for id, button in pairs(window.buttons) do
    FrameKit.Fill(button.background, id == window.selected and Theme.COLORS.optionSelected or Theme.COLORS.surface)
  end
end

local function pageById(id)
  for _, page in ipairs(pages) do
    if page.id == id then
      return page
    end
  end
  return nil
end

local function createContent(page)
  local layout = Theme.LAYOUT
  local frame = _G["CreateFrame"]("Frame", nil, window.frame)
  frame:SetPoint("TOPLEFT", window.frame, "TOPLEFT", layout.NAV_WIDTH + 2 * layout.PADDING, -(layout.TITLE_BAR_HEIGHT + layout.PADDING))
  frame:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -layout.PADDING, layout.PADDING)
  local entry = { frame = frame, view = page.Create(frame) }
  window.content[page.id] = entry
  return entry
end

local function showPage(id)
  local page = pageById(id)
  if page == nil then
    return
  end
  for _, entry in pairs(window.content) do
    entry.frame:Hide()
  end
  local entry = window.content[id] or createContent(page)
  window.selected = id
  entry.frame:Show()
  entry.view.Refresh()
  paintNav()
end

local function addNavButton(page)
  local layout = Theme.LAYOUT
  local index = 0
  for _ in pairs(window.buttons) do
    index = index + 1
  end
  local button = _G["CreateFrame"]("Button", nil, window.nav)
  button:SetSize(layout.NAV_WIDTH, layout.NAV_BUTTON_HEIGHT)
  button:SetPoint("TOPLEFT", window.nav, "TOPLEFT", 0, -index * layout.NAV_BUTTON_HEIGHT)
  button.pageId = page.id
  button.background = button:CreateTexture(nil, "BACKGROUND")
  button.background:SetAllPoints(button)
  button.label = FrameKit.Text(button, Theme.FONTS.body, Theme.COLORS.textPrimary)
  button.label:SetPoint("LEFT", button, "LEFT", layout.PADDING, 0)
  button.label:SetText(page.title)
  button:SetScript("OnClick", function()
    showPage(page.id)
  end)
  window.buttons[page.id] = button
end

local function create()
  local layout = Theme.LAYOUT
  local frame = _G["CreateFrame"]("Frame", FRAME_NAME, _G["UIParent"])
  frame:SetFrameStrata("DIALOG")
  frame:SetSize(layout.SETTINGS_WIDTH, layout.SETTINGS_HEIGHT)
  FrameKit.Panel(frame)
  FrameKit.Draggable(frame, UI_KEY)
  FrameKit.Place(frame, UI_KEY, FALLBACK_POSITION)
  FrameKit.TitleBar(frame, Localization.Text("Craft Alert — Settings"))
  local nav = _G["CreateFrame"]("Frame", nil, frame)
  nav:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.PADDING, -(layout.TITLE_BAR_HEIGHT + layout.PADDING))
  nav:SetSize(layout.NAV_WIDTH, layout.SETTINGS_HEIGHT - layout.TITLE_BAR_HEIGHT - 2 * layout.PADDING)
  frame:Hide()
  table.insert(_G["UISpecialFrames"], FRAME_NAME)
  return { frame = frame, nav = nav, content = {}, buttons = {}, selected = nil }
end

-- Adds a page to the navigation (Task 4.2: Linked accounts). Pages show in the order added.
function SettingsWindow.AddPage(page)
  pages[#pages + 1] = page
  if window then
    addNavButton(page)
  end
end

-- Opens the window on the page last shown (the first page at first), or closes it.
function SettingsWindow.Toggle()
  if window == nil then
    window = create()
    for _, page in ipairs(pages) do
      addNavButton(page)
    end
  end
  local frame = window.frame
  if frame:IsShown() then
    frame:Hide()
    return
  end
  frame:Show()
  showPage(window.selected or (pages[1] and pages[1].id))
end

SettingsWindow.AddPage(PageGeneral)
SettingsWindow.AddPage(PageAlerts)
SettingsWindow.AddPage(PageGreetings)
SettingsWindow.AddPage(PageKeywords)
SettingsWindow.AddPage(PageCrafters)
SettingsWindow.AddPage(PageTest)

ns.SettingsWindow = SettingsWindow
return SettingsWindow
