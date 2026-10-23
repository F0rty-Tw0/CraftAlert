local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")

-- Lead-cards spec §1, right column: a card's Request, Matched and Crafters rows, each a gold label
-- and its value. Every text is a region of the card itself: LinkHover sees only those, so the
-- request's links hover. The rows keep fixed places; a row the lead has nothing for is hidden and
-- leaves its space empty. §1.1: the crafters in order, the picked one first, in class colours.
local CardBody = {}

local format = string.format
local sort = table.sort
local type = type

local REQUEST, MATCHED, CRAFTERS = 1, 2, 3
local LABELS = { "Request", "Matched", "Crafters" }
-- Row tops below the card's top: the request takes two lines, the others one.
local TOPS = { -4, -32, -50 }

-- `text` in r, g, b as a colour code. From r/g/b only: a RAID_CLASS_COLORS entry may lack colorStr.
local function colored(text, r, g, b)
  return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) .. text .. "|r"
end

-- `text` in a Theme colour ({ r, g, b, a }).
local function themed(text, color)
  return colored(text, color[1], color[2], color[3])
end

-- The request wraps to two lines at most; a client without SetMaxLines clips it at two lines'
-- height instead.
local function wrapTwoLines(value)
  value:SetWordWrap(true)
  value:SetJustifyV("TOP")
  if value.SetMaxLines then
    value:SetMaxLines(2)
  else
    value:SetHeight(TOPS[REQUEST] - TOPS[MATCHED])
  end
end

-- The labels and values on `card`: card.labels and card.values, each { request, matched, crafters }.
function CardBody.Create(card)
  local layout, fonts = Theme.LAYOUT, Theme.FONTS
  local valueLeft = layout.CARD_LEFT_WIDTH + layout.CARD_LABEL_WIDTH
  card.labels, card.values = {}, {}
  for row, label in ipairs(LABELS) do
    local title = FrameKit.Text(card, fonts.name)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", layout.CARD_LEFT_WIDTH, TOPS[row])
    title:SetWidth(layout.CARD_LABEL_WIDTH)
    title:SetText(Localization.Text(label))
    local value = FrameKit.Text(card, row == REQUEST and fonts.title or fonts.body)
    value:SetPoint("TOPLEFT", card, "TOPLEFT", valueLeft, TOPS[row])
    value:SetPoint("RIGHT", card, "RIGHT", -layout.PADDING, 0)
    card.labels[row], card.values[row] = title, value
  end
  wrapTwoLines(card.values[REQUEST])
end

-- A { key = string, rank = number or nil } entry.
local function isCrafter(entry)
  return type(entry) == "table" and type(entry.key) == "string" and (entry.rank == nil or type(entry.rank) == "number")
end

-- lead.crafters' valid entries (a newer schema's data is kept as it is, by Schema); a restored lead
-- has none, or no usable one: its picked crafter alone.
local function craftersOf(lead)
  local valid = {}
  for _, entry in ipairs(type(lead.crafters) == "table" and lead.crafters or {}) do
    if isCrafter(entry) then
      valid[#valid + 1] = entry
    end
  end
  if #valid > 0 then
    return valid
  end
  if lead.crafter == nil then
    return {}
  end
  return { { key = lead.crafter, rank = lead.rank, byConc = lead.rankConc } }
end

local function pickedFirst(a, b)
  if a.picked ~= b.picked then
    return a.picked
  end
  return a.name < b.name
end

-- The class token saved with the character `key`, or nil.
local function classOf(key)
  local db = _G["CraftAlertDB"]
  local characters = type(db) == "table" and db.characters
  local character = type(characters) == "table" and characters[key]
  if type(character) ~= "table" then
    return nil
  end
  return character.class
end

-- The lead's crafters, the picked one first, then the rest by the name the greeting uses:
-- { key, name, rank ("R2 (conc)" or nil), color (RAID_CLASS_COLORS entry or nil), picked }.
function CardBody.Crafters(lead)
  local entries = {}
  for _, crafter in ipairs(craftersOf(lead)) do
    entries[#entries + 1] = {
      key = crafter.key,
      name = Greeting.CrafterName(crafter.key),
      rank = LeadText.Rank({ rank = crafter.rank, rankConc = crafter.byConc }),
      color = FrameKit.ClassColor(classOf(crafter.key)),
      picked = crafter.key == lead.crafter,
    }
  end
  sort(entries, pickedFirst)
  return entries
end

-- Why in white, then the profession in gold; whichever is set, nil for neither.
local function matchedText(lead)
  local colors = Theme.COLORS
  local why = lead.why and themed(lead.why, colors.white)
  local profession = lead.profName and themed(lead.profName, colors.gold)
  if why and profession then
    return why .. " · " .. profession
  end
  return why or profession
end

-- The first crafter in its class colour (white unknown), then in grey its rank and how many more.
local function craftersText(lead)
  local colors = Theme.COLORS
  local entries = CardBody.Crafters(lead)
  local first = entries[1]
  if first == nil then
    return themed(Localization.Text("None known"), colors.grey)
  end
  local color = first.color
  local text = color and colored(first.name, color.r, color.g, color.b) or themed(first.name, colors.white)
  local tail = first.rank and (" " .. first.rank) or ""
  if #entries > 1 then
    tail = tail .. " " .. Localization.Text("+%d more", #entries - 1)
  end
  if tail == "" then
    return text
  end
  return text .. themed(tail, colors.grey)
end

-- Shows `text` in the row's value, or hides the label and value when it is nil.
local function setRow(card, row, text)
  local label, value = card.labels[row], card.values[row]
  if text == nil then
    label:Hide()
    value:Hide()
    return
  end
  value:SetText(text)
  label:Show()
  value:Show()
end

function CardBody.Paint(card, lead)
  setRow(card, REQUEST, lead.message)
  setRow(card, MATCHED, matchedText(lead))
  setRow(card, CRAFTERS, craftersText(lead))
end

ns.CardBody = CardBody
return CardBody
