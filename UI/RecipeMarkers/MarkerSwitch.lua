local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Index = ns.Index or require("CraftAlert.Model.Index")
local RecipeMute = ns.RecipeMute or require("CraftAlert.UI.Settings.RecipeMute")
local MarkerState = ns.MarkerState or require("CraftAlert.UI.RecipeMarkers.MarkerState")

-- The mute switch the recipe markers put on a Blizzard recipe row (ModernRows on Retail and
-- Forever, ClassicRows on the Classic windows). A click mutes the row's rank chain without
-- selecting the row. Nothing is written on Blizzard's rows: each row's switch lives in `markers`,
-- its chain and shown record on the switch itself.
local MarkerSwitch = {}

local ipairs = ipairs

local SWITCH_SIZE = 14 -- 16 would overlap a fully truncated "[n]" count by 1 px (spec F5)

local markers = {} -- Blizzard row frame -> our switch

function MarkerSwitch.Hide(row)
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
  Index.RequestRebuildSoon("mute")
end

-- The switch on `row`, created on first use, 14 × 14 at the row's right end, or with its right
-- edge on `anchor`'s left when given (a Classic row's skill-up count, R2).
local function switchOf(row, anchor)
  local switch = markers[row]
  if switch == nil then
    switch = RecipeMute.Create(row, onClick)
    switch:SetSize(SWITCH_SIZE, SWITCH_SIZE)
    if anchor then
      switch:ClearAllPoints()
      switch:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    end
    markers[row] = switch
  end
  return switch
end

-- Shows the switch of `row` for the stored rank chain `chain` (lowest rank first) and the record
-- of the rank the row shows, or hides it when the chain is empty. `anchor`: as switchOf.
function MarkerSwitch.Show(row, chain, shown, anchor)
  if MarkerState.Of(chain, shown) == "hidden" then
    MarkerSwitch.Hide(row)
    return
  end
  local switch = switchOf(row, anchor)
  switch.chain, switch.recipe = chain, shown
  paintSwitch(switch)
  switch:Show()
end

ns.MarkerSwitch = MarkerSwitch
return MarkerSwitch
