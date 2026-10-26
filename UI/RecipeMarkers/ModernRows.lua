local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local Index = ns.Index or require("CraftAlert.Model.Index")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")
local RecipeMute = ns.RecipeMute or require("CraftAlert.UI.Settings.RecipeMute")
local MarkerState = ns.MarkerState or require("CraftAlert.UI.RecipeMarkers.MarkerState")

-- Recipe markers on Retail and Forever (spec 2026-10-26-recipe-markers §6.2-6.5): the Settings
-- mute switch on every learned, stored recipe row of Blizzard's profession window. A click mutes
-- the recipe's rank chain without selecting the row. Nothing is written on Blizzard's rows,
-- nodes or recipe infos: each row's switch lives in `markers`, its state on the switch itself.
local ModernRows = {}

local ipairs = ipairs
local type = type

local ADDON = "Blizzard_Professions"
local LOADED_EVENT = "ADDON_LOADED"
local SWITCH_SIZE = 14 -- 16 would overlap a fully truncated "[n]" count by 1 px (spec F5)

---@type table
local db = nil -- set by Install; nil means every call is a no-op
local professionsLoaded = false
local hooked = false
---@type table
local scrollBox = nil
local markers = {} -- Blizzard row frame -> our switch

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

local function hide(row)
  local switch = markers[row]
  if switch then
    switch:Hide()
  end
end

-- Paints a switch from its own chain: crossed out when every rank is muted, greyed when untracked.
local function paintSwitch(switch)
  local state = MarkerState.Of(switch.chain, switch.recipe)
  RecipeMute.Paint(switch, state == "muted", state == "untracked")
end

-- A click mutes every stored rank of the chain, or unmutes them all when all are muted (D5), then
-- repaints and asks for the rebuild that repaints the other rows and an open Settings list.
local function onClick(switch)
  local target = MarkerState.Of(switch.chain, switch.recipe) ~= "muted"
  for _, record in ipairs(switch.chain) do
    record.muted = target or nil
  end
  paintSwitch(switch)
  Index.RequestRebuild("mute")
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
  return chain, recipes[shownInfo.recipeID] or chain[#chain]
end

-- The switch on `row`, created on first use, 14 × 14 at the row's right end.
local function switchOf(row)
  local switch = markers[row]
  if switch == nil then
    switch = RecipeMute.Create(row, onClick)
    switch:SetSize(SWITCH_SIZE, SWITCH_SIZE)
    markers[row] = switch
  end
  return switch
end

-- Shows, paints or hides the switch of one row for the recipe its node holds (spec §6.3).
local function paint(row, node)
  local data = node and node:GetData()
  local recipeInfo = type(data) == "table" and data.recipeInfo or nil
  if recipeInfo == nil then
    return hide(row)
  end
  local highest = professionsHelper("GetHighestLearnedRecipe")
  local shownInfo = highest and highest(recipeInfo) or recipeInfo
  local character = db.characters[PlayerName.Own()]
  if gated(shownInfo) or character == nil or character.recipes == nil then
    return hide(row)
  end
  local chain, shown = chainOf(recipeInfo, shownInfo, character.recipes)
  if MarkerState.Of(chain, shown) == "hidden" then
    return hide(row)
  end
  local switch = switchOf(row)
  switch.chain, switch.recipe = chain, shown
  paintSwitch(switch)
  switch:Show()
end

-- ScrollUtil's OnInitializedFrame callback: (owner, row, node).
local function onInitialized(_, row, node)
  paint(row, node)
end

local function walk()
  scrollBox:ForEachFrame(paint)
end

-- Registers the row callback once, while the setting is on and the client has the list, then
-- paints the rows already there. We walk them ourselves rather than through `iterateExisting`.
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
