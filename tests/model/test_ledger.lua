local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

-- Spec §8 and §13 "Names and ledger": daily counters keyed by the local date, fed by the leads'
-- "new", "greeted" and "replied" events. Local noon on 2026-10-27, so the day keys do not depend
-- on the machine's time zone.
local NOON = os.time({ year = 2026, month = 10, day = 27, hour = 12 })
local DAY = 24 * 60 * 60
local TODAY = "2026-10-27"
local TEST_GUID = "Player-0-CRAFTALERTTEST-1"

-- Real Matcher over the fixture's item index, real Leads and a fresh Ledger, installed. → ns, db.
local function setup()
  local ns = Fixture.load("retail")
  Wow.clock.time = NOON
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  local db
  Fixture.itemIndex(ns, function(captured)
    db = captured
  end)
  for _, name in ipairs({ "Model.RealmTag", "Model.CrafterRank", "Model.Leads", "Model.Ledger" }) do
    ns[string.match(name, "%.(%w+)$")] = Fresh.require(name)
  end
  ns.Ledger.Install(db)
  ns.Leads.Restore(db)
  return ns, db
end

local function newLead(ns, customer, text, guid)
  text = text or "LF plate belt"
  local result = ns.Matcher.Match("trade", text, "Someone-Else")
  return ns.Leads.OnMatch(result, customer, text, "trade", guid)
end

local function counters(seen, greeted, replied, filled)
  return { seen = seen, greeted = greeted, replied = replied, filled = filled or 0 }
end

-- One "seen" per new lead, none for the same request again (Leads' dedupe fires "change", not
-- "new"), none for the lead being viewed ("seen" event); greeted and replied once per lead.
local function testCountsLeadEvents()
  local ns, db = setup()
  local lead = newLead(ns, "Bob-Realm")
  newLead(ns, "Bob-Realm")
  ns.Leads.MarkSeen(lead.id)
  Assert.same(ns.Ledger.Today(), counters(1, 0, 0), "an update and a view count nothing")
  newLead(ns, "Cy-Realm")
  ns.Leads.MarkGreeted(lead.id)
  ns.Leads.MarkGreeted(lead.id)
  ns.Leads.MarkReplied(lead.id)
  ns.Leads.MarkReplied(lead.id)
  Assert.same(ns.Ledger.Today(), counters(2, 1, 1))
  Assert.same(db.ledger[TODAY], counters(2, 1, 1), "stored under today's date")
end

-- A `/ca test` lead never counts (checklist C24, test_slash_commands.lua).
local function testSkipsTestLeads()
  local ns, db = setup()
  local lead = newLead(ns, "Test0-Realm", nil, TEST_GUID)
  Assert.equal(lead.test, true)
  ns.Leads.MarkGreeted(lead.id)
  ns.Leads.MarkReplied(lead.id)
  Assert.same(ns.Ledger.Today(), counters(0, 0, 0))
  Assert.equal(db.ledger[TODAY], nil, "no day record for a test lead")
end

-- A new day starts at zero; the week lists today first, then the six days before it.
local function testDaysAndWeek()
  local ns, db = setup()
  db.ledger["2026-10-21"] = counters(4, 3, 2, 1)
  db.ledger["2026-10-20"] = counters(9, 9, 9, 9)
  newLead(ns, "Bob-Realm")
  Wow.clock.time = NOON + DAY
  Assert.same(ns.Ledger.Today(), counters(0, 0, 0), "a new day")
  ns.Ledger.Add("filled")
  Assert.same(db.ledger["2026-10-28"], counters(0, 0, 0, 1))
  Wow.clock.time = NOON
  local week = ns.Ledger.LastDays(7)
  Assert.equal(#week, 7)
  Assert.same(week[1], { day = TODAY, seen = 1, greeted = 0, replied = 0, filled = 0 })
  Assert.same(week[2], { day = "2026-10-26", seen = 0, greeted = 0, replied = 0, filled = 0 })
  Assert.same(week[7], { day = "2026-10-21", seen = 4, greeted = 3, replied = 2, filled = 1 })
  -- Late in the evening of today, as at a minute past midnight, the week still ends today.
  Wow.clock.time = NOON + 11 * 60 * 60 + 59 * 60
  Assert.equal(ns.Ledger.LastDays(7)[1].day, TODAY)
  Assert.equal(ns.Ledger.LastDays(7)[7].day, "2026-10-21")
end

-- Add tells its listeners (the strip repaints on a fill, which fires no Leads "change"); an
-- unknown field or a call before Install changes nothing.
local function testAddAndListeners()
  local ns = Fixture.load("retail")
  Wow.clock.time = NOON
  local Ledger = Fresh.require("Model.Ledger")
  Ledger.Add("seen")
  Assert.same(Ledger.Today(), counters(0, 0, 0), "nothing before Install")
  local db = ns.Defaults.Db()
  Ledger.Install(db)
  local calls = 0
  Ledger.OnChange(function()
    calls = calls + 1
  end)
  Ledger.Add("filled")
  Ledger.Add("bogus")
  Assert.same(Ledger.Today(), counters(0, 0, 0, 1))
  Assert.equal(calls, 1, "one call per counted Add")
end

return function()
  testCountsLeadEvents()
  testSkipsTestLeads()
  testDaysAndWeek()
  testAddAndListeners()
  Wow.reset()
end
