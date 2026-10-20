local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local EVENT = "GET_ITEM_INFO_RECEIVED"
local BS = 164
local BATCH = 50

-- Two characters with recipes whose bind is unknown; 101 is shared, 102 already has a bind.
local function setup(extraItems)
  local ns = Fixture.load()
  local state = ProfessionsRetail.install({})
  local BindLookup = Fresh.require("Professions.BindLookup")
  local db = ns.Defaults.Db()
  db.characters["A-Realm"] = Fixture.character({ BS }, {
    [1] = { name = "a", item = 101, prof = BS },
    [2] = { name = "b", item = 102, prof = BS, bind = 1 },
  })
  db.characters["B-Realm"] = Fixture.character({ BS }, { [1] = { name = "a", item = 101, prof = BS } })
  for i = 1, extraItems or 0 do
    db.characters["A-Realm"].recipes[1000 + i] = { name = "r" .. i, item = 1000 + i, prof = BS }
  end
  local run = { builds = 0, reasons = {} }
  ns.Index.Configure(db, {})
  ns.Index.OnRebuilt(function()
    run.builds = run.builds + 1
    run.reasons[#run.reasons + 1] = ns.Index.lastReason
  end)
  BindLookup.Configure(db)
  return state, BindLookup, db, run
end

local function registered()
  return Wow.frames[1] ~= nil and Wow.frames[1]:IsEventRegistered(EVENT)
end

-- The client loads the item, then tells the addon.
local function arrive(state, itemID, success)
  state.cached[itemID] = success ~= false or nil
  Wow.fireEvent(EVENT, itemID, success ~= false)
end

return function()
  -- Queue → request → event → debounce timer → bind stored on every character → one rebuild.
  local state, BindLookup, db, run = setup()
  state.bind[101] = 2
  Assert.falsy(registered(), "nothing registered before a request is pending")
  BindLookup.Queue(101)
  BindLookup.Queue(101)
  Assert.same(state.requests, { 101 }, "an item is requested once")
  Assert.truthy(registered())
  Assert.equal(#Wow.timers, 0, "no timer until data arrives")
  Wow.fireEvent(EVENT, 999, true)
  Assert.equal(#Wow.timers, 0, "an item nobody queued is ignored")
  arrive(state, 101)
  Assert.equal(#Wow.timers, 1)
  Assert.equal(Wow.timers[1].delay, 1, "1 s debounce")
  Assert.equal(db.characters["A-Realm"].recipes[1].bind, nil, "stored when the timer fires")
  Wow.runTimers()
  Assert.equal(db.characters["A-Realm"].recipes[1].bind, 2)
  Assert.equal(db.characters["B-Realm"].recipes[1].bind, 2)
  Assert.equal(db.characters["A-Realm"].recipes[2].bind, 1, "a known bind stays")
  Assert.equal(BindLookup.lastStored, 2)
  Assert.equal(run.builds, 1)
  Assert.same(run.reasons, { "bind" })
  Assert.falsy(registered(), "unregistered once nothing is pending")
  BindLookup.Queue(101)
  Assert.same(state.requests, { 101 }, "requested once ever")

  -- A cached item needs no request.
  state, BindLookup, db, run = setup()
  state.bind[101], state.cached[101] = 0, true
  BindLookup.Queue(101)
  Assert.same(state.requests, {})
  Assert.falsy(registered())
  Wow.runTimers()
  Assert.equal(db.characters["A-Realm"].recipes[1].bind, 0)
  Assert.equal(run.builds, 1)

  -- A failed load stores nothing and rebuilds nothing.
  state, BindLookup, db, run = setup()
  BindLookup.Queue(101)
  arrive(state, 101, false)
  Wow.runTimers()
  Assert.equal(db.characters["A-Realm"].recipes[1].bind, nil)
  Assert.equal(BindLookup.lastStored, 0)
  Assert.equal(run.builds, 0)
  Assert.falsy(registered())

  -- Batches of 50 (§4.4 rule 7): the next batch goes out after the debounce timer.
  state, BindLookup, db, run = setup(120)
  for i = 1, 120 do
    state.bind[1000 + i] = 1
    BindLookup.Queue(1000 + i)
  end
  Assert.equal(#state.requests, BATCH)
  Assert.equal(state.requests[BATCH], 1000 + BATCH)
  for i = 1, BATCH do
    arrive(state, 1000 + i)
  end
  Assert.falsy(registered(), "nothing in flight between batches")
  Wow.runTimers()
  Assert.equal(#state.requests, 2 * BATCH)
  Assert.truthy(registered())
  Assert.equal(db.characters["A-Realm"].recipes[1001].bind, 1)
  Assert.equal(db.characters["A-Realm"].recipes[1051].bind, nil)
  for i = BATCH + 1, 2 * BATCH do
    arrive(state, 1000 + i)
  end
  Wow.runTimers()
  Assert.equal(#state.requests, 120, "the last batch holds the rest")
  for i = 2 * BATCH + 1, 120 do
    arrive(state, 1000 + i)
  end
  Wow.runTimers()
  Assert.equal(db.characters["A-Realm"].recipes[1120].bind, 1)
  Assert.equal(run.builds, 3, "one rebuild per batch")
  Assert.falsy(registered())
end
