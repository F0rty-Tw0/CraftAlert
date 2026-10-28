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
local CardBody = ns.CardBody or require("CraftAlert.UI.CardBody")
local MainCrafterMenu = ns.MainCrafterMenu or require("CraftAlert.UI.MainCrafterMenu")

-- Lead-cards spec §2: what the lead tooltips say. Each builder fills a tooltip that already has its
-- owner: a gold title, white text, a blank line, green instruction lines. The details pane's zones
-- (UI/LeadDetails.lua, UI/DetailsBody.lua) and the list rows (UI/LeadRow.lua: Chat, Compact)
-- decide when one shows. InfoLines builds no tooltip: it gives the lines of a customer's info line
-- in a WhisperMessenger conversation (UI/BridgeInfo.lua).
local CardTipText = {}

local format = string.format
local tostring = tostring

-- As GameTooltip_SetTitle: replaces the lines, wrapping.
local function title(tip, text)
  local gold = Theme.COLORS.gold
  tip:SetText(text, gold[1], gold[2], gold[3], 1, true)
end

local function white(tip, text)
  _G["GameTooltip_AddHighlightLine"](tip, text)
end

local function instruction(tip, text)
  _G["GameTooltip_AddInstructionLine"](tip, text)
end

-- A blank line, then each of `lines` green: the gap Blizzard leaves above instruction lines.
local function instructions(tip, lines)
  _G["GameTooltip_AddBlankLineToTooltip"](tip)
  for _, text in ipairs(lines) do
    instruction(tip, text)
  end
end

-- A line in a Theme colour (a table with an alpha slot), wrapping.
local function stateLine(tip, text, color)
  tip:AddLine(text, color[1], color[2], color[3], true)
end

-- The customer in class colour, their class, and whether they were greeted (blue) or replied
-- (green). The class name needs the token anyway, so it is read once, with or without a colour table.
function CardTipText.Customer(tip, lead)
  local token = FlavorCompat.ClassOf(lead.guid)
  tip:SetText(tostring(lead.customer), FrameKit.ClassRGB(FrameKit.ClassColor(token), Theme.COLORS.gold))
  local className = FrameKit.ClassName(token)
  if className then
    white(tip, className)
  end
  if lead.greeted then
    stateLine(tip, Localization.Text("Greeted"), Theme.COLORS.greeted)
  end
  if lead.replied then
    stateLine(tip, Localization.Text("Replied"), Theme.COLORS.replied)
  end
end

function CardTipText.What(tip, lead)
  title(tip, LeadText.What(lead))
  white(tip, Localization.Text(lead.kind == "profession" and "Profession request" or "Item request"))
end

function CardTipText.Matched(tip, lead)
  title(tip, Localization.Text("Matched"))
  if lead.why then
    for _, part in ipairs(LeadText.WhyParts(lead.why)) do
      white(tip, part)
    end
  end
  if lead.profName then
    white(tip, lead.profName)
  end
end

-- Every crafter in the card's order, name in class colour and rank in grey; who was picked; a realm
-- warning; what a click does when the main-crafter menu can open.
function CardTipText.Crafters(tip, lead)
  title(tip, Localization.Text("Crafters"))
  local grey = Theme.COLORS.grey
  for _, crafter in ipairs(CardBody.Crafters(lead)) do
    local r, g, b = FrameKit.ClassRGB(crafter.color, Theme.COLORS.white)
    tip:AddDoubleLine(crafter.name, crafter.rank or "", r, g, b, grey[1], grey[2], grey[3])
  end
  if lead.crafter then
    white(tip, Localization.Text("Picked for this lead: %s", Greeting.CrafterName(lead.crafter)))
  end
  local realm = LeadText.RealmTag(lead)
  if realm then
    white(tip, realm)
  end
  if MainCrafterMenu.CanOpen(lead) then
    instructions(tip, { Localization.Text("Click: choose the main crafter") })
  end
end

-- "Greet", who gets the whisper (when there is a lead), and the first three click lines (the
-- fourth, dismiss, is not the button's).
function CardTipText.Greet(tip, lead)
  title(tip, Localization.Text("Greet"))
  if lead then
    white(tip, Localization.Text("Whispers %s", tostring(lead.customer)))
  end
  local lines = LeadText.ClickLines()
  instructions(tip, { lines[1], lines[2], lines[3] })
end

-- No click line on Whisper and Dismiss: the button's label is the click.
function CardTipText.Whisper(tip)
  title(tip, Localization.Text("Whisper"))
  white(tip, Localization.Text("Open a whisper without the greeting"))
end

function CardTipText.Dismiss(tip)
  title(tip, Localization.Text("Dismiss"))
  white(tip, Localization.Text("Remove this lead"))
end

local function customerColor(lead, fallback)
  return FrameKit.ClassRGB(FrameKit.GuidClassColor(lead.guid), fallback)
end

-- Row-chat-tooltip spec: "[HH:MM] [Channel] [Name]: message", the customer in class colour, the
-- message with its links; a lead without a channel has no channel part.
local function chatText(lead)
  local name = FrameKit.ColorCode(tostring(lead.customer), customerColor(lead, Theme.COLORS.white))
  local channel = LeadText.Channel(lead)
  local channelPart = channel and format("[%s] ", channel) or ""
  return format("[%s] %s[%s]: %s", _G["date"]("%H:%M", lead.time), channelPart, name, lead.message)
end

-- What a row click does (a left click selects, never greets).
local function rowClickLines(tip)
  instructions(tip, { Localization.Text("Click: select"), Localization.Text("Right-click: dismiss") })
end

-- The lead's latest chat line, then the row's click lines.
function CardTipText.Chat(tip, lead)
  tip:SetText(tostring(lead.customer), customerColor(lead, Theme.COLORS.gold))
  tip:AddLine(chatText(lead), 1, 1, 1, true)
  rowClickLines(tip)
end

-- An icon-only row (spec 6a): the customer in class colour and what they asked for, the text the
-- row hides; the chat line when there is one; the click lines. A lead without a message still has one.
function CardTipText.Compact(tip, lead)
  tip:SetText(tostring(lead.customer), customerColor(lead, Theme.COLORS.gold))
  white(tip, LeadText.What(lead))
  if lead.message then
    tip:AddLine(chatText(lead), 1, 1, 1, true)
  end
  rowClickLines(tip)
end

-- At most 7 crafter lines: with the headline, Matched and chat lines, WM's 10-line cap holds.
local MAX_CRAFTER_LINES = 7

-- The tooltip lines of a customer's info line in a WM conversation (SetContactInfo's tooltipLines):
-- the headline in gold, Matched, one line per crafter (class-coloured name, rank in grey), the chat
-- line. WM draws every line white, so colour comes only from the codes. A pure function, no tooltip.
function CardTipText.InfoLines(lead)
  local gold, grey = Theme.COLORS.gold, Theme.COLORS.grey
  local lines = { FrameKit.ThemeCode(LeadText.Headline(lead), gold) }
  local matched = CardBody.MatchedText(lead, Theme.COLORS.white)
  if matched then
    lines[#lines + 1] = Localization.Text("Matched: %s", matched)
  end
  for index, crafter in ipairs(CardBody.Crafters(lead)) do
    if index > MAX_CRAFTER_LINES then
      break
    end
    local line = FrameKit.ClassCode(crafter.name, crafter.color)
    lines[#lines + 1] = crafter.rank and (line .. " " .. FrameKit.ThemeCode(crafter.rank, grey)) or line
  end
  if lead.message then
    lines[#lines + 1] = chatText(lead)
  end
  return lines
end

ns.CardTipText = CardTipText
return CardTipText
