local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Constants = ns.Constants or require("CraftAlert.Core.Constants")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local Defaults = ns.Defaults or require("CraftAlert.Persistence.Defaults")

-- Shape check for CraftAlertDB (spec §10), run once at load. Wrong types fall back to
-- defaults (a string where a number belongs is wrong, not converted), unknown keys in
-- fixed-shape tables are dropped, numbers are clamped. A db saved by a newer version
-- keeps its unknown keys and its schema number, and costs one chat warning.
-- Pure data: no time, no player name, so it is safe at ADDON_LOADED.
local Schema = {}

local huge = math.huge
local gsub = string.gsub
local type = type
local pairs = pairs
local ipairs = ipairs

local RANGES = { toastDuration = { 5, 120 }, leadTimeoutMin = { 1, 60 }, opacity = { 0.3, 1.0 } }
local SETTING_OPTIONAL = { craftScanImported = "number", craftScanPrompted = "boolean" }
local PROFESSION_SHAPE = { name = "", primary = false, read = false }
local RECIPE_FIELDS = {
  name = "string",
  prof = "key",
  item = "number",
  ranks = "table",
  bind = "number",
  muted = "boolean",
  reachRank = "number",
  reachCost = "number",
  reachConc = "number",
}
local CHARACTER_FIELDS =
  { source = "string", importedAt = "number", realms = "table", professions = "table", recipes = "table", concentration = "table" }
local LEAD_FIELDS = {
  id = "number",
  customer = "string",
  crafter = "string",
  time = "number",
  guid = "string",
  message = "string",
  channel = "string",
  kind = "string",
  prof = "key",
  group = "key",
  why = "string",
  cannotOrder = "boolean",
  greeted = "boolean",
  replied = "boolean",
  arrivedWhileAfk = "boolean",
  test = "boolean",
  profName = "string",
  recipeName = "string",
  itemID = "number",
  itemLink = "string",
  rank = "number",
  rankConc = "boolean",
}
local COUNTERS = { seen = 0, greeted = 0, replied = 0, filled = 0 }
local UI_FRAMES = { toast = true, window = true, launcher = true }
local DAY_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"

-- Set by Validate; read by every dropUnknown.
local keepUnknown = false

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= huge and value ~= -huge
end

local function isName(value)
  return type(value) == "string" and value ~= ""
end

local function isKey(value)
  return isNumber(value) or isName(value)
end

local function isString(value)
  return type(value) == "string"
end

local function isDay(value)
  return type(value) == "string" and string.find(value, DAY_PATTERN) ~= nil
end

local function isScalar(value)
  return isNumber(value) or type(value) == "string" or type(value) == "boolean"
end

local function isAny()
  return true
end

local CHECKS = {
  boolean = function(value)
    return type(value) == "boolean"
  end,
  string = isString,
  number = isNumber,
  table = function(value)
    return type(value) == "table"
  end,
  key = isKey,
}

-- Fixed-shape table: scalar defaults replace wrong types; `optional` ({key = typeName})
-- fields are cleared when wrong; every other key is dropped (unless keepUnknown).
local function fixShape(tbl, defaults, optional)
  for key, default in pairs(defaults) do
    local check = CHECKS[type(default)]
    if check and not check(tbl[key]) then
      tbl[key] = default
    end
  end
  for key, typeName in pairs(optional or {}) do
    if tbl[key] ~= nil and not CHECKS[typeName](tbl[key]) then
      tbl[key] = nil
    end
  end
  if keepUnknown then
    return tbl
  end
  for key in pairs(tbl) do
    if defaults[key] == nil and not (optional and optional[key]) then
      tbl[key] = nil
    end
  end
  return tbl
end

-- Open map: entries whose key or value fails its check are removed; a non-table becomes {}.
local function fixMap(map, keyOk, valueOk)
  if type(map) ~= "table" then
    return {}
  end
  for key, value in pairs(map) do
    if not keyOk(key) or not valueOk(value) then
      map[key] = nil
    end
  end
  return map
end

-- Map of records: fixOne repairs a record in place and returns it, or nil to drop it.
local function fixRecords(map, keyOk, fixOne)
  if type(map) ~= "table" then
    return {}
  end
  for key, record in pairs(map) do
    if not keyOk(key) or type(record) ~= "table" or fixOne(record) == nil then
      map[key] = nil
    end
  end
  return map
end

-- Array of values that pass valueOk, as a new array in key order; nil when `list` is not a
-- table. Walks every numeric key, not ipairs, so a hole (`leads[1] = nil`) keeps the rest.
local function fixList(list, valueOk)
  if type(list) ~= "table" then
    return nil
  end
  local keys = {}
  for key in pairs(list) do
    if type(key) == "number" and key >= 1 and key % 1 == 0 and key ~= math.huge then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local kept = {}
  for _, key in ipairs(keys) do
    if valueOk(list[key]) then
      kept[#kept + 1] = list[key]
    end
  end
  return kept
end

local function fixSettings(settings)
  local defaults = Defaults.Settings()
  if type(settings) ~= "table" then
    return defaults
  end
  fixShape(settings, defaults, SETTING_OPTIONAL)
  for key, range in pairs(RANGES) do
    settings[key] = math.max(range[1], math.min(range[2], settings[key]))
  end
  local kits = Constants.flavors[FlavorCompat.flavorKey].soundKits
  local isKit = settings.sound == 0
  for _, kit in ipairs(kits) do
    isKit = isKit or settings.sound == kit
  end
  if not isKit then
    settings.sound = defaults.sound
  end
  for _, name in ipairs({ "channels", "templates" }) do
    local sub = type(settings[name]) == "table" and settings[name] or {}
    settings[name] = fixShape(sub, defaults[name])
  end
  settings.notes = fixMap(settings.notes, isKey, isString)
  settings.extraSlang = fixMap(settings.extraSlang, isString, isString)
  settings.intentWords = fixList(settings.intentWords, isString) or defaults.intentWords
  settings.blockerWords = fixList(settings.blockerWords, isString) or defaults.blockerWords
  return settings
end

local function fixProfession(record)
  return fixShape(record, PROFESSION_SHAPE)
end

-- A recipe without a usable name or profession cannot be matched or shown: dropped.
local function fixRecipe(record)
  if not isString(record.name) or not isKey(record.prof) then
    return nil
  end
  fixShape(record, {}, RECIPE_FIELDS)
  if record.ranks ~= nil then
    local ranks = fixList(record.ranks, isNumber)
    record.ranks = #ranks > 0 and ranks or nil
  end
  -- Rank, cost and concentration are one measurement: all three or none.
  if not (isNumber(record.reachRank) and isNumber(record.reachCost) and isNumber(record.reachConc)) then
    record.reachRank, record.reachCost, record.reachConc = nil, nil, nil
  end
  return record
end

-- RealmTag.CannotOrder compares stored realms with plain ==, so a hand-edited "Area 52" is
-- stripped like Store does, here, once. A realm left blank names no realm and is dropped.
local function fixRealms(list)
  local realms = {}
  for _, realm in ipairs(fixList(list, isString) or {}) do
    local stripped = gsub(realm, "[ %-]", "")
    if stripped ~= "" then
      realms[#realms + 1] = stripped
    end
  end

  return realms
end

local SNAPSHOT_NUMBERS = { "amount", "at", "cycleMs", "perCycle", "max" }

local function isSnapshot(value)
  if type(value) ~= "table" then
    return false
  end
  for _, field in ipairs(SNAPSHOT_NUMBERS) do
    if not isNumber(value[field]) then
      return false
    end
  end
  return value.cycleMs > 0
end

-- Per-currency concentration snapshots; nil when none is valid.
local function fixConcentration(map)
  if type(map) ~= "table" then
    return nil
  end
  fixMap(map, isNumber, isSnapshot)
  return next(map) ~= nil and map or nil
end

local function fixCharacter(record)
  if record.source ~= "local" and record.source ~= "import" then
    record.source = "local"
  end
  fixShape(record, { enabled = true }, CHARACTER_FIELDS)
  record.realms = fixRealms(record.realms)
  record.professions = fixRecords(record.professions, isKey, fixProfession)
  record.recipes = fixRecords(record.recipes, isKey, fixRecipe)
  record.concentration = fixConcentration(record.concentration)
  return record
end

local function fixDay(record)
  fixShape(record, COUNTERS)
  for key in pairs(COUNTERS) do
    record[key] = math.max(0, record[key])
  end
  return record
end

-- The lead record is owned by Model/Leads.lua. What pruning, display and the greeting cannot do
-- without (a customer, a crafter and a time) is required; any other wrong-typed field is
-- cleared, as a lead without it is valid. A bad id is cleared too: Leads.Restore gives a fresh one.
local function fixLead(lead)
  if type(lead) ~= "table" then
    return false
  end
  local required = isName(lead.customer) and isName(lead.crafter) and isNumber(lead.time)
  if not required then
    return false
  end
  fixShape(lead, {}, LEAD_FIELDS)
  return true
end

local function fixLeads(list)
  return fixList(list, fixLead) or {}
end

local function fixUi(ui)
  if type(ui) ~= "table" then
    return {}
  end
  if not keepUnknown then
    for key in pairs(ui) do
      if not UI_FRAMES[key] then
        ui[key] = nil
      end
    end
  end
  for key in pairs(UI_FRAMES) do
    if type(ui[key]) == "table" then
      -- A newer schema may store nested frame values (e.g. a size table): keep them.
      fixMap(ui[key], isKey, keepUnknown and isAny or isScalar)
    else
      ui[key] = nil
    end
  end
  return ui
end

local function warnNewer(version)
  ChatPrint.Line(
    Localization.Text(
      "Your saved data comes from a newer Craft Alert (schema %s). Fields this version does not know are kept; update Craft Alert to use them.",
      tostring(version)
    )
  )
end

-- Repairs `db` in place and returns it; anything that is not a table becomes a fresh db.
function Schema.Validate(db)
  if type(db) ~= "table" then
    return Defaults.Db()
  end
  local version = isNumber(db.schema) and db.schema >= Defaults.schemaVersion and db.schema or Defaults.schemaVersion
  db.schema = version
  keepUnknown = version > Defaults.schemaVersion
  if keepUnknown then
    warnNewer(version)
  end
  db.settings = fixSettings(db.settings)
  db.characters = fixRecords(db.characters, isName, fixCharacter)
  db.leads = fixLeads(db.leads)
  db.ledger = fixRecords(db.ledger, isDay, fixDay)
  db.recentGreeted = fixMap(db.recentGreeted, isName, isNumber)
  if not keepUnknown then
    db.ignored = nil
  end
  db.ui = fixUi(db.ui)
  keepUnknown = false
  return db
end

ns.Schema = Schema
return Schema
