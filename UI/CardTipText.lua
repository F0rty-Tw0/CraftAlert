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

-- Lead-cards spec §2, §2.1: what a card's tooltips say. Each builder fills a tooltip that already has
-- its owner: a gold title, white text, green instruction lines. UI/CardTips.lua owns the zones and
-- decides when a tooltip shows.
local CardTipText = {}

local format = string.format
local tostring = tostring
local type = type

local WHY_SEPARATOR = " + "
-- The words of a lead's channel key (Core/ScanGate.lua), localized when shown.
local CHANNEL_NAMES = {
  trade = "Trade",
  services = "Services",
  general = "General",
  lfg = "LFG",
  guild = "Guild",
  communities = "Community",
}

local function title(tip, text)
  _G["GameTooltip_SetTitle"](tip, text, _G["NORMAL_FONT_COLOR"])
end

local function white(tip, text)
  _G["GameTooltip_AddHighlightLine"](tip, text)
end

local function instruction(tip, text)
  _G["GameTooltip_AddInstructionLine"](tip, text)
end

-- r, g, b of a class colour (a RAID_CLASS_COLORS entry), else of `fallback` (a Theme colour).
local function rgbOf(color, fallback)
  if color then
    return color.r, color.g, color.b
  end
  return fallback[1], fallback[2], fallback[3]
end

local function customerColor(lead, fallback)
  return rgbOf(FrameKit.ClassColor(FlavorCompat.ClassOf(lead.guid)), fallback)
end

-- The customer in class colour, their class, and whether they were greeted or replied.
function CardTipText.Customer(tip, lead)
  tip:SetText(tostring(lead.customer), customerColor(lead, Theme.COLORS.gold))
  local names = _G["LOCALIZED_CLASS_NAMES_MALE"]
  local token = FlavorCompat.ClassOf(lead.guid)
  local className = token and type(names) == "table" and names[token]
  if className then
    white(tip, className)
  end
  if lead.greeted then
    white(tip, Localization.Text("Greeted"))
  end
  if lead.replied then
    white(tip, Localization.Text("Replied"))
  end
end

function CardTipText.What(tip, lead)
  title(tip, LeadText.What(lead))
  white(tip, Localization.Text(lead.kind == "profession" and "Profession request" or "Item request"))
end

-- Each part of the why text (the Matcher joins its tokens with " + ") on its own line.
local function whyParts(why)
  local parts, from = {}, 1
  while true do
    local at = string.find(why, WHY_SEPARATOR, from, true)
    if at == nil then
      parts[#parts + 1] = string.sub(why, from)
      return parts
    end
    parts[#parts + 1] = string.sub(why, from, at - 1)
    from = at + #WHY_SEPARATOR
  end
end

function CardTipText.Matched(tip, lead)
  title(tip, Localization.Text("Matched"))
  for _, part in ipairs(lead.why and whyParts(lead.why) or {}) do
    white(tip, part)
  end
  if lead.profName then
    _G["GameTooltip_AddColoredLine"](tip, lead.profName, _G["NORMAL_FONT_COLOR"])
  end
end

-- Every crafter in the card's order, name in class colour and rank in grey; who was picked; a realm warning.
function CardTipText.Crafters(tip, lead)
  title(tip, Localization.Text("Crafters"))
  local grey = Theme.COLORS.grey
  for _, crafter in ipairs(CardBody.Crafters(lead)) do
    local r, g, b = rgbOf(crafter.color, Theme.COLORS.white)
    tip:AddDoubleLine(crafter.name, crafter.rank or "", r, g, b, grey[1], grey[2], grey[3])
  end
  if lead.crafter then
    white(tip, Localization.Text("Picked for this lead: %s", Greeting.CrafterName(lead.crafter)))
  end
  if lead.cannotOrder then
    white(tip, Localization.Text("Can't send an order (realm)"))
  end
end

-- "Greet" and the first three click lines (the fourth, dismiss, is not the button's).
function CardTipText.Greet(tip)
  title(tip, Localization.Text("Greet"))
  local lines = LeadText.ClickLines()
  for index = 1, 3 do
    instruction(tip, lines[index])
  end
end

local function channelName(key)
  local name = CHANNEL_NAMES[key]
  return name and Localization.Text(name) or tostring(key)
end

-- `text` in r, g, b as a colour code.
local function colored(text, r, g, b)
  return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) .. text .. "|r"
end

-- "[HH:MM] [Channel] [Name]: message", the customer in class colour, the message with its links.
local function chatText(lead)
  local name = colored(tostring(lead.customer), customerColor(lead, Theme.COLORS.white))
  return format("[%s] [%s] [%s]: %s", _G["date"]("%H:%M", lead.time), channelName(lead.channel), name, lead.message)
end

-- The lead's latest chat line (§2.1), then what clicking does.
function CardTipText.Chat(tip, lead)
  tip:SetText(Localization.Text("Chat with %s", tostring(lead.customer)), customerColor(lead, Theme.COLORS.gold))
  tip:AddLine(chatText(lead), 1, 1, 1, true)
  local lines = LeadText.ClickLines()
  instruction(tip, lines[1])
  instruction(tip, lines[4])
end

ns.CardTipText = CardTipText
return CardTipText
