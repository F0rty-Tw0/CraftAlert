local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local ProfessionsClassic = require("tests.helpers.professions_classic")

-- Spec §5.2 row 2 and §13 "Readers" on Classic: the TradeSkill window (every Classic flavor) is
-- read as Slicer job "read", one list row per step, into lowercase-name recipe keys.
local CHAR = "Me-Realm"
local FLAVORS = { "era", "tbc", "wrath", "cata", "mop" }

local function enchanting(rows)
  return { line = "Enchanting", rows = rows }
end

local function recipesOf(db)
  return db.characters[CHAR].recipes
end

local function row(name, item)
  return { name = name, item = item }
end

local function wand()
  return row("Lesser Magic Wand", 11287)
end

local function rod()
  return row("Runed Copper Rod", 6218)
end

local function oil()
  return row("Minor Wizard Oil", 20744)
end

-- Advances the profile clock past the Slicer budget on every row read, so one tick reads one row.
-- → the row indexes read so far.
local function logRowReads()
  local original, calls = _G["GetTradeSkillInfo"], {}
  Wow.stub("GetTradeSkillInfo", function(index)
    calls[#calls + 1] = index
    Wow.clock.profile = Wow.clock.profile + 3
    return original(index)
  end)
  return calls
end

local function runOneTick()
  local timer = table.remove(Wow.timers, 1)
  timer.fn()
end

-- Header and subheader rows skipped, a non-|Hitem: link stores no item, bind requested for the
-- items whose bind is unknown, the profession marked read, one rebuild.
local function testShape(flavor)
  local state = { tradeSkill = enchanting(ProfessionsClassic.shapeRows()) }
  local ns, db, run = ProfessionsClassic.login(flavor, state)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  ns.Slicer.Drain()
  Assert.same(recipesOf(db), ProfessionsClassic.shapeStored(), flavor)
  Assert.equal(db.characters[CHAR].professions.enchanting.read, true, flavor)
  Assert.equal(db.characters[CHAR].professions.blacksmithing.read, false, flavor)
  Assert.same(state.requests, { 11287, 6218 }, flavor)
  local read = ns.ClassicReader.lastRead
  Assert.same({ read.prof, read.stored, read.pendingBind, read.steps }, { "enchanting", 3, 2, 5 }, flavor)
  Assert.equal(type(read.ms), "number", flavor)
  Assert.equal(ns.ClassicReader.newestRead, read, flavor)
  Assert.same(run.reasons, { "read" }, flavor)
end

-- Install configures the bind lookup: the bind types of cached items land on the stored recipes.
local function testBindLands()
  local state = { tradeSkill = enchanting({ wand(), rod() }), cached = { [11287] = true, [6218] = true }, bind = { [11287] = 2, [6218] = 0 } }
  local ns, db = ProfessionsClassic.login("tbc", state)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  ns.Slicer.Drain()
  Wow.runTimers()
  Assert.equal(recipesOf(db)["lesser magic wand"].bind, 2)
  Assert.equal(recipesOf(db)["runed copper rod"].bind, 0)
end

-- Nothing is read from another player's list, a profession the character does not store, a
-- closed window, or in an instance.
local function testGuards()
  local cases = {
    linked = function(state)
      state.tradeSkill.linked = true
    end,
    cooking = function(state)
      state.tradeSkill.line = "Cooking"
    end,
    closed = function(state)
      state.tradeSkill.open = false
    end,
    instance = function()
      Wow.stub("IsInInstance", function()
        return true
      end)
    end,
  }
  for name, apply in pairs(cases) do
    local state = { tradeSkill = enchanting({ wand() }) }
    local ns, db = ProfessionsClassic.login("tbc", state)
    apply(state)
    Wow.fireEvent("TRADE_SKILL_SHOW")
    Wow.fireEvent("TRADE_SKILL_UPDATE")
    ns.Slicer.Drain()
    Assert.same(recipesOf(db), {}, name)
    Assert.equal(ns.ClassicReader.lastRead, nil, name)
  end
end

-- A filtered (partial) list, then the full one, then a filtered one again: reads only add, the
-- player's mute and a known bind survive, a changed output item forgets its bind.
local function testPartialThenFull()
  local state = { tradeSkill = enchanting({ wand() }) }
  local ns, db = ProfessionsClassic.login("wrath", state)
  Wow.fireEvent("TRADE_SKILL_SHOW")
  ns.Slicer.Drain()
  local recipes = recipesOf(db)
  recipes["lesser magic wand"].muted = true
  recipes["lesser magic wand"].bind = 2

  state.tradeSkill.rows = { wand(), rod(), oil() }
  Wow.fireEvent("TRADE_SKILL_UPDATE")
  ns.Slicer.Drain()
  Assert.same(recipes["lesser magic wand"], { item = 11287, name = "Lesser Magic Wand", prof = "enchanting", muted = true, bind = 2 })
  Assert.truthy(recipes["runed copper rod"])
  Assert.truthy(recipes["minor wizard oil"])

  state.tradeSkill.rows = { row("Lesser Magic Wand", 11288) }
  Wow.fireEvent("TRADE_SKILL_UPDATE")
  ns.Slicer.Drain()
  Assert.same(recipes["lesser magic wand"], { item = 11288, name = "Lesser Magic Wand", prof = "enchanting", muted = true })
  Assert.truthy(recipes["runed copper rod"], "a filtered read keeps what it does not list")
  Assert.truthy(recipes["minor wizard oil"])
end

-- An update with the same row count re-reads nothing; one with another count restarts the
-- running job from the first row.
local function testUpdates()
  local state = { tradeSkill = enchanting({ wand(), rod() }) }
  local ns, db = ProfessionsClassic.login("tbc", state)
  local calls = logRowReads()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  ns.Slicer.Drain()
  Wow.runTimers()
  Assert.same(calls, { 1, 2 })
  Wow.fireEvent("TRADE_SKILL_UPDATE")
  ns.Slicer.Drain()
  Assert.same(calls, { 1, 2 }, "same count: no re-read")

  state.tradeSkill.rows = { wand(), rod(), oil() }
  Wow.fireEvent("TRADE_SKILL_UPDATE")
  runOneTick()
  Assert.same(calls, { 1, 2, 1 })
  state.tradeSkill.rows[4] = row("Lesser Mana Oil", 20747)
  Wow.fireEvent("TRADE_SKILL_UPDATE")
  ns.Slicer.Drain()
  Assert.same(calls, { 1, 2, 1, 1, 2, 3, 4 }, "a new count restarts the job")
  Assert.equal(ns.ClassicReader.lastRead.stored, 4)
  Assert.truthy(recipesOf(db)["lesser mana oil"])
end

-- A close cancels the read: what it stored so far still reaches the index.
local function testCloseCancels()
  local state = { tradeSkill = enchanting({ wand(), rod(), oil() }) }
  local ns, db, run = ProfessionsClassic.login("mop", state)
  local calls = logRowReads()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runOneTick()
  Assert.same(calls, { 1 }, "one row per step")
  Wow.fireEvent("TRADE_SKILL_CLOSE")
  Assert.falsy(ns.Slicer.IsRunning("read"))
  Wow.runTimers()
  Assert.same(calls, { 1 })
  Assert.same(recipesOf(db), { ["lesser magic wand"] = { item = 11287, name = "Lesser Magic Wand", prof = "enchanting" } })
  Assert.same(run.reasons, { "read" })
  Assert.equal(ns.ClassicReader.lastRead, nil, "a cancelled read is not a finished one")
end

return function()
  for _, flavor in ipairs(FLAVORS) do
    testShape(flavor)
  end
  testBindLands()
  testGuards()
  testPartialThenFull()
  testUpdates()
  testCloseCancels()
end
