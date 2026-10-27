local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local Base36 = ns.Base36 or require("CraftAlert.Persistence.Base36")
local ExportFields = ns.ExportFields or require("CraftAlert.Persistence.ExportFields")
local Index = ns.Index or require("CraftAlert.Model.Index")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")
local BindLookup = ns.BindLookup or require("CraftAlert.Professions.BindLookup")

-- Spec §10.1: the alt-account export string. Encode writes this account's local characters,
-- Decode validates a pasted string whole before anything is written, Apply stores it as
-- imported characters. Wire format version 1, a contract between accounts and builds (a build
-- reads its own version and refuses any other):
--   string     = "CA1:" flavor ":" body ":" checksum
--   flavor     = FlavorCompat.flavorKey: retail forever era tbc wrath cata mop
--   checksum   = Adler-32 of everything before the last ":", 7 base-36 digits, zero-padded
--   body       = empty, or records joined by ";", each record's fields joined by ","
--   character  = "c," key "," class "," realms          (the records after it are its own)
--   profession = "p," profKey "," name
--   recipe     = "r," recipeKey "," profKey "," name "," item "," ranks "," line "," muted
-- Field grammar, record parsing, counts and bounds: Persistence/ExportFields.lua. Recipe IDs ascend, the first
-- written whole and each next as the step from the one before. `bind`, `primary`, `read` and the
-- quality-rank fields are not written; imported professions count as read.
local ExportString = {}

local concat = table.concat
local find = string.find
local floor = math.floor
local ipairs = ipairs
local match = string.match
local max = math.max
local pairs = pairs
local sort = table.sort
local sub = string.sub

local VERSION = "1"
local CHECKSUM_WIDTH = 7
local ADLER_MOD = 65521
local CHUNK = 4096 -- checksum bytes between pause calls
local TRIM_SLACK = 64 -- spaces around a pasted string that may push it past MAX.length

local Fields = ExportFields
local MAX = Fields.MAX

local function noPause() end

-- Adler-32, the sums reduced once per CHUNK (exact in doubles: b stays under 2^33).
local function checksum(text, pause)
  local byte = string.byte
  local a, b = 1, 0
  local length = #text
  for start = 1, length, CHUNK do
    local stop = start + CHUNK - 1
    if stop > length then
      stop = length
    end
    for i = start, stop do
      a = a + byte(text, i)
      b = b + a
    end
    a, b = a % ADLER_MOD, b % ADLER_MOD
    pause(8)
  end
  local digits = Base36.Encode(b * 65536 + a)
  return string.rep("0", CHECKSUM_WIDTH - #digits) .. digits
end

-- Numbers first, ascending, then strings: a Retail and a Classic key never meet, but sort must
-- not raise if they do. Each kind sorts with the default comparator, which runs in C (a Lua
-- comparator took 20 ms in one slice for a character's 5000 recipes).
local function sortedKeys(map)
  local numbers, strings = {}, {}
  for key in pairs(map) do
    local keys = type(key) == "number" and numbers or strings
    keys[#keys + 1] = key
  end
  sort(numbers)
  sort(strings)
  for _, key in ipairs(strings) do
    numbers[#numbers + 1] = key
  end
  return numbers
end

-- The character record and its profession records, or nil when the key cannot be written.
local function characterRecords(key, character, parts)
  if not Fields.IsCharacterKey(key) then
    return nil
  end
  local class = Fields.IsClass(character.class) and character.class or ""
  parts[#parts + 1] = concat({ "c", Fields.Text(key), class, Fields.TextList(character.realms) }, ",")
  local professions = {}
  for _, prof in ipairs(sortedKeys(character.professions)) do
    local name = character.professions[prof].name
    if #professions < MAX.professions and Fields.KeyField(prof) and Fields.IsText(name, true) then
      professions[prof] = true
      parts[#parts + 1] = concat({ "p", Fields.KeyField(prof), Fields.Text(name) }, ",")
    end
  end
  return professions
end

-- → the recipe record, or nil for a recipe Decode would refuse (so it is left out).
local function recipeRecord(keyField, recipe)
  local item, line = Fields.NumberField(recipe.item), Fields.NumberField(recipe.line)
  local ranks = Fields.NumberList(recipe.ranks)
  if item == nil or line == nil or ranks == nil or not Fields.IsText(recipe.name, false) then
    return nil
  end
  local muted = recipe.muted == true and "m" or ""
  return concat({ "r", keyField, Fields.KeyField(recipe.prof), Fields.Text(recipe.name), item, ranks, line, muted }, ",")
end

local function recipeRecords(character, professions, parts, pause)
  local written, previous = 0, 0
  for _, key in ipairs(sortedKeys(character.recipes)) do
    local recipe = character.recipes[key]
    local keyField
    if type(key) == "number" then
      keyField = Fields.IsId(key) and Base36.Encode(key - previous) or nil
    else
      keyField = Fields.KeyField(key)
    end
    local record = keyField and professions[recipe.prof] and recipeRecord(keyField, recipe)
    if record and written < MAX.recipes then
      parts[#parts + 1] = record
      written = written + 1
      previous = type(key) == "number" and key or previous
    end
    pause(1)
  end
end

-- → the export string of the db's local characters (imported ones are never passed on).
function ExportString.Encode(db, flavorKey, pause)
  pause = pause or noPause
  local parts, characters = {}, 0
  for _, key in ipairs(sortedKeys(db.characters)) do
    local character = db.characters[key]
    if character.source ~= "import" and characters < MAX.characters then
      local professions = characterRecords(key, character, parts)
      if professions then
        characters = characters + 1
        recipeRecords(character, professions, parts, pause)
      end
    end
  end
  local head = "CA" .. VERSION .. ":" .. flavorKey .. ":" .. concat(parts, ";")
  return head .. ":" .. checksum(head, pause)
end

local function damaged(what)
  return Localization.Text("The string is damaged (%s).", what)
end

-- → head, version, flavor, body, checksum, or nil. The checksum's ":" is looked for in the last
-- CHECKSUM_WIDTH + 1 bytes and the body checked with a plain find: one "[^:]*" pattern
-- backtracked over the whole string when its end was damaged.
local function split(text)
  local version, flavor, bodyAt = match(text, "^CA(%d+):(%l+):()")
  local sumAt = bodyAt and find(text, ":%w+$", max(bodyAt, #text - CHECKSUM_WIDTH))
  if sumAt == nil then
    return nil
  end
  local body = sub(text, bodyAt, sumAt - 1)
  if find(body, ":", 1, true) then
    return nil
  end
  return sub(text, 1, sumAt - 1), version, flavor, body, sub(text, sumAt + 1)
end

-- → { flavor, characters = { { key, class, realms, professions = { [key] = name }, recipes =
-- { [key] = { name, prof, item, ranks, line, muted } } }... } }, or nil and one error message.
-- Leading and trailing spaces (a paste's newline) are ignored, up to TRIM_SLACK bytes at each
-- end, which may push the string past MAX.length. Only TRIM_SLACK + 1 bytes at each end are
-- looked at: a scan over a 509 KB run of spaces took 45 ms in one slice.
function ExportString.Decode(text, flavorKey, pause)
  pause = pause or noPause
  if type(text) ~= "string" then
    return nil, Localization.Text("Not a Craft Alert export string.")
  end
  if #text > MAX.length + TRIM_SLACK then
    return nil, Localization.Text("The string is too long.")
  end
  local tail = sub(text, -(TRIM_SLACK + 1))
  local first, last = find(sub(text, 1, TRIM_SLACK + 1), "%S"), match(tail, "^.*()%S")
  if #text > TRIM_SLACK + 1 and not (first and last) then
    return nil, Localization.Text("The string has too many spaces around it.")
  end
  text = first and sub(text, first, #text - #tail + last) or ""
  if #text > MAX.length then
    return nil, Localization.Text("The string is too long.")
  end
  local head, version, flavor, body, sum = split(text)
  if head == nil and find(text, "^CA%d+:") then
    return nil, damaged(Localization.Text("incomplete"))
  elseif head == nil then
    return nil, Localization.Text("Not a Craft Alert export string.")
  end
  if version ~= VERSION then
    return nil, Localization.Text("This string comes from another Craft Alert version (format %s).", version)
  end
  if flavor ~= flavorKey then
    return nil, Localization.Text("This string was made on %s; this game is %s.", flavor, flavorKey)
  end
  if sum ~= checksum(head, pause) then
    return nil, damaged(Localization.Text("checksum"))
  end
  -- Records split with a plain find: a "[^;]*" match took 6 ms in one slice over a 590 KB record.
  -- Each record weighs one pause per 256 bytes, so the clock is read before a long one (eight
  -- 10 KB records, about 3 ms each, once ran between two clock reads).
  local state = Fields.NewState()
  local start, number = 1, 0
  while body ~= "" and start <= #body + 1 do
    local stop = find(body, ";", start, true) or #body + 1
    number = number + 1
    pause(1 + floor((stop - start) / 256))
    local err = Fields.ParseRecord(state, sub(body, start, stop - 1))
    if err then
      return nil, damaged(Localization.Text("%s %d", err, number))
    end
    start = stop + 1
  end
  return { flavor = flavor, characters = state.characters }
end

-- The stored record of one decoded character. An earlier import's enabled flag and main crafter
-- choices are kept; its recipes and realms are replaced (a recipe whose item did not change keeps
-- the bind already looked up). Every item without a bind is queued for the lookup.
local function imported(old, incoming, now, pause)
  local professions = {}
  for key, name in pairs(incoming.professions) do
    local previous = old and old.professions[key]
    professions[key] = { name = name, primary = previous ~= nil and previous.primary == true, read = true }
  end
  local recipes, count = {}, 0
  for key, fields in pairs(incoming.recipes) do
    local previous = old and old.recipes[key]
    local bind = previous and previous.item == fields.item and previous.bind or nil
    recipes[key] =
      { name = fields.name, prof = fields.prof, item = fields.item, ranks = fields.ranks, line = fields.line, muted = fields.muted, bind = bind }
    if fields.item and bind == nil then
      BindLookup.Queue(fields.item)
    end
    count = count + 1
    pause(1)
  end
  -- Stored stripped: RealmTag.CannotOrder compares them as they are. One pause per realm: 19
  -- characters of 50 long realms took 9 ms unpaused.
  local realms = {}
  for _, realm in ipairs(incoming.realms) do
    local stripped = RealmTag.Strip(realm)
    if stripped ~= "" then
      realms[#realms + 1] = stripped
    end
    pause(1)
  end
  local record = { source = "import", importedAt = now, enabled = old == nil or old.enabled ~= false, class = incoming.class }
  record.realms, record.professions, record.recipes = realms, professions, recipes
  return record, count
end

-- Stores decoded data → counts { characters, recipes, skipped }. A character this account has as
-- its own (`source = "local"`) is skipped and counted, checked again right before the write:
-- another job (the CraftScan import) may have stored it in the pauses. The caller rebuilds the
-- index.
function ExportString.Apply(db, data, pause)
  pause = pause or noPause
  local counts = { characters = 0, recipes = 0, skipped = 0 }
  local now = _G["time"]()
  local function isOwn(key)
    local character = db.characters[key]
    return character ~= nil and character.source ~= "import"
  end
  for _, incoming in ipairs(data.characters) do
    local record, recipes
    if not isOwn(incoming.key) then
      record, recipes = imported(db.characters[incoming.key], incoming, now, pause)
    end
    if record == nil or isOwn(incoming.key) then
      counts.skipped = counts.skipped + 1
    else
      db.characters[incoming.key] = record
      counts.characters, counts.recipes = counts.characters + 1, counts.recipes + recipes
    end
  end
  return counts
end

-- Slicer job "export": onDone(the export string of the db's local characters), or onCancel()
-- when the job errors or a new export replaces it.
function ExportString.StartExport(db, onDone, onCancel)
  Slicer.Run("export", function(pause)
    return ExportString.Encode(db, FlavorCompat.flavorKey, pause)
  end, onDone, onCancel)
end

-- Slicer job "import": decodes and applies `text`, then requests the index rebuild →
-- onDone(counts), or onDone(nil, error message) with nothing written; onCancel() when the job
-- errors or a new import replaces it.
function ExportString.StartImport(db, text, onDone, onCancel)
  Slicer.Run("import", function(pause)
    local data, err = ExportString.Decode(text, FlavorCompat.flavorKey, pause)
    if data == nil then
      return nil, err
    end
    return ExportString.Apply(db, data, pause)
  end, function(counts, err)
    if counts then
      Index.RequestRebuild("import")
    end
    onDone(counts, err)
  end, onCancel)
end

ns.ExportString = ExportString
return ExportString
