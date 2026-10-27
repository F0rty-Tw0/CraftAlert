local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local ClassicReader = ns.ClassicReader or require("CraftAlert.Professions.ClassicReader")

-- Spec §5.2 row 3: Enchanting's CraftFrame on Era and TBC, read as Slicer job "craftRead" (the
-- TradeSkill window's "read" can run beside it). The same frame hosts Hunter Beast Training,
-- which ClassicReader skips as a profession the character does not store.
local CraftReader = {}

local CRAFT = {
  show = "CRAFT_SHOW",
  update = "CRAFT_UPDATE",
  close = "CRAFT_CLOSE",
  job = "craftRead",
  line = "GetCraftDisplaySkillLine",
  count = "GetNumCrafts",
  row = function(index)
    local name, _, kind = _G["GetCraftInfo"](index)
    return name, kind, _G["GetCraftItemLink"](index)
  end,
}

-- The last Craft window read, for the sim: { prof, stored, pendingBind, ms, steps }.
CraftReader.lastRead = nil

function CraftReader.Install(accountDb)
  if not FlavorCompat.hasCraftFrame then
    return
  end
  ClassicReader.Watch(CraftReader, CRAFT, accountDb)
end

ns.CraftReader = CraftReader
return CraftReader
