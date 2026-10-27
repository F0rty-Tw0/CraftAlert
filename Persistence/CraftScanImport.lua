local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local Defaults = ns.Defaults or require("CraftAlert.Persistence.Defaults")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")
local MainCrafter = ns.MainCrafter or require("CraftAlert.Model.MainCrafter")
local BindLookup = ns.BindLookup or require("CraftAlert.Professions.BindLookup")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")

-- Spec §10.2: the one-time CraftScan import (Retail). Reads CraftScan_DB and never writes it;
-- anything malformed is skipped and counted, never aborting the rest. This account's characters
-- (sourceID nil or settings.my_uuid) come in as `source = "local"`; existing Craft Alert data wins:
-- only missing characters, professions, recipes and realms are added, an existing mute or main
-- crafter is never changed, and a greeting replaces a template only while it is still the default.
-- Recipe fields come from ModernReader.FieldsOf (an alt's recipe reads with the window closed).
local CraftScanImport = {}

local gsub = string.gsub
local ipairs = ipairs
local pairs = pairs
local type = type

local JOB = "craftscan"
-- CraftScan's RECIPE_STATES (CraftScan Consts.lua:238-241).
local PENDING_REVIEW, SCANNING_ON, SCANNING_OFF, UNLEARNED = 1, 2, 3, 4
local GREETINGS = {
  GREETING_I_CAN_CRAFT_ITEM = "item",
  GREETING_I_HAVE_PROF = "profession",
  GREETING_ALT_CAN_CRAFT_ITEM = "altItem",
  GREETING_ALT_HAS_PROF = "altProfession",
}
local MAX_GREETING = 255

-- The professions Craft Alert listens for; CraftScan also scans Cooking (185).
local crafting = {} -- skill-line ID -> true
for _, entry in ipairs(ProfessionWords.entries) do
  crafting[entry.skillLineID] = true
end

local function noPause() end

local function isId(value)
  return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 2147483647
end

local function tableOr(value)
  return type(value) == "table" and value or nil
end

-- The keys of a CraftScan_DB table, copied before a walk that pauses: CraftScan writes its data
-- at runtime, and a key added during `pairs` is undefined in Lua 5.1. A key gone by the time it
-- is read is skipped as malformed.
local function keysOf(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  return keys
end

-- realmID ("_N" or a realm name) → its stripped realm names, from connected_realms, sorted.
local function realmLists(src)
  local lists = {}
  for name, realmID in pairs(tableOr(src.connected_realms) or {}) do
    if type(name) == "string" and type(realmID) == "string" then
      local list = lists[realmID] or {}
      list[#list + 1] = RealmTag.Strip(name)
      lists[realmID] = list
    end
  end
  for _, list in pairs(lists) do
    table.sort(list)
  end
  return lists
end

local function realmsOf(lists, realmID)
  if lists[realmID] then
    return lists[realmID]
  end
  return string.find(realmID, "^_%d+$") and {} or { RealmTag.Strip(realmID) }
end

-- The Craft Alert key of a CraftScan key, compared without apostrophes (legacy CraftScan keys lack
-- them): an existing character's key, else the realm spelled as a known realm of the group; a
-- bare name in a group of several realms gets the player's realm.
local function keyOf(db, csKey, realms)
  csKey = gsub(csKey, "|", "")
  local bare = PlayerName.StripApostrophes(csKey)
  for key in pairs(db.characters) do
    if PlayerName.StripApostrophes(key) == bare then
      return key
    end
  end
  -- A key without a realm takes the realm it is stored under, when that is one realm.
  if not string.find(csKey, "-", 1, true) and #realms == 1 then
    return PlayerName.Normalize(csKey .. "-" .. realms[1])
  end
  local name, realm = PlayerName.NameOf(csKey), PlayerName.RealmOf(csKey)
  for _, known in ipairs(realms) do
    if realm and PlayerName.StripApostrophes(known) == PlayerName.StripApostrophes(realm) then
      return PlayerName.Normalize(name .. "-" .. known)
    end
  end
  return PlayerName.Normalize(csKey)
end

-- → muted (true/false), or nil to skip; second value: whether the record was malformed.
local function stateOf(recipe, profession, parentOff)
  local state = recipe.scan_state
  if state == nil then
    -- Legacy record (before scan_state), mapped as CraftScan's own upgrade does (Utils.lua:788-810).
    state = (recipe.enabled == true or profession.all_enabled == true) and SCANNING_ON or PENDING_REVIEW
  end
  if state == UNLEARNED then
    return nil, false
  end
  if state ~= SCANNING_ON and state ~= PENDING_REVIEW and state ~= SCANNING_OFF then
    return nil, true
  end
  return parentOff or state ~= SCANNING_ON, false
end

-- One CraftScan profession of a character into `character` (Craft Alert shape).
local function importProfession(ctx, character, parents, profession)
  local prof = profession.parentProfID
  local recipes = tableOr(profession.recipes)
  if not crafting[prof] or recipes == nil then
    ctx.counts.skipped = ctx.counts.skipped + 1
    return
  end
  local parent = tableOr(parents[prof]) or {}
  local parentOff = parent.scanning_enabled == false or parent.character_disabled == true
  local name = nil
  for _, recipeID in ipairs(keysOf(recipes)) do
    local recipe = recipes[recipeID]
    local muted, malformed = nil, true
    if isId(recipeID) and type(recipe) == "table" then
      muted, malformed = stateOf(recipe, profession, parentOff)
    end
    local fields, profInfo
    if muted ~= nil and character.recipes[recipeID] == nil then
      fields, profInfo = ModernReader.FieldsOf(recipeID)
      malformed = fields == nil
    end
    if fields then
      fields.prof, fields.muted = prof, muted or nil
      character.recipes[recipeID] = fields
      if fields.item then
        BindLookup.Queue(fields.item)
      end
      ctx.counts.recipes = ctx.counts.recipes + 1
      ctx.counts.muted = ctx.counts.muted + (muted and 1 or 0)
      name = name or (profInfo and profInfo.parentProfessionName ~= "" and profInfo.parentProfessionName) or nil
    end
    if malformed then
      ctx.counts.skipped = ctx.counts.skipped + 1
    end
    -- Up to three client calls per recipe: the Slicer reads its clock after each one.
    ctx.pause(8)
  end
  -- One profession comes from several expansions; the first walked may name nothing (all
  -- unlearned), so a later one fills the empty name.
  local stored = character.professions[prof]
  name = type(name) == "string" and name or nil
  if stored == nil then
    character.professions[prof] = { name = name or "", primary = false, read = true }
  elseif stored.name == "" and name then
    stored.name = name
  end
  if parent.primary_crafter == true then
    ctx.primaries[prof] = ctx.primaries[prof] or {}
    ctx.primaries[prof][#ctx.primaries[prof] + 1] = ctx.key
  end
end

local function importCharacter(ctx, csKey, record, realms)
  local key = type(csKey) == "string" and keyOf(ctx.db, csKey, realms) or nil
  local professions = tableOr(record.professions)
  if key == nil or professions == nil then
    ctx.counts.skipped = ctx.counts.skipped + 1
    return
  end
  local character = ctx.db.characters[key]
  if character == nil then
    character = { source = "local", enabled = true, realms = {}, professions = {}, recipes = {} }
    ctx.db.characters[key] = character
  end
  if #character.realms == 0 then
    for i, realm in ipairs(realms) do
      character.realms[i] = realm
    end
  end
  ctx.key = key
  local parents = tableOr(record.parent_professions) or {}
  for _, profID in ipairs(keysOf(professions)) do
    local profession = professions[profID]
    if type(profession) == "table" then
      importProfession(ctx, character, parents, profession)
    else
      ctx.counts.skipped = ctx.counts.skipped + 1
    end
  end
  ctx.counts.characters = ctx.counts.characters + 1
end

-- Several CraftScan primaries for one profession: the lowest key, and only when Craft Alert has none.
local function setPrimaries(db, primaries)
  for prof, keys in pairs(primaries) do
    table.sort(keys)
    if MainCrafter.Of(db, prof) == nil then
      MainCrafter.Set(db, keys[1], prof, true)
    end
  end
end

-- The first MAX_GREETING bytes, never ending inside a UTF-8 character.
local function capped(text)
  local cut = MAX_GREETING
  while cut > 0 and cut < #text and string.byte(text, cut + 1) >= 128 and string.byte(text, cut + 1) < 192 do -- a continuation byte
    cut = cut - 1
  end
  return string.sub(text, 1, cut)
end

local function importGreetings(db, settings, counts)
  local defaults = Defaults.Settings().templates
  for tag, text in pairs(tableOr(settings.greeting) or {}) do
    local key = GREETINGS[tag]
    -- `rev` is CraftScan's sync revision, not a greeting.
    if tag ~= "rev" then
      if key == nil or type(text) ~= "string" or text == "" then
        counts.skipped = counts.skipped + 1
      elseif db.settings.templates[key] == defaults[key] then
        text = gsub(gsub(gsub(text, "{profession_link}", "{profession}"), "|", ""), "[\r\n]", " ")
        db.settings.templates[key] = capped(text)
        counts.greetings = counts.greetings + 1
      end
    end
  end
end

-- Imports `src` (CraftScan_DB) into `db` → counts { characters, recipes, muted, greetings, skipped }.
-- pause: Slicer.Run's (tests may leave it out).
function CraftScanImport.Run(db, src, pause)
  local counts = { characters = 0, recipes = 0, muted = 0, greetings = 0, skipped = 0 }
  local ctx = { db = db, counts = counts, pause = pause or noPause, primaries = {} }
  local settings = tableOr(src.settings) or {}
  local mine = settings.my_uuid
  local lists = realmLists(src)
  local srcRealms = tableOr(src.realms) or {}
  for _, realmID in ipairs(keysOf(srcRealms)) do
    local realm = srcRealms[realmID]
    local characters = type(realmID) == "string" and type(realm) == "table" and tableOr(realm.characters) or nil
    if characters == nil then
      counts.skipped = counts.skipped + 1
    else
      local realms = realmsOf(lists, realmID)
      for _, csKey in ipairs(keysOf(characters)) do
        local record = characters[csKey]
        local own = type(record) == "table" and (record.sourceID == nil or record.sourceID == mine)
        if type(record) ~= "table" then
          counts.skipped = counts.skipped + 1
        elseif own then
          importCharacter(ctx, csKey, record, realms)
        end
      end
    end
  end
  setPrimaries(db, ctx.primaries)
  importGreetings(db, settings, counts)
  return counts
end

-- Slicer job "craftscan" → onDone(counts) once the import ended and the index rebuild is requested,
-- or onCancel() when the job errors or a new CraftScan import replaces it.
function CraftScanImport.Start(db, src, onDone, onCancel)
  Slicer.Run(JOB, function(pause)
    return CraftScanImport.Run(db, src, pause)
  end, function(counts)
    Index.RequestRebuild("craftscan")
    onDone(counts)
  end, onCancel)
end

ns.CraftScanImport = CraftScanImport
return CraftScanImport
