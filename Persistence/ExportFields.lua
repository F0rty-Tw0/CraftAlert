local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Base36 = ns.Base36 or require("CraftAlert.Persistence.Base36")

-- The field grammar of the export string (Persistence/ExportString.lua), part of its version 1
-- contract. Writers return the field, or nil for a value the readers would refuse (the caller
-- leaves that value out); readers return the value, or nil/false for a field they refuse.
--   number = an ID, 1..MAX_ID, in base 36 (Persistence/Base36.lua); "" for none
--   key    = a number, or "~" text for a string key (Classic names)
--   text   = 1..MAX.text bytes, no "|" (a UI escape) and no control byte; "%" ":" ";" "," "."
--            "~" written as "%" and two hex digits
--   list   = items joined by "." (realms: texts; ranks: numbers); "" for none
local ExportFields = {}

local byte = string.byte
local char = string.char
local find = string.find
local format = string.format
local gmatch = string.gmatch
local gsub = string.gsub
local match = string.match
local sub = string.sub
local tonumber = tonumber
local type = type

local MAX_ID = 2147483647

-- Bounds checked on decode, kept on encode. The user's real Retail account (6 characters,
-- 2,983 recipes) exports about 100 KB.
ExportFields.MAX = {
  length = 600000,
  characters = 200,
  professions = 20,
  recipes = 5000,
  ranks = 5,
  realms = 50,
  text = 200,
}

local ESCAPES = {}
for _, special in ipairs({ "%", ":", ";", ",", ".", "~" }) do
  ESCAPES[special] = format("%%%02X", byte(special))
end

local function unescape(hex)
  return char(tonumber(hex, 16))
end

function ExportFields.IsId(n)
  return type(n) == "number" and n % 1 == 0 and n >= 1 and n <= MAX_ID
end

-- allowEmpty: "" passes too.
function ExportFields.IsText(text, allowEmpty)
  if type(text) ~= "string" or #text > ExportFields.MAX.text or (text == "" and not allowEmpty) then
    return false
  end
  return not find(text, "[|%z\1-\31\127]")
end

-- "Name-Realm" with the realm as stored (no space or hyphen); Forever names keep their space.
function ExportFields.IsCharacterKey(key)
  return ExportFields.IsText(key, false) and find(key, "^[^%-]+%-[^%- ]+$") ~= nil
end

-- A class token as the client gives it ("DEATHKNIGHT").
function ExportFields.IsClass(class)
  return type(class) == "string" and #class <= 20 and find(class, "^%u+$") ~= nil
end

-- Text written for a field; call only with IsText text.
function ExportFields.Text(text)
  return (gsub(text, "[%%:;,%.~]", ESCAPES))
end

-- → the text, or nil for a field holding a raw separator, a bad escape or a refused byte.
function ExportFields.ReadText(field)
  if find(field, "[:;,%.~]") or find((gsub(field, "%%%x%x", "")), "%%") then
    return nil
  end
  local text = gsub(field, "%%(%x%x)", unescape)
  return ExportFields.IsText(text, true) and text or nil
end

function ExportFields.KeyField(key)
  if type(key) == "number" then
    return ExportFields.IsId(key) and Base36.Encode(key) or nil
  end
  return ExportFields.IsText(key, false) and "~" .. ExportFields.Text(key) or nil
end

function ExportFields.ReadKey(field)
  if sub(field, 1, 1) == "~" then
    local text = ExportFields.ReadText(sub(field, 2))
    return text ~= "" and text or nil
  end
  local n = Base36.Decode(field)
  return ExportFields.IsId(n) and n or nil
end

-- "" for nil.
function ExportFields.NumberField(n)
  if n == nil then
    return ""
  end
  return ExportFields.IsId(n) and Base36.Encode(n) or nil
end

-- → nil for "", the number, or false for a refused field.
function ExportFields.ReadNumber(field)
  if field == "" then
    return nil
  end
  local n = Base36.Decode(field)
  return ExportFields.IsId(n) and n or false
end

-- Ranks: "" for none; only the first MAX.ranks are written.
function ExportFields.NumberList(list)
  if type(list) ~= "table" then
    return list == nil and "" or nil
  end
  local fields = {}
  for i = 1, math.min(#list, ExportFields.MAX.ranks) do
    fields[i] = ExportFields.NumberField(list[i])
    if fields[i] == nil or fields[i] == "" then
      return nil
    end
  end
  return table.concat(fields, ".")
end

-- → nil for "", the list, or false for a refused field or more than `max` items.
function ExportFields.ReadNumberList(field, max)
  if field == "" then
    return nil
  end
  local list = {}
  for item in gmatch(field .. ".", "([^.]*)%.") do
    local n = ExportFields.ReadNumber(item)
    if not n or #list >= max then
      return false
    end
    list[#list + 1] = n
  end
  return list
end

-- Realms: the non-empty texts of `list`, at most MAX.realms.
function ExportFields.TextList(list)
  local fields = {}
  for _, text in ipairs(type(list) == "table" and list or {}) do
    if #fields < ExportFields.MAX.realms and ExportFields.IsText(text, false) then
      fields[#fields + 1] = ExportFields.Text(text)
    end
  end
  return table.concat(fields, ".")
end

-- → the texts ({} for ""), or nil for an empty or refused item or more than `max` items.
function ExportFields.ReadTextList(field, max)
  local list = {}
  if field == "" then
    return list
  end
  for item in gmatch(field .. ".", "([^.]*)%.") do
    local text = ExportFields.ReadText(item)
    if text == nil or text == "" or #list >= max then
      return nil
    end
    list[#list + 1] = text
  end
  return list
end

-- → the fields of a record, or nil when it has a field count other than `count`.
local function fieldsOf(record, count)
  local fields = {}
  for field in gmatch(record .. ",", "([^,]*),") do
    fields[#fields + 1] = field
  end
  return #fields == count and fields or nil
end

-- The record parsers fill `state` (NewState); each → nil or a word naming what was refused.
local PARSE = {}

function PARSE.c(state, record)
  local f = fieldsOf(record, 4)
  if f == nil then
    return "character"
  end
  local key, realms = ExportFields.ReadText(f[2]), ExportFields.ReadTextList(f[4], ExportFields.MAX.realms)
  if not (key and ExportFields.IsCharacterKey(key) and realms and (f[3] == "" or ExportFields.IsClass(f[3]))) then
    return "character"
  end
  if state.seen[key] or #state.characters >= ExportFields.MAX.characters then
    return "character count"
  end
  state.seen[key] = true
  state.current = { key = key, class = f[3] ~= "" and f[3] or nil, realms = realms, professions = {}, recipes = {} }
  state.characters[#state.characters + 1] = state.current
  state.lastId, state.professionCount, state.recipeCount = 0, 0, 0
  return nil
end

function PARSE.p(state, record)
  local f = fieldsOf(record, 3)
  local character = state.current
  local key = f and ExportFields.ReadKey(f[2])
  local name = f and ExportFields.ReadText(f[3])
  if character == nil or key == nil or name == nil or character.professions[key] ~= nil then
    return "profession"
  end
  state.professionCount = state.professionCount + 1
  if state.professionCount > ExportFields.MAX.professions then
    return "profession count"
  end
  character.professions[key] = name
  return nil
end

local function readRecipeKey(state, field)
  if find(field, "^~") then
    return ExportFields.ReadKey(field)
  end
  local step = Base36.Decode(field)
  local id = step and step > 0 and state.lastId + step or nil
  if id and ExportFields.IsId(id) then
    state.lastId = id
    return id
  end
  return nil
end

function PARSE.r(state, record)
  local f = fieldsOf(record, 8)
  local character = state.current
  if f == nil or character == nil then
    return "recipe"
  end
  local key, prof, name = readRecipeKey(state, f[2]), ExportFields.ReadKey(f[3]), ExportFields.ReadText(f[4])
  local item, ranks, line = ExportFields.ReadNumber(f[5]), ExportFields.ReadNumberList(f[6], ExportFields.MAX.ranks), ExportFields.ReadNumber(f[7])
  if key == nil or prof == nil or character.recipes[key] ~= nil or character.professions[prof] == nil then
    return "recipe"
  end
  local ok = name ~= nil and name ~= "" and item ~= false and ranks ~= false and line ~= false
  if not ok or (f[8] ~= "" and f[8] ~= "m") then
    return "recipe"
  end
  state.recipeCount = state.recipeCount + 1
  if state.recipeCount > ExportFields.MAX.recipes then
    return "recipe count"
  end
  character.recipes[key] = { name = name, prof = prof, item = item, ranks = ranks, line = line, muted = f[8] == "m" or nil }
  return nil
end

-- The parse state: decoded characters in string order, the one the next records belong to.
function ExportFields.NewState()
  return { characters = {}, seen = {}, current = nil, lastId = 0, professionCount = 0, recipeCount = 0 }
end

-- Adds one record to `state` → nil, or a word naming what was refused.
function ExportFields.ParseRecord(state, record)
  local parse = PARSE[match(record, "^(%l),")]
  if parse == nil then
    return "record"
  end
  return parse(state, record)
end

ns.ExportFields = ExportFields
return ExportFields
