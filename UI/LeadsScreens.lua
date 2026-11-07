local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LedgerStrip = ns.LedgerStrip or require("CraftAlert.UI.LedgerStrip")
local ScreenSlide = ns.ScreenSlide or require("CraftAlert.UI.ScreenSlide")

-- Phone-style slide spec: where the panes of a LeadsView (UI/LeadsView.lua) sit, and which show.
-- Wide, the split view: the list pane at the left, the details right of it past the 1 px divider,
-- "Clear all" in the band over the list and the ledger counts right of the list. Narrow (a host
-- too small for both panes), one screen at a time over the full width under the ledger line: the
-- List or the Details. The ledger line spans the host, its counts from the left edge, "Clear all"
-- left of the strip's right control and the counts cut before it.
local LeadsScreens = {}

-- Re-anchors the details pane, "Clear all" and the ledger text for the view's narrow flag; runs
-- when the view crosses between narrow and wide. A slide in flight ends first: its end restores
-- the anchors saved at its start, which would undo these.
function LeadsScreens.Anchor(view)
  ScreenSlide.FinishNow()
  local padding = Theme.LAYOUT.PADDING
  local parent, strip, pane, clearAll = view.parent, view.strip, view.detailsPane, view.clearAll
  pane:ClearAllPoints()
  clearAll:ClearAllPoints()
  if view.narrow then
    pane:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -Theme.LAYOUT.LEDGER_HEIGHT)
    clearAll:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -(strip.rightInset or padding), 0)
    LedgerStrip.SetLeftEdge(strip, nil)
    LedgerStrip.SetExtraInset(strip, clearAll:GetWidth() + padding)
  else
    -- off-scale: the 1 px divider between the panes.
    pane:SetPoint("TOPLEFT", view.listPane, "TOPRIGHT", 1, 0)
    clearAll:SetPoint("BOTTOMRIGHT", view.listPane, "TOPRIGHT", -padding, 0)
    LedgerStrip.SetLeftEdge(strip, view.listPane)
    LedgerStrip.SetExtraInset(strip, 0)
  end
  pane:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
end

-- Ends a slide in flight and forgets the shown screen, so the next Apply swaps at once: a show, a
-- width crossing and a first paint never slide.
function LeadsScreens.Reset(view)
  ScreenSlide.FinishNow()
  view.shownPane, view.shownScreen = nil, nil
end

-- Shows the panes the screen needs. Wide: both and the divider. Narrow: the List's pane, or the
-- details pane on the Details and on a List with no leads (it holds the empty text); no divider.
-- Narrow, a change of screen (List <-> Details) slides (UI/ScreenSlide.lua) when a pane was shown
-- before; the first paint and the empty text coming or going swap at once. view.shownPane and
-- view.shownScreen remember what the last call showed (nil: nothing yet, or wide), so a refresh on
-- the same pane leaves a slide in flight alone. view.screen, not LeadsView.Screen: LeadsView loads
-- after this module.
function LeadsScreens.Apply(view)
  if not view.narrow then
    LeadsScreens.Reset(view)
    view.listPane:Show()
    view.detailsPane:Show()
    view.divider:Show()
    return
  end
  view.divider:Hide()
  local want = (view.screen == "list" and #view.leads > 0) and "list" or "details"
  local changed = view.shownScreen ~= view.screen
  view.shownScreen = view.screen
  if want == view.shownPane then
    return
  end
  local slide = view.shownPane ~= nil and changed
  view.shownPane = want
  local wantPane, otherPane = view.detailsPane, view.listPane
  if want == "list" then
    wantPane, otherPane = view.listPane, view.detailsPane
  end
  if slide then
    ScreenSlide.Show(otherPane, wantPane, want == "details" and 1 or -1)
    return
  end
  ScreenSlide.FinishNow()
  otherPane:Hide()
  wantPane:Show()
end

ns.LeadsScreens = LeadsScreens
return LeadsScreens
