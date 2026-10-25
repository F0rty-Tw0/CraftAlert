local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadCard = ns.LeadCard or require("CraftAlert.UI.LeadCard")

-- Spec §7.3, lead-cards spec §1: the cards of the leads window (UI/LeadCard.lua). Newest first, as
-- many as fit the frame; the window feeds it the leads and the wheel, which scrolls by one card.
-- Cards are children of the window's inset and span its full width.
local CardList = {}

local floor = math.floor
local max = math.max
local min = math.min

-- The inset's height from the frame's own size and the offsets anchorInset gives it: the client
-- sizes the inset from its anchors only, which may still read 0 on the first open.
local function rowsThatFit(frame)
  local layout = Theme.LAYOUT
  local insetHeight = frame:GetHeight() - layout.INSET_TOP - layout.INSET_BOTTOM
  local height = insetHeight - 2 * layout.PADDING
  return max(0, floor((height + layout.CARD_GAP) / (layout.CARD_HEIGHT + layout.CARD_GAP)))
end

local function rowAt(list, index)
  local row = list.rows[index]
  if row then
    return row
  end
  local layout, inset = Theme.LAYOUT, list.inset
  row = LeadCard.Create(list.inset, index, list)
  local top = layout.PADDING + (index - 1) * (layout.CARD_HEIGHT + layout.CARD_GAP)
  row:SetPoint("TOPLEFT", inset, "TOPLEFT", layout.PADDING, -top)
  row:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -layout.PADDING, -top)
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
function CardList.New(inset)
  return { inset = inset, rows = {}, empty = createEmptyText(inset), offset = 0 }
end

-- Re-reads `leads` into the rows, from the scroll offset down.
function CardList.Refresh(list, leads)
  local fit = rowsThatFit(list.inset:GetParent())
  list.offset = max(0, min(list.offset, #leads - fit))
  -- Bounded by the leads, not the frame height: a huge saved height must not loop for ever.
  local shown = max(0, min(fit, #leads - list.offset))
  for index = 1, max(shown, #list.rows) do
    local lead = index <= shown and leads[list.offset + index] or nil
    if lead then
      LeadCard.Show(rowAt(list, index), lead)
    elseif list.rows[index] then
      LeadCard.Clear(list.rows[index])
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
function CardList.Clear(list)
  for _, row in ipairs(list.rows) do
    LeadCard.Clear(row)
  end
  list.empty:Hide()
end

-- Scrolls by `delta` wheel notches (positive = up); the next Refresh clamps the offset.
function CardList.Scroll(list, delta)
  list.offset = list.offset - delta
end

function CardList.ResetTop(list)
  list.offset = 0
end

-- The top row when the list is at the top and the row shows, else nil.
function CardList.TopRow(list)
  local row = list.rows[1]
  if list.offset ~= 0 or not row or not row:IsVisible() then
    return nil
  end
  return row
end

ns.CardList = CardList
return CardList
