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
local RecipeRarity = ns.RecipeRarity or require("CraftAlert.UI.Settings.RecipeRarity")
local RecipeMute = ns.RecipeMute or require("CraftAlert.UI.Settings.RecipeMute")

-- The Crafters page's recipe list: search, Mute all / Unmute all over the listed recipes, "Only
-- <expansion>" over the whole profession, then the scrolling rows with icon, name in its rarity
-- colour (UI/Settings/RecipeRarity.lua) and the mute speaker (UI/Settings/RecipeMute.lua). Mute
-- changes rebuild the index (§6.2), once per click. An untracked recipe's row is greyed.
local RecipeList = {}

local find = string.find
local lower = string.lower

local RECIPE_ROWS = 8

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

-- Unmuted first, then muted, then untracked (they never alert, muted or not).
local function groupOf(recipe)
  if RecipeMute.Untracked(recipe) then
    return 3
  end
  return recipe.muted and 2 or 1
end

local function byGroup(a, b)
  if a.group ~= b.group then
    return a.group < b.group
  end
  return RecipeList.ByText(a, b)
end

-- The profession's recipes whose name holds the search text, by group, then by name.
local function recipeItems(character, prof, search)
  local items = {}
  local needle = lower(search or "")
  for key, recipe in pairs(character and character.recipes or {}) do
    if recipe.prof == prof and find(lower(recipe.name), needle, 1, true) then
      items[#items + 1] = { key = key, recipe = recipe, text = recipe.name, group = groupOf(recipe) }
    end
  end
  table.sort(items, byGroup)
  return items
end

local function recipeIcon(item)
  local itemId, spellId = item.recipe.item, item.key
  return (type(itemId) == "number" and select(5, FlavorCompat.GetItemInfoInstant(itemId)))
    or (type(spellId) == "number" and FlavorCompat.GetSpellTexture(spellId))
    or Theme.ICON
end

-- The highest stored `line` among the profession's recipes (spec Design 2: line IDs rise with each
-- expansion), or nil when none has one.
local function currentLine(character, prof)
  local current
  for _, recipe in pairs(character and character.recipes or {}) do
    if recipe.prof == prof and recipe.line and (current == nil or recipe.line > current) then
      current = recipe.line
    end
  end
  return current
end

-- The line's expansion name, or nil: an empty name and a client without the call give none.
local function expansionName(line)
  local api = _G["C_TradeSkillUI"]
  if type(api) ~= "table" or type(api.GetProfessionInfoBySkillLineID) ~= "function" then
    return nil
  end
  local info = api.GetProfessionInfoBySkillLineID(line)
  local name = type(info) == "table" and info.expansionName
  return type(name) == "string" and name ~= "" and name or nil
end

-- Mute all and Unmute all share a row, half each less the gap; their anchors set the widths.
local function createMuteAll(column, muteAll)
  local gap = Theme.LAYOUT.PADDING / 2
  local bar = Controls.Bar(column, Theme.LAYOUT.BUTTON_HEIGHT)
  local mute = Controls.Button(bar, Localization.Text("Mute all"), 0, function()
    muteAll(true)
  end, Localization.Text("Mutes every recipe the list shows. With a search typed, only the recipes it finds."))
  mute:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  mute:SetPoint("TOPRIGHT", bar, "TOP", -gap, 0)
  local unmute = Controls.Button(bar, Localization.Text("Unmute all"), 0, function()
    muteAll(false)
  end, Localization.Text("Unmutes every recipe the list shows. With a search typed, only the recipes it finds."))
  unmute:SetPoint("TOPLEFT", bar, "TOP", gap, 0)
  unmute:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
end

-- The "Only <expansion>" button, full width on its own row. Hidden, its row keeps its height.
local function createOnlyCurrent(column, onClick)
  local bar = Controls.Bar(column, Theme.LAYOUT.BUTTON_HEIGHT)
  local button = Controls.Button(bar, "", 0, onClick)
  button:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  button:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  local tip = Localization.Text("Alerts only for this expansion's recipes: all older ones are muted and your own picks are replaced.")
  Controls.Tip(button, function()
    return button:GetText()
  end, tip)
  return button
end

-- Labels the button for the profession's current line (one lookup), or hides it when none.
local function paintOnlyCurrent(button, line)
  if line == nil then
    button:Hide()
    return
  end
  local name = expansionName(line)
  button.label:SetText(name and Localization.Text("Only %s", name) or Localization.Text("Only current expansion"))
  button:Show()
end

-- The line over an empty list: the search found nothing, the character has no profession, or no
-- recipe was read yet.
local function emptyText(search, prof)
  if search ~= "" then
    return Localization.Text("No recipe matches your search.")
  end
  if prof == nil then
    return Localization.Text("No professions read for this character yet.")
  end
  return Localization.Text("No recipes read yet. Open this profession's window in the game to read them.")
end

-- list: { search, recipes, empty, character, prof, Show }; `character` and `prof` are what Show last got.
function RecipeList.Create(column)
  local list = {}

  local function render()
    local search = list.search.input:GetText()
    local items = recipeItems(list.character, list.prof, search)
    paintOnlyCurrent(list.onlyCurrent, currentLine(list.character, list.prof))
    list.recipes.Render(items, list.showRecipe)
    list.empty:SetText(emptyText(search, list.prof))
    list.empty:SetShown(#items == 0)
  end

  -- One index rebuild when any of the recipes changed, then the list again.
  local function afterMute(changed)
    if changed > 0 then
      Index.RequestRebuild("mute")
    end
    render()
  end

  -- Sets every listed recipe to `muted`.
  local function muteAll(muted)
    local changed = 0
    for _, item in ipairs(recipeItems(list.character, list.prof, list.search.input:GetText())) do
      if (item.recipe.muted == true) ~= muted then
        item.recipe.muted = muted or nil
        changed = changed + 1
      end
    end
    afterMute(changed)
  end

  -- Alerts only for the current line over the profession's whole list, the search ignored; a
  -- recipe without a line is left alone.
  local function onlyCurrent()
    local current, changed = currentLine(list.character, list.prof), 0
    for _, recipe in pairs(list.character and list.character.recipes or {}) do
      local muted = recipe.line ~= current
      if recipe.prof == list.prof and recipe.line and (recipe.muted == true) ~= muted then
        recipe.muted = muted or nil
        changed = changed + 1
      end
    end
    afterMute(changed)
  end

  -- The recipe tooltip for `row`, read at hover time: the row is reused and the character can change.
  local function showTooltip(row)
    RecipeTooltip.Show(row, list.character)
  end

  -- Repaints the listed items in place: the row stays under the pointer until the next refresh.
  local function repaint()
    list.recipes.Render(list.recipes.items, list.showRecipe)
  end

  -- An index rebuild repaints the rows only while the page shows them.
  local function repaintIfShown()
    if list.recipes.frame:IsVisible() then
      repaint()
    end
  end

  local function createRecipeRow(row)
    local size = Theme.LAYOUT.ROW_ICON_SIZE
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(size, size)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = FrameKit.Text(row, Theme.FONTS.body)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", Theme.LAYOUT.PADDING, 0)
    row.mute = RecipeMute.Create(row, function()
      row.item.recipe.muted = not row.item.recipe.muted or nil
      Index.RequestRebuild("mute")
      repaint()
    end)
    -- On a narrow page a long name is cut short of the speaker.
    row.name:SetPoint("RIGHT", row.mute, "LEFT", -Theme.LAYOUT.PADDING, 0)
    row:SetScript("OnEnter", function()
      row.hovered = true
      showTooltip(row)
    end)
    -- The tooltip's own update (GameTooltipTemplate's, every 0.2 s while shown) calls this instead of
    -- rebuilding from the item data, which would drop our lines once an uncached item loads.
    row.UpdateTooltip = showTooltip
    row:SetScript("OnLeave", function()
      row.hovered = nil
      Tooltip.HideIfOwned(row)
    end)
    -- Closing the settings under the cursor hides the row without an OnLeave.
    row:HookScript("OnHide", function()
      row.hovered = nil
    end)
  end

  -- A row the pointer is on repaints its tooltip. The client can hide the tooltip without an
  -- OnLeave (a fade, another owner), so what is shown does not tell whether the row is hovered.
  function list.showRecipe(row, item)
    local muted, greyed = item.recipe.muted == true, RecipeMute.Untracked(item.recipe)
    local dim = muted or greyed
    row.item = item
    row.name:SetText(item.text)
    RecipeRarity.Paint(row.name, item.recipe.item, dim, repaint)
    row.icon:SetTexture(recipeIcon(item))
    row.icon:SetDesaturated(dim)
    row.icon:SetAlpha(dim and Theme.DIM_ALPHA or 1)
    row.mute.recipe = item.recipe
    RecipeMute.Paint(row.mute, muted, greyed)
    if row.hovered then
      showTooltip(row)
    end
  end

  list.search = Controls.Search(
    column,
    Localization.Text("Search recipes"),
    render,
    Localization.Text("Type part of a recipe's name. The list narrows as you type.")
  )
  createMuteAll(column, muteAll)
  list.onlyCurrent = createOnlyCurrent(column, onlyCurrent)
  list.recipes = Controls.List(column, RECIPE_ROWS, createRecipeRow)
  local frame, padding = list.recipes.frame, Theme.LAYOUT.PADDING
  list.empty = FrameKit.Text(frame, Theme.FONTS.body, Theme.COLORS.textSecondary)
  list.empty:SetWordWrap(true)
  list.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
  list.empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padding, -padding)
  -- A mute made elsewhere (the profession window) shows when the index rebuilds; the order stays.
  Index.OnRebuilt(repaintIfShown)

  -- Shows `prof`'s recipes of `character` (a db.characters record, or nil) under the current search.
  function list.Show(character, prof)
    list.character, list.prof = character, prof
    render()
  end
  return list
end

ns.RecipeList = RecipeList
return RecipeList
