local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local PageHeader = ns.PageHeader or require("CraftAlert.UI.Settings.PageHeader")

-- The settings pane's (SettingsPane.lua) two layouts. Wide: the split, the nav left of the page
-- pane. Narrow: one screen at a time, the nav or the page pane, each filling the pane, the page
-- under a back-arrow header. `pane` is SettingsPane's table; `narrow` its mode.
local PaneScreens = {}

-- A page's box, PANE_PADDING in from the page pane on every side; narrow, under the header.
function PaneScreens.PlaceBox(pane, box, narrow)
  local layout = Theme.LAYOUT
  local inset = layout.PANE_PADDING
  local top = inset
  if narrow then
    top = inset + layout.NAV_BUTTON_HEIGHT
  end
  box:SetPoint("TOPLEFT", pane.right, "TOPLEFT", inset, -top)
  box:SetPoint("BOTTOMRIGHT", pane.right, "BOTTOMRIGHT", -inset, inset)
end

-- Anchors both panes and every built page's box for the mode. Wide, the nav is pane.navWidth wide.
function PaneScreens.Anchor(pane, narrow)
  local container, nav, right = pane.container, pane.nav, pane.right
  nav:ClearAllPoints()
  right:ClearAllPoints()
  nav:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  if narrow then
    nav:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  else
    nav:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(pane.navWidth)
    -- off-scale: the 1 px divider between the panes.
    right:SetPoint("TOPLEFT", nav, "TOPRIGHT", 1, 0)
  end
  right:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
  for _, entry in pairs(pane.content) do
    PaneScreens.PlaceBox(pane, entry.frame, narrow)
  end
end

-- The page header across the top of the page pane, PANE_PADDING in, above its art; onBack runs
-- on the arrow's click.
function PaneScreens.AddHeader(pane, onBack)
  local inset, right = Theme.LAYOUT.PANE_PADDING, pane.right
  local header = PageHeader.New(right, onBack)
  header:SetPoint("TOPLEFT", right, "TOPLEFT", inset, -inset)
  header:SetPoint("TOPRIGHT", right, "TOPRIGHT", -inset, -inset)
  header:SetFrameLevel(right:GetFrameLevel() + 2)
  pane.header = header
end

-- The one place that shows or hides the panes. Wide: both, the selected page's nav button marked.
-- Narrow: the nav alone with no button marked (pane.screen "nav"), or the page pane under its
-- header titled `title` ("page").
function PaneScreens.Apply(pane, narrow, title)
  local split = not narrow
  local onPage = narrow and pane.screen == "page"
  pane.nav:SetShown(split or pane.screen == "nav")
  pane.right:SetShown(split or onPage)
  pane.divider:SetShown(split)
  pane.header:SetShown(onPage)
  if onPage then
    pane.header.title:SetText(title)
  end
  for pageId, button in pairs(pane.buttons) do
    button.selected:SetShown(split and pageId == pane.selected)
  end
end

ns.PaneScreens = PaneScreens
return PaneScreens
