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

-- Lead-cards spec §2: what the details pane's tooltips say. Each builder fills a tooltip that
-- already has its owner: a gold title, white text, green instruction lines. UI/LeadDetails.lua and
-- UI/DetailsBody.lua own the zones and decide when a tooltip shows.
local CardTipText = {}

local tostring = tostring
local type = type

local WHY_SEPARATOR = " + "

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

-- r, g, b of a class colour (a RAID_CLASS_COLORS entry), else of `fallback` (a Theme colour).
local function rgbOf(color, fallback)
  if color then
    return color.r, color.g, color.b
  end
  return fallback[1], fallback[2], fallback[3]
end

-- The customer in class colour, their class, and whether they were greeted or replied. The class
-- name needs the token anyway, so it is read once, with or without a colour table.
function CardTipText.Customer(tip, lead)
  local token = FlavorCompat.ClassOf(lead.guid)
  tip:SetText(tostring(lead.customer), rgbOf(FrameKit.ClassColor(token), Theme.COLORS.gold))
  local names = _G["LOCALIZED_CLASS_NAMES_MALE"]
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
    local gold = Theme.COLORS.gold
    tip:AddLine(lead.profName, gold[1], gold[2], gold[3], true)
  end
end

-- Every crafter in the card's order, name in class colour and rank in grey; who was picked; a realm
-- warning; what a click does when the main-crafter menu can open.
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
  if MainCrafterMenu.CanOpen(lead) then
    instruction(tip, Localization.Text("Click to choose the main crafter"))
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

ns.CardTipText = CardTipText
return CardTipText
