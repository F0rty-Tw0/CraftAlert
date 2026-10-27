local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local ExportString = ns.ExportString or require("CraftAlert.Persistence.ExportString")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")
local CraftScanPrompt = ns.CraftScanPrompt or require("CraftAlert.UI.CraftScanPrompt")

-- Spec §9 Linked accounts, §10.1: this account's export string to copy, a box to paste another
-- account's string into, and the characters imported so far with their import date. On Retail a
-- button imports CraftScan's data (§10.2), enabled while CraftScan's saved data is loaded. The
-- jobs run sliced (ExportString, CraftScanPrompt.Import) and rebuild the index when they end. No box caps
-- its letters: a large account's string is about 100 KB.
local PageLinked = { id = "linked", title = Localization.Text("Linked accounts") }

local concat = table.concat
local sort = table.sort

local IMPORT_WIDTH = 100
local CRAFTSCAN_WIDTH = 180

local function db()
  return _G["CraftAlertDB"]
end

-- An InputBoxTemplate box on a row of its own, inset as Controls.Input's box; `label` names the
-- row (`row.settingsLabel`, as a control's row) and `row.input` is the box.
local function textBox(column, label)
  local layout = Theme.LAYOUT
  local row = Controls.Bar(column, layout.INPUT_HEIGHT)
  row.settingsLabel = label
  local box = _G["CreateFrame"]("EditBox", nil, row, "InputBoxTemplate")
  box:SetPoint("TOPLEFT", row, "TOPLEFT", 5, 0)
  box:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  box:SetAutoFocus(false)
  box:SetFontObject(Theme.FONTS.setting)
  box:SetTextInsets(layout.INPUT_INSET.left, layout.INPUT_INSET.right, 0, 0)
  row.input = box
  return box
end

-- "Name-Realm, imported <date>" per imported character, by key.
local function importedText()
  local keys = {}
  for key, character in pairs(db().characters) do
    if character.source == "import" then
      keys[#keys + 1] = key
    end
  end
  if #keys == 0 then
    return Localization.Text("No characters imported yet.")
  end
  sort(keys)
  local lines = {}
  for i, key in ipairs(keys) do
    local at = db().characters[key].importedAt
    local day = type(at) == "number" and _G["date"]("%Y-%m-%d", at) or "?"
    lines[i] = Localization.Text("%s, imported %s", key, day)
  end
  return concat(lines, "\n")
end

-- Read-only: a typed change puts the string back; the focus selects all of it for Ctrl+C.
local function createExport(column, page)
  Controls.Section(column, Localization.Text("Export this account"))
  local hint = Controls.Note(column)
  hint:SetText(Localization.Text("Copy this string and paste it on the Linked accounts page of your other account."))
  local box = textBox(column, Localization.Text("Export string"))
  local shown = ""
  local function show(text)
    shown = text
    box:SetText(text)
  end
  box:SetScript("OnTextChanged", function(_, userInput)
    if userInput then
      box:SetText(shown)
      box:HighlightText()
    end
  end)
  box:HookScript("OnEditFocusGained", function()
    box:HighlightText()
  end)
  page.exportBox = box
  -- Started before the placeholder shows: starting cancels a running export, which clears the box.
  function page.Export()
    ExportString.StartExport(db(), show, function()
      show("")
    end)
    show(Localization.Text("Making the string..."))
  end
end

local function createImport(column, page)
  Controls.Section(column, Localization.Text("Import another account"))
  local box = textBox(column, Localization.Text("Import string"))
  local result
  local button
  button = Controls.Button(column.parent, Localization.Text("Import"), IMPORT_WIDTH, function()
    button:Disable()
    result:SetText(Localization.Text("Importing..."))
    ExportString.StartImport(db(), box:GetText(), function(counts, err)
      button:Enable()
      if counts == nil then
        result:SetText(err)
        return
      end
      box:SetText("")
      result:SetText(Localization.Text("Imported %d characters, %d recipes (%d skipped).", counts.characters, counts.recipes, counts.skipped))
      page.ShowImported()
    end, function()
      button:Enable()
      result:SetText("")
    end)
  end)
  Controls.Place(column, button)
  result = Controls.Note(column)
  page.importBox, page.importButton, page.importResult = box, button, result
  Controls.Section(column, Localization.Text("Imported characters"))
  local list = Controls.Note(column)
  function page.ShowImported()
    list:SetText(importedText())
  end
end

-- CraftScan (Retail only): one import of this account's characters, recipes and greetings.
local function createCraftScan(column, page)
  Controls.Section(column, Localization.Text("CraftScan"))
  local result
  local button
  button = Controls.Button(column.parent, Localization.Text("Import from CraftScan"), CRAFTSCAN_WIDTH, function()
    if type(_G["CraftScan_DB"]) ~= "table" then
      return
    end
    button:Disable()
    result:SetText(Localization.Text("Importing..."))
    CraftScanPrompt.Import(db(), function(line)
      button:Enable()
      result:SetText(line)
      page.ShowImported()
    end, function()
      button:Enable()
      result:SetText("")
    end)
  end)
  Controls.Place(column, button)
  result = Controls.Note(column)
  page.craftScanButton, page.craftScanResult = button, result
  function page.ShowCraftScan()
    local loaded = type(_G["CraftScan_DB"]) == "table"
    button:SetEnabled(loaded and not Slicer.IsRunning("craftscan"))
    result:SetText(loaded and "" or Localization.Text("CraftScan's data is not loaded: enable CraftScan to import it."))
  end
end

function PageLinked.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  local page = {}
  createExport(column, page)
  createImport(column, page)
  if FlavorCompat.isRetail then
    createCraftScan(column, page)
  end
  function page.Refresh()
    page.Export()
    page.importResult:SetText("")
    page.importButton:SetEnabled(not Slicer.IsRunning("import"))
    page.ShowImported()
    if page.ShowCraftScan then
      page.ShowCraftScan()
    end
  end
  return page
end

ns.PageLinked = PageLinked
return PageLinked
