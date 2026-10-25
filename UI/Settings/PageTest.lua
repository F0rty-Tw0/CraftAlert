local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local CrafterRank = ns.CrafterRank or require("CraftAlert.Model.CrafterRank")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local Controls = ns.SettingsControls or require("CraftAlert.UI.Settings.Controls")

-- Spec §9 Test: a text box → the result and its "why". This page only previews: it runs
-- §6.3 steps 2-5 (Matcher.MatchUngated, sender "Test" on the player's realm, ignore check
-- skipped), creates no lead, sends nothing and counts nothing. `/ca test` is separate: it
-- makes a real test lead through the real path.
local PageTest = { id = "test", title = Localization.Text("Test") }

local concat = table.concat
local tostring = tostring

local function db()
  return _G["CraftAlertDB"]
end

-- What matched: the crafter's recipe name for an item, the profession name otherwise.
local function describe(result, crafter)
  local character = crafter and db().characters[crafter]
  if result.kind == "item" then
    for i = 1, result.entryCount do
      local entry = result.entries[i]
      local recipe = character and entry.character == crafter and character.recipes[entry.recipeKey]
      if recipe then
        return Localization.Text("Item: %s", recipe.name)
      end
    end
    return Localization.Text("Item: %s", tostring(result.group))
  end
  local profession = character and character.professions[result.prof]
  return Localization.Text("Profession: %s", profession and profession.name or tostring(result.prof))
end

local function whyOf(result)
  local parts = {}
  for i = 1, result.whyCount do
    parts[i] = tostring(result.why[i])
  end
  return concat(parts, " + ")
end

-- → the result lines for `text`, read out of the Matcher's reused result at once.
local function run(text)
  local result = Matcher.MatchUngated(text)
  if result == nil then
    return { Localization.Text("No match (stopped at: %s)", tostring(Matcher.lastStop)) }
  end
  local crafter = CrafterRank.Pick(result, PlayerName.TestCustomer(), db(), { skipIgnore = true })
  return {
    describe(result, crafter),
    Localization.Text("Why: %s", whyOf(result)),
    Localization.Text("Crafter: %s", crafter or Localization.Text("none of your enabled characters")),
  }
end

function PageTest.Create(parent)
  local column = Controls.Column(parent, Theme.LAYOUT.PAGE_PADDING)
  Controls.Section(column, Localization.Text("Try a trade chat line"))
  local output
  local input = Controls.Input(column, Localization.Text("Test a line"), function(text)
    output:SetText(concat(run(text), "\n"))
  end)
  output = Controls.Note(column)
  local function refresh()
    input.Set("")
    output:SetText(Localization.Text("Type a request like: LF plate belt"))
  end
  return { Refresh = refresh }
end

ns.PageTest = PageTest
return PageTest
