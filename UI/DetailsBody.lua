local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local CardBody = ns.CardBody or require("CraftAlert.UI.CardBody")
local CardTipText = ns.CardTipText or require("CraftAlert.UI.CardTipText")
local MainCrafterMenu = ns.MainCrafterMenu or require("CraftAlert.UI.MainCrafterMenu")

-- Details spec A.3-A.5, the details pane's body, top to bottom: the Request bubble, the grid
-- (Matched, Crafters, Quality, Realm: gold labels in an 84 px column, values right of it) and the
-- Greet sends bubble with its "to …" target and the green Shift-click hint. Each bubble is a
-- mouse-enabled tooltip-backdrop Button holding its own text, so it hovers that text's links
-- (LinkHover); the body hovers the grid's. A block or a row the lead has nothing for hides and
-- takes no space, and the body is as tall as what shows (Arrange, on each paint and each width).
-- Tooltip zones lie over Matched and Crafters (never over a bubble); a left-click on the Crafters
-- zone opens the main-crafter menu (main-crafter spec §3), every other click on a zone does
-- nothing. UI/LeadDetails.lua builds the header, the strip and the action bar around it.
local DetailsBody = {}

local find = string.find
local ipairs = ipairs
local max = math.max
local min = math.min
local unpack = unpack

local ANCHOR = "ANCHOR_RIGHT"
local PAD = Theme.LAYOUT.DETAILS_PADDING
-- Between blocks; a label's height and its gap to the bubble under it; a bubble's text padding.
local BLOCK_GAP, LABEL_HEIGHT, LABEL_GAP, BUBBLE_PAD_X, BUBBLE_PAD_Y = 18, 14, 5, 12, 10
-- The grid: its label column and the gap to the values, one value line, the gap between rows.
local LABEL_WIDTH, COLUMN_GAP, LINE_HEIGHT, ROW_GAP = 84, 12, 14, 9
local VALUE_LEFT = PAD + LABEL_WIDTH + COLUMN_GAP
local HINT_HEIGHT, BUBBLE_LINES, CRAFTER_LINES = 12, 4, 3

local FONTS, COLORS = Theme.FONTS, Theme.COLORS
-- The bubbles: each one's key in sections.labels / bubbles / texts, its label and backdrop colours.
local BUBBLES = {
  request = { label = "Request", center = { 0.17, 0.14, 0.09, 0.9 }, border = { 0.35, 0.29, 0.19, 1 } },
  greet = { label = "Greet sends", center = { 0.14, 0.13, 0.11, 0.9 }, border = { 0.24, 0.22, 0.19, 1 } },
}
-- The grid's rows, top to bottom: each one's key in sections.labels / lines, its label, how many
-- value lines it has and their colour (the font's white when none).
local ROWS = {
  { key = "matched", label = "Matched", lines = 1 },
  { key = "crafters", label = "Crafters", lines = CRAFTER_LINES },
  { key = "quality", label = "Quality", lines = 2 },
  { key = "realm", label = "Realm", lines = 1, color = COLORS.warning },
}

local function swallow() end

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
  zone:SetScript("OnLeave", Tooltip.HideIfOwned)
  return zone
end

-- A bubble's label on the body, and the bubble with its text wrapped to BUBBLE_LINES lines (a
-- client without SetMaxLines lets it run on).
local function createBubble(sections, key)
  local spec, body = BUBBLES[key], sections.body
  local label = FrameKit.Text(body, FONTS.name)
  label:SetText(Localization.Text(spec.label))
  local bubble = _G["CreateFrame"]("Button", nil, body, "TooltipBackdropTemplate")
  bubble:EnableMouse(true)
  bubble:SetBackdropColor(unpack(spec.center))
  bubble:SetBackdropBorderColor(unpack(spec.border))
  LinkHover.Attach(bubble, nil)
  local text = FrameKit.Text(bubble, FONTS.title)
  text:SetPoint("TOPLEFT", bubble, "TOPLEFT", BUBBLE_PAD_X, -BUBBLE_PAD_Y)
  text:SetWordWrap(true)
  text:SetJustifyV("TOP")
  if text.SetMaxLines then
    text:SetMaxLines(BUBBLE_LINES)
  end
  sections.labels[key], sections.bubbles[key], sections.texts[key] = label, bubble, text
end

-- Greet sends' extras: "to <target>" right of its label, the hint under its bubble. The target's
-- 55 % white is folded opaque: the name's class colour code keeps its full colour.
local function createGreetExtras(sections)
  local body, label = sections.body, sections.labels.greet
  local target = FrameKit.Text(body, FONTS.body, FrameKit.Opaque(COLORS.textSecondary))
  target:SetPoint("TOP", label, "TOP", 0, 0)
  target:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
  local hint = FrameKit.Text(body, FONTS.body, COLORS.green)
  hint:SetPoint("TOPLEFT", sections.bubbles.greet, "BOTTOMLEFT", 0, -LABEL_GAP)
  hint:SetText(Localization.Text("Shift-click Greet to edit first"))
  sections.texts.target, sections.texts.hint = target, hint
end

local function createRows(sections)
  local body = sections.body
  for _, row in ipairs(ROWS) do
    local label = FrameKit.Text(body, FONTS.name)
    label:SetText(Localization.Text(row.label))
    local lines = {}
    for index = 1, row.lines do
      lines[index] = FrameKit.Text(body, FONTS.title, row.color)
      lines[index]:SetPoint("TOPLEFT", body, "TOPLEFT", VALUE_LEFT, 0)
      lines[index]:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
    end
    sections.labels[row.key], sections.lines[row.key] = label, lines
  end
end

local function createZones(sections)
  local body, labels, lines = sections.body, sections.labels, sections.lines
  sections.zones.matched = DetailsBody.Zone(sections, body, labels.matched, lines.matched[1], CardTipText.Matched)
  local crafters = DetailsBody.Zone(sections, body, labels.crafters, lines.crafters[CRAFTER_LINES], CardTipText.Crafters)
  crafters:SetScript("OnClick", function(zone, button)
    local lead = sections.lead
    if button == "LeftButton" and lead and MainCrafterMenu.CanOpen(lead) then
      MainCrafterMenu.Open(zone, lead)
    end
  end)
  sections.zones.crafters = crafters
end

-- The body's blocks on `body`. → sections: { body, labels (request, matched, crafters, quality,
-- realm, greet), lines (each grid row's value lines, top first), bubbles (request, greet), texts
-- (request, greet, target, hint), zones (matched, crafters), width (0: the body's own), lead }.
function DetailsBody.Create(body)
  local sections = { body = body, width = 0, labels = {}, lines = {}, bubbles = {}, texts = {}, zones = {} }
  createBubble(sections, "request")
  createRows(sections)
  createBubble(sections, "greet")
  createGreetExtras(sections)
  createZones(sections)
  return sections
end

-- Shows `text` in the bubble `key` with its label, or hides both when it is nil or only spaces
-- (as GreetAction, which sends no greeting without a non-space character).
local function setBubble(sections, key, text)
  local shown = text ~= nil and find(text, "%S") ~= nil
  sections.labels[key]:SetShown(shown)
  sections.bubbles[key]:SetShown(shown)
  if shown then
    sections.texts[key]:SetText(text)
  end
end

-- Shows `values` (an array, possibly empty) on the row's lines, hiding the label without any.
local function setRow(sections, key, values)
  for index, line in ipairs(sections.lines[key]) do
    line:SetShown(values[index] ~= nil)
    line:SetText(values[index])
  end
  sections.labels[key]:SetShown(values[1] ~= nil)
end

-- The name in its class colour (white unknown), then the rank in grey.
local function crafterLine(crafter)
  local name = FrameKit.ClassCode(crafter.name, crafter.color, COLORS.white)
  if crafter.rank == nil then
    return name
  end
  return name .. FrameKit.ThemeCode(" " .. crafter.rank, COLORS.grey)
end

-- One crafter per line, at most CRAFTER_LINES; the last line ends with how many more there are.
-- None: "None known" in grey.
local function crafterValues(lead)
  local entries, values = CardBody.Crafters(lead), {}
  for index = 1, min(#entries, CRAFTER_LINES) do
    values[index] = crafterLine(entries[index])
  end
  local more = #entries - CRAFTER_LINES
  if more > 0 then
    values[CRAFTER_LINES] = values[CRAFTER_LINES] .. FrameKit.ThemeCode(" " .. Localization.Text("+%d more", more), COLORS.grey)
  end
  values[1] = values[1] or FrameKit.ThemeCode(Localization.Text("None known"), COLORS.grey)
  return values
end

-- Greet sends, for an ungreeted lead only: the greeting (a blank one hides the block) and "to"
-- the whisper target in the customer's class colour (plain when unknown), left out when there is
-- none.
local function paintGreet(sections, lead)
  local greeting = not lead.greeted and Greeting.Build(lead, _G["CraftAlertDB"].settings) or nil
  setBubble(sections, "greet", greeting)
  local shown = sections.bubbles.greet:IsShown()
  local target = shown and GreetAction.Target(lead) or nil
  sections.texts.target:SetShown(target ~= nil)
  local name = target and FrameKit.ClassCode(target, FrameKit.GuidClassColor(lead.guid))
  sections.texts.target:SetText(name and Localization.Text("to %s", name) or nil)
  sections.texts.hint:SetShown(shown)
end

-- The bubble `key` at `top` (px below the body's top) under its label, `width` wide, as tall as
-- its text and padding. → the block's height, 0 when it is hidden.
local function placeBubble(sections, key, top, width)
  local bubble, text = sections.bubbles[key], sections.texts[key]
  if not bubble:IsShown() then
    return 0
  end
  local body = sections.body
  sections.labels[key]:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -top)
  bubble:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(top + LABEL_HEIGHT + LABEL_GAP))
  bubble:SetWidth(max(1, width - 2 * PAD))
  text:SetWidth(max(1, width - 2 * PAD - 2 * BUBBLE_PAD_X))
  bubble:SetHeight(text:GetStringHeight() + 2 * BUBBLE_PAD_Y)
  return LABEL_HEIGHT + LABEL_GAP + bubble:GetHeight()
end

-- The shown rows from `top`, ROW_GAP apart, each as tall as its shown lines; the Crafters zone
-- ends at the last shown crafter. → the grid's height.
local function placeGrid(sections, top)
  local body, rowTop = sections.body, top
  for _, row in ipairs(ROWS) do
    local label, lines = sections.labels[row.key], sections.lines[row.key]
    if label:IsShown() then
      label:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -rowTop)
      local shown = 0
      for index, line in ipairs(lines) do
        line:SetPoint("TOPLEFT", body, "TOPLEFT", VALUE_LEFT, -(rowTop + (index - 1) * LINE_HEIGHT))
        shown = line:IsShown() and index or shown
      end
      if row.key == "crafters" then
        sections.zones.crafters:SetPoint("BOTTOMRIGHT", lines[shown], "BOTTOMRIGHT", 0, 0)
      end
      rowTop = rowTop + shown * LINE_HEIGHT + ROW_GAP
    end
  end
  return rowTop - ROW_GAP - top
end

-- Places the shown blocks BLOCK_GAP apart inside PAD, at the width SetWidth gave (else the
-- body's own), and sets the body's height to theirs. The grid always shows (Crafters at least
-- reads "None known").
function DetailsBody.Arrange(sections)
  local width = sections.width > 0 and sections.width or sections.body:GetWidth()
  local top = PAD
  local request = placeBubble(sections, "request", top, width)
  top = request > 0 and top + request + BLOCK_GAP or top
  top = top + placeGrid(sections, top)
  local greet = placeBubble(sections, "greet", top + BLOCK_GAP, width)
  if greet > 0 then
    top = top + BLOCK_GAP + greet + LABEL_GAP + HINT_HEIGHT
  end
  sections.body:SetHeight(top + PAD)
end

-- The body is `width` wide (0 or less: not known yet, the body's own then): the bubbles re-wrap.
function DetailsBody.SetWidth(sections, width)
  sections.width = width
  DetailsBody.Arrange(sections)
end

function DetailsBody.Paint(sections, lead)
  sections.lead = lead
  setBubble(sections, "request", lead.message)
  setRow(sections, "matched", { CardBody.MatchedText(lead) })
  setRow(sections, "crafters", crafterValues(lead))
  setRow(sections, "quality", LeadText.Quality(lead, _G["CraftAlertDB"]) or {})
  setRow(sections, "realm", { LeadText.RealmTag(lead) })
  paintGreet(sections, lead)
  sections.zones.matched:SetShown(sections.labels.matched:IsShown())
  DetailsBody.Arrange(sections)
end

ns.DetailsBody = DetailsBody
return DetailsBody
