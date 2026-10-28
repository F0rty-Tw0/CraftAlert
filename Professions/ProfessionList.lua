local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Defaults = ns.Defaults or require("CraftAlert.Persistence.Defaults")
local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")

-- Spec §5.1: the current character's crafting professions, keyed by base skill-line ID on
-- Retail and Forever and by the lowercase English name on Classic. GetProfessions when the
-- client has it (Retail, Forever, Cata, MoP), else the skill-line list (Era, TBC, Wrath).
-- Gathering, cooking, fishing and first aid are left out by listing only the professions
-- ProfessionWords knows. Runs at login.
local ProfessionList = {}

local ipairs = ipairs
local pairs = pairs
local select = select
local lower = string.lower
local sort = table.sort

local SLOTS = 6 -- GetProfessions returns prof1, prof2, then the secondary slots
local PROFESSION_SLOTS = 2

local crafting = {} -- skill-line ID -> ProfessionWords entry
local craftingNames = {} -- englishName -> true
for _, entry in ipairs(ProfessionWords.entries) do
  crafting[entry.skillLineID] = entry
  craftingNames[entry.englishName] = true
end

local order = {}

-- → { { key, name }... } in GetProfessions slot order, the number of slots in use and of
-- profession slots (prof1, prof2) in use; nil when the API is missing or a slot's skill line
-- has not loaded (unknown data). The 7th GetProfessionInfo return is the skill line on Cata
-- and MoP too (inferred from Retail).
local function slotProfessions(getProfessions)
  local getInfo = _G["GetProfessionInfo"]
  if type(getInfo) ~= "function" then
    return nil
  end
  local list, slots, professionSlots = {}, 0, 0
  for position = 1, SLOTS do
    local index = select(position, getProfessions())
    if index then
      slots = slots + 1
      professionSlots = professionSlots + (position <= PROFESSION_SLOTS and 1 or 0)
      local name, _, _, _, _, _, skillLine = getInfo(index)
      if skillLine == nil then
        return nil
      end
      local entry = crafting[skillLine]
      if entry then
        list[#list + 1] = { key = FlavorCompat.isClassic and entry.englishName or skillLine, name = name }
      end
    end
  end

  return list, slots, professionSlots
end

-- The skill-line list (Era, TBC, Wrath) as slotProfessions answers, every visible non-header
-- line counting as a profession slot, plus hidden = true when a collapsed header may hide a
-- crafting profession; nil when the API is missing. Every crafting profession sits under the one
-- Professions header, so a visible crafting line shows nothing of them is hidden.
local function skillLineProfessions()
  local getCount = _G["GetNumSkillLines"]
  local getInfo = _G["GetSkillLineInfo"]
  if type(getCount) ~= "function" or type(getInfo) ~= "function" then
    return nil
  end
  local list, lines, hidden = {}, 0, false
  for index = 1, getCount() or 0 do
    local name, isHeader, isExpanded = getInfo(index)
    if isHeader and not isExpanded then
      hidden = true
    end
    if not isHeader and type(name) == "string" then
      lines = lines + 1
      local key = lower(name)
      if craftingNames[key] then
        list[#list + 1] = { key = key, name = name }
      end
    end
  end

  return list, lines, lines, hidden and #list == 0
end

local function currentProfessions()
  local getProfessions = _G["GetProfessions"]
  if type(getProfessions) == "function" then
    return slotProfessions(getProfessions)
  end
  return skillLineProfessions()
end

-- Whether a known read must not be written: nothing to create, or, for a character with
-- professions stored, no slot at all or only secondary slots (at login those can load
-- before prof1 and prof2).
local function isPartial(list, slots, professionSlots, character)
  if character == nil then
    return #list == 0
  end
  local hasStored = next(character.professions) ~= nil

  return hasStored and (slots == 0 or professionSlots == 0)
end

local function sameOrder(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end

  return true
end

-- Before the first usable read of a session, the stored professions stand in, sorted. Only the
-- key type Refresh writes on this flavor: the Schema keeps both, and sorting a mix raises.
local function seedOrder(character)
  if #order > 0 or character == nil then
    return
  end
  local keyType = FlavorCompat.isClassic and "string" or "number"
  local keys = {}
  for key in pairs(character.professions) do
    if type(key) == keyType then
      keys[#keys + 1] = key
    end
  end
  sort(keys)
  order = keys
end

local function dropRecipes(recipes, professionKey)
  for recipeKey, recipe in pairs(recipes) do
    if recipe.prof == professionKey then
      recipes[recipeKey] = nil
    end
  end
end

-- Rebuilds the character's professions from the client (`primary` is the player's choice
-- per profession, so it is kept, never derived from the slot) and removes the recipes of a
-- profession it no longer has. Other characters are never touched. Unknown data writes
-- nothing, so a failed lookup cannot wipe stored recipes: a missing API, a slot whose
-- skill line has not loaded, or, for a character that has professions stored, no slot or
-- line at all or secondary slots only (a partial read at login); then the stored professions
-- seed Order. A collapsed skill-line header may hide a profession, so then every stored one
-- the visible lines do not list is kept unchanged, with its recipes, after the visible ones
-- in Order.
-- Trade-off: a character that unlearns both professions keeps its stale data until it
-- learns one. A list of non-crafting professions only (gathering...) is real data and drops.
-- Runs at login and on SKILL_LINES_CHANGED. → whether Order changed (rebuild the index).
function ProfessionList.Refresh(db, charKey)
  local list, slots, professionSlots, hidden = currentProfessions()
  local character = db.characters[charKey]
  if list == nil or isPartial(list, slots, professionSlots, character) then
    seedOrder(character)
    return false
  end
  if character == nil then
    character = Defaults.Character()
    db.characters[charKey] = character
  end
  character.class = FlavorCompat.OwnClass() or character.class
  local previous = character.professions
  local professions, keys = {}, {}
  for _, profession in ipairs(list) do
    local old = previous[profession.key]
    professions[profession.key] = {
      name = profession.name,
      primary = old ~= nil and old.primary == true,
      read = old ~= nil and old.read == true,
      newestLine = old and old.newestLine or nil,
    }
    keys[#keys + 1] = profession.key
  end
  local kept = {}
  for key, old in pairs(previous) do
    if professions[key] == nil and hidden then
      professions[key] = old
      -- Only name keys join Order: a Retail skill-line ID would make the sort raise.
      if type(key) == "string" then
        kept[#kept + 1] = key
      end
    elseif professions[key] == nil then
      dropRecipes(character.recipes, key)
    end
  end
  sort(kept)
  for _, key in ipairs(kept) do
    keys[#keys + 1] = key
  end
  character.professions = professions
  local changed = not sameOrder(order, keys)
  order = keys

  return changed
end

-- The current character's professionKeys in slot order (the §6.3 step 4.4 tie-break).
function ProfessionList.Order()
  return order
end

function ProfessionList.IsStored(db, charKey, professionKey)
  local character = db.characters[charKey]
  return character ~= nil and character.professions[professionKey] ~= nil
end

-- Names of the character's professions never read, for the login hint (§5.2).
function ProfessionList.UnreadNames(db, charKey)
  local names = {}
  local character = db.characters[charKey]
  for _, profession in pairs(character and character.professions or {}) do
    if not profession.read then
      names[#names + 1] = profession.name
    end
  end
  sort(names)
  return names
end

ns.ProfessionList = ProfessionList
return ProfessionList
