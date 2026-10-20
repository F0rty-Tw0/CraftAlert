local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")

-- Spec §7.3: one row of the leads window. Customer and age on top; item or profession, crafter
-- and realm tag below; greeted check, replied tag and the "Block" button on the right. Clicks
-- follow the toast's table (§7.1). The row frame carries its lead and the GetTime() at which
-- that lead appeared in it (§7.5 rule 3).
local LeadRow = {}

local concat = table.concat
local tostring = tostring

local function now()
  return _G["GetTime"]()
end

local function onClick(row, button)
  ClickRouter.Handle(button, row.lead, row.shownAt)
end

local function onBlock(button)
  local lead = button.row.lead
  if lead then
    Leads.Block(lead.customer)
  end
end

local function setShown(region, shown)
  if shown then
    region:Show()
  else
    region:Hide()
  end
end

local function createBlockButton(row)
  local layout = Theme.LAYOUT
  local button = _G["CreateFrame"]("Button", nil, row)
  button:SetSize(layout.BLOCK_BUTTON_WIDTH, layout.BLOCK_BUTTON_HEIGHT)
  button:SetPoint("RIGHT", row, "RIGHT", -layout.PADDING, 0)
  FrameKit.Panel(button, Theme.COLORS.danger)
  local label = FrameKit.Text(button, Theme.FONTS.detail, Theme.COLORS.textPrimary)
  label:SetPoint("CENTER", button, "CENTER", 0, 0)
  label:SetJustifyH("CENTER")
  label:SetText(Localization.Text("Block"))
  button.row = row
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", onBlock)
  return button
end

local function createMarks(row, blockButton)
  local size = Theme.LAYOUT.ROW_ICON_SIZE
  local replied = FrameKit.Text(row, Theme.FONTS.detail, Theme.COLORS.accent)
  replied:SetPoint("RIGHT", blockButton, "LEFT", -Theme.LAYOUT.PADDING, 0)
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
  local background = row:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(row)
  FrameKit.Fill(background, colors.surfaceRaised)
  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints(row)
  FrameKit.Fill(hover, colors.rowHover)
  row.blockButton = createBlockButton(row)
  row.greetedIcon, row.repliedTag = createMarks(row, row.blockButton)
  row.name = FrameKit.Text(row, fonts.name)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", layout.PADDING, -4)
  row.age = FrameKit.Text(row, fonts.detail, colors.textTimestamp)
  row.age:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.detail = FrameKit.Text(row, fonts.body, colors.textSecondary)
  row.detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", layout.PADDING, 4)
  row.detail:SetPoint("RIGHT", row.greetedIcon, "LEFT", -layout.PADDING, 0)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", onClick)
  row:Hide()
  return row
end

-- What matched, the crafter and the realm tag on one line.
local function detailText(lead)
  local parts = { LeadText.What(lead), LeadText.Crafter(lead) }
  parts[#parts + 1] = LeadText.RealmTag(lead)
  return concat(parts, " · ")
end

-- Shows `lead` in the row; a lead new to the row counts as shown from now.
function LeadRow.Show(row, lead)
  if row.lead ~= lead then
    row.shownAt = now()
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
  row:Hide()
end

ns.LeadRow = LeadRow
return LeadRow
