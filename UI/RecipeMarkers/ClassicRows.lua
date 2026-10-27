local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local ClassicReader = ns.ClassicReader or require("CraftAlert.Professions.ClassicReader")
local MarkerSwitch = ns.MarkerSwitch or require("CraftAlert.UI.RecipeMarkers.MarkerSwitch")

-- Recipe markers on the Classic flavors (plan 03-markers, Revision 2026-10-27): the Settings mute
-- switch on every stored recipe row of the TradeSkill window and, on Era and TBC, Enchanting's
-- Craft window. Blizzard calls the window's update function by name on every list change and
-- scroll; our hooksecurefunc post-hook walks the row buttons it just filled. A row's record is our
-- record of its lowercase name, only when stored for the window's profession. Nothing is written
-- on Blizzard's rows (MarkerSwitch), and Refresh walks the rows itself: it never calls Blizzard's
-- update (spec §4.3 rule 3).
local ClassicRows = {}

local ipairs = ipairs
local lower = string.lower
local type = type

local LOADED_EVENT = "ADDON_LOADED"
local SKIPPED_KINDS = { header = true, subheader = true }

-- A window's addon, update function and row buttons (`prefix`1..`_G[displayed]`), and its calls
-- as ClassicReader names them. info(index) → name, kind of one list row.
local TRADE_SKILL = {
  addon = "Blizzard_TradeSkillUI",
  update = "TradeSkillFrame_Update",
  prefix = "TradeSkillSkill",
  displayed = "TRADE_SKILLS_DISPLAYED",
  line = "GetTradeSkillLine",
  linked = "IsTradeSkillLinked",
  info = function(index)
    local name, kind = _G["GetTradeSkillInfo"](index)
    return name, kind
  end,
}

local CRAFT = {
  addon = "Blizzard_CraftUI",
  update = "CraftFrame_Update",
  prefix = "Craft",
  displayed = "CRAFTS_DISPLAYED",
  line = "GetCraftDisplaySkillLine",
  info = function(index)
    local name, _, kind = _G["GetCraftInfo"](index)
    return name, kind
  end,
}

---@type table
local db = nil -- set by Install; nil means every call is a no-op
local sources = {} -- the windows this flavor has
local loaded, hooked = {}, {} -- by source

-- The profession whose records the window's rows show, or nil when a gate hides every switch:
-- the setting, an instance, another player's list, or a window not showing a profession the
-- character stores (Beast Training, Cooking, closed).
local function shownProfession(source)
  if not db.settings.recipeMarkers or FlavorCompat.InInstance() then
    return nil
  end
  return ClassicReader.WindowProfession(source, db)
end

-- Our record of list row `index`, stored for `profession`; nil for a header or subheader.
local function recordOf(source, index, recipes, profession)
  local name, kind = source.info(index)
  if type(name) ~= "string" or SKIPPED_KINDS[kind] then
    return nil
  end
  local record = recipes[lower(name)]
  if record == nil or record.prof ~= profession then
    return nil
  end
  return record
end

-- Shows, paints or hides the switch of each row button. A hidden button is past the end of the
-- list and keeps an old ID, so it gets none. On MoP the switch sits left of the row's skill-up
-- count (R2); Wrath and Cata rows have no such frame, so it sits at the row's right end.
local function walk(source)
  local profession = shownProfession(source)
  local character = profession and db.characters[PlayerName.Own()]
  local recipes = character and character.recipes
  local displayed = _G[source.displayed]
  for i = 1, type(displayed) == "number" and displayed or 0 do
    local rowName = source.prefix .. i
    local row = _G[rowName]
    if row == nil then
      return
    end
    local record = recipes and row:IsShown() and recordOf(source, row:GetID(), recipes, profession)
    if record then
      MarkerSwitch.Show(row, { record }, record, _G[rowName .. "NumSkillUps"])
    else
      MarkerSwitch.Hide(row)
    end
  end
end

-- Hooks the window's update once, while the setting is on and the client has it, then paints the
-- rows already there.
local function hook(source)
  if hooked[source] or not db.settings.recipeMarkers or type(_G[source.update]) ~= "function" then
    return
  end
  _G["hooksecurefunc"](source.update, function()
    walk(source)
  end)
  hooked[source] = true
  walk(source)
end

-- Hooks now when the window's addon is loaded, else when it loads.
local function watch(source)
  sources[#sources + 1] = source
  if FlavorCompat.IsAddOnLoaded(source.addon) then
    loaded[source] = true
    hook(source)
    return
  end
  local function onAddonLoaded(name)
    if name ~= source.addon then
      return
    end
    EventRouter.Off(LOADED_EVENT, onAddonLoaded)
    loaded[source] = true
    hook(source)
  end
  EventRouter.On(LOADED_EVENT, onAddonLoaded)
end

-- At PLAYER_LOGIN (the own character key is needed to paint): the TradeSkill window, and the Craft
-- window where the flavor has it.
function ClassicRows.Install(accountDb)
  db = accountDb
  watch(TRADE_SKILL)
  if FlavorCompat.hasCraftFrame then
    watch(CRAFT)
  end
end

-- Repaints every row, hooking first when the setting was turned on after a window's addon loaded.
-- On rebuilds, gate changes and the setting toggle; a no-op before Install.
function ClassicRows.Refresh()
  if db == nil then
    return
  end
  for _, source in ipairs(sources) do
    if hooked[source] then
      walk(source)
    elseif loaded[source] then
      hook(source)
    end
  end
end

ns.ClassicRows = ClassicRows
return ClassicRows
