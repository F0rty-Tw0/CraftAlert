local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")
local MarkerSwitch = ns.MarkerSwitch or require("CraftAlert.UI.RecipeMarkers.MarkerSwitch")

-- Recipe markers on Retail and Forever (spec 2026-10-26-recipe-markers §6.2-6.5): the Settings
-- mute switch on every learned, stored recipe row of Blizzard's profession window. A click mutes
-- the recipe's rank chain without selecting the row (MarkerSwitch). Nothing is written on
-- Blizzard's rows, nodes or recipe infos.
local ModernRows = {}

local ipairs = ipairs
local type = type

local ADDON = "Blizzard_Professions"
local LOADED_EVENT = "ADDON_LOADED"

---@type table
local db = nil -- set by Install; nil means every call is a no-op
local professionsLoaded = false
local hooked = false
---@type table
local scrollBox = nil

-- `_G.Professions[name]` when the client has it.
local function professionsHelper(name)
  local professions = _G["Professions"]
  if type(professions) ~= "table" or type(professions[name]) ~= "function" then
    return nil
  end
  return professions[name]
end

-- ProfessionsFrame.CraftingPage.RecipeList.ScrollBox, nil when any step is missing.
local function findScrollBox()
  local node = _G["ProfessionsFrame"]
  for _, key in ipairs({ "CraftingPage", "RecipeList", "ScrollBox" }) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
  end
  return type(node) == "table" and node or nil
end

-- True when a gate hides the row's switch: the setting, an instance, another player's or a special
-- list, or a shown rank that is not learned or is disabled (Blizzard's lock icon sits there).
local function gated(shownInfo)
  return not db.settings.recipeMarkers
    or FlavorCompat.InInstance()
    or ModernReader.IsBlocked()
    or shownInfo.learned ~= true
    or shownInfo.disabled == true
end

-- Our stored records of the row's rank chain, lowest rank first, and the record of the shown rank
-- (else the chain's last). Without the rank helpers the chain is the shown recipe's record alone.
local function chainOf(recipeInfo, shownInfo, recipes)
  local chain = {}
  local enumerate = professionsHelper("EnumerateRecipes")
  if enumerate then
    for _, rankInfo in enumerate(recipeInfo) do
      local record = recipes[rankInfo.recipeID]
      if record then
        chain[#chain + 1] = record
      end
    end
  elseif recipes[shownInfo.recipeID] then
    chain[1] = recipes[shownInfo.recipeID]
  end
  local shown = recipes[shownInfo.recipeID] or chain[#chain]
  return chain, shown
end

-- Shows, paints or hides the switch of one row for the recipe its node holds (spec §6.3).
local function paint(row, node)
  local data = node and node:GetData()
  local recipeInfo = type(data) == "table" and data.recipeInfo or nil
  if recipeInfo == nil then
    MarkerSwitch.Hide(row)
    return
  end
  local shownInfo = recipeInfo
  local highest = professionsHelper("GetHighestLearnedRecipe")
  if highest then
    shownInfo = highest(recipeInfo) or recipeInfo
  end
  local character = db.characters[PlayerName.Own()]
  if gated(shownInfo) or character == nil or character.recipes == nil then
    MarkerSwitch.Hide(row)
    return
  end
  local chain, shown = chainOf(recipeInfo, shownInfo, character.recipes)
  MarkerSwitch.Show(row, chain, shown)
end

-- ScrollUtil's OnInitializedFrame callback: (owner, row, node).
local function onInitialized(_, row, node)
  paint(row, node)
end

-- ForEachFrame stops at the first truthy return, so paint's return must not reach it.
local function walk()
  scrollBox:ForEachFrame(function(row, node)
    paint(row, node)
  end)
end

-- Registers the row callback once, while the setting is on and the client has the list, then
-- paints the rows already there. `iterateExisting` is false: ScrollUtil would pass ForEachFrame our
-- callback, which gets (frame, elementData) there but (owner, frame, elementData) from the
-- initialized-frame hook; `walk` is the one adapter.
local function hook()
  if hooked or not db.settings.recipeMarkers then
    return
  end
  local box = findScrollBox()
  local scrollUtil = _G["ScrollUtil"]
  if box == nil or type(scrollUtil) ~= "table" or type(scrollUtil.AddInitializedFrameCallback) ~= "function" then
    return
  end
  scrollUtil.AddInitializedFrameCallback(box, onInitialized, ModernRows, false)
  hooked, scrollBox = true, box
  walk()
end

local function onAddonLoaded(name)
  if name ~= ADDON then
    return
  end
  EventRouter.Off(LOADED_EVENT, onAddonLoaded)
  professionsLoaded = true
  hook()
end

-- At PLAYER_LOGIN (the own character key is needed to paint): hooks now when Blizzard_Professions
-- is loaded, else when it loads.
function ModernRows.Install(accountDb)
  db = accountDb
  if FlavorCompat.IsAddOnLoaded(ADDON) then
    professionsLoaded = true
    hook()
  else
    EventRouter.On(LOADED_EVENT, onAddonLoaded)
  end
end

-- Repaints every row, hooking first when the setting was turned on after the addon loaded. On
-- rebuilds, gate changes and the setting toggle; a no-op before Install.
function ModernRows.Refresh()
  if db == nil then
    return
  end
  if hooked then
    walk()
  elseif professionsLoaded then
    hook()
  end
end

ns.ModernRows = ModernRows
return ModernRows
