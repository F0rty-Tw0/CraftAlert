local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")
local RecipeTooltip = ns.RecipeTooltip or require("CraftAlert.UI.Settings.RecipeTooltip")

-- Spec §9 Crafters: one character at a time (current, same-account, imported) with enable,
-- remove (asks for a second click) and, per profession, the primary flag and the recipe list
-- with search, recipe icons and mute. Enable, remove and mute rebuild the index (§6.2); the
-- primary flag is read when a lead picks its crafter (§6.3 step 5), so it rebuilds nothing.
local PageCrafters = { id = "crafters", title = Localization.Text("Crafters") }

local find = string.find
local lower = string.lower

local RECIPE_ROWS = 8
local MUTE_WIDTH = 64
local REMOVE_WIDTH = 140

local function db()
  return _G["CraftAlertDB"]
end

-- Case-insensitive: names read before the client spelling was kept are stored lowercase. Equal
-- names fall back to the key, so the order never depends on pairs(): recipe IDs in number order,
-- then name keys (Classic) as text. Comparing a number with a name as text could loop.
local function byText(a, b)
  local left, right = lower(a.text), lower(b.text)
  if left ~= right then
    return left < right
  end
  local leftType, rightType = type(a.key), type(b.key)
  if leftType ~= rightType then
    return leftType < rightType -- "number" < "string"
  end
  if leftType == "number" then
    return a.key < b.key
  end
  return tostring(a.key) < tostring(b.key)
end

local function characterOptions()
  local options = {}
  for key, character in pairs(db().characters) do
    local imported = character.source == "import"
    local source = key == PlayerName.Own() and "this character" or (imported and "imported" or "same account")
    options[#options + 1] = { value = key, text = Localization.Text("%s (%s)", key, Localization.Text(source)), key = key }
  end
  table.sort(options, function(a, b)
    return a.key < b.key
  end)
  return options
end

local function professionOptions(character)
  local options = {}
  for key, profession in pairs(character and character.professions or {}) do
    options[#options + 1] = { value = key, text = profession.name ~= "" and profession.name or tostring(key), key = key }
  end
  table.sort(options, byText)
  return options
end

-- The shown profession's recipes whose name holds the search text, by name.
local function recipeItems(character, prof, search)
  local items = {}
  local needle = lower(search or "")
  for key, recipe in pairs(character and character.recipes or {}) do
    if recipe.prof == prof and find(lower(recipe.name), needle, 1, true) then
      items[#items + 1] = { key = key, recipe = recipe, text = recipe.name }
    end
  end
  table.sort(items, byText)
  return items
end

-- Primary is one crafter per profession: setting it clears every other character's flag.
local function setPrimary(charKey, prof, on)
  for key, character in pairs(db().characters) do
    local profession = character.professions[prof]
    if profession and (key == charKey or on) then
      profession.primary = key == charKey and on
    end
  end
end

local function recipeIcon(item)
  local itemId, spellId = item.recipe.item, item.key
  return (type(itemId) == "number" and select(5, FlavorCompat.GetItemInfoInstant(itemId)))
    or (type(spellId) == "number" and FlavorCompat.GetSpellTexture(spellId))
    or Theme.ICON
end

local function shownCharacter(page)
  return db().characters[page.character.Value()]
end

-- The recipe tooltip for `row`, read at hover time: the row is reused and the character can change.
local function showTooltip(row)
  RecipeTooltip.Show(row, shownCharacter(row.page))
end

local function createRecipeRow(row)
  local size = Theme.LAYOUT.ROW_ICON_SIZE
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(size, size)
  row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.name = FrameKit.Text(row, Theme.FONTS.body)
  row.name:SetPoint("LEFT", row.icon, "RIGHT", Theme.LAYOUT.PADDING, 0)
  row.mute = Controls.Button(row, "", MUTE_WIDTH, function()
    row.item.recipe.muted = not row.item.recipe.muted or nil
    Index.RequestRebuild("mute")
    row.page.ShowRecipes()
  end)
  row.mute:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row:SetScript("OnEnter", showTooltip)
  -- The tooltip's own update (GameTooltipTemplate's, every 0.2 s while shown) calls this instead of
  -- rebuilding from the item data, which would drop our lines once an uncached item loads.
  row.UpdateTooltip = showTooltip
  row:SetScript("OnLeave", function()
    Tooltip.Get():Hide()
  end)
end

local function showRecipe(row, item)
  local muted = item.recipe.muted == true
  row.item = item
  row.name:SetText(item.text)
  row.icon:SetTexture(recipeIcon(item))
  row.icon:SetDesaturated(muted)
  row.icon:SetAlpha(muted and Theme.DIM_ALPHA or 1)
  row.mute.label:SetText(muted and Localization.Text("Unmute") or Localization.Text("Mute"))
  if Tooltip.Get():IsOwned(row) then
    showTooltip(row)
  end
end

-- page: { character, enabled, remove, profession, primary, search, recipes, ... }
local function createCharacterRows(column, page)
  Controls.Section(column, Localization.Text("Character"))
  page.character = Controls.Choice(column, Localization.Text("Character"), {}, function()
    page.ShowCharacter()
  end)
  page.enabled = Controls.Toggle(column, Localization.Text("Listen for this character"), function(on)
    local character = shownCharacter(page)
    if character then
      character.enabled = on
      Index.RequestRebuild("crafter")
    end
  end)
  page.remove = Controls.Button(column.parent, Localization.Text("Remove character"), REMOVE_WIDTH, function()
    if shownCharacter(page) == nil then
      return
    end
    if not page.confirming then
      page.confirming = true
      page.remove.label:SetText(Localization.Text("Click again to remove"))
      return
    end
    local key = page.character.Value()
    db().characters[key] = nil
    -- The current character is stored again from the client, as at login: the profession
    -- readers only record a character that is stored, and the realm tag needs its realms.
    if key == PlayerName.Own() then
      ProfessionList.Refresh(db(), key)
      RealmTag.Store(db(), key)
    end
    Index.RequestRebuild("crafter")
    page.Refresh()
  end)
  Controls.Place(column, page.remove)
end

local function createProfessionRows(column, page)
  Controls.Section(column, Localization.Text("Professions"))
  page.profession = Controls.Choice(column, Localization.Text("Profession"), {}, function()
    page.ShowProfession()
  end)
  page.primary = Controls.Toggle(column, Localization.Text("Primary crafter for this profession"), function(on)
    if page.profession.Value() ~= nil then
      setPrimary(page.character.Value(), page.profession.Value(), on)
    end
  end)
  page.search = Controls.Input(column, Localization.Text("Search recipes"), function()
    page.ShowRecipes()
  end)
  page.recipes = Controls.List(column, RECIPE_ROWS, createRecipeRow)
  for _, row in ipairs(page.recipes.rows) do
    row.page = page
  end
end

function PageCrafters.Create(parent)
  local column = Controls.Column(parent)
  local page = {}
  createCharacterRows(column, page)
  createProfessionRows(column, page)
  function page.ShowRecipes()
    local items = recipeItems(shownCharacter(page), page.profession.Value(), page.search.input:GetText())
    page.recipes.Render(items, showRecipe)
  end
  function page.ShowProfession()
    local profession = (shownCharacter(page) or { professions = {} }).professions[page.profession.Value()]
    page.primary.Set(profession ~= nil and profession.primary)
    page.search.Set("")
    page.ShowRecipes()
  end
  function page.ShowCharacter()
    local character = shownCharacter(page)
    page.confirming = false
    page.remove.label:SetText(Localization.Text("Remove character"))
    page.enabled.Set(character ~= nil and character.enabled ~= false)
    page.profession.SetOptions(professionOptions(character), nil)
    page.ShowProfession()
  end
  function page.Refresh()
    local current = page.character.Value()
    if current == nil or db().characters[current] == nil then
      current = PlayerName.Own()
    end
    page.character.SetOptions(characterOptions(), current)
    page.ShowCharacter()
  end
  return page
end

ns.PageCrafters = PageCrafters
return PageCrafters
