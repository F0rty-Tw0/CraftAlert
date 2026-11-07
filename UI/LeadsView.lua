local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadDetails = ns.LeadDetails or require("CraftAlert.UI.LeadDetails")
local LeadsList = ns.LeadsList or require("CraftAlert.UI.LeadsList")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local LedgerStrip = ns.LedgerStrip or require("CraftAlert.UI.LedgerStrip")
local ClearAllLink = ns.ClearAllLink or require("CraftAlert.UI.ClearAllLink")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local Status = ns.Status or require("CraftAlert.Core.Status")
local ScrollView = ns.ScrollView or require("CraftAlert.UI.ScrollView")
local LeadsScreens = ns.LeadsScreens or require("CraftAlert.UI.LeadsScreens")

-- Spec A.2, A.6, assumption 2: the leads split view, built into any parent frame (the leads
-- window's content frame, or a WhisperMessenger panel host). The ledger line (UI/LedgerStrip.lua,
-- spec §8) across the top, "Clear all" at its right (UI/ClearAllLink.lua); under it the list pane (UI/LeadsList.lua) on the left, the details
-- pane (UI/LeadDetails.lua) of the selected lead on the right, a 1 px divider between them; with
-- no leads the details pane says so (the list may be WM's icon rail, too narrow for the text). Each pane paints its atlas behind an InsetFrameTemplate art frame, as
-- WhisperMessenger's panes do (RetailChrome.lua:56-58,70,85-88, WM). The selection follows the
-- lead by id across refreshes; the root frame takes the mouse wheel and scrolls the list, as does
-- a drag of the list's bar. In a narrow host (SetNarrow, phone-style slide spec) one screen shows
-- at a time (UI/LeadsScreens.lua): the List, nothing selected, nothing marked seen; a row's click
-- opens its Details, which Back leaves for the List again.
local LeadsView = {}

local floor = math.floor

-- A frame over the whole pane, at the details' level, holding the centred, wrapping text.
local function createEmpty(pane)
  local empty = _G["CreateFrame"]("Frame", nil, pane)
  empty:SetAllPoints(pane)
  empty:SetFrameLevel(pane:GetFrameLevel() + 2)
  local text = FrameKit.Wrapped(empty, Theme.FONTS.body, Theme.COLORS.textSecondary)
  text:SetPoint("LEFT", pane, "LEFT", Theme.LAYOUT.PANE_PADDING, 0)
  text:SetPoint("RIGHT", pane, "RIGHT", -Theme.LAYOUT.PANE_PADDING, 0)
  text:SetJustifyH("CENTER")
  text:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))
  empty.text = text
  empty:Hide()
  return empty
end

-- Why the details pane is empty: the paused line when the addon is not listening, else the plain
-- text (while listening, "Listening in Trade — ..." would not explain an empty list).
local function emptyText()
  local state = ScanGate.State()
  if not state.active then
    return Status.Text(state)
  end
  return Localization.Text("No leads right now. Requests you can craft show up here.")
end

local function positionOf(leads, id)
  for position, lead in ipairs(leads) do
    if lead.id == id then
      return position
    end
  end
  return nil
end

-- The lead to select in `leads`: the selected one while it is there; when it left, the lead now
-- at its old position, else the last; with none selected yet, the newest.
local function pick(view, leads)
  local id = view.selectedId
  if id == nil then
    return leads[1]
  end
  local position = positionOf(leads, id)
  if position then
    return leads[position]
  end
  return leads[positionOf(view.leads, id)] or leads[#leads]
end

-- Narrow: the List selects nothing; the Details keep their lead by id, and go back to the List
-- when it left (no jump to another lead).
local function selectNarrow(view, leads)
  if view.screen ~= "details" then
    return nil
  end
  local position = positionOf(leads, view.selectedId)
  if position then
    return leads[position]
  end
  view.screen = "list"
  return nil
end

-- Re-reads `leads` (newest first) into the list and the details of the selected lead, which is
-- seen first (the badge's count drops, and its row paints without the unseen dot), and the ledger
-- line. The list gets the height under that line.
function LeadsView.Refresh(view, leads)
  local selected
  if view.narrow then
    selected = selectNarrow(view, leads)
  else
    selected = pick(view, leads)
  end
  view.selectedId = selected and selected.id
  view.leads = leads
  if selected then
    Leads.MarkSeen(selected.id)
  end
  LedgerStrip.Refresh(view.strip)
  ClearAllLink.SetEnabled(view.clearAll, #leads > 0)
  local height = view.getHeight() - Theme.LAYOUT.LEDGER_HEIGHT
  LeadsList.Refresh(view.list, leads, LeadsList.Fit(height), view.selectedId)
  view.empty:SetShown(#leads == 0)
  if #leads == 0 then
    view.empty.text:SetText(emptyText())
  end
  if selected then
    LeadDetails.Show(view.details, selected)
  else
    LeadDetails.Clear(view.details)
  end
  if view.narrow then
    LeadsScreens.Apply(view)
  end
end

-- Scrolls by `delta` wheel notches (positive = up); the refresh clamps the offset. On the narrow
-- Details the details body scrolls instead, never the hidden list.
function LeadsView.Scroll(view, delta)
  if view.screen == "details" then
    ScrollView.Wheel(view.details.scroll, delta)
    return
  end
  view.list.offset = view.list.offset - delta
  LeadsView.Refresh(view, view.leads)
end

-- The view in `parent`. opts.getHeight(): the height the panes get (the host's, never read from
-- the view's own frames, which may read 0 on the first open); opts.getListWidth(): the list
-- pane's width.
function LeadsView.New(parent, opts)
  local view = { parent = parent, getHeight = opts.getHeight, getListWidth = opts.getListWidth, leads = {}, narrow = false }
  local frame = _G["CreateFrame"]("Frame", nil, parent)
  frame:SetAllPoints(parent)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    LeadsView.Scroll(view, delta)
  end)
  view.frame = frame
  view.strip = LedgerStrip.New(frame, parent)
  view.listPane = FrameKit.InsetPane(frame, Theme.ART.PANEL_BACKGROUND)
  view.listPane:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -Theme.LAYOUT.LEDGER_HEIGHT)
  view.listPane:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  -- In the band over the list, at its right (in the strip: it hides with it, in an instance); the
  -- counts start right of the list. LeadsScreens.Anchor places it and the details pane.
  view.clearAll = ClearAllLink.Build(view.strip)
  view.detailsPane = FrameKit.InsetPane(frame, Theme.ART.WIDE_PANEL_BACKGROUND)
  LeadsScreens.Anchor(view)
  view.divider = FrameKit.Divider(frame, view.listPane)
  view.list = LeadsList.New(view.listPane, function(row)
    view.selectedId = row.lead.id
    if view.narrow then
      view.screen = "details"
    end
    LeadsView.Refresh(view, view.leads)
  end, function(value)
    view.list.offset = floor(value + 0.5)
    LeadsView.Refresh(view, view.leads)
  end)
  view.details = LeadDetails.New(view.detailsPane)
  view.details.frame:SetFrameLevel(view.detailsPane:GetFrameLevel() + 2)
  view.empty = createEmpty(view.detailsPane)
  LeadsView.Layout(view)
  return view
end

-- Repaints both panes, the divider, the rows (the ones built later too), the details header, strip
-- and boxes, and the list's and the body's scroll bars for `look` (UI/PanelLook.lua).
function LeadsView.ApplyLook(view, look)
  FrameKit.PaintPane(view.listPane, Theme.ART.PANEL_BACKGROUND, look, "bg_secondary")
  FrameKit.PaintPane(view.detailsPane, Theme.ART.WIDE_PANEL_BACKGROUND, look, "bg_primary")
  FrameKit.PaintDivider(view.divider, look)
  LeadsList.ApplyLook(view.list, look)
  LeadDetails.ApplyLook(view.details, look)
end

-- Re-reads the list width; the details get the rest of the parent (0 wide: not known yet). A list
-- narrower than the minimum (WM's divider on its rail) is icon-only, and "Clear all" hides when the
-- band over the list cannot hold it. Narrow: full-size rows whatever the width, "Clear all" on the
-- ledger line, the details as wide as the parent.
function LeadsView.Layout(view)
  local listWidth = view.getListWidth()
  if view.narrow then
    view.listPane:SetWidth(listWidth)
    LeadsList.SetCompact(view.list, false)
    view.clearAll:Show()
    LeadDetails.Layout(view.details, view.parent:GetWidth())
    return
  end
  view.listPane:SetWidth(listWidth)
  view.clearAll:SetShown(listWidth >= view.clearAll:GetWidth() + 2 * Theme.LAYOUT.PADDING)
  LeadsList.SetCompact(view.list, listWidth < Theme.LAYOUT.LIST_MIN_WIDTH)
  LeadDetails.Layout(view.details, view.parent:GetWidth() - listWidth - 1)
end

-- Back to the top with nothing selected: the next refresh selects the newest lead (narrow: on
-- the List).
function LeadsView.ResetTop(view)
  view.list.offset = 0
  view.selectedId = nil
  if view.narrow then
    view.screen = "list"
  end
end

-- Empties the rows, the details and the empty text, so the next refresh shows each lead afresh
-- (a new shownAt); the selection is kept.
function LeadsView.Clear(view)
  LeadsList.Clear(view.list)
  LeadDetails.Clear(view.details)
  view.empty:Hide()
end

function LeadsView.TopRow(view)
  return LeadsList.TopRow(view.list)
end

function LeadsView.Selected(view)
  local position = positionOf(view.leads, view.selectedId)
  return position and view.leads[position]
end

-- BridgePanel calls it when its host crosses the narrow threshold; the caller lays out and
-- refreshes after. To narrow: the List, nothing selected, the details' back arrow on (Back). To wide:
-- the arrow off; a lead shown in the Details stays selected, else the next refresh selects the newest.
function LeadsView.SetNarrow(view, narrow)
  if narrow == view.narrow then
    return
  end
  if narrow then
    view.screen = "list"
    view.selectedId = nil
  else
    if view.screen ~= "details" then
      view.selectedId = nil
    end
    view.screen = nil
  end
  view.narrow = narrow
  LeadDetails.SetBack(view.details, narrow and function()
    LeadsView.Back(view)
  end or nil)
  LeadsScreens.Anchor(view)
  LeadsScreens.Apply(view)
end

-- "split" while wide, else the narrow screen: "list" or "details".
function LeadsView.Screen(view)
  return view.narrow and view.screen or "split"
end

-- Narrow Details to the List, at the same scroll offset, nothing selected; a no-op elsewhere.
function LeadsView.Back(view)
  if view.screen ~= "details" then
    return
  end
  view.screen = "list"
  view.selectedId = nil
  LeadsView.Refresh(view, view.leads)
end

ns.LeadsView = LeadsView
return LeadsView
