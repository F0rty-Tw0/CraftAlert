local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Defaults = ns.Defaults or require("CraftAlert.Persistence.Defaults")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 Greetings / §7.4: the four templates, one note per profession, and a live preview
-- that runs Greeting.Build on a sample lead for each template. Greetings are built at click
-- time, so nothing is rebuilt here; the preview repaints after each change.
local PageGreetings = { id = "greetings", title = Localization.Text("Greetings") }

local find = string.find

local TEMPLATES = {
  { key = "item", label = "Item", kind = "item", own = true },
  { key = "altItem", label = "Alt item", kind = "item", own = false },
  { key = "profession", label = "Profession", kind = "profession", own = true },
  { key = "altProfession", label = "Alt profession", kind = "profession", own = false },
}

local function db()
  return _G["CraftAlertDB"]
end

-- Every profession some character has, { { value = key, text = name }, ... } by name.
local function professionOptions()
  local seen, options = {}, {}
  for _, character in pairs(db().characters) do
    for key, profession in pairs(character.professions or {}) do
      if not seen[key] then
        seen[key] = true
        options[#options + 1] = { value = key, text = profession.name ~= "" and profession.name or tostring(key) }
      end
    end
  end
  table.sort(options, function(a, b)
    return a.text < b.text
  end)
  return options
end

local function textOf(options, value)
  for _, option in ipairs(options) do
    if option.value == value then
      return option.text
    end
  end
  return nil
end

-- A lead as Leads.OnMatch makes it, for the player (own) or an alt on the player's realm.
local function sampleLead(template, prof, profName)
  local own = PlayerName.Own() or "Me-Realm"
  local realm = PlayerName.RealmOf(own) or "Realm"
  return {
    customer = "Customer-" .. realm,
    crafter = template.own and own or ("Alt-" .. realm),
    kind = template.kind,
    prof = prof,
    profName = profName or Localization.Text("Blacksmithing"),
    recipeName = template.kind == "item" and Localization.Text("Sample Item") or nil,
  }
end

local function createPreview(column)
  Controls.Section(column, Localization.Text("Preview"))
  local lines = {}
  for i = 1, #TEMPLATES do
    lines[i] = Controls.Note(column, Theme.FONTS.body)
  end
  return lines
end

-- The note box edits the note of the profession the choice shows.
local function createNotes(column, state, repaint)
  Controls.Section(column, Localization.Text("Profession note (added after the greeting)"))
  state.profession = Controls.Choice(column, Localization.Text("Note for"), {}, repaint)
  state.note = Controls.Input(column, Localization.Text("Note"), function(text)
    local prof = state.profession.Value()
    if prof ~= nil then
      db().settings.notes[prof] = text ~= "" and text or nil
    end
    repaint()
  end)
end

function PageGreetings.Create(parent)
  local column = Controls.Column(parent)
  local add, refresh = Controls.Refresher()
  local state = { options = {} }
  local lines
  local function repaint()
    local settings = db().settings
    local prof = state.profession.Value()
    state.note.Set(prof ~= nil and settings.notes[prof] or "")
    for i, template in ipairs(TEMPLATES) do
      local greeting = Greeting.Build(sampleLead(template, prof, textOf(state.options, prof)), settings)
      lines[i]:SetText(Localization.Text("%s: %s", template.label, greeting))
    end
  end
  Controls.Section(column, Localization.Text("Templates ({item} {crafter} {profession} {customer})"))
  for _, template in ipairs(TEMPLATES) do
    local input
    -- An emptied template would send an empty whisper: it falls back to the default.
    input = Controls.Input(column, Localization.Text(template.label), function(text)
      if not find(text, "%S") then
        text = Defaults.Settings().templates[template.key]
        input.Set(text)
      end
      db().settings.templates[template.key] = text
      repaint()
    end)
    add(function()
      input.Set(db().settings.templates[template.key])
    end)
  end
  createNotes(column, state, repaint)
  lines = createPreview(column)
  add(function()
    state.options = professionOptions()
    state.profession.SetOptions(state.options, state.profession.Value())
    repaint()
  end)
  return { Refresh = refresh }
end

ns.PageGreetings = PageGreetings
return PageGreetings
