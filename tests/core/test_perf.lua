local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local SlashFixture = require("tests.helpers.slash_fixture")

-- debugprofilestop() answers the queued times (milliseconds), one per call; a call with the
-- queue empty raises, so a stray timing call fails the test where it happens.
local function scriptClock(times)
  local next = 0
  Wow.stub("debugprofilestop", function()
    next = next + 1
    return assert(times[next], "debugprofilestop called more often than scripted")
  end)
  return function()
    return next
  end
end

-- GetAddOnMemoryUsage("CraftAlert") answers the queued KB values.
local function scriptMemory(values)
  local next = 0
  Wow.stub("GetAddOnMemoryUsage", function(name)
    Assert.equal(name, "CraftAlert")
    next = next + 1
    return values[next]
  end)
end

-- A line on a custom channel (zone channel 0): the scan gate drops it at step 1.
local function fireCustomChannel()
  Wow.fireEvent("CHAT_MSG_CHANNEL", "hello", "Bob-Draenor", "", "5. Custom", "Bob-Draenor", "", 0, 5, "Custom", 0, 1, nil)
end

local function lastChat()
  local lines = SlashFixture.chat()
  return lines[#lines]
end

-- §4.4 `/ca perf`: the timed handler replaces HandleChat, reports from inside itself once 60 s
-- have passed, and Stop gives HandleChat back with no timing call left on the hot path.
return function()
  local ns = SlashFixture.load()
  local Perf = ns.Perf
  ns.Index.lastBuildMs = 12.5
  Perf.loginMs = 42
  Assert.equal(Perf.IsRunning(), false)

  -- Start: one notice, one clock read for the report schedule, one memory reading.
  local calls = scriptClock({ 0, 100, 100.010, 200, 200.5, 60000, 60000.030, 60100, 60100.010 })
  scriptMemory({ 100, 130.5 })
  Perf.Start()
  Assert.equal(Perf.IsRunning(), true)
  Assert.same(SlashFixture.chat(), { "Perf on: timing each chat line, a report every 60 s. /ca perf again stops it. Memory 100.0 KB." })
  Perf.Start()
  Assert.equal(#Wow.chat, 1, "starting twice changes nothing")

  -- Lines still reach HandleChat: a match makes its lead. Nothing is reported before 60 s.
  SlashFixture.fireTrade("hello there", "Bob-Draenor")
  Assert.equal(calls(), 3, "two reads around the line")
  SlashFixture.fireTrade("LF mongoose", "Cy-Draenor")
  Assert.equal(ns.Leads.Latest().customer, "Cy-Draenor", "HandleChat ran inside the timer")
  Assert.equal(#Wow.chat, 1, "no report yet")

  -- The first line after 60 s carries the report: an unmatched line and a channel the gate
  -- drops count as hot path lines (a stale "match" must not make it a matched one).
  fireCustomChannel()
  Assert.equal(lastChat(), "Perf: Lines 2, mean 20.0 us, max 30.0 us. Matched 1, mean 500.0 us, max 500.0 us. Login 42.0 ms, index build 12.5 ms.")
  Assert.equal(#Wow.chat, 2)
  fireCustomChannel()
  Assert.equal(#Wow.chat, 2, "the next report waits another 60 s")

  -- Stop: HandleChat is back (no clock read for the next line), totals and memory are printed.
  Perf.Stop()
  Assert.equal(Perf.IsRunning(), false)
  Assert.equal(
    lastChat(),
    "Perf off: Lines 3, mean 16.7 us, max 30.0 us. Matched 1, mean 500.0 us, max 500.0 us. Login 42.0 ms, index build 12.5 ms. Memory 100.0 KB to 130.5 KB."
  )
  local reads = calls()
  SlashFixture.fireTrade("LF mongoose", "Di-Draenor")
  fireCustomChannel()
  Assert.equal(calls(), reads, "no timing call on the hot path when perf is off")
  Assert.equal(ns.Leads.Latest().customer, "Di-Draenor", "HandleChat handles the line again")
  Perf.Stop()
  Assert.equal(#Wow.chat, 3, "stopping twice prints nothing")

  -- A run with no lines, no login time and no memory API says so instead of dividing by zero.
  Perf.loginMs = nil
  ns.Index.lastBuildMs = nil
  Wow.stub("GetAddOnMemoryUsage", nil)
  scriptClock({ 0 })
  Wow.chat = {}
  Perf.Start()
  Perf.Stop()
  Assert.same(SlashFixture.chat(), {
    "Perf on: timing each chat line, a report every 60 s. /ca perf again stops it.",
    "Perf off: Lines 0. Matched 0. Login n/a, index build n/a.",
  })
end
