local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local DetailsBody = ns.DetailsBody or require("CraftAlert.UI.DetailsBody")

-- Spec A.4: the split view's details pane, the selected lead in full. A 56 px header (the
-- profession or item icon, the customer and the age, what was asked for, the greeted / replied /
-- realm status), the body's sections (UI/DetailsBody.lua), and an action bar with Greet, Whisper
-- and Dismiss. The header and the body each hover their links (LinkHover); tooltip zones lie over
-- the customer and, while it holds no link, the what line. The pane carries the GetTime() at
-- which its lead became the shown one, and the buttons run the look rule on it (§7.5 rule 3).
local LeadDetails = {}

local min = math.min
local select = select
local tostring = tostring
local type = type
local unpack = unpack

local ANCHOR = "ANCHOR_RIGHT"
-- Header lines: ICON_GAP right of the icon, the name NAME_TOP below the header's top, LINE_GAP
-- between lines, AGE_GAP between the name and the age.
local ICON_GAP, NAME_TOP, LINE_GAP, AGE_GAP = 10, -5, -3, 6
-- Action bar buttons: BUTTON_GAP apart, at most BUTTON_WIDTH wide (spec A.4 small hosts).
local BUTTON_GAP, BUTTON_WIDTH, BUTTON_HEIGHT = 8, 100, 22
local STATUS_GAP = "  "

-- Left to right: each button's key in details.buttons, its label and what it does to the shown
-- lead, read at click time. Greet and Dismiss act as a left and a right click, look rule included.
local ACTIONS = {
  {
    key = "greet",
    label = "Greet",
    run = function(details)
      ClickRouter.Handle("LeftButton", details.lead, details.shownAt)
    end,
  },
  {
    key = "whisper",
    label = "Whisper",
    run = function(details)
      GreetAction.Empty(details.lead)
    end,
  },
  {
    key = "dismiss",
    label = "Dismiss",
    run = function(details)
      ClickRouter.Handle("RightButton", details.lead, details.shownAt)
    end,
  },
}

local function now()
  return _G["GetTime"]()
end

local function themed(text, color)
  return FrameKit.ColorCode(text, unpack(color))
end

-- Forgets the header's and the body's hovered link and hides a tooltip any of the pane's frames owns.
local function hideOwned(details)
  LinkHover.Clear(details.header)
  LinkHover.Clear(details.body)
  for _, children in ipairs({ details.zones, details.buttons }) do
    for _, child in pairs(children) do
      DetailsBody.HideIfOwned(child)
    end
  end
end

local function createHeader(details)
  local layout, fonts = Theme.LAYOUT, Theme.FONTS
  local header = _G["CreateFrame"]("Button", nil, details.frame)
  header:SetHeight(layout.DETAILS_HEADER_HEIGHT)
  header:SetPoint("TOPLEFT", details.frame, "TOPLEFT", 0, -2)
  header:SetPoint("TOPRIGHT", details.frame, "TOPRIGHT", 0, -2)
  details.fill = header:CreateTexture(nil, "BACKGROUND")
  details.fill:SetAllPoints(header)
  details.fill:SetColorTexture(unpack(Theme.COLORS.headerFill))
  details.icon = header:CreateTexture(nil, "ARTWORK")
  details.icon:SetSize(layout.HEADER_ICON_SIZE, layout.HEADER_ICON_SIZE)
  details.icon:SetPoint("LEFT", header, "LEFT", layout.DETAILS_PADDING, 0)
  local textLeft = layout.DETAILS_PADDING + layout.HEADER_ICON_SIZE + ICON_GAP
  details.name = FrameKit.Text(header, _G["GameFontNormalLarge"] and fonts.heading or fonts.name)
  details.name:SetPoint("TOPLEFT", header, "TOPLEFT", textLeft, NAME_TOP)
  details.age = FrameKit.Text(header, fonts.detail, Theme.COLORS.textTimestamp)
  details.age:SetPoint("LEFT", details.name, "RIGHT", AGE_GAP, 0)
  details.what = FrameKit.Text(header, fonts.body)
  details.what:SetPoint("TOPLEFT", details.name, "BOTTOMLEFT", 0, LINE_GAP)
  details.what:SetPoint("RIGHT", header, "RIGHT", -layout.DETAILS_PADDING, 0)
  details.status = FrameKit.Text(header, fonts.body)
  details.status:SetPoint("TOPLEFT", details.what, "BOTTOMLEFT", 0, LINE_GAP)
  details.status:SetPoint("RIGHT", header, "RIGHT", -layout.DETAILS_PADDING, 0)
  LinkHover.Attach(header, nil)
  return header
end

local function createButton(details, action, previous)
  local button = _G["CreateFrame"]("Button", nil, details.bar, "UIPanelButtonTemplate")
  button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  if previous then
    button:SetPoint("LEFT", previous, "RIGHT", BUTTON_GAP, 0)
  else
    button:SetPoint("LEFT", details.bar, "LEFT", Theme.LAYOUT.DETAILS_PADDING, 0)
  end
  button:SetText(Localization.Text(action.label))
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", function()
    if details.lead then
      action.run(details)
    end
  end)
  return button
end

local function createBar(details)
  local bar = _G["CreateFrame"]("Frame", nil, details.frame)
  bar:SetHeight(Theme.LAYOUT.ACTION_BAR_HEIGHT)
  bar:SetPoint("BOTTOMLEFT", details.frame, "BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", details.frame, "BOTTOMRIGHT", 0, 0)
  details.bar = bar
  details.buttons = {}
  local previous
  for _, action in ipairs(ACTIONS) do
    previous = createButton(details, action, previous)
    details.buttons[action.key] = previous
  end
  local greet = details.buttons.greet
  greet:HookScript("OnEnter", function()
    local tip = Tooltip.Get()
    tip:SetOwner(greet, ANCHOR)
    CardTipText.Greet(tip)
    tip:Show()
  end)
  greet:HookScript("OnLeave", DetailsBody.HideIfOwned)
end

-- On screen again (the window reopened, UIParent back after Alt+Z): the lead counts as shown from
-- now, so the time under the hidden UI is no look (§7.5 rule 3).
local function onShow(details)
  if details.lead then
    details.shownAt = now()
  end
end

-- The pane inside `parent`, covering it, empty until Show.
function LeadDetails.New(parent)
  local details = {}
  local frame = _G["CreateFrame"]("Frame", nil, parent)
  frame:SetAllPoints(parent)
  details.frame = frame
  details.header = createHeader(details)
  createBar(details)
  local body = _G["CreateFrame"]("Button", nil, frame)
  body:SetClipsChildren(true)
  body:SetPoint("TOPLEFT", details.header, "BOTTOMLEFT", 0, 0)
  body:SetPoint("BOTTOMRIGHT", details.bar, "TOPRIGHT", 0, 0)
  LinkHover.Attach(body, nil)
  details.body = body
  details.sections = DetailsBody.Create(body)
  details.zones = {
    name = DetailsBody.Zone(details, details.header, details.name, details.name, CardTipText.Customer),
    what = DetailsBody.Zone(details, details.header, details.what, details.what, CardTipText.What),
    matched = details.sections.zones.matched,
    crafters = details.sections.zones.crafters,
  }
  frame:SetScript("OnShow", function()
    onShow(details)
  end)
  frame:SetScript("OnHide", function()
    hideOwned(details)
  end)
  frame:Hide()
  return details
end

-- The profession's icon, else the item's, else the addon's.
local function iconOf(lead)
  local itemIcon = type(lead.itemID) == "number" and select(5, FlavorCompat.GetItemInfoInstant(lead.itemID))
  return FrameKit.ProfessionIcon(lead.prof) or itemIcon or Theme.ICON
end

-- What was asked for, then the profession in gold unless that is what was asked for.
local function whatText(lead)
  local what, profession = LeadText.What(lead), lead.profName
  if profession == nil or profession == what then
    return what
  end
  return what .. " · " .. themed(profession, Theme.COLORS.gold)
end

-- Greeted (green, after the check), replied (accent), then the realm warning; each when set.
local function statusText(lead)
  local colors, parts = Theme.COLORS, {}
  if lead.greeted then
    parts[#parts + 1] = "|T" .. Theme.GREETED_ICON .. ":14|t " .. themed(Localization.Text("Greeted"), colors.greeted)
  end
  if lead.replied then
    parts[#parts + 1] = themed(Localization.Text("Replied"), colors.accent)
  end
  local realm = LeadText.RealmTag(lead)
  if realm then
    parts[#parts + 1] = themed(realm, colors.warning)
  end
  return table.concat(parts, STATUS_GAP)
end

local function paintHeader(details, lead)
  details.icon:SetTexture(iconOf(lead))
  details.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(details.name, lead.guid)
  details.age:SetText(LeadText.Age(_G["time"]() - lead.time))
  details.what:SetText(whatText(lead))
  details.status:SetText(statusText(lead))
end

-- Shows `lead`; one other than the shown lead counts as shown from now and takes down the
-- tooltip the pane's frames own. The same lead repainted (edited in place) keeps its time.
function LeadDetails.Show(details, lead)
  if details.lead ~= lead then
    details.shownAt = now()
    hideOwned(details)
  end
  details.lead = lead
  paintHeader(details, lead)
  DetailsBody.Paint(details.sections, lead)
  details.zones.what:SetShown(lead.itemLink == nil)
  details.frame:Show()
end

function LeadDetails.Clear(details)
  details.lead, details.shownAt, details.sections.lead = nil, nil, nil
  details.frame:Hide()
end

-- The pane is `width` wide (0 or less: not known yet): the three buttons share it, up to
-- BUTTON_WIDTH each.
function LeadDetails.Layout(details, width)
  local room = Theme.LAYOUT.DETAILS_PADDING * 2 + BUTTON_GAP * (#ACTIONS - 1)
  local buttonWidth = width > 0 and min(BUTTON_WIDTH, (width - room) / #ACTIONS) or BUTTON_WIDTH
  for _, button in pairs(details.buttons) do
    button:SetWidth(buttonWidth)
  end
end

ns.LeadDetails = LeadDetails
return LeadDetails
