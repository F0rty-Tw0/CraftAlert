local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local MainCrafter = ns.MainCrafter or require("CraftAlert.Model.MainCrafter")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Main-crafter spec §3: the menu a lead card's Crafters zone opens (UI/CardTips.lua). Blizzard's
-- context menu: a title, one radio per enabled character that knows the lead's profession, then
-- None. Choosing writes the flag (MainCrafter) and re-picks this lead only (Leads.Repick).
local MainCrafterMenu = {}

local pairs = pairs
local sort = table.sort

local function db()
  return _G["CraftAlertDB"]
end

-- The keys of the enabled characters that know `prof`, by the name the greeting uses, then key.
local function craftersOf(prof)
  local keys = {}
  for key, character in pairs(db().characters) do
    if character.enabled ~= false and character.professions[prof] ~= nil then
      keys[#keys + 1] = key
    end
  end
  sort(keys, function(a, b)
    local nameA, nameB = Greeting.CrafterName(a), Greeting.CrafterName(b)
    if nameA ~= nameB then
      return nameA < nameB
    end
    return a < b
  end)
  return keys
end

local function nameOf(key)
  local name = Greeting.CrafterName(key)
  local color = FrameKit.ClassColor(db().characters[key].class)
  if color then
    return FrameKit.ColorCode(name, color.r, color.g, color.b)
  end
  return name
end

function MainCrafterMenu.CanOpen(lead)
  return lead.prof ~= nil and #craftersOf(lead.prof) > 0
end

-- `owner` anchors the menu. A radio's data is its character key, false for None.
function MainCrafterMenu.Open(owner, lead)
  local menuUtil = _G["MenuUtil"]
  if menuUtil == nil then
    return
  end
  local prof = lead.prof
  local function isSelected(key)
    return (MainCrafter.Of(db(), prof) or false) == key
  end
  local function setSelected(key)
    if isSelected(key) then
      return
    end
    if key then
      MainCrafter.Set(db(), key, prof, true)
    else
      MainCrafter.Clear(db(), prof)
    end
    Leads.Repick(lead.id)
  end
  menuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(Localization.Text("Main crafter for %s", lead.profName or ""))
    for _, key in ipairs(craftersOf(prof)) do
      root:CreateRadio(nameOf(key), isSelected, setSelected, key)
    end
    root:CreateRadio(Localization.Text("None"), isSelected, setSelected, false)
  end)
end

ns.MainCrafterMenu = MainCrafterMenu
return MainCrafterMenu
