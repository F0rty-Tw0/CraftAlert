local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local ScrollView = ns.ScrollView or require("CraftAlert.UI.ScrollView")
local ScrollBar = ns.ScrollBar or require("CraftAlert.UI.ScrollBar")
local RowArt = ns.RowArt or require("CraftAlert.UI.RowArt")
local PanelLook = ns.PanelLook or require("CraftAlert.UI.PanelLook")
local PaneScreens = ns.PaneScreens or require("CraftAlert.UI.Settings.PaneScreens")

-- Native-HUD spec §7.1, UI uplift spec B.1: Craft Alert's settings, a pane with the split view's
-- two-pane look: navigation on the left, one page at a time on the right. One pane, in whichever
-- host attached it last (the leads window's content frame, or another addon's panel). A page is
-- { id, title, Create(parent) → { Refresh() } }: built the first time it is selected, refreshed
-- from the db each time it is shown. The pane loads before the pages (the leads window needs it,
-- and the pages load after the window), so the built-in pages are looked up on the first
-- Attach, never at load. In a narrow host (SetNarrow) it shows one screen at a time instead: the
-- nav, or a page under a back-arrow header (PaneScreens.lua).
local SettingsPane = {}

-- Module names under CraftAlert.UI.Settings, in nav order.
local BUILT_IN = { "PageGeneral", "PageAlerts", "PageGreetings", "PageKeywords", "PageCrafters", "PageLinked", "PageTest" }

local added = {} -- pages from AddPage, after the built-ins
local pages = {} -- every page in nav order, filled by the first Attach
---@type table
local pane = nil -- { host, onBack, onDetach, container, nav, right, divider, back, header, navWidth, screen, content = { [id] = { frame, view, bar } }, buttons = { [id] = button }, selected }
local lastLook = PanelLook.NATIVE -- what pages and nav buttons built later paint with
local narrow = false -- one screen at a time (pane.screen: "nav" or "page"), not the split

local function pageById(id)
  for _, page in ipairs(pages) do
    if page.id == id then
      return page
    end
  end
  return nil
end

-- A page scrolls (UI/ScrollView.lua, WhisperMessenger's scroll view) in a box PANE_PADDING
-- in from the pane on every side, above its inset art: the bar hugs the box's right, inside the
-- inset border, as WhisperMessenger's. The page draws on the view's content, the box less the
-- bar wide; the page's column pads its rows (PAGE_PADDING) and makes it as tall as they are.
-- Narrow, the box starts under the page header (PaneScreens.lua).
local function createContent(page)
  local box = _G["CreateFrame"]("Frame", nil, pane.right)
  PaneScreens.PlaceBox(pane, box, narrow)
  box:SetFrameLevel(pane.right:GetFrameLevel() + 2)
  local scroll = ScrollView.Create(box)
  local entry = { frame = box, view = page.Create(scroll.content), bar = scroll.bar }
  ScrollBar.ApplyLook(scroll.bar, lastLook)
  pane.content[page.id] = entry
  return entry
end

local function applyScreen()
  local page = pageById(pane.selected)
  PaneScreens.Apply(pane, narrow, page and page.title)
end

-- Narrow, the page's screen comes up before the page shows and refreshes, as wide shows it in a
-- shown pane.
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
  if narrow then
    pane.screen = "page"
  end
  applyScreen()
  entry.frame:Show()
  entry.view.Refresh()
end

local function addNavButton(page, index)
  local layout = Theme.LAYOUT
  local button = _G["CreateFrame"]("Button", nil, pane.nav)
  button:SetHeight(layout.NAV_BUTTON_HEIGHT)
  button:SetFrameLevel(pane.nav:GetFrameLevel() + 2)
  local top = -(layout.SPACE.XS + (index - 1) * layout.NAV_BUTTON_HEIGHT)
  button:SetPoint("TOPLEFT", pane.nav, "TOPLEFT", layout.NAV_BUTTON_INSET, top)
  button:SetPoint("TOPRIGHT", pane.nav, "TOPRIGHT", -layout.NAV_BUTTON_INSET, top)
  button.pageId = page.id
  button.label = FrameKit.Text(button, Theme.FONTS.name)
  button.label:SetPoint("LEFT", button, "LEFT", layout.SPACE.M, 0)
  button.label:SetText(page.title)
  button.hover = FrameKit.ListHighlight(button)
  button.selected = button:CreateTexture(nil, "ARTWORK")
  button.selected:SetAllPoints(button)
  button.selected:Hide()
  RowArt.ApplyLook(button.hover, button.selected, lastLook, nil)
  button:SetScript("OnClick", function()
    showPage(page.id)
  end)
  pane.buttons[page.id] = button
end

-- Adds a page to the navigation, after the built-in pages. Before the first Attach it waits; after
-- it the nav button comes at once.
function SettingsPane.AddPage(page)
  if pane == nil then
    added[#added + 1] = page
    return
  end
  pages[#pages + 1] = page
  addNavButton(page, #pages)
end

-- The first Attach makes the pane, hidden, in `host`.
local function build(host)
  local layout, art = Theme.LAYOUT, Theme.ART
  local container = _G["CreateFrame"]("Frame", nil, host)
  container:Hide()
  local nav = FrameKit.InsetPane(container, art.PANEL_BACKGROUND)
  local right = FrameKit.InsetPane(container, art.WIDE_PANEL_BACKGROUND)
  local divider = FrameKit.Divider(container, nav)
  pane = { container = container, nav = nav, right = right, divider = divider, content = {}, buttons = {}, selected = nil }
  pane.navWidth, pane.screen = layout.LIST_WIDTH, "nav"
  PaneScreens.AddHeader(pane, function()
    pane.screen = "nav"
    applyScreen()
  end)
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
  -- Anchored SPACE.XS in from both sides of the nav, so its width follows the nav's.
  local back = Controls.Button(nav, Localization.Text("Back to leads"), 0, function()
    pane.onBack()
  end)
  back:SetHeight(layout.NAV_BUTTON_HEIGHT)
  back:SetFrameLevel(nav:GetFrameLevel() + 2)
  back:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", layout.SPACE.XS, layout.SPACE.XS)
  back:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -layout.SPACE.XS, layout.SPACE.XS)
  pane.back = back
end

-- Puts the pane in `host`, filling it, hidden or shown as it was; the first call makes it. The
-- last host to attach owns it: the previous owner's `onDetach` runs once, before the move, so it
-- can fall back to what it showed. `onBack` runs when the Back button at the bottom of the nav is
-- clicked. `lift` puts the pane that many levels above the host (else one, a child's own level),
-- over frames the host's owner raises above the host's children (WhisperMessenger's divider
-- handle); a lifted pane takes the mouse, so nothing under it is clicked or dragged through it.
-- Each Attach starts the split view: an owner that wants narrow asks after it, so the shared pane
-- never carries one owner's narrow mode to the next.
function SettingsPane.Attach(host, onBack, onDetach, lift)
  if pane == nil then
    build(host)
  end
  ---@cast pane -nil
  if pane.host ~= host and pane.onDetach then
    pane.onDetach()
  end
  pane.host, pane.onBack, pane.onDetach = host, onBack, onDetach
  local container = pane.container
  container:SetParent(host)
  container:ClearAllPoints()
  container:SetAllPoints(host)
  container:SetFrameLevel(host:GetFrameLevel() + (lift or 1))
  container:EnableMouse(lift ~= nil)
  narrow = false
  PaneScreens.Anchor(pane, narrow)
  applyScreen()
end

-- The nav's width in the split view (the pane is built at LIST_WIDTH); Back's anchors follow it.
-- While narrow it is kept for the next split.
function SettingsPane.SetNavWidth(width)
  pane.navWidth = width
  if not narrow then
    pane.nav:SetWidth(width)
  end
end

-- Narrow: one screen at a time, starting on the nav. Back to wide: the split, on the page last
-- shown (the first page at first) when the pane is shown. A repeat of the current mode does nothing.
function SettingsPane.SetNarrow(value)
  value = value and true or false
  if value == narrow then
    return
  end
  narrow = value
  if pane == nil then
    return
  end
  PaneScreens.Anchor(pane, narrow)
  if narrow or not pane.container:IsShown() then
    pane.screen = "nav"
    applyScreen()
  else
    showPage(pane.selected or pages[1].id)
  end
end

-- "split" (wide, or no pane yet), else the narrow screen: "nav" or "page".
function SettingsPane.Screen()
  if pane == nil or not narrow then
    return "split"
  end
  return pane.screen
end

-- Repaints both panes, their divider, the nav buttons and every built page's scroll bar for `look`;
-- the pages and buttons built later paint with it too. Callers apply it after Attach: the bridge
-- its WM look, the leads window NATIVE.
function SettingsPane.ApplyLook(look)
  lastLook = look
  FrameKit.PaintPane(pane.nav, Theme.ART.PANEL_BACKGROUND, look, "bg_secondary")
  FrameKit.PaintPane(pane.right, Theme.ART.WIDE_PANEL_BACKGROUND, look, "bg_primary")
  FrameKit.PaintDivider(pane.divider, look)
  for _, button in pairs(pane.buttons) do
    RowArt.ApplyLook(button.hover, button.selected, look, nil)
  end
  for _, entry in pairs(pane.content) do
    ScrollBar.ApplyLook(entry.bar, look)
  end
end

-- Shows the pane on the page last shown (the first page at first), refreshed from the db; narrow,
-- on the nav.
function SettingsPane.Show()
  pane.container:Show()
  if narrow then
    pane.screen = "nav"
    applyScreen()
    return
  end
  showPage(pane.selected or pages[1].id)
end

function SettingsPane.Hide()
  if pane then
    pane.container:Hide()
  end
end

ns.SettingsPane = SettingsPane
return SettingsPane
