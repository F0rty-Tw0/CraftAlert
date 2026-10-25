local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local CardBody = ns.CardBody or require("CraftAlert.UI.CardBody")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local MainCrafterMenu = ns.MainCrafterMenu or require("CraftAlert.UI.MainCrafterMenu")

-- Spec A.4, the details pane's body: the Request, Matched, Crafters and Channel sections, each a
-- gold label over its value, at fixed places from the body's top. Every text is a region of the
-- body frame, so LinkHover on it sees the request's links. A section the lead has nothing for
-- hides and leaves its space. Tooltip zones lie over Matched and Crafters (never over the
-- Request); a left-click on the Crafters zone opens the main-crafter menu (main-crafter spec §3),
-- and every other click on a zone does nothing. UI/LeadDetails.lua builds the header and the
-- action bar around it.
local DetailsBody = {}

local ipairs = ipairs
local unpack = unpack

local ANCHOR = "ANCHOR_RIGHT"
-- Heights: a label, one line of a single-line value or of the request, one crafter line.
local LABEL_HEIGHT, LINE_HEIGHT, CRAFTER_LINE_HEIGHT = 14, 14, 12
local REQUEST_LINES, CRAFTER_LINES = 4, 3
-- The first label's distance below the body's top.
local FIRST_TOP = 12

local FONTS, COLORS = Theme.FONTS, Theme.COLORS
-- Top to bottom: each section's key in sections.labels / sections.values (sections.crafters for
-- the crafter lines), its label, the height under the label, and its value's font and colour.
local SECTIONS = {
  { key = "request", label = "Request", height = REQUEST_LINES * LINE_HEIGHT, font = FONTS.title },
  { key = "matched", label = "Matched", height = LINE_HEIGHT, font = FONTS.body },
  { key = "crafters", label = "Crafters", height = CRAFTER_LINES * CRAFTER_LINE_HEIGHT, font = FONTS.body },
  { key = "channel", label = "Channel", height = LINE_HEIGHT, font = FONTS.body, color = COLORS.textSecondary },
}

-- The section stack's height: the first label's offset, every label and value, the gaps between.
DetailsBody.HEIGHT = FIRST_TOP + (#SECTIONS - 1) * Theme.LAYOUT.DETAILS_GAP
for _, section in ipairs(SECTIONS) do
  DetailsBody.HEIGHT = DetailsBody.HEIGHT + LABEL_HEIGHT + section.height
end

local function themed(text, color)
  return FrameKit.ColorCode(text, unpack(color))
end

local function swallow() end

function DetailsBody.HideIfOwned(frame)
  local tip = Tooltip.Get()
  if tip:IsOwned(frame) then
    tip:Hide()
  end
end

-- A mouse-enabled Button child of `parent`, with no text, over the regions `first` through `last`.
-- The cursor on it shows `build(tip, holder.lead)`, the lead read then; a click does nothing.
function DetailsBody.Zone(holder, parent, first, last, build)
  local zone = _G["CreateFrame"]("Button", nil, parent)
  zone:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
  zone:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
  zone:EnableMouse(true)
  zone:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  zone:SetScript("OnClick", swallow)
  zone:SetScript("OnEnter", function()
    local lead = holder.lead
    if lead == nil then
      return
    end
    local tip = Tooltip.Get()
    tip:SetOwner(zone, ANCHOR)
    build(tip, lead)
    tip:Show()
  end)
  zone:SetScript("OnLeave", DetailsBody.HideIfOwned)
  return zone
end

-- One line from `top` to the body's right edge, both PADDING in.
local function valueText(body, section, top)
  local padding = Theme.LAYOUT.DETAILS_PADDING
  local text = FrameKit.Text(body, section.font, section.color)
  text:SetPoint("TOPLEFT", body, "TOPLEFT", padding, top)
  text:SetPoint("RIGHT", body, "RIGHT", -padding, 0)
  return text
end

-- The request wraps to REQUEST_LINES lines; a client without SetMaxLines clips it at their height.
local function wrapRequest(value)
  value:SetWordWrap(true)
  value:SetJustifyV("TOP")
  if value.SetMaxLines then
    value:SetMaxLines(REQUEST_LINES)
  else
    value:SetHeight(REQUEST_LINES * LINE_HEIGHT)
  end
end

local function createZones(sections, body)
  local labels = sections.labels
  sections.zones.matched = DetailsBody.Zone(sections, body, labels.matched, sections.values.matched, CardTipText.Matched)
  local crafters = DetailsBody.Zone(sections, body, labels.crafters, sections.crafters[CRAFTER_LINES], CardTipText.Crafters)
  crafters:SetScript("OnClick", function(zone, button)
    local lead = sections.lead
    if button == "LeftButton" and lead and MainCrafterMenu.CanOpen(lead) then
      MainCrafterMenu.Open(zone, lead)
    end
  end)
  sections.zones.crafters = crafters
end

-- The sections' texts on `body` and the two zones. → sections: { labels, values (request,
-- matched, channel), crafters (the lines, top first), zones (matched, crafters), lead }.
function DetailsBody.Create(body)
  local sections = { labels = {}, values = {}, crafters = {}, zones = {} }
  local top = -FIRST_TOP
  for _, section in ipairs(SECTIONS) do
    local label = FrameKit.Text(body, FONTS.name)
    label:SetPoint("TOPLEFT", body, "TOPLEFT", Theme.LAYOUT.DETAILS_PADDING, top)
    label:SetText(Localization.Text(section.label))
    sections.labels[section.key] = label
    top = top - LABEL_HEIGHT
    if section.key == "crafters" then
      for index = 1, CRAFTER_LINES do
        sections.crafters[index] = valueText(body, section, top - (index - 1) * CRAFTER_LINE_HEIGHT)
      end
    else
      sections.values[section.key] = valueText(body, section, top)
    end
    top = top - section.height - Theme.LAYOUT.DETAILS_GAP
  end
  wrapRequest(sections.values.request)
  createZones(sections, body)
  return sections
end

-- Shows `text` in the section `key`, or hides its label and value when it is nil.
local function setSection(sections, key, text)
  local label, value = sections.labels[key], sections.values[key]
  label:SetShown(text ~= nil)
  value:SetShown(text ~= nil)
  if text ~= nil then
    value:SetText(text)
  end
end

local function channelText(lead)
  local at = _G["date"]("%H:%M", lead.time)
  local name = LeadText.Channel(lead)
  return name and (name .. " · " .. at) or at
end

-- The name in its class colour (white unknown), then the rank in grey.
local function crafterLine(crafter)
  local color = crafter.color
  local name = color and FrameKit.ColorCode(crafter.name, color.r, color.g, color.b) or themed(crafter.name, COLORS.white)
  if crafter.rank == nil then
    return name
  end
  return name .. themed(" " .. crafter.rank, COLORS.grey)
end

-- One crafter per line, at most CRAFTER_LINES; the last line ends with how many more there are.
-- None: "None known" in grey.
local function paintCrafters(lines, lead)
  local entries = CardBody.Crafters(lead)
  for index, line in ipairs(lines) do
    local crafter = entries[index]
    line:SetShown(crafter ~= nil)
    if crafter then
      line:SetText(crafterLine(crafter))
    end
  end
  local more = #entries - CRAFTER_LINES
  if more > 0 then
    local last = lines[CRAFTER_LINES]
    last:SetText(last:GetText() .. themed(" " .. Localization.Text("+%d more", more), COLORS.grey))
  end
  if entries[1] == nil then
    lines[1]:SetText(themed(Localization.Text("None known"), COLORS.grey))
    lines[1]:Show()
  end
end

function DetailsBody.Paint(sections, lead)
  sections.lead = lead
  setSection(sections, "request", lead.message)
  setSection(sections, "matched", CardBody.MatchedText(lead))
  setSection(sections, "channel", channelText(lead))
  paintCrafters(sections.crafters, lead)
  sections.zones.matched:SetShown(sections.values.matched:IsShown())
end

ns.DetailsBody = DetailsBody
return DetailsBody
