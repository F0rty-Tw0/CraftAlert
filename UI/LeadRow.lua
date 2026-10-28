local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local RowArt = ns.RowArt or require("CraftAlert.UI.RowArt")

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
-- the row (onSelect), right click dismisses through ClickRouter with the look rule. The row
-- carries its lead and the GetTime() at which that lead appeared in it (§7.5 rule 3).
local LeadRow = {}

local select = select
local tostring = tostring
local type = type

-- Whisper pink for a lead whose customer has an unread whisper, when ChatTypeInfo has no WHISPER.
local FALLBACK_PINK = { 1, 0.5, 1, 1 }

-- WM's row numbers: EDGE from the row's sides, ICON_GAP after the icon, MARK_GAP between the marks
-- and before the second line's end, NAME_GAP between the name and the age.
-- off-scale: the row's edge, the icon gap and the name gap are WhisperMessenger's row numbers.
local EDGE, ICON_GAP, NAME_GAP = 6, 10, 2
local MARK_GAP = Theme.LAYOUT.SPACE.XS
local ANCHOR = "ANCHOR_RIGHT"

local function now()
  return _G["GetTime"]()
end

---@type fun(lead: table): number|nil
local unreadOf = nil -- WhisperMessenger's unread count of a lead's customer; nil: none known

-- `fn(lead) -> integer` says how many whispers of the lead's customer the player has not read in
-- WhisperMessenger (WhisperBridge.Activate sets it); nil clears it.
function LeadRow.SetUnreadSource(fn)
  unreadOf = fn
end

-- Whisper pink, read at paint time (the player can recolour the whisper chat type).
local function whisperPink()
  local info = _G["ChatTypeInfo"]
  local whisper = type(info) == "table" and info.WHISPER
  if type(whisper) ~= "table" then
    return FALLBACK_PINK
  end
  return { whisper.r, whisper.g, whisper.b, 1 }
end

-- The dot's colour, first match wins: pink while the customer has an unread whisper, gold while
-- the lead is unseen and ungreeted, else the details header's state colour.
local function dotColor(lead)
  local unread = unreadOf and unreadOf(lead)
  if type(unread) == "number" and unread >= 1 then
    return whisperPink()
  end
  return Leads.IsUnseen(lead) and Theme.COLORS.gold or select(2, LeadText.State(lead))
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

local function onClick(row, button)
  if button == "LeftButton" then
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

-- The item's icon, else the profession's, else the addon's.
local function iconOf(lead)
  local itemIcon = type(lead.itemID) == "number" and select(5, FlavorCompat.GetItemInfoInstant(lead.itemID))
  return itemIcon or FrameKit.ProfessionIcon(lead.prof) or Theme.ICON
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

-- Shows `lead` in the row; a lead new to the row counts as shown from now. A chat tooltip the row
-- shows is rebuilt for it (a refresh, a wheel scroll, a new chat line).
function LeadRow.Show(row, lead)
  if row.lead ~= lead then
    row.shownAt = now()
  end
  row.lead = lead
  row.icon:SetTexture(iconOf(lead))
  RowArt.PaintDot(row.dot, dotColor(lead))
  row.name:SetText(tostring(lead.customer))
  -- A customer of unknown class: white on the row (spec D6).
  local r, g, b = FrameKit.ClassRGB(FrameKit.GuidClassColor(lead.guid), Theme.COLORS.white)
  row.name:SetTextColor(r, g, b, 1)
  row.age:SetText(LeadText.Age(_G["time"]() - lead.time))
  row.what:SetText(LeadText.What(lead))
  placeMarks(row, lead)
  row:Show()
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
-- fades it back in. The second line's colour is set every time: Clear hides the selection alone.
function LeadRow.SetSelected(row, selected)
  if row.selected:IsShown() ~= selected then
    row.selected:SetShown(selected)
    if selected then
      RowArt.Hover(row.hover, false, true)
    elseif row:IsMouseOver() then
      RowArt.Hover(row.hover, true)
    end
  end
  local color = selected and Theme.COLORS.white or Theme.COLORS.textSecondary
  row.what:SetTextColor(color[1], color[2], color[3], color[4])
end

-- Hiding the row hides its chat tooltip and its hover too (the OnHide hook).
function LeadRow.Clear(row)
  row.lead, row.shownAt = nil, nil
  row.selected:Hide()
  row:Hide()
end

ns.LeadRow = LeadRow
return LeadRow
