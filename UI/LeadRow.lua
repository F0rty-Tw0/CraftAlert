local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local WhoCity = ns.WhoCity or require("CraftAlert.Core.WhoCity")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local RowArt = ns.RowArt or require("CraftAlert.UI.RowArt")
local LeadRowPaint = ns.LeadRowPaint or require("CraftAlert.UI.LeadRowPaint")

-- Spec A.3: one 48 px row of the leads list pane, WhisperMessenger's contact-row layout
-- (UI/ContactsList/RowView.lua:67-118, WM). The item or profession icon, the customer in class
-- colour with the age on its right, and below what was requested, then the greeted check and the
-- replied tag at the bottom right. The icon is round (RowArt, spec D5) and carries a status dot, as
-- WM's contacts: whisper pink while the customer has a whisper the player has not read in WM,
-- else gold for an unseen, ungreeted lead (spec B, the badge's rule), else the details header's
-- state colour (LeadText.State). The texts, the selected overlay and the
-- hover's fade are WM's too (spec D1-D9); the hover never shows over the selected row. On WM's
-- rail the row is compact (spec 6a): only the icon, centred. No link hover; one tooltip while the
-- cursor is on the row: the latest chat line (row-chat-tooltip spec), or when compact the
-- customer, the request and that line. The details pane has the other tooltips. Left click selects
-- the row (onSelect), on Forever and Classic after asking /who for the asker (Core/WhoCity.lua),
-- right click dismisses through ClickRouter with the look rule. The row
-- carries its lead and the GetTime() at which that lead appeared in it (§7.5 rule 3).
local LeadRow = {}

-- WM's row numbers: EDGE from the row's sides, ICON_GAP after the icon, MARK_GAP between the marks
-- and before the second line's end, NAME_GAP between the name and the age.
-- off-scale: the row's edge, the icon gap and the name gap are WhisperMessenger's row numbers.
local EDGE, ICON_GAP, NAME_GAP = 6, 10, 2
local MARK_GAP = Theme.LAYOUT.SPACE.XS
local ANCHOR = "ANCHOR_RIGHT"

local function now()
  return _G["GetTime"]()
end

-- `fn(lead) -> integer` says how many whispers of the lead's customer the player has not read in
-- WhisperMessenger (WhisperBridge.Activate sets it); nil clears it.
function LeadRow.SetUnreadSource(fn)
  LeadRowPaint.SetUnreadSource(fn)
end

-- Whether the row shows the tooltip: one another frame owns is never rewritten (nor hidden:
-- Tooltip.HideIfOwned).
local function ownsTip(row)
  local tip = Tooltip.Get()
  return tip:IsShown() and tip:IsOwned(row)
end

-- The row's lead's latest chat line; a full row's lead without a message shows none. A compact row
-- shows its tooltip either way: it is the only place its text is.
local function showChat(row)
  local lead = row.lead
  if lead == nil or (lead.message == nil and not row.compact) then
    Tooltip.HideIfOwned(row)
    return
  end
  local tip = Tooltip.Get()
  tip:SetOwner(row, ANCHOR)
  tip:SetMinimumWidth(Theme.LAYOUT.ROW_TIP_WIDTH)
  if row.compact then
    CardTipText.Compact(tip, lead)
  else
    CardTipText.Chat(tip, lead)
  end
  tip:Show()
end

local function onEnter(row)
  if not row.selected:IsShown() then
    RowArt.Hover(row.hover, true)
  end
  showChat(row)
end

local function onLeave(row)
  RowArt.Hover(row.hover, false)
  Tooltip.HideIfOwned(row)
end

-- Hidden (cleared, the window closed): the row comes back without the hover of its last use.
local function onHide(row)
  RowArt.Hover(row.hover, false, true)
  Tooltip.HideIfOwned(row)
end

-- Spec §9 B2: a left click on Forever and Classic first asks /who for the asker (a hardware event,
-- which SendWho needs); a lookup that raises never stops the select.
local function onClick(row, button)
  if button == "LeftButton" then
    if not FlavorCompat.isRetail then
      pcall(WhoCity.TryFor, row.lead)
    end
    row.onSelect(row)
  elseif button == "RightButton" then
    ClickRouter.Handle("RightButton", row.lead, row.shownAt)
  end
end

-- On screen again (the window reopened, UIParent back after Alt+Z): the lead counts as shown
-- from now, so the time under the hidden UI is no look (§7.5 rule 3).
local function onShow(row)
  if row.lead then
    row.shownAt = now()
  end
end

local function createMarks(row)
  local size = Theme.LAYOUT.ROW_ICON_SIZE
  local greeted = row:CreateTexture(nil, "ARTWORK")
  greeted:SetSize(size, size)
  greeted:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -EDGE, 4)
  greeted:SetTexture(Theme.GREETED_ICON)
  -- The check art is green: desaturated first, so the greeted blue is the colour that shows.
  local color = Theme.COLORS.greeted
  greeted:SetDesaturated(true)
  greeted:SetVertexColor(color[1], color[2], color[3], color[4])
  local replied = FrameKit.Text(row, Theme.FONTS.detail, Theme.COLORS.replied)
  replied:SetText(Localization.Text("replied"))
  return greeted, replied
end

-- A hidden row inside `parent`; the list anchors it. index: its slot, 1 at the top; onSelect(row):
-- called on a left click.
function LeadRow.Create(parent, index, onSelect)
  local layout, colors, fonts = Theme.LAYOUT, Theme.COLORS, Theme.FONTS
  local row = _G["CreateFrame"]("Button", nil, parent)
  row:SetHeight(layout.ROW_HEIGHT)
  row.isLeadRow, row.rowIndex, row.onSelect = true, index, onSelect
  row.hover, row.selected = RowArt.Overlays(row)
  row.iconFrame = RowArt.RoundIcon(row, layout.LIST_ICON_SIZE)
  row.iconFrame:SetPoint("LEFT", row, "LEFT", EDGE, 0)
  row.icon = row.iconFrame.texture
  row.dot = RowArt.Dot(row, row.iconFrame)
  -- WM puts the age's top 4 px above the name's (-6 from the row's top); anchored to the row, as
  -- the name's RIGHT already anchors to the age.
  row.age = FrameKit.Text(row, fonts.detail, colors.textSecondary)
  -- off-scale: WhisperMessenger row text offsets (-2, 1, -1).
  row.age:SetPoint("TOPRIGHT", row, "TOPRIGHT", -EDGE, -2)
  row.name = FrameKit.Text(row, fonts.name)
  row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", ICON_GAP, 1)
  row.name:SetPoint("RIGHT", row.age, "LEFT", -NAME_GAP, 0)
  row.what = FrameKit.Text(row, fonts.detail, colors.textSecondary)
  row.greetedIcon, row.repliedTag = createMarks(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", onClick)
  row:SetScript("OnShow", onShow)
  row:SetScript("OnEnter", onEnter)
  row:SetScript("OnLeave", onLeave)
  row:HookScript("OnHide", onHide)
  row:Hide()
  return row
end

-- The greeted check outermost, the replied tag left of it; the second line ends MARK_GAP short of
-- whichever marks show. A compact row shows neither.
local function placeMarks(row, lead)
  local tag = row.repliedTag
  row.greetedIcon:SetShown(lead.greeted and not row.compact)
  tag:SetShown(lead.replied and not row.compact)
  tag:ClearAllPoints()
  if lead.greeted then
    tag:SetPoint("BOTTOMRIGHT", row.greetedIcon, "BOTTOMLEFT", -MARK_GAP, 0)
  else
    tag:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -EDGE, 4)
  end
  local greetedWidth = lead.greeted and Theme.LAYOUT.ROW_ICON_SIZE + MARK_GAP or 0
  local marksWidth = greetedWidth + (lead.replied and tag:GetStringWidth() + MARK_GAP or 0)
  row.what:ClearAllPoints()
  -- off-scale: WhisperMessenger row text offset.
  row.what:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", ICON_GAP, -1)
  row.what:SetPoint("RIGHT", row, "RIGHT", -(EDGE + marksWidth), 0)
end

local scratch = {} -- LeadRowPaint.Read's table for the next Show; swapped with the row's on a repaint

-- Paints `paint` (a LeadRowPaint.Read table for the row's lead) into the row and shows it.
local function repaint(row, paint)
  row.icon:SetTexture(paint.icon)
  RowArt.PaintDot(row.dot, paint.dot)
  row.name:SetText(paint.name)
  row.name:SetTextColor(paint.nameR, paint.nameG, paint.nameB, 1)
  row.age:SetText(paint.age)
  row.what:SetText(paint.what)
  placeMarks(row, row.lead)
  row:Show()
end

-- Shows `lead` in the row; a lead new to the row counts as shown from now. A shown row whose paint
-- would not change (UI/LeadRowPaint.lua) is left as it is. A chat tooltip the row shows is rebuilt
-- for it (a refresh, a wheel scroll, a new chat line).
function LeadRow.Show(row, lead)
  if row.lead ~= lead then
    row.shownAt = now()
  end
  row.lead = lead
  LeadRowPaint.Read(lead, scratch)
  if not (row:IsShown() and LeadRowPaint.Same(row.painted, scratch)) then
    row.painted, scratch = scratch, row.painted or {}
    repaint(row, row.painted)
  end
  if ownsTip(row) then
    showChat(row)
  end
end

-- Compact: only the icon, centred in the row; else the full row. Applies to the lead shown now and
-- to the next ones.
function LeadRow.SetCompact(row, compact)
  row.compact = compact
  row.iconFrame:ClearAllPoints()
  if compact then
    row.iconFrame:SetPoint("CENTER", row, "CENTER", 0, 0)
  else
    row.iconFrame:SetPoint("LEFT", row, "LEFT", EDGE, 0)
  end
  row.name:SetShown(not compact)
  row.age:SetShown(not compact)
  row.what:SetShown(not compact)
  -- Without a lead the marks wait for Show, which places them.
  if row.lead then
    placeMarks(row, row.lead)
  end
end

-- Called on every row at each list refresh, so the hover changes only with the selection: the
-- click that selects a hovered row drops its hover at once; a row deselected under the cursor
-- fades it back in. The second line's colour is set only when it changes (`row.whatSelected`):
-- nothing else colours that line, and Clear hides the selection alone.
function LeadRow.SetSelected(row, selected)
  if row.selected:IsShown() ~= selected then
    row.selected:SetShown(selected)
    if selected then
      RowArt.Hover(row.hover, false, true)
    elseif row:IsMouseOver() then
      RowArt.Hover(row.hover, true)
    end
  end
  if row.whatSelected == selected then
    return
  end
  row.whatSelected = selected
  local color = selected and Theme.COLORS.white or Theme.COLORS.textSecondary
  row.what:SetTextColor(color[1], color[2], color[3], color[4])
end

-- The hover and selected overlays for `look`; the selected one keeps today's tint when native.
function LeadRow.ApplyLook(row, look)
  RowArt.ApplyLook(row.hover, row.selected, look, Theme.COLORS.selectedTint)
end

-- Hiding the row hides its chat tooltip and its hover too (the OnHide hook).
function LeadRow.Clear(row)
  row.lead, row.shownAt = nil, nil
  row.selected:Hide()
  row:Hide()
end

ns.LeadRow = LeadRow
return LeadRow
