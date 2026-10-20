local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local NOW = 1792000000
local DAY = 86400

-- Fresh SavedState with `db` as the loaded SavedVariable (nil = first run) and time() = NOW.
local function load(db)
  Wow.reset()
  Wow.flavor("retail")
  Wow.clock.time = NOW
  Wow.stub("CraftAlertDB", db)
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.Constants")
  Fresh.require("Core.Localization")
  Fresh.require("Core.ChatPrint")
  Fresh.require("Persistence.Defaults")
  Fresh.require("Persistence.Schema")
  return Fresh.require("Persistence.SavedState")
end

local function dayKey(secondsAgo)
  return os.date("%Y-%m-%d", NOW - secondsAgo)
end

local function testFirstRun()
  local SavedState = load(nil)
  local db = SavedState.Load()
  Assert.equal(SavedState.isFirstRun, true)
  Assert.equal(rawget(_G, "CraftAlertDB"), db)
  Assert.equal(db.schema, 1)
  Assert.same(db.characters, {})
  Assert.equal(db.settings.enable, true)
end

-- A corrupt (non-table) db is replaced by a fresh one, so the first-run hint must show.
local function testCorruptDbCountsAsFirstRun()
  local SavedState = load("junk")
  local db = SavedState.Load()
  Assert.equal(SavedState.isFirstRun, true)
  Assert.equal(type(db), "table")
  Assert.equal(rawget(_G, "CraftAlertDB"), db)
end

local function testExistingDbIsBoundNotReplaced()
  local existing = { schema = 1, settings = { toastDuration = 30 }, characters = {} }
  local SavedState = load(existing)
  local db = SavedState.Load()
  Assert.equal(SavedState.isFirstRun, false)
  Assert.equal(db, existing)
  Assert.equal(rawget(_G, "CraftAlertDB"), existing)
  Assert.equal(db.settings.toastDuration, 30)
  Assert.equal(db.settings.leadTimeoutMin, 10)
  -- A second call sees the db the first one stored.
  Assert.equal(SavedState.Load(), existing)
  Assert.equal(SavedState.isFirstRun, false)
end

-- Load runs at ADDON_LOADED, before PlayerName.Init: it must not touch the normalizer.
local function testNeverCallsPlayerName()
  local SavedState = load({ characters = { ["Bob-Realm"] = {} }, leads = { { customer = "Cus-Realm", crafter = "Bob-Realm", time = NOW } } })
  local PlayerName = Fresh.require("Core.PlayerName")
  local function trap()
    error("PlayerName used during SavedState.Load")
  end
  PlayerName.Normalize = trap
  PlayerName.Init = trap
  PlayerName.Own = trap
  PlayerName.RealmOf = trap
  Wow.stub("UnitName", trap)
  Wow.stub("GetNormalizedRealmName", trap)
  Wow.stub("GetRealmName", trap)
  local db = SavedState.Load()
  Assert.truthy(db.characters["Bob-Realm"])
  Assert.equal(#db.leads, 1)
end

-- Review Focus 5: schema = 2, strings for numbers, 5,000 leads.
local function testNewerHandEditedDb()
  local leads = {}
  for i = 1, 5000 do
    leads[i] = { id = i, customer = "Cus" .. i .. "-Realm", crafter = "Me-Realm", time = NOW - (5000 - i) * 0.5 }
  end
  local SavedState = load({
    schema = 2,
    settings = { toastDuration = "30", leadTimeoutMin = "60", opacity = "high" },
    leads = leads,
  })
  local db = SavedState.Load()
  Assert.equal(db.schema, 2)
  Assert.equal(db.settings.toastDuration, 20)
  Assert.equal(db.settings.leadTimeoutMin, 10)
  -- leadTimeoutMin fell back to 10 minutes, so only the leads younger than 600 s survive,
  -- and the 100-lead cap keeps the newest of those.
  Assert.equal(#db.leads, 100)
  Assert.equal(db.leads[1].id, 4901)
  Assert.equal(db.leads[100].id, 5000)
  Assert.equal(#Wow.chat, 1)
end

local function testLeadCapKeepsNewest()
  local leads = {}
  for i = 1, 250 do
    -- Stored out of order on purpose: age, not position, decides who is dropped.
    leads[i] = { id = i, customer = "Cus-Realm", crafter = "Me-Realm", time = NOW - (i % 250) }
  end
  local db = load({ settings = { leadTimeoutMin = 60 }, leads = leads }).Load()
  Assert.equal(#db.leads, 100)
  for _, lead in ipairs(db.leads) do
    Assert.truthy(NOW - lead.time < 100, "an older lead survived the cap")
  end
end

local function testLeadExpiryUsesTimeStubAndTimeout()
  local db = load({
    settings = { leadTimeoutMin = 1 },
    leads = {
      { id = 1, customer = "A-Realm", crafter = "Me-Realm", time = NOW - 61 },
      { id = 2, customer = "B-Realm", crafter = "Me-Realm", time = NOW - 60 },
      { id = 3, customer = "C-Realm", crafter = "Me-Realm", time = NOW - 5 },
      { id = 4, customer = "D-Realm", crafter = "Me-Realm", time = NOW + 500 },
    },
  }).Load()
  local ids = {}
  for _, lead in ipairs(db.leads) do
    ids[#ids + 1] = lead.id
  end
  Assert.same(ids, { 2, 3, 4 })
end

local function testLedgerKeeps30Days()
  local db = load({
    ledger = {
      [dayKey(0)] = { seen = 1 },
      [dayKey(29 * DAY)] = { seen = 2 },
      [dayKey(30 * DAY)] = { seen = 3 },
      [dayKey(31 * DAY)] = { seen = 4 },
      [dayKey(400 * DAY)] = { seen = 5 },
    },
  }).Load()
  Assert.equal(db.ledger[dayKey(0)].seen, 1)
  Assert.equal(db.ledger[dayKey(29 * DAY)].seen, 2)
  Assert.equal(db.ledger[dayKey(30 * DAY)].seen, 3)
  Assert.equal(db.ledger[dayKey(31 * DAY)], nil)
  Assert.equal(db.ledger[dayKey(400 * DAY)], nil)
end

local function testRecentGreetedKeeps24Hours()
  local db = load({
    recentGreeted = { ["A-Realm"] = NOW - DAY, ["B-Realm"] = NOW - DAY - 1, ["C-Realm"] = NOW - 10 },
  }).Load()
  Assert.same(db.recentGreeted, { ["A-Realm"] = NOW - DAY, ["C-Realm"] = NOW - 10 })
end

local function testRecipeRecordKeepsMutedDropsUnknown()
  local db = load({
    characters = {
      ["Bob-Realm"] = {
        recipes = { [9001] = { item = 1, name = "Belt", prof = 164, muted = true, foo = "x" } },
      },
    },
  }).Load()
  Assert.same(db.characters["Bob-Realm"].recipes[9001], { item = 1, name = "Belt", prof = 164, muted = true })
end

return function()
  testFirstRun()
  testCorruptDbCountsAsFirstRun()
  testExistingDbIsBoundNotReplaced()
  testNeverCallsPlayerName()
  testNewerHandEditedDb()
  testLeadCapKeepsNewest()
  testLeadExpiryUsesTimeStubAndTimeout()
  testLedgerKeeps30Days()
  testRecentGreetedKeeps24Hours()
  testRecipeRecordKeepsMutedDropsUnknown()
end
