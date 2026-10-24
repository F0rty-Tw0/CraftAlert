local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Index = ns.Index or require("CraftAlert.Model.Index")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Tooltip = ns.Tooltip or require("CraftAlert.UI.Tooltip")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")
local RecipeTooltip = ns.RecipeTooltip or require("CraftAlert.UI.Settings.RecipeTooltip")

-- The Crafters page's recipe list: search, Mute all / Unmute all over the listed recipes, then the
-- scrolling rows with icon, name and mute. Mute changes rebuild the index (§6.2), once per click.
local RecipeList = {}

local find = string.find
local lower = string.lower

local RECIPE_ROWS = 8
local MUTE_WIDTH = 64
local MUTE_ALL_WIDTH = 96

-- Case-insensitive: names read before the client spelling was kept are stored lowercase. Equal
-- names fall back to the key, so the order never depends on pairs(): recipe IDs in number order,
-- then name keys (Classic) as text. Comparing a number with a name as text could loop.
function RecipeList.ByText(a, b)
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

-- The profession's recipes whose name holds the search text, by name.
local function recipeItems(character, prof, search)
  local items = {}
  local needle = lower(search or "")
  for key, recipe in pairs(character and character.recipes or {}) do
    if recipe.prof == prof and find(lower(recipe.name), needle, 1, true) then
      items[#items + 1] = { key = key, recipe = recipe, text = recipe.name }
    end
  end
  table.sort(items, RecipeList.ByText)
  return items
end

local function recipeIcon(item)
  local itemId, spellId = item.recipe.item, item.key
  return (type(itemId) == "number" and select(5, FlavorCompat.GetItemInfoInstant(itemId)))
    or (type(spellId) == "number" and FlavorCompat.GetSpellTexture(spellId))
    or Theme.ICON
end

-- list: { search, recipes, character, prof, Show }; `character` and `prof` are what Show last got.
function RecipeList.Create(column)
  local list = {}

  local function render()
    list.recipes.Render(recipeItems(list.character, list.prof, list.search.input:GetText()), list.showRecipe)
  end

  -- Sets every listed recipe to `muted`; one index rebuild when any changed.
  local function muteAll(muted)
    local changed = 0
    for _, item in ipairs(recipeItems(list.character, list.prof, list.search.input:GetText())) do
      if (item.recipe.muted == true) ~= muted then
        item.recipe.muted = muted or nil
        changed = changed + 1
      end
    end
    if changed > 0 then
      Index.RequestRebuild("mute")
    end
    render()
  end

  -- The recipe tooltip for `row`, read at hover time: the row is reused and the character can change.
  local function showTooltip(row)
    RecipeTooltip.Show(row, list.character)
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
      render()
    end)
    row.mute:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row:SetScript("OnEnter", function()
      row.hovered = true
      showTooltip(row)
    end)
    -- The tooltip's own update (GameTooltipTemplate's, every 0.2 s while shown) calls this instead of
    -- rebuilding from the item data, which would drop our lines once an uncached item loads.
    row.UpdateTooltip = showTooltip
    row:SetScript("OnLeave", function()
      row.hovered = nil
      Tooltip.Get():Hide()
    end)
  end

  -- A row the pointer is on repaints its tooltip. The client can hide the tooltip without an
  -- OnLeave (a fade, another owner), so what is shown does not tell whether the row is hovered.
  function list.showRecipe(row, item)
    local muted = item.recipe.muted == true
    row.item = item
    row.name:SetText(item.text)
    row.icon:SetTexture(recipeIcon(item))
    row.icon:SetDesaturated(muted)
    row.icon:SetAlpha(muted and Theme.DIM_ALPHA or 1)
    row.mute.label:SetText(muted and Localization.Text("Unmute") or Localization.Text("Mute"))
    if row.hovered then
      showTooltip(row)
    end
  end

  list.search = Controls.Input(column, Localization.Text("Search recipes"), render)
  local mute = Controls.Button(column.parent, Localization.Text("Mute all"), MUTE_ALL_WIDTH, function()
    muteAll(true)
  end)
  Controls.Place(column, mute)
  local unmute = Controls.Button(column.parent, Localization.Text("Unmute all"), MUTE_ALL_WIDTH, function()
    muteAll(false)
  end)
  unmute:SetPoint("LEFT", mute, "RIGHT", Theme.LAYOUT.PADDING, 0)
  list.recipes = Controls.List(column, RECIPE_ROWS, createRecipeRow)

  -- Shows `prof`'s recipes of `character` (a db.characters record, or nil) under the current search.
  function list.Show(character, prof)
    list.character, list.prof = character, prof
    render()
  end
  return list
end

ns.RecipeList = RecipeList
return RecipeList
