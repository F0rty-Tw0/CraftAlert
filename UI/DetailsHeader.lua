local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local RowArt = ns.RowArt or require("CraftAlert.UI.RowArt")

-- Details spec A.1-A.2: the details pane's header and the info strip under it. The header: the
-- round profession or item icon with a status dot, the customer at 17 px in class colour, then
-- two 55 % white lines (class, status and age; channel and time). The strip: what the lead wants,
-- its profession in gold and the crafter in class colour, on up to two lines the client cuts with
-- "…", the strip as tall as they need (FitStrip); it hovers its link (LinkHover). UI/LeadDetails.lua lays the tooltip zones over the name and
-- the strip.
local DetailsHeader = {}

local find = string.find
local max = math.max
local min = math.min
local select = select
local tostring = tostring
local type = type
local unpack = unpack

-- The name ICON_GAP right of the icon and NAME_TOP below the header's top, NAME_SIZE px high;
-- LINE_GAP between the header's lines.
local ICON_GAP, NAME_TOP, NAME_SIZE, LINE_GAP = 10, -8, 17, -3
local NAME_LEFT = Theme.LAYOUT.DETAILS_PADDING + Theme.LAYOUT.HEADER_ICON_SIZE + ICON_GAP
local LINE_SEPARATOR, STRIP_SEPARATOR = "  -  ", " · "
-- The strip's text wraps to at most STRIP_LINES lines.
local STRIP_LINES = 2
-- The strip's plain words: textSecondary with its alpha folded into the colour, so the link,
-- the profession and the crafter keep their full colour.
local STRIP_COLOR = FrameKit.Opaque(Theme.COLORS.textSecondary)

-- Line 1: "Class  -  status  -  age"; a customer of unknown class leaves the class part out.
function DetailsHeader.LineOne(lead)
  local parts = { FrameKit.ClassName(FlavorCompat.ClassOf(lead.guid)) }
  parts[#parts + 1] = Localization.Text((LeadText.State(lead)))
  parts[#parts + 1] = LeadText.Age(_G["time"]() - lead.time)
  return table.concat(parts, LINE_SEPARATOR)
end

-- Line 2: "Channel  -  HH:MM", the time alone for a lead without a channel.
function DetailsHeader.LineTwo(lead)
  local at = _G["date"]("%H:%M", lead.time)
  local channel = LeadText.Channel(lead)
  return channel and (channel .. LINE_SEPARATOR .. at) or at
end

-- The crafter's short name in the class saved for them, white when none is; nil without a crafter.
local function crafterText(lead, db)
  if lead.crafter == nil then
    return nil
  end
  local character = db.characters[lead.crafter]
  local color = character and FrameKit.ClassColor(character.class)
  return FrameKit.ClassCode(Greeting.CrafterName(lead.crafter), color, Theme.COLORS.white)
end

-- The strip: "Wants <link or recipe> · <profession> · <crafter>", each part (and the " · "
-- before it) left out when missing; a profession lead "Wants a <profession> crafter" ("an"
-- before a vowel). Colour codes for the profession (gold) and the crafter; the link keeps its own.
function DetailsHeader.Strip(lead, db)
  local profName = lead.profName
  local profession = profName and FrameKit.ThemeCode(profName, Theme.COLORS.gold)
  if lead.kind == "profession" and profession then
    local article = find(profName, "^[AEIOUaeiou]") and "Wants an %s crafter" or "Wants a %s crafter"
    return Localization.Text(article, profession)
  end
  local what = lead.itemLink or lead.recipeName
  local parts = { what and Localization.Text("Wants %s", what) }
  -- A nil part adds nothing.
  parts[#parts + 1] = profession
  parts[#parts + 1] = crafterText(lead, db)
  return table.concat(parts, STRIP_SEPARATOR)
end

-- The profession's icon, else the item's, else the addon's.
local function iconOf(lead)
  local itemIcon = type(lead.itemID) == "number" and select(5, FlavorCompat.GetItemInfoInstant(lead.itemID))
  return FrameKit.ProfessionIcon(lead.prof) or itemIcon or Theme.ICON
end

-- GameFontNormalLarge's own file at NAME_SIZE when the client has the font, else GameFontNormal.
local function createName(header)
  if not _G["GameFontNormalLarge"] then
    return FrameKit.Text(header, Theme.FONTS.name)
  end
  local name = FrameKit.Text(header, Theme.FONTS.heading)
  local file, _, flags = name:GetFont()
  name:SetFont(file, NAME_SIZE, flags)
  return name
end

-- A 1 px line along the frame's `edge` ("TOP" or "BOTTOM"), as the mock's borders.
local function divider(frame, edge)
  local line = frame:CreateTexture(nil, "BORDER")
  line:SetHeight(1)
  line:SetPoint(edge .. "LEFT", frame, edge .. "LEFT", 0, 0)
  line:SetPoint(edge .. "RIGHT", frame, edge .. "RIGHT", 0, 0)
  line:SetColorTexture(unpack(Theme.COLORS.divider))
end

local function createStrip(details)
  local padding = Theme.LAYOUT.DETAILS_PADDING
  local strip = _G["CreateFrame"]("Button", nil, details.frame)
  strip:SetHeight(Theme.LAYOUT.INFO_STRIP_HEIGHT)
  strip:SetPoint("TOPLEFT", details.header, "BOTTOMLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", details.header, "BOTTOMRIGHT", 0, 0)
  local fill = strip:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(strip)
  fill:SetColorTexture(unpack(Theme.COLORS.headerFill))
  divider(strip, "TOP")
  divider(strip, "BOTTOM")
  local text = FrameKit.Text(strip, Theme.FONTS.body, STRIP_COLOR)
  text:SetPoint("LEFT", strip, "LEFT", padding, 0)
  text:SetWordWrap(true)
  if text.SetMaxLines then
    text:SetMaxLines(STRIP_LINES)
  end
  LinkHover.Attach(strip, nil)
  details.strip, details.stripText = strip, text
end

-- The header (details.header: fill, icon, dot, name, lineOne, lineTwo) at the pane's top and
-- the strip (details.strip, its text details.stripText) under it.
function DetailsHeader.Create(details)
  local layout, fonts = Theme.LAYOUT, Theme.FONTS
  local header = _G["CreateFrame"]("Frame", nil, details.frame)
  header:SetHeight(layout.DETAILS_HEADER_HEIGHT)
  header:SetPoint("TOPLEFT", details.frame, "TOPLEFT", 0, -2)
  header:SetPoint("TOPRIGHT", details.frame, "TOPRIGHT", 0, -2)
  details.header = header
  details.fill = header:CreateTexture(nil, "BACKGROUND")
  details.fill:SetAllPoints(header)
  details.fill:SetColorTexture(unpack(Theme.COLORS.headerFill))
  details.icon = RowArt.RoundIcon(header, layout.HEADER_ICON_SIZE)
  details.icon:SetPoint("LEFT", header, "LEFT", layout.DETAILS_PADDING, 0)
  details.dot = RowArt.Dot(header, details.icon)
  details.name = createName(header)
  details.name:SetPoint("TOPLEFT", header, "TOPLEFT", NAME_LEFT, NAME_TOP)
  local previous = details.name
  for _, key in ipairs({ "lineOne", "lineTwo" }) do
    local line = FrameKit.Text(header, fonts.body, Theme.COLORS.textSecondary)
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, LINE_GAP)
    line:SetPoint("RIGHT", header, "RIGHT", -layout.DETAILS_PADDING, 0)
    details[key], previous = line, line
  end
  createStrip(details)
end

-- Cuts the name with an ellipsis so it ends details.rightInset before the header's right edge.
-- Run when the width, the inset or the name changes. The name is as wide as its text first, so
-- the client measures it uncut (an unset width is 0, so the cut keeps at least 1).
function DetailsHeader.FitName(details)
  local name = details.name
  name:SetWidth(0)
  if details.width <= 0 then
    return
  end
  name:SetWidth(max(1, min(name:GetStringWidth(), details.width - NAME_LEFT - details.rightInset)))
end

-- Wraps the strip's text at the pane's width less the padding on each side, to STRIP_LINES lines
-- (the client cuts the last with "…"), and grows the strip by the lines past the first, so the
-- padding stays INFO_STRIP_HEIGHT's. Run when the width or the text changes; a width not known yet
-- (0) leaves one uncut line.
function DetailsHeader.FitStrip(details)
  local text, padding = details.stripText, Theme.LAYOUT.DETAILS_PADDING
  text:SetWidth(details.width > 0 and max(1, details.width - 2 * padding) or 0)
  local lines, height = text.GetNumLines and text:GetNumLines() or 1, text:GetStringHeight()
  local extra = lines > 1 and height - height / lines or 0
  details.strip:SetHeight(Theme.LAYOUT.INFO_STRIP_HEIGHT + extra)
end

function DetailsHeader.Paint(details, lead)
  local _, dotColor = LeadText.State(lead)
  details.icon.texture:SetTexture(iconOf(lead))
  RowArt.PaintDot(details.dot, dotColor)
  details.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(details.name, lead.guid)
  DetailsHeader.FitName(details)
  details.lineOne:SetText(DetailsHeader.LineOne(lead))
  details.lineTwo:SetText(DetailsHeader.LineTwo(lead))
  details.stripText:SetText(DetailsHeader.Strip(lead, _G["CraftAlertDB"]))
  DetailsHeader.FitStrip(details)
end

ns.DetailsHeader = DetailsHeader
return DetailsHeader
