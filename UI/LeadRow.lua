local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")

-- Spec §7.3: one row of the leads window. Customer and age on top; item or profession, crafter
-- and realm tag below; greeted check and replied tag on the right. No fill: the quest-log hover
-- texture lights the row under the cursor. Clicks follow the toast's table (§7.1); the item link
-- in the detail line shows its tooltip, and a click while it is hovered goes to the link, never
-- to the lead (native-HUD spec §4.6). The row frame carries its lead and the GetTime() at which
-- that lead appeared in it (§7.5 rule 3).
local LeadRow = {}

local concat = table.concat
local tostring = tostring

local function now()
  return _G["GetTime"]()
end

local function onClick(row, button)
  local overLink = LinkHover.IsOverLink(row)
  if overLink then
    return
  end
  ClickRouter.Handle(button, row.lead, row.shownAt)
end

-- On screen again (the window reopened, UIParent back after Alt+Z): the lead counts as shown
-- from now, so the time under the hidden UI is no look (§7.5 rule 3).
local function onShow(row)
  if row.lead then
    row.shownAt = now()
  end
end

local function setShown(region, shown)
  if shown then
    region:Show()
  else
    region:Hide()
  end
end

local function createMarks(row)
  local size = Theme.LAYOUT.ROW_ICON_SIZE
  local replied = FrameKit.Text(row, Theme.FONTS.detail, Theme.COLORS.accent)
  replied:SetPoint("RIGHT", row, "RIGHT", -Theme.LAYOUT.PADDING, 0)
  replied:SetText(Localization.Text("replied"))
  local greeted = row:CreateTexture(nil, "ARTWORK")
  greeted:SetSize(size, size)
  greeted:SetPoint("RIGHT", replied, "LEFT", -4, 0)
  greeted:SetTexture(Theme.GREETED_ICON)
  return greeted, replied
end

-- A hidden row inside `parent`; the window anchors it. index: its slot, 1 at the top.
function LeadRow.Create(parent, index)
  local layout, colors, fonts = Theme.LAYOUT, Theme.COLORS, Theme.FONTS
  local row = _G["CreateFrame"]("Button", nil, parent)
  row:SetHeight(layout.ROW_HEIGHT)
  row.isLeadRow, row.rowIndex = true, index
  row.hover = FrameKit.ListHighlight(row)
  row.greetedIcon, row.repliedTag = createMarks(row)
  row.name = FrameKit.Text(row, fonts.name)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", layout.PADDING, -4)
  row.age = FrameKit.Text(row, fonts.detail, colors.textTimestamp)
  row.age:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.detail = FrameKit.Text(row, fonts.body, colors.textSecondary)
  row.detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", layout.PADDING, 4)
  row.detail:SetPoint("RIGHT", row.greetedIcon, "LEFT", -layout.PADDING, 0)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", onClick)
  row:SetScript("OnShow", onShow)
  LinkHover.Attach(row, nil)
  row:Hide()
  return row
end

-- What matched, the crafter, the rank and the realm tag on one line.
local function detailText(lead)
  local parts = { LeadText.What(lead), LeadText.Crafter(lead) }
  parts[#parts + 1] = LeadText.Rank(lead)
  parts[#parts + 1] = LeadText.RealmTag(lead)
  return concat(parts, " · ")
end

-- Shows `lead` in the row; a lead new to the row counts as shown from now, and the link under
-- the cursor belonged to the old lead.
function LeadRow.Show(row, lead)
  if row.lead ~= lead then
    row.shownAt = now()
    LinkHover.Clear(row)
  end
  row.lead = lead
  row.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(row.name, lead.guid)
  row.age:SetText(LeadText.Age(_G["time"]() - lead.time))
  row.detail:SetText(detailText(lead))
  setShown(row.greetedIcon, lead.greeted)
  setShown(row.repliedTag, lead.replied)
  row:Show()
end

function LeadRow.Clear(row)
  row.lead, row.shownAt = nil, nil
  LinkHover.Clear(row)
  row:Hide()
end

ns.LeadRow = LeadRow
return LeadRow
