local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")

-- Spec §7.4: the greeting whisper for a lead. Pure text; nothing here is sent.
local Greeting = {}

local byte = string.byte
local find = string.find
local gsub = string.gsub
local match = string.match
local sub = string.sub
local type = type

local MAX_LENGTH = 255

-- Template by lead kind and whether the chosen crafter is the player's own character.
local OWN_TEMPLATE = { item = "item", profession = "profession" }
local ALT_TEMPLATE = { item = "altItem", profession = "altProfession" }

local function nameOf(key)
  return match(key, "^[^-]*")
end

-- The player's own realm is dropped, as Ambiguate does; an alt on another realm keeps it.
local function crafterName(key)
  if PlayerName.RealmOf(key) == PlayerName.RealmOf(PlayerName.Own()) then
    return nameOf(key)
  end
  return key
end

local PIPE = 124 -- "|"

-- Whether the pipe at `at` starts an escape sequence: in a run of pipes each "||" is a literal
-- pipe, so only the last pipe of an odd run does.
local function startsCode(text, at)
  local first = at
  while first > 1 and byte(text, first - 1) == PIPE do
    first = first - 1
  end
  return (at - first) % 2 == 0
end

-- Drops a colour start (`pattern`, from its pipe) the cut left at the end of `kept`, unless
-- that pipe is escaped and the rest is plain text.
local function dropColorStart(kept, pattern)
  local at = match(kept, "()" .. pattern .. "$")
  if at and startsCode(kept, at) then
    return sub(kept, 1, at - 1)
  end
  return kept
end

-- The 255-byte chat limit must not leave half a UTF-8 character, half a hyperlink, a
-- partial colour code or a lone escape pipe behind.
local function cap(text)
  if #text <= MAX_LENGTH then
    return text
  end
  local cut = MAX_LENGTH
  local following = byte(text, cut + 1)
  while cut > 0 and following >= 128 and following < 192 do -- a continuation byte
    cut = cut - 1
    following = byte(text, cut + 1)
  end
  local kept = sub(text, 1, cut)
  local open, at = nil, find(kept, "|H", 1, true)
  while at do
    open = at
    at = find(kept, "|H", at + 1, true)
  end
  if open and not find(kept, "|h.-|h", open) then
    -- Drop the half link and the colour code in front of it. A named colour (|cnIQ4:) is left
    -- at the end by that cut, so the partial-code cleanup below takes it.
    local colored = open > 10 and find(sub(kept, open - 10, open - 1), "^|c%x%x%x%x%x%x%x%x$") and startsCode(kept, open - 10)
    kept = sub(kept, 1, colored and open - 11 or open - 1)
  end
  -- A lone trailing pipe and a partial colour start can each expose the other ("||c" cut to
  -- "||" + "c" → "|"), so trim both until neither is left.
  local before
  repeat
    before = kept
    if #match(kept, "|*$") % 2 == 1 then
      kept = sub(kept, 1, -2)
    end
    kept = dropColorStart(kept, "|c%x?%x?%x?%x?%x?%x?%x?")
    kept = dropColorStart(kept, "|cn[%w_]*:?")
  until kept == before
  return kept
end

-- → the greeting text for `lead` (Leads.OnMatch record) from settings.templates and notes.
function Greeting.Build(lead, settings)
  local own = lead.crafter == PlayerName.Own()
  local templates = own and OWN_TEMPLATE or ALT_TEMPLATE
  local text = settings.templates[templates[lead.kind == "profession" and "profession" or "item"]] or ""
  local values = {
    customer = nameOf(lead.customer),
    crafter = crafterName(lead.crafter),
    item = lead.itemLink or lead.recipeName or lead.profName or "",
    profession = lead.profName or "",
  }
  -- A function replacement keeps `%` in names literal; an unknown tag returns nil and stays.
  text = gsub(text, "{(%w+)}", function(tag)
    return values[tag]
  end)
  local note = settings.notes[lead.prof]
  if type(note) == "string" and note ~= "" then
    text = text .. " " .. note
  end
  return cap((gsub(text, "[\r\n]+", " ")))
end

ns.Greeting = Greeting
return Greeting
