local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function newSlicer()
  Wow.reset()
  Fresh.require("Core.EventRouter")
  return Fresh.require("Core.Slicer")
end

-- A job whose step i costs costs[i] ms of the stubbed profile clock and logs its name.
local function costJob(log, name, costs)
  local index = 0
  local job = { cancels = 0 }
  function job.step()
    index = index + 1
    log[#log + 1] = name
    Wow.clock.profile = Wow.clock.profile + costs[index]
    return index == #costs
  end
  function job.onCancel()
    job.cancels = job.cancels + 1
  end
  return job
end

local function runOneTick()
  table.remove(Wow.timers, 1).fn()
end

local function captureErrors()
  local reported = {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      reported[#reported + 1] = err
    end
  end)
  return reported
end

local function testBudgetStopsAfterTwoOneMsSteps()
  local Slicer = newSlicer()
  local log = {}
  Slicer.Start("read", costJob(log, "A", { 1, 1, 1 }))

  runOneTick()
  Assert.equal(Slicer.stats.steps, 2, "two 1 ms steps fill the 2 ms budget")
  Assert.equal(Wow.pendingTimers(0), 1)
  Wow.runTimers()
  Assert.equal(#log, 3)
  Assert.falsy(Slicer.IsRunning("read"))
  Assert.equal(Wow.pendingTimers(0), 0, "a finished job schedules nothing")
end

local function testSlowStepIsPaidBackByIdleTicks()
  local Slicer = newSlicer()
  Slicer.Start("read", costJob({}, "A", { 9, 1 }))

  local perTick = {}
  local before = 0
  for tick = 1, 6 do
    runOneTick()
    perTick[tick] = Slicer.stats.steps - before
    before = Slicer.stats.steps
  end

  Assert.same(perTick, { 1, 0, 0, 0, 0, 1 }, "debt 7 -> 5 -> 3 -> 1 -> 0, then a step")
  Assert.equal(Slicer.stats.ticks, 6)
  Assert.equal(Slicer.stats.longestTickMs, 9)
  Assert.equal(Wow.pendingTimers(0), 0)
end

local function testJobsAlternate()
  local Slicer = newSlicer()
  local log = {}
  Slicer.Start("a", costJob(log, "A", { 1, 1 }))
  Slicer.Start("b", costJob(log, "B", { 1, 1 }))

  Wow.runTimers()
  Assert.same(log, { "A", "B", "A", "B" })
end

local function testCursorResumesAfterLastJobThatRan()
  local Slicer = newSlicer()
  local log = {}
  Slicer.Start("a", costJob(log, "A", { 3, 3, 3 }))
  Slicer.Start("b", costJob(log, "B", { 1, 1, 1 }))

  Wow.runTimers()
  Assert.same(log, { "A", "B", "A", "B", "A", "B" }, "a cursor reset to the first job would run A three times first")
end

local function testStartingARunningNameCancelsTheOldJob()
  local Slicer = newSlicer()
  local log = {}
  local job1 = costJob(log, "one", { 1, 1, 1 })
  local job2 = costJob(log, "two", { 1 })
  Slicer.Start("x", job1)
  Slicer.Start("x", job2)

  Assert.equal(job1.cancels, 1)
  Wow.runTimers()
  Assert.same(log, { "two" })
  Assert.equal(job2.cancels, 0, "a finished job is not cancelled")
end

local function testIdleStartsShareOneTimer()
  local Slicer = newSlicer()
  Slicer.Start("a", costJob({}, "A", { 1 }))
  Slicer.Start("b", costJob({}, "B", { 1 }))

  Assert.equal(Wow.pendingTimers(0), 1)
end

local function testRaisingStepIsReportedAndOthersGoOn()
  local Slicer = newSlicer()
  local reported = captureErrors()
  local log = {}
  local bad = { cancels = 0 }
  function bad.step()
    error("boom", 0)
  end
  function bad.onCancel()
    bad.cancels = bad.cancels + 1
  end
  Slicer.Start("A", bad)
  Slicer.Start("B", costJob(log, "B", { 1, 1 }))

  Wow.runTimers()
  Assert.same(reported, { "boom" })
  Assert.falsy(Slicer.IsRunning("A"))
  Assert.equal(bad.cancels, 1)
  Assert.same(log, { "B", "B" }, "B still finishes")
  Assert.falsy(Slicer.IsRunning("B"))
end

local function testStepMayCancelItsOwnJob()
  local Slicer = newSlicer()
  local reported = captureErrors()
  local job = { cancels = 0 }
  function job.step()
    Slicer.Cancel("A")
    return false
  end
  function job.onCancel()
    job.cancels = job.cancels + 1
  end
  Slicer.Start("A", job)

  Wow.runTimers()
  Assert.falsy(Slicer.IsRunning("A"))
  Assert.equal(job.cancels, 1)
  Assert.same(reported, {})
  Assert.equal(Wow.pendingTimers(0), 0)
end

local function testCombatPausesUntilRegenEnabled()
  local Slicer = newSlicer()
  local log = {}
  Slicer.Start("A", costJob(log, "A", { 1, 1 }))
  Wow.combat = true

  runOneTick()
  Assert.equal(#log, 0, "no step in combat")
  Assert.equal(Wow.pendingTimers(0), 0, "no timer in combat")
  Assert.truthy(Slicer.IsRunning("A"))

  Wow.combat = false
  Wow.fireEvent("PLAYER_REGEN_ENABLED")
  Assert.equal(Wow.pendingTimers(0), 1)
  Wow.runTimers()
  Assert.equal(#log, 2)
  Assert.falsy(Slicer.IsRunning("A"))
  Wow.fireEvent("PLAYER_REGEN_ENABLED")
  Assert.equal(Wow.pendingTimers(0), 0, "the combat listener is gone")
end

local function testDrainFinishesEveryJob()
  local Slicer = newSlicer()
  local log = {}
  Slicer.Start("a", costJob(log, "A", { 3, 3, 3 }))
  Slicer.Start("b", costJob(log, "B", { 3, 3, 3 }))
  runOneTick()

  Slicer.Drain()
  Assert.falsy(Slicer.IsRunning("a"))
  Assert.falsy(Slicer.IsRunning("b"))
  Assert.equal(#log, 6)
  Assert.equal(Wow.pendingTimers(0), 1, "the scheduled tick stays")
  Wow.runTimers()
  Assert.equal(Wow.pendingTimers(0), 0, "and finds nothing to do")
  Assert.equal(#log, 6)
end

local function testResetStatsZeroesCounters()
  local Slicer = newSlicer()
  Slicer.Start("A", costJob({}, "A", { 5, 1 }))
  runOneTick()
  Assert.truthy(Slicer.stats.steps > 0)

  Slicer.ResetStats()
  Assert.same(Slicer.stats, { ticks = 0, steps = 0, longestTickMs = 0 })
end

-- Run: the work yields at pause once BUDGET_MS has passed in a step, onDone gets its results
-- (nils kept), an error carries its message to the handler, a cancel runs onCancel only.
local function testRunSlicesCoroutineWork()
  local Slicer = newSlicer()
  local reported = captureErrors()
  Wow.stub("debugprofilestop", function()
    Wow.clock.profile = Wow.clock.profile + 0.25
    return Wow.clock.profile
  end)
  local done = nil
  Slicer.Run("work", function(pause)
    local sum = 0
    for i = 1, 200 do
      sum = sum + i
      pause(1)
    end
    return sum, nil, "end"
  end, function(...)
    done = { n = select("#", ...), ... }
  end)
  Slicer.Drain()
  Assert.same(done, { n = 3, 20100, nil, "end" })
  Assert.truthy(Slicer.stats.steps > 1, "the work yielded, steps " .. Slicer.stats.steps)

  Slicer.Run("bad", function()
    error("broken work", 0)
  end, function()
    error("onDone must not run")
  end)
  Slicer.Drain()
  Assert.equal(#reported, 1)
  Assert.truthy(string.find(reported[1], "broken work", 1, true))

  local cancelled = 0
  Slicer.Run("cut", function(pause)
    for _ = 1, 1000 do
      pause(8)
    end
  end, function()
    error("onDone must not run")
  end, function()
    cancelled = cancelled + 1
  end)
  Slicer.Cancel("cut")
  Slicer.Drain()
  Assert.equal(cancelled, 1)
end

-- Run → { ms, steps }: by onDone it holds the CPU ms of every resume and the step count; a job
-- that onDone restarts under its own name runs on instead of being taken for done.
local function testRunRestartedFromOnDoneRunsOn()
  local Slicer = newSlicer()
  local seen, restarts, finished = nil, 0, 0
  local run
  local function start()
    run = Slicer.Run("index", function(pause)
      for _ = 1, 6 do
        Wow.clock.profile = Wow.clock.profile + 1
        pause(8) -- yields on every second ms: 2 + 2 + 2 ms, then a step that returns
      end
      return "built"
    end, function(result)
      seen = { result = result, ms = run.ms, steps = run.steps }
      finished = finished + 1
      if restarts == 0 then
        restarts = 1
        start()
      end
    end)
  end
  start()
  Slicer.Drain()
  Assert.equal(finished, 2, "the job onDone started ran too")
  Assert.falsy(Slicer.IsRunning("index"))
  Assert.same(seen, { result = "built", ms = 6, steps = 4 })
end

-- A step that restarts its own job and then raises is reported; the replacement runs on.
local function testRaisingStepKeepsItsReplacement()
  local Slicer = newSlicer()
  local reported = captureErrors()
  local log = {}
  local bad = { cancels = 0 }
  function bad.step()
    Slicer.Start("A", costJob(log, "new", { 1, 1 }))
    error("boom", 0)
  end
  Slicer.Start("A", bad)

  Wow.runTimers()
  Assert.same(reported, { "boom" })
  Assert.same(log, { "new", "new" }, "the replacement finished")
end

return function()
  testRunSlicesCoroutineWork()
  testRunRestartedFromOnDoneRunsOn()
  testRaisingStepKeepsItsReplacement()
  testBudgetStopsAfterTwoOneMsSteps()
  testSlowStepIsPaidBackByIdleTicks()
  testJobsAlternate()
  testCursorResumesAfterLastJobThatRan()
  testStartingARunningNameCancelsTheOldJob()
  testIdleStartsShareOneTimer()
  testRaisingStepIsReportedAndOthersGoOn()
  testStepMayCancelItsOwnJob()
  testCombatPausesUntilRegenEnabled()
  testDrainFinishesEveryJob()
  testResetStatsZeroesCounters()
  Wow.reset()
end
