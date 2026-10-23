local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadRow = ns.LeadRow or require("CraftAlert.UI.LeadRow")

-- Spec §7.3: the rows of the leads window. Newest first, as many as fit the frame; the window
-- feeds it the leads and the wheel. Rows are children of the window's inset and fill its left
-- LIST_COLUMN_WIDTH (the details pane takes the rest). list.onRowEnter, when set, is called with
-- the row the cursor has rested on for HOVER_DWELL seconds.
local LeadsList = {}

-- Long enough for a cursor crossing rows on its way to the pane to pin nothing.
local HOVER_DWELL = 0.2

local floor = math.floor
local max = math.max
local min = math.min

-- The inset's height from the frame's own size and the offsets anchorInset gives it: the client
-- sizes the inset from its anchors only, which may still read 0 on the first open.
local function rowsThatFit(frame)
  local layout = Theme.LAYOUT
  local insetHeight = frame:GetHeight() - layout.INSET_TOP - layout.INSET_BOTTOM
  local height = insetHeight - 2 * layout.PADDING
  return max(0, floor((height + layout.ROW_GAP) / (layout.ROW_HEIGHT + layout.ROW_GAP)))
end

-- The cursor on `row` is only a candidate: it pins when it still rests on the same lead's visible
-- row after the dwell. A newer enter, a leave, a scroll or a clear drops the candidate; a closed
-- window hides the row, so no close hook is needed.
local function startDwell(list, row)
  if not row.lead then
    return
  end
  list.dwellGen = list.dwellGen + 1
  local generation = list.dwellGen
  local id = row.lead.id
  list.dwellRow = row
  _G["C_Timer"].After(HOVER_DWELL, function()
    local rested = list.dwellRow
    if generation ~= list.dwellGen or not rested or not rested:IsVisible() or not rested:IsMouseOver() then
      return
    end
    if rested.lead and rested.lead.id == id and list.onRowEnter then
      list.onRowEnter(rested)
    end
  end)
end

local function rowAt(list, index)
  local row = list.rows[index]
  if row then
    return row
  end
  local layout, inset = Theme.LAYOUT, list.inset
  row = LeadRow.Create(list.inset, index)
  local top = layout.PADDING + (index - 1) * (layout.ROW_HEIGHT + layout.ROW_GAP)
  row:SetPoint("TOPLEFT", inset, "TOPLEFT", layout.PADDING, -top)
  row:SetPoint("RIGHT", inset, "LEFT", layout.LIST_COLUMN_WIDTH - layout.PADDING, 0)
  -- HookScript, not SetScript: LinkHover's hooks on the row stay.
  row:HookScript("OnEnter", function(entered)
    startDwell(list, entered)
  end)
  row:HookScript("OnLeave", function()
    list.dwellRow = nil
  end)
  list.rows[index] = row
  return row
end

local function createEmptyText(inset)
  local empty = FrameKit.Text(inset, Theme.FONTS.body, Theme.COLORS.textSecondary)
  empty:SetPoint("CENTER", inset, "CENTER", 0, 0)
  empty:SetJustifyH("CENTER")
  empty:SetText(Localization.Text("No leads right now. Requests you can craft show up here."))

  return empty
end

-- The list in `inset` (the template's inset of the window frame, which sizes it): no rows yet,
-- scrolled to the top.
function LeadsList.New(inset)
  return { inset = inset, rows = {}, empty = createEmptyText(inset), offset = 0, dwellGen = 0 }
end

-- Re-reads `leads` into the rows, from the scroll offset down.
function LeadsList.Refresh(list, leads)
  local fit = rowsThatFit(list.inset:GetParent())
  list.offset = max(0, min(list.offset, #leads - fit))
  -- Bounded by the leads, not the frame height: a huge saved height must not loop for ever.
  local shown = max(0, min(fit, #leads - list.offset))
  for index = 1, max(shown, #list.rows) do
    local lead = index <= shown and leads[list.offset + index] or nil
    if lead then
      LeadRow.Show(rowAt(list, index), lead)
    elseif list.rows[index] then
      LeadRow.Clear(list.rows[index])
    end
  end
  if #leads == 0 then
    list.empty:Show()
  else
    list.empty:Hide()
  end
end

-- Hides every row, the empty text and each row's lead, so the next list draw shows each one afresh
-- (its shownAt is then new, which VisibleLatest and SendGuard's look rule read).
function LeadsList.Clear(list)
  for _, row in ipairs(list.rows) do
    LeadRow.Clear(row)
  end
  list.empty:Hide()
  list.dwellRow = nil
end

-- Scrolls by `delta` wheel notches (positive = up); the next Refresh clamps the offset.
function LeadsList.Scroll(list, delta)
  list.offset = list.offset - delta
  list.dwellRow = nil
end

function LeadsList.ResetTop(list)
  list.offset = 0
end

-- The top row when the list is at the top and the row shows, else nil.
function LeadsList.TopRow(list)
  local row = list.rows[1]
  if list.offset ~= 0 or not row or not row:IsVisible() then
    return nil
  end
  return row
end

ns.LeadsList = LeadsList
return LeadsList
