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
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local CardBody = ns.CardBody or require("CraftAlert.UI.CardBody")
local CardHover = ns.CardHover or require("CraftAlert.UI.CardHover")
local CardTips = ns.CardTips or require("CraftAlert.UI.CardTips")

-- Lead-cards spec §1: one card of the leads window, full width. On the left the item or profession
-- icon, the customer, the age, the greeted check and the replied tag, then what matched and the
-- realm tag; on the right the Request / Matched / Crafters rows (UI/CardBody.lua). Every text is a
-- region of the card. No fill: the quest-log hover texture lights the card under the cursor, and
-- the Greet / Whisper / Dismiss buttons show with it (UI/CardHover.lua). Tooltips: UI/CardTips.lua.
-- Clicks follow the toast's table (§7.1); a link under the cursor shows its tooltip, and a click
-- while it is hovered goes to the link, never to the lead (native-HUD spec §4.6). The card frame
-- carries its lead and the GetTime() at which that lead appeared in it (§7.5 rule 3).
local LeadRow = {}

local min = math.min
local select = select
local tostring = tostring
local type = type

-- Line 1's gaps: GAP after the icon and after the name, MARK_GAP before the greeted check and the
-- replied tag.
local GAP, MARK_GAP = 6, 4

local function now()
  return _G["GetTime"]()
end

local function onClick(card, button)
  local overLink = LinkHover.IsOverLink(card)
  if overLink then
    return
  end
  ClickRouter.Handle(button, card.lead, card.shownAt)
end

-- On screen again (the window reopened, UIParent back after Alt+Z): the lead counts as shown
-- from now, so the time under the hidden UI is no look (§7.5 rule 3).
local function onShow(card)
  if card.lead then
    card.shownAt = now()
  end
end

-- The greeted check right after the age; the replied tag's place depends on the check (placeReplied).
local function createMarks(card)
  local size = Theme.LAYOUT.ROW_ICON_SIZE
  local greeted = card:CreateTexture(nil, "ARTWORK")
  greeted:SetSize(size, size)
  greeted:SetPoint("LEFT", card.age, "RIGHT", MARK_GAP, 0)
  greeted:SetTexture(Theme.GREETED_ICON)
  local replied = FrameKit.Text(card, Theme.FONTS.detail, Theme.COLORS.accent)
  replied:SetText(Localization.Text("replied"))
  return greeted, replied
end

-- The replied tag follows the greeted check when it shows, else the age.
local function placeReplied(card, greeted)
  card.repliedTag:ClearAllPoints()
  card.repliedTag:SetPoint("LEFT", greeted and card.greetedIcon or card.age, "RIGHT", MARK_GAP, 0)
end

-- Line 1 ends PADDING short of the right column: the name truncates so the age and marks always
-- show. The width is cleared first, as a set width bounds what GetStringWidth measures.
local function fitName(card, lead)
  local layout = Theme.LAYOUT
  local nameLeft = layout.PADDING + layout.HEADER_ICON_SIZE + GAP
  local room = layout.CARD_LEFT_WIDTH - layout.PADDING - nameLeft - GAP - card.age:GetStringWidth()
  if lead.greeted then
    room = room - MARK_GAP - layout.ROW_ICON_SIZE
  end
  if lead.replied then
    room = room - MARK_GAP - card.repliedTag:GetStringWidth()
  end
  card.name:SetWidth(0)
  card.name:SetWidth(min(card.name:GetStringWidth(), room))
end

-- A left-column line right under `above`, ending PADDING short of the right column.
local function leftLine(card, above, font, color)
  local layout = Theme.LAYOUT
  local line = FrameKit.Text(card, font, color)
  line:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
  line:SetPoint("RIGHT", card, "LEFT", layout.CARD_LEFT_WIDTH - layout.PADDING, 0)
  return line
end

-- A hidden card inside `parent`; the list anchors it. index: its slot, 1 at the top; list: the
-- list it belongs to (CardHover shows one card's buttons at a time).
function LeadRow.Create(parent, index, list)
  local layout, colors, fonts = Theme.LAYOUT, Theme.COLORS, Theme.FONTS
  local card = _G["CreateFrame"]("Button", nil, parent)
  card:SetHeight(layout.CARD_HEIGHT)
  card.isLeadRow, card.rowIndex = true, index
  card.hover = FrameKit.ListHighlight(card)
  card.icon = card:CreateTexture(nil, "ARTWORK")
  card.icon:SetSize(layout.HEADER_ICON_SIZE, layout.HEADER_ICON_SIZE)
  card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", layout.PADDING, -4)
  card.name = FrameKit.Text(card, fonts.name)
  card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", GAP, 0)
  card.age = FrameKit.Text(card, fonts.detail, colors.textTimestamp)
  card.age:SetPoint("LEFT", card.name, "RIGHT", GAP, 0)
  card.greetedIcon, card.repliedTag = createMarks(card)
  card.what = leftLine(card, card.name, fonts.name)
  card.realm = leftLine(card, card.what, fonts.body, colors.warning)
  CardBody.Create(card)
  card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  card:SetScript("OnClick", onClick)
  card:SetScript("OnShow", onShow)
  LinkHover.Attach(card, CardTips.ShowChat)
  CardHover.Attach(card, list)
  CardTips.Attach(card)
  card:Hide()
  return card
end

-- The item's icon, else the profession's, else the addon's.
local function iconOf(lead)
  local itemIcon = type(lead.itemID) == "number" and select(5, FlavorCompat.GetItemInfoInstant(lead.itemID))
  return itemIcon or FrameKit.ProfessionIcon(lead.prof) or Theme.ICON
end

-- Shows `lead` in the card; a lead new to the card counts as shown from now, the link under the
-- cursor belonged to the old lead, and so does a tooltip any of the card's frames owns (CardTips).
function LeadRow.Show(card, lead)
  local leadChanged = card.lead ~= lead
  if leadChanged then
    card.shownAt = now()
    LinkHover.Clear(card)
  end
  card.lead = lead
  card.icon:SetTexture(iconOf(lead))
  card.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(card.name, lead.guid)
  card.age:SetText(LeadText.Age(_G["time"]() - lead.time))
  card.what:SetText(LeadText.What(lead))
  local realm = LeadText.RealmTag(lead)
  card.realm:SetText(realm)
  card.realm:SetShown(realm ~= nil)
  card.greetedIcon:SetShown(lead.greeted)
  card.repliedTag:SetShown(lead.replied)
  placeReplied(card, lead.greeted)
  fitName(card, lead)
  CardBody.Paint(card, lead)
  CardTips.Refresh(card, leadChanged)
  card:Show()
end

function LeadRow.Clear(card)
  card.lead, card.shownAt = nil, nil
  LinkHover.Clear(card)
  card:Hide()
end

ns.LeadRow = LeadRow
return LeadRow
