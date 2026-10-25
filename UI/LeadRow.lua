local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")

-- Spec A.3: one 48 px row of the leads list pane, WhisperMessenger's contact-row layout
-- (UI/ContactsList/RowView.lua:67-118, WM). The item or profession icon, the customer in class
-- colour with the age on its right, and below what was requested, then the greeted check and the
-- replied tag at the bottom right. No link hover; one tooltip, the latest chat line while the
-- cursor is on the row (row-chat-tooltip spec). The details pane has the other tooltips.
-- Left click selects the row (onSelect), right click dismisses through ClickRouter with the look
-- rule. The row carries its lead and the GetTime() at which that lead appeared in it (§7.5 rule 3).
local LeadRow = {}

local select = select
local tostring = tostring
local type = type

-- WM's row numbers: EDGE from the row's sides, ICON_GAP after the icon, MARK_GAP between the marks
-- and before the second line's end.
local EDGE, ICON_GAP, MARK_GAP = 6, 10, 4
local ANCHOR = "ANCHOR_RIGHT"

local function now()
  return _G["GetTime"]()
end

-- Only a tooltip the row shows: one another frame owns is never hidden or rewritten.
local function ownsTip(row)
  local tip = Tooltip.Get()
  return tip:IsShown() and tip:IsOwned(row)
end

local function hideChat(row)
  if ownsTip(row) then
    Tooltip.Get():Hide()
  end
end

-- The row's lead's latest chat line; a lead without a message shows none.
local function showChat(row)
  local lead = row.lead
  if lead == nil or lead.message == nil then
    hideChat(row)
    return
  end
  local tip = Tooltip.Get()
  tip:SetOwner(row, ANCHOR)
  CardTipText.Chat(tip, lead)
  tip:Show()
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

local function createSelected(row)
  local art = Theme.ART
  local selected = row:CreateTexture(nil, "ARTWORK")
  selected:SetAllPoints(row)
  selected:SetTexture(art.LIST_SELECTED)
  selected:SetBlendMode("ADD")
  selected:SetAlpha(art.LIST_SELECTED_ALPHA)
  selected:Hide()
  return selected
end

local function createMarks(row)
  local size = Theme.LAYOUT.ROW_ICON_SIZE
  local greeted = row:CreateTexture(nil, "ARTWORK")
  greeted:SetSize(size, size)
  greeted:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -EDGE, 4)
  greeted:SetTexture(Theme.GREETED_ICON)
  local replied = FrameKit.Text(row, Theme.FONTS.detail, Theme.COLORS.accent)
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
  row.hover = FrameKit.ListHighlight(row)
  row.selected = createSelected(row)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(layout.LIST_ICON_SIZE, layout.LIST_ICON_SIZE)
  row.icon:SetPoint("LEFT", row, "LEFT", EDGE, 0)
  row.age = FrameKit.Text(row, fonts.detail, colors.textTimestamp)
  row.age:SetPoint("TOPRIGHT", row, "TOPRIGHT", -EDGE, -4)
  row.name = FrameKit.Text(row, fonts.name)
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", ICON_GAP, -1)
  row.name:SetPoint("RIGHT", row.age, "LEFT", -EDGE, 0)
  row.what = FrameKit.Text(row, fonts.body)
  row.greetedIcon, row.repliedTag = createMarks(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", onClick)
  row:SetScript("OnShow", onShow)
  row:SetScript("OnEnter", showChat)
  row:SetScript("OnLeave", hideChat)
  row:HookScript("OnHide", hideChat)
  row:Hide()
  return row
end

-- The item's icon, else the profession's, else the addon's.
local function iconOf(lead)
  local itemIcon = type(lead.itemID) == "number" and select(5, FlavorCompat.GetItemInfoInstant(lead.itemID))
  return itemIcon or FrameKit.ProfessionIcon(lead.prof) or Theme.ICON
end

-- The greeted check outermost, the replied tag left of it; the second line ends MARK_GAP short of
-- whichever marks show.
local function placeMarks(row, lead)
  local tag = row.repliedTag
  row.greetedIcon:SetShown(lead.greeted)
  tag:SetShown(lead.replied)
  tag:ClearAllPoints()
  if lead.greeted then
    tag:SetPoint("BOTTOMRIGHT", row.greetedIcon, "BOTTOMLEFT", -MARK_GAP, 0)
  else
    tag:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -EDGE, 4)
  end
  local greetedWidth = lead.greeted and Theme.LAYOUT.ROW_ICON_SIZE + MARK_GAP or 0
  local marksWidth = greetedWidth + (lead.replied and tag:GetStringWidth() + MARK_GAP or 0)
  row.what:ClearAllPoints()
  row.what:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", ICON_GAP, 1)
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
  row.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(row.name, lead.guid)
  row.age:SetText(LeadText.Age(_G["time"]() - lead.time))
  row.what:SetText(LeadText.What(lead))
  placeMarks(row, lead)
  row:Show()
  if ownsTip(row) then
    showChat(row)
  end
end

function LeadRow.SetSelected(row, selected)
  row.selected:SetShown(selected)
end

-- Hiding the row hides its chat tooltip too (the OnHide hook).
function LeadRow.Clear(row)
  row.lead, row.shownAt = nil, nil
  row.selected:Hide()
  row:Hide()
end

ns.LeadRow = LeadRow
return LeadRow
