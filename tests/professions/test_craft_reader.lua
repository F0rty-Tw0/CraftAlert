local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local ProfessionsClassic = require("tests.helpers.professions_classic")

-- Spec §5.2 row 3 and §13 "Readers": Enchanting's CraftFrame on Era and TBC is read as Slicer job
-- "craftRead" into the same stored shape as the TradeSkill window; Beast Training is ignored.
local CHAR = "Me-Realm"

local function recipesOf(db)
  return db.characters[CHAR].recipes
end

local function isRegistered(event)
  for _, frame in ipairs(Wow.frames) do
    if frame.events[event] then
      return true
    end
  end
  return false
end

local function testShape(flavor)
  local state = { craft = { line = "Enchanting", rows = ProfessionsClassic.shapeRows() } }
  local ns, db, run = ProfessionsClassic.login(flavor, state)
  Wow.fireEvent("CRAFT_SHOW")
  ns.Slicer.Drain()
  Assert.same(recipesOf(db), ProfessionsClassic.shapeStored(), flavor)
  Assert.equal(db.characters[CHAR].professions.enchanting.read, true, flavor)
  local read = ns.CraftReader.lastRead
  Assert.same({ read.prof, read.stored, read.pendingBind }, { "enchanting", 3, 2 }, flavor)
  Assert.equal(ns.ClassicReader.newestRead, read, flavor)
  Assert.equal(ns.ClassicReader.lastRead, nil, flavor)
  Assert.same(run.reasons, { "read" }, flavor)
end

-- The hunter's pet training opens the same frame.
local function testBeastTraining()
  local state = { craft = { line = "Beast Training", rows = { { name = "Growl", kind = "header" }, { name = "Growl (Rank 1)" } } } }
  local ns, db = ProfessionsClassic.login("era", state)
  Wow.fireEvent("CRAFT_SHOW")
  ns.Slicer.Drain()
  Assert.same(recipesOf(db), {})
  Assert.equal(ns.CraftReader.lastRead, nil)
end

-- Only Era and TBC with the Craft calls present get the reader.
local function testInstallOnlyWithCraftFrame()
  local rows = ProfessionsClassic.shapeRows()
  for _, flavor in ipairs({ "wrath", "cata", "mop" }) do
    local ns, db = ProfessionsClassic.login(flavor, { craft = { line = "Enchanting", rows = rows } })
    Assert.falsy(isRegistered("CRAFT_SHOW"), flavor)
    Wow.fireEvent("CRAFT_SHOW")
    ns.Slicer.Drain()
    Assert.same(recipesOf(db), {}, flavor)
  end
  ProfessionsClassic.login("tbc", {})
  Assert.falsy(isRegistered("CRAFT_SHOW"), "no GetCraftDisplaySkillLine")
end

-- Both windows open at once on TBC: two jobs, and closing one leaves the other running.
local function testBothWindows()
  local state = {
    tradeSkill = { line = "Blacksmithing", rows = { { name = "Copper Chain Belt", item = 2851 }, { name = "Rough Copper Vest", item = 2852 } } },
    craft = { line = "Enchanting", rows = ProfessionsClassic.shapeRows() },
  }
  local ns, db = ProfessionsClassic.login("tbc", state)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  Wow.fireEvent("CRAFT_SHOW")
  Assert.truthy(ns.Slicer.IsRunning("read"))
  Assert.truthy(ns.Slicer.IsRunning("craftRead"))
  Wow.fireEvent("CRAFT_CLOSE")
  Assert.falsy(ns.Slicer.IsRunning("craftRead"))
  Assert.truthy(ns.Slicer.IsRunning("read"))
  ns.Slicer.Drain()
  Assert.same(recipesOf(db)["copper chain belt"], { item = 2851, name = "Copper Chain Belt", prof = "blacksmithing" })
  Assert.truthy(recipesOf(db)["rough copper vest"])

  Wow.fireEvent("CRAFT_SHOW")
  ns.Slicer.Drain()
  Assert.equal(ns.CraftReader.lastRead.stored, 3)
  Assert.equal(ns.ClassicReader.lastRead.prof, "blacksmithing")
  Assert.equal(ns.ClassicReader.newestRead, ns.CraftReader.lastRead)
end

return function()
  testShape("era")
  testShape("tbc")
  testBeastTraining()
  testInstallOnlyWithCraftFrame()
  testBothWindows()
end
