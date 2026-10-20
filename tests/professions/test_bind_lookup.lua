local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local EVENT = "GET_ITEM_INFO_RECEIVED"
local BS = 164
local BATCH = 50

-- Two characters with recipes whose bind is unknown; 101 is shared, 102 already has a bind,
-- and A holds a second recipe for 101 whose bind is known (a read never overwrites it).
local function setup(extraItems)
  local ns = Fixture.load()
  local state = ProfessionsRetail.install({})
  local BindLookup = Fresh.require("Professions.BindLookup")
  local db = ns.Defaults.Db()
  db.characters["A-Realm"] = Fixture.character({ BS }, {
    [1] = { name = "a", item = 101, prof = BS },
    [2] = { name = "b", item = 102, prof = BS, bind = 1 },
    [3] = { name = "c", item = 101, prof = BS, bind = 1 },
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

-- Runs the one pending 1 s bind timer (not the index rebuild timer).
local function tick()
  for i, timer in ipairs(Wow.timers) do
    if timer.delay == 1 then
      table.remove(Wow.timers, i)
      timer.fn()
      return
    end
  end
  error("no bind timer pending")
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
  Assert.equal(#Wow.timers, 1, "a request arms the timer")
  Wow.fireEvent(EVENT, 999, true)
  Assert.equal(#Wow.timers, 1, "an item nobody queued is ignored")
  arrive(state, 101)
  Assert.equal(#Wow.timers, 1, "still one pending timer")
  Assert.equal(Wow.timers[1].delay, 1, "1 s debounce")
  Assert.equal(db.characters["A-Realm"].recipes[1].bind, nil, "stored when the timer fires")
  Wow.runTimers()
  Assert.equal(db.characters["A-Realm"].recipes[1].bind, 2)
  Assert.equal(db.characters["B-Realm"].recipes[1].bind, 2)
  Assert.equal(db.characters["A-Realm"].recipes[2].bind, 1, "an item nobody asked about is untouched")
  Assert.equal(db.characters["A-Realm"].recipes[3].bind, 1, "a known bind stays")
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

  -- Batches of 50 (§4.4 rule 7): the next batch goes out on the timer after the last one
  -- arrived, and the index is rebuilt once when everything has drained.
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
  tick()
  Assert.equal(#state.requests, 2 * BATCH)
  Assert.truthy(registered())
  Assert.equal(db.characters["A-Realm"].recipes[1001].bind, 1)
  Assert.equal(db.characters["A-Realm"].recipes[1051].bind, nil)
  Assert.equal(#Wow.timers, 1, "no rebuild between batches")
  for i = BATCH + 1, 2 * BATCH do
    arrive(state, 1000 + i)
  end
  tick()
  Assert.equal(#state.requests, 120, "the last batch holds the rest")
  Assert.equal(#Wow.timers, 1, "still no rebuild")
  for i = 2 * BATCH + 1, 120 do
    arrive(state, 1000 + i)
  end
  tick()
  Assert.equal(#Wow.timers, 1, "the drain requests the rebuild")
  Wow.runTimers()
  Assert.equal(db.characters["A-Realm"].recipes[1120].bind, 1)
  Assert.equal(run.builds, 1, "one rebuild per drain, not per batch")
  Assert.same(run.reasons, { "bind" })
  Assert.equal(BindLookup.lastStored, 120, "stored over the whole drain")
  Assert.falsy(registered())
  -- A later drain reports and rebuilds for its own stores only.
  BindLookup.Queue(101)
  arrive(state, 101, false)
  tick()
  Wow.runTimers()
  Assert.equal(BindLookup.lastStored, 0, "the next drain starts from 0")
  Assert.equal(run.builds, 1, "a drain that stores nothing rebuilds nothing")

  -- A waiting item whose data the client cached meanwhile is stored on the tick that sends it:
  -- that tick does not end the drain early, and the drain rebuilds once for all of it.
  state, BindLookup, db, run = setup(BATCH + 1)
  for i = 1, BATCH + 1 do
    state.bind[1000 + i] = 1
    BindLookup.Queue(1000 + i)
  end
  for i = 1, BATCH do
    arrive(state, 1000 + i)
  end
  state.cached[1000 + BATCH + 1] = true
  tick()
  Assert.equal(#state.requests, BATCH, "the cached item needs no request")
  Assert.equal(BindLookup.lastStored, nil, "the drain is not over")
  Assert.equal(Wow.pendingTimers(0), 0, "no rebuild yet")
  tick()
  Assert.equal(db.characters["A-Realm"].recipes[1000 + BATCH + 1].bind, 1)
  Assert.equal(BindLookup.lastStored, BATCH + 1)
  Wow.runTimers()
  Assert.equal(run.builds, 1, "one rebuild for the whole drain")

  -- An item that never answers is given up after 10 ticks, so it cannot block the window or
  -- keep the event registered; it is not retried this session.
  state, BindLookup, db, run = setup(60)
  for i = 1, BATCH + 1 do
    BindLookup.Queue(1000 + i)
  end
  Assert.equal(#state.requests, BATCH)
  for _ = 1, 9 do
    tick()
  end
  Assert.equal(#state.requests, BATCH, "still waiting at tick 9")
  tick()
  Assert.equal(#state.requests, BATCH + 1, "tick 10 gives up and sends the next item")
  -- The item sent at tick 10 gets its own 10 ticks.
  for _ = 11, 19 do
    tick()
  end
  Assert.truthy(registered(), "the late item is still in flight at tick 19")
  tick()
  Assert.falsy(registered(), "everything given up at tick 20: unregistered")
  Wow.runTimers()
  Assert.equal(run.builds, 0)
  Assert.equal(db.characters["A-Realm"].recipes[1001].bind, nil)
  BindLookup.Queue(1001)
  Assert.equal(#state.requests, BATCH + 1, "not retried this session")
  Assert.equal(#Wow.timers, 0)
end
