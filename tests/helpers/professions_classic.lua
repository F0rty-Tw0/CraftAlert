-- Classic profession API stubs (Era to MoP), shared by the Classic tests and tools/sim.lua.
--   local state = ProfessionsClassic.install({ skillLines = { { name = "Professions", header = true }, { name = "Blacksmithing" } } })
--   state.skillLines[1].collapsed = true   -- the player folded the header
-- state.skillLines: GetNumSkillLines/GetSkillLineInfo rows (Era, TBC, Wrath), each
-- { name, header, collapsed }. A collapsed header reports isExpanded false; the lines the client
-- would hide under it are the test's to leave out.
-- state.slots: when set, GetProfessions/GetProfessionInfo as on Cata and MoP (ProfessionsRetail's
-- slot shape) in place of the skill lines.
-- state.tradeSkill: the open TradeSkill window, { line = "Blacksmithing", rows = {...}, linked };
-- state.tradeSkill.open = false closes it (GetTradeSkillLine answers "UNKNOWN").
-- state.craft: the open CraftFrame window (Era, TBC), { line = "Enchanting", rows = {...} }. Set
-- it before loading FlavorCompat: hasCraftFrame looks for GetCraftDisplaySkillLine at load.
-- A row: { name, kind = "header" | "subheader" | "optimal" (default), item = itemID, link }; the
-- item link is built from `item` unless `link` gives one (an enchant's |Henchant: link). An index
-- past the list (a row button's stale or unset ID) has no info, as in the client.
-- state.items, bind, cached, requests, autoCache: C_Item data as in ProfessionsRetail.installItems.
--   local ns, db, run = ProfessionsClassic.login("tbc", { craft = { line = "Enchanting", rows = ProfessionsClassic.shapeRows() } })
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local ProfessionsClassic = {}

local function installSkillLines(state)
  Wow.stub("GetNumSkillLines", function()
    return #state.skillLines
  end)
  Wow.stub("GetSkillLineInfo", function(index)
    local line = state.skillLines[index]
    if line == nil then
      return nil
    end
    local header = line.header == true
    return line.name, header, header and not line.collapsed, 1, 0, 0, 300
  end)
end

local function rowLink(row)
  if row.link then
    return row.link
  end
  return row.item and ("|cffffffff|Hitem:" .. row.item .. "::::::::20:::::|h[" .. row.name .. "]|h|r") or nil
end

local function windowLine(window)
  if window.open == false then
    return "UNKNOWN", 0, 0
  end
  return window.line, 1, 300
end

local function installTradeSkill(window)
  window.rows = window.rows or {}
  Wow.stub("GetTradeSkillLine", function()
    return windowLine(window)
  end)
  Wow.stub("GetNumTradeSkills", function()
    return #window.rows
  end)
  Wow.stub("GetTradeSkillInfo", function(index)
    local row = window.rows[index]
    if row == nil then
      return nil
    end
    local kind = row.kind or "optimal"
    return row.name, kind, 0, kind == "header"
  end)
  Wow.stub("GetTradeSkillItemLink", function(index)
    return rowLink(window.rows[index])
  end)
  Wow.stub("IsTradeSkillLinked", function()
    return window.linked == true
  end)
end

local function installCraft(window)
  window.rows = window.rows or {}
  Wow.stub("GetCraftDisplaySkillLine", function()
    return windowLine(window)
  end)
  Wow.stub("GetNumCrafts", function()
    return #window.rows
  end)
  Wow.stub("GetCraftInfo", function(index)
    local row = window.rows[index]
    if row == nil then
      return nil
    end
    local kind = row.kind or "optimal"
    return row.name, "", kind, 0, kind == "header", 0, 1
  end)
  Wow.stub("GetCraftItemLink", function(index)
    return rowLink(window.rows[index])
  end)
end

-- One Enchanting list both windows show (§13 "Readers": identical stored shape), and what a full
-- read of it stores.
function ProfessionsClassic.shapeRows()
  return {
    { name = "Bracer", kind = "header" },
    { name = "Health", kind = "subheader" },
    { name = "Enchant Bracer - Minor Health", link = "|cffffd000|Henchant:7418|h[Enchant Bracer - Minor Health]|h|r" },
    { name = "Lesser Magic Wand", item = 11287 },
    { name = "Runed Copper Rod", item = 6218, kind = "trivial" },
  }
end

function ProfessionsClassic.shapeStored()
  return {
    ["enchant bracer - minor health"] = { name = "Enchant Bracer - Minor Health", prof = "enchanting" },
    ["lesser magic wand"] = { item = 11287, name = "Lesser Magic Wand", prof = "enchanting" },
    ["runed copper rod"] = { item = 6218, name = "Runed Copper Rod", prof = "enchanting" },
  }
end

function ProfessionsClassic.install(state)
  state = state or {}
  state.skillLines = state.skillLines or {}
  if state.slots then
    ProfessionsRetail.installSlots(state)
  else
    installSkillLines(state)
  end
  if state.tradeSkill then
    installTradeSkill(state.tradeSkill)
  end
  if state.craft then
    installCraft(state.craft)
  end
  ProfessionsRetail.installItems(state)
  return state
end

-- Tests only: "Me-Realm" logged in with Blacksmithing and Enchanting on the skill lines (unless
-- `state` lists others), the stubs of `state` installed, then the Classic readers loaded fresh and
-- installed. → ns (Fixture's modules plus ProfessionList, BindLookup, ClassicReader, CraftReader),
-- the account db, run = { builds, reasons } of the index rebuilds since.
function ProfessionsClassic.login(flavor, state)
  local ns = Fixture.load(flavor)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  state.skillLines = state.skillLines or { { name = "Professions", header = true }, { name = "Blacksmithing" }, { name = "Enchanting" } }
  ProfessionsClassic.install(state)
  ns.PlayerName.Init()
  ns.FlavorCompat = Fresh.require("Core.FlavorCompat") -- hasCraftFrame reads the Craft stubs at load
  ns.ProfessionList = Fresh.require("Professions.ProfessionList")
  ns.BindLookup = Fresh.require("Professions.BindLookup")
  Fresh.require("Professions.RecipeStore")
  Fresh.require("Professions.ReadJob")
  ns.ClassicReader = Fresh.require("Professions.ClassicReader")
  ns.CraftReader = Fresh.require("Professions.CraftReader")
  local db = ns.Defaults.Db()
  ns.ProfessionList.Refresh(db, "Me-Realm")
  local run = { builds = 0, reasons = {} }
  ns.Index.Configure(db, {})
  ns.Index.OnRebuilt(function()
    run.builds = run.builds + 1
    run.reasons[#run.reasons + 1] = ns.Index.lastReason
  end)
  ns.ClassicReader.Install(db)
  ns.CraftReader.Install(db)
  return ns, db, run
end

return ProfessionsClassic
