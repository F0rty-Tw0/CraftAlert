local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local RealmTag = ns.RealmTag or require("CraftAlert.Model.RealmTag")
local MainCrafter = ns.MainCrafter or require("CraftAlert.Model.MainCrafter")
local ProfessionList = ns.ProfessionList or require("CraftAlert.Professions.ProfessionList")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")
local RecipeList = ns.RecipeList or require("CraftAlert.UI.Settings.RecipeList")

-- Spec §9 Crafters: one character at a time (current, same-account, imported) with enable,
-- remove (asks for a second click) and, per profession, the main crafter flag (stored as
-- `primary`) and the recipe list (RecipeList).
-- Enable, remove and mute rebuild the index (§6.2); the flag is read when a lead
-- picks its crafter (§6.3 step 5), so it rebuilds nothing.
local PageCrafters = { id = "crafters", title = Localization.Text("Crafters") }

local function db()
  return _G["CraftAlertDB"]
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
  table.sort(options, RecipeList.ByText)
  return options
end

local function shownCharacter(page)
  return db().characters[page.character.Value()]
end

-- page: { character, enabled, remove, profession, primary (the main crafter toggle), list, ... }
local function createCharacterRows(column, page)
  Controls.Section(column, Localization.Text("This character"))
  page.character = Controls.Choice(column, Localization.Text("Character"), {}, function()
    page.ShowCharacter()
  end, Localization.Text("Pick whose professions and recipes this page shows."))
  page.enabled = Controls.Toggle(column, Localization.Text("Listen for this character"), function(on)
    local character = shownCharacter(page)
    if character then
      character.enabled = on
      Index.RequestRebuild("crafter")
    end
  end, Localization.Text("Alerts for this character's recipes. Off, its recipes are left out of matching."))
  local removeTip = Localization.Text(
    "Deletes this character's saved professions and recipes. It asks for a second click. Your logged-in character comes back empty until you open a profession window."
  )
  page.remove = Controls.Button(column.parent, Localization.Text("Remove character"), Theme.LAYOUT.BUTTON_WIDTH.L, function()
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
  end, removeTip)
  Controls.Place(column, page.remove)
end

local function createProfessionRows(column, page)
  Controls.Section(column, Localization.Text("Recipes"))
  page.profession = Controls.Choice(column, Localization.Text("Profession"), {}, function()
    page.ShowProfession()
  end)
  page.primary = Controls.Toggle(
    column,
    Localization.Text("Main crafter for this profession"),
    function(on)
      if page.profession.Value() ~= nil then
        MainCrafter.Set(db(), page.character.Value(), page.profession.Value(), on)
      end
    end,
    Localization.Text(
      "When several of your characters can craft a request, this one is chosen first and gets the greeting. One main crafter per profession."
    )
  )
  page.list = RecipeList.Create(column)
end

function PageCrafters.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local page = {}
  createCharacterRows(column, page)
  createProfessionRows(column, page)
  function page.ShowProfession()
    local profession = (shownCharacter(page) or { professions = {} }).professions[page.profession.Value()]
    page.primary.Set(profession ~= nil and profession.primary)
    page.list.search.Set("")
    page.list.Show(shownCharacter(page), page.profession.Value())
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
