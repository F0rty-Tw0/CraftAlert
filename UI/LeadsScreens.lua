local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local LedgerStrip = ns.LedgerStrip or require("CraftAlert.UI.LedgerStrip")

-- Phone-style slide spec: where the panes of a LeadsView (UI/LeadsView.lua) sit, and which show.
-- Wide, the split view: the list pane at the left, the details right of it past the 1 px divider,
-- "Clear all" in the band over the list and the ledger counts right of the list. Narrow (a host
-- too small for both panes), one screen at a time over the full width under the ledger line: the
-- List or the Details. The ledger line spans the host, its counts from the left edge, "Clear all"
-- left of the strip's right control and the counts cut before it.
local LeadsScreens = {}

-- Re-anchors the details pane, "Clear all" and the ledger text for the view's narrow flag; runs
-- when the view crosses between narrow and wide.
function LeadsScreens.Anchor(view)
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

-- Shows the panes the screen needs. Wide: both and the divider. Narrow: the List's pane, or the
-- details pane on the Details and on a List with no leads (it holds the empty text); no divider.
function LeadsScreens.Apply(view)
  if not view.narrow then
    view.listPane:Show()
    view.detailsPane:Show()
    view.divider:Show()
    return
  end
  local showList = view.screen == "list" and #view.leads > 0
  view.listPane:SetShown(showList)
  view.detailsPane:SetShown(not showList)
  view.divider:Hide()
end

ns.LeadsScreens = LeadsScreens
return LeadsScreens
