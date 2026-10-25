local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local MainCrafter = ns.MainCrafter or require("CraftAlert.Model.MainCrafter")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Main-crafter spec §3: the menu the details pane's Crafters zone opens (UI/LeadDetails.lua). Blizzard's
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
  local color = FrameKit.ClassColor(db().characters[key].class)
  return FrameKit.ClassCode(Greeting.CrafterName(key), color)
end

-- Whether a click can open the menu: Blizzard's menu API is there and an enabled character knows the
-- lead's profession. Asked on every hover, so it stops at the first one and builds no list.
function MainCrafterMenu.CanOpen(lead)
  local prof = lead.prof
  if prof == nil or _G["MenuUtil"] == nil then
    return false
  end
  for _, character in pairs(db().characters) do
    if character.enabled ~= false and character.professions[prof] ~= nil then
      return true
    end
  end
  return false
end

-- Whether a character other than `key` carries the profession's flag; old data can flag several.
local function flaggedBesides(key, prof)
  for other, character in pairs(db().characters) do
    local profession = character.professions[prof]
    if other ~= key and profession and profession.primary == true then
      return true
    end
  end
  return false
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
    if isSelected(key) and not flaggedBesides(key, prof) then
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
