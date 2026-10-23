local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Native-HUD spec §7.1: Craft Alert's settings, a pane in the leads window's inset. Left
-- navigation, one page at a time. A page is { id, title, Create(parent) → { Refresh() } }: built
-- the first time it is selected, refreshed from the db each time it is shown. The pane loads
-- before the pages (the leads window needs it, and the pages load after the window), so the
-- built-in pages are looked up on the first Build, never at load.
local SettingsPane = {}

-- Module names under CraftAlert.UI.Settings, in nav order.
local BUILT_IN = { "PageGeneral", "PageAlerts", "PageGreetings", "PageKeywords", "PageCrafters", "PageTest" }

local added = {} -- pages from AddPage, after the built-ins
local pages = {} -- every page in nav order, filled by Build
---@type table
local pane = nil -- { host, container, nav, content = { [id] = { frame, view } }, buttons = { [id] = button }, selected }

local function pageById(id)
  for _, page in ipairs(pages) do
    if page.id == id then
      return page
    end
  end
  return nil
end

local function createContent(page)
  local padding = Theme.LAYOUT.PADDING
  local frame = _G["CreateFrame"]("Frame", nil, pane.container)
  frame:SetPoint("TOPLEFT", pane.nav, "TOPRIGHT", padding, 0)
  frame:SetPoint("BOTTOMRIGHT", pane.host, "BOTTOMRIGHT", -padding, padding)
  local entry = { frame = frame, view = page.Create(frame) }
  pane.content[page.id] = entry
  return entry
end

local function showPage(id)
  local page = pageById(id)
  if page == nil then
    return
  end
  for _, entry in pairs(pane.content) do
    entry.frame:Hide()
  end
  local entry = pane.content[id] or createContent(page)
  pane.selected = id
  entry.frame:Show()
  entry.view.Refresh()
  for pageId, button in pairs(pane.buttons) do
    if pageId == id then
      button.selected:Show()
    else
      button.selected:Hide()
    end
  end
end

local function addNavButton(page, index)
  local layout, art = Theme.LAYOUT, Theme.ART
  local button = _G["CreateFrame"]("Button", nil, pane.nav)
  button:SetHeight(layout.NAV_BUTTON_HEIGHT)
  local top = -(4 + (index - 1) * layout.NAV_BUTTON_HEIGHT)
  button:SetPoint("TOPLEFT", pane.nav, "TOPLEFT", 4, top)
  button:SetPoint("TOPRIGHT", pane.nav, "TOPRIGHT", -4, top)
  button.pageId = page.id
  button.label = FrameKit.Text(button, Theme.FONTS.body)
  button.label:SetPoint("LEFT", button, "LEFT", layout.PADDING, 0)
  button.label:SetText(page.title)
  FrameKit.ListHighlight(button)
  button.selected = button:CreateTexture(nil, "ARTWORK")
  button.selected:SetAllPoints(button)
  button.selected:SetTexture(art.LIST_SELECTED)
  button.selected:SetBlendMode("ADD")
  button.selected:SetAlpha(art.LIST_SELECTED_ALPHA)
  button.selected:Hide()
  button:SetScript("OnClick", function()
    showPage(page.id)
  end)
  pane.buttons[page.id] = button
end

-- Adds a page to the navigation (Task 4.2: Linked accounts), after the built-in pages. Before the
-- first Build it waits; after it the nav button comes at once.
function SettingsPane.AddPage(page)
  if pane == nil then
    added[#added + 1] = page
    return
  end
  pages[#pages + 1] = page
  addNavButton(page, #pages)
end

-- Makes the pane in `host` (the leads window's inset), hidden. Runs once; later calls return.
-- `onBack` runs when the Back button at the bottom of the nav is clicked.
function SettingsPane.Build(host, onBack)
  if pane then
    return
  end
  local padding = Theme.LAYOUT.PADDING
  local container = _G["CreateFrame"]("Frame", nil, host)
  container:SetAllPoints(host)
  container:Hide()
  local nav = _G["CreateFrame"]("Frame", nil, container, "InsetFrameTemplate")
  nav:SetPoint("TOPLEFT", host, "TOPLEFT", padding, -padding)
  nav:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", padding, padding)
  nav:SetWidth(Theme.LAYOUT.NAV_WIDTH)
  pane = { host = host, container = container, nav = nav, content = {}, buttons = {}, selected = nil }
  for _, name in ipairs(BUILT_IN) do
    pages[#pages + 1] = ns[name] or require("CraftAlert.UI.Settings." .. name)
  end
  for _, page in ipairs(added) do
    pages[#pages + 1] = page
  end
  for index, page in ipairs(pages) do
    addNavButton(page, index)
  end
  -- Controls loads after the pane (TOC), so it resolves here, not at load.
  local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")
  local back = Controls.Button(nav, Localization.Text("Back to leads"), Theme.LAYOUT.NAV_WIDTH - 8, function()
    onBack()
  end)
  back:SetHeight(Theme.LAYOUT.NAV_BUTTON_HEIGHT)
  back:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 4, 4)
  back:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -4, 4)
end

-- Shows the pane on the page last shown (the first page at first), refreshed from the db.
function SettingsPane.Show()
  pane.container:Show()
  showPage(pane.selected or pages[1].id)
end

function SettingsPane.Hide()
  if pane then
    pane.container:Hide()
  end
end

ns.SettingsPane = SettingsPane
return SettingsPane
