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

-- Spec A.2, A.6, assumption 2: the leads split view, built into any parent frame (the leads
-- window's content frame, or a WhisperMessenger panel host). The ledger line (UI/LedgerStrip.lua,
-- spec §8) across the top; under it the list pane (UI/LeadsList.lua) on the left, the details
-- pane (UI/LeadDetails.lua) of the selected lead on the right, a 1 px divider between them; with
-- no leads the details pane says so (the list may be WM's icon rail, too narrow for the text). Each pane paints its atlas behind an InsetFrameTemplate art frame, as
-- WhisperMessenger's panes do (RetailChrome.lua:56-58,70,85-88, WM). The selection follows the
-- lead by id across refreshes; the root frame takes the mouse wheel and scrolls the list, as does
-- a drag of the list's bar.
local LeadsView = {}

local floor = math.floor

-- A pane: its atlas in a BACKGROUND texture, then the inset's border one level above. The inset's
-- marble Bg would cover the atlas, so it hides when the atlas paints and stays when it cannot
-- (Classic flavors: no fill but the inset's own).
local function createPane(parent, atlas)
  local pane = _G["CreateFrame"]("Frame", nil, parent)
  pane.bg = pane:CreateTexture(nil, "BACKGROUND")
  pane.bg:SetAllPoints(pane)
  pane.art = _G["CreateFrame"]("Frame", nil, pane, "InsetFrameTemplate")
  pane.art:SetAllPoints(pane)
  pane.art:SetFrameLevel(pane:GetFrameLevel() + 1)
  if FrameKit.PaintPanel(pane.bg, atlas) then
    pane.art.Bg:Hide()
  end
  return pane
end

local function createDivider(view)
  local color, listPane = Theme.COLORS.divider, view.listPane
  local divider = view.frame:CreateTexture(nil, "BORDER")
  divider:SetWidth(1)
  divider:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 0, 0)
  divider:SetPoint("BOTTOMLEFT", listPane, "BOTTOMRIGHT", 0, 0)
  divider:SetColorTexture(color[1], color[2], color[3], color[4])
  return divider
end

-- A frame over the whole pane, at the details' level, holding the centred, wrapping text.
local function createEmpty(pane)
  local empty = _G["CreateFrame"]("Frame", nil, pane)
  empty:SetAllPoints(pane)
  empty:SetFrameLevel(pane:GetFrameLevel() + 2)
  local text = FrameKit.Text(empty, Theme.FONTS.body, Theme.COLORS.textSecondary)
  text:SetPoint("LEFT", pane, "LEFT", Theme.LAYOUT.PANE_PADDING, 0)
  text:SetPoint("RIGHT", pane, "RIGHT", -Theme.LAYOUT.PANE_PADDING, 0)
  text:SetWordWrap(true)
  text:SetJustifyH("CENTER")
  text:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))
  empty.text = text
  empty:Hide()
  return empty
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

-- Re-reads `leads` (newest first) into the list and the details of the selected lead, which is
-- seen first (the badge's count drops, and its row paints without the unseen dot), and the ledger
-- line. The list gets the height under that line.
function LeadsView.Refresh(view, leads)
  local selected = pick(view, leads)
  view.selectedId = selected and selected.id
  view.leads = leads
  if selected then
    Leads.MarkSeen(selected.id)
  end
  LedgerStrip.Refresh(view.strip)
  local height = view.getHeight() - Theme.LAYOUT.LEDGER_HEIGHT
  LeadsList.Refresh(view.list, leads, LeadsList.Fit(height), view.selectedId)
  view.empty:SetShown(#leads == 0)
  if selected then
    LeadDetails.Show(view.details, selected)
  else
    LeadDetails.Clear(view.details)
  end
end

-- Scrolls by `delta` wheel notches (positive = up); the refresh clamps the offset.
function LeadsView.Scroll(view, delta)
  view.list.offset = view.list.offset - delta
  LeadsView.Refresh(view, view.leads)
end

-- The view in `parent`. opts.getHeight(): the height the panes get (the host's, never read from
-- the view's own frames, which may read 0 on the first open); opts.getListWidth(): the list
-- pane's width.
function LeadsView.New(parent, opts)
  local view = { parent = parent, getHeight = opts.getHeight, getListWidth = opts.getListWidth, leads = {} }
  local frame = _G["CreateFrame"]("Frame", nil, parent)
  frame:SetAllPoints(parent)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    LeadsView.Scroll(view, delta)
  end)
  view.frame = frame
  view.strip = LedgerStrip.New(frame, parent)
  view.listPane = createPane(frame, Theme.ART.PANEL_BACKGROUND)
  view.listPane:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -Theme.LAYOUT.LEDGER_HEIGHT)
  view.listPane:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  view.detailsPane = createPane(frame, Theme.ART.WIDE_PANEL_BACKGROUND)
  -- off-scale: the 1 px divider between the panes.
  view.detailsPane:SetPoint("TOPLEFT", view.listPane, "TOPRIGHT", 1, 0)
  view.detailsPane:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  view.divider = createDivider(view)
  view.list = LeadsList.New(view.listPane, function(row)
    view.selectedId = row.lead.id
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

-- Re-reads the list width; the details get the rest of the parent (0 wide: not known yet). A list
-- narrower than the minimum (WM's divider on its rail) is icon-only.
function LeadsView.Layout(view)
  local listWidth = view.getListWidth()
  view.listPane:SetWidth(listWidth)
  LeadsList.SetCompact(view.list, listWidth < Theme.LAYOUT.LIST_MIN_WIDTH)
  LeadDetails.Layout(view.details, view.parent:GetWidth() - listWidth - 1)
end

-- Back to the top with nothing selected: the next refresh selects the newest lead.
function LeadsView.ResetTop(view)
  view.list.offset = 0
  view.selectedId = nil
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

ns.LeadsView = LeadsView
return LeadsView
