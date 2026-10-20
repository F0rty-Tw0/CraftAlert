local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local ProfessionWords = ns.ProfessionWords or require("CraftAlert.Model.ProfessionWords")

-- Spec §5.1: the current character's crafting professions, keyed by base skill-line ID
-- (Retail and Forever; the Classic name keys arrive with the Classic task). Gathering,
-- cooking, fishing and first aid are left out by listing only the skill lines
-- ProfessionWords knows. Runs at login.
local ProfessionList = {}

local ipairs = ipairs
local pairs = pairs
local select = select
local sort = table.sort

local SLOTS = 6 -- GetProfessions returns prof1, prof2, then the secondary slots
local PROFESSION_SLOTS = 2

local crafting = {}
for _, entry in ipairs(ProfessionWords.entries) do
  crafting[entry.skillLineID] = true
end

local order = {}

-- → { { key, name }... } in GetProfessions slot order, the number of slots in use and of
-- profession slots (prof1, prof2) in use; nil when the API is missing or a slot's skill line
-- has not loaded (unknown data).
local function currentProfessions()
  local getProfessions = _G["GetProfessions"]
  local getInfo = _G["GetProfessionInfo"]
  if type(getProfessions) ~= "function" or type(getInfo) ~= "function" then
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
      if crafting[skillLine] then
        list[#list + 1] = { key = skillLine, name = name }
      end
    end
  end

  return list, slots, professionSlots
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

-- Before the first usable read of a session, the stored professions stand in, sorted.
local function seedOrder(character)
  if #order > 0 or character == nil then
    return
  end
  local keys = {}
  for key in pairs(character.professions) do
    keys[#keys + 1] = key
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
-- skill line has not loaded, or, for a character that has professions stored, no slot at all
-- or secondary slots only (a partial read at login); then the stored professions seed Order.
-- Trade-off: a character that unlearns both professions keeps its stale data until it
-- learns one. A list of non-crafting professions only (gathering...) is real data and drops.
-- Runs at login and on SKILL_LINES_CHANGED. → whether Order changed (rebuild the index).
function ProfessionList.Refresh(db, charKey)
  local list, slots, professionSlots = currentProfessions()
  local character = db.characters[charKey]
  if list == nil or isPartial(list, slots, professionSlots, character) then
    seedOrder(character)
    return false
  end
  if character == nil then
    character = { source = "local", enabled = true, realms = {}, professions = {}, recipes = {} }
    db.characters[charKey] = character
  end
  local previous = character.professions
  local professions, keys = {}, {}
  for _, profession in ipairs(list) do
    local old = previous[profession.key]
    professions[profession.key] = { name = profession.name, primary = old ~= nil and old.primary == true, read = old ~= nil and old.read == true }
    keys[#keys + 1] = profession.key
  end
  for key in pairs(previous) do
    if professions[key] == nil then
      dropRecipes(character.recipes, key)
    end
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
