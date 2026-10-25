local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")

-- What a lead's Matched and Crafters show, as data: the details pane (UI/DetailsBody.lua) and the
-- tooltips (UI/CardTipText.lua) read both. Lead-cards spec §1.1: the crafters in order, the
-- picked one first, in class colours.
local CardBody = {}

local sort = table.sort
local type = type

-- `text` in a Theme colour ({ r, g, b, a }).
local function themed(text, color)
  return FrameKit.ColorCode(text, color[1], color[2], color[3])
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
function CardBody.MatchedText(lead)
  local colors = Theme.COLORS
  local why = lead.why and themed(lead.why, colors.white)
  local profession = lead.profName and themed(lead.profName, colors.gold)
  if why and profession then
    return why .. " · " .. profession
  end
  return why or profession
end

ns.CardBody = CardBody
return CardBody
