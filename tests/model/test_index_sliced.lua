local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")
local Synthetic = require("tests.helpers.synthetic_index")

-- Sliced index rebuild (spec 2026-10-26-sliced-index-build §3-§4): Index.RequestRebuild runs
-- Index.Build as the Slicer job "index", a coroutine that yields at pause points; Rebuild()
-- stays synchronous. The profile clock advances on every read, so the build really yields.
local JOB = "index"
local TICK_MS = 0.25 -- profile clock advance per debugprofilestop call

local function advancingClock()
  Wow.stub("debugprofilestop", function()
    Wow.clock.profile = Wow.clock.profile + TICK_MS
    return Wow.clock.profile
  end)
end

-- The perf fixture (10 characters, 2,000 recipes), configured like the client.
local function setup()
  local ns = Fixture.load()
  local db, items = Synthetic.db(ns)
  Synthetic.stubItems(items)
  ns.Index.Configure(db, {
    ownKey = "Me-Realm",
    professionOrder = function()
      return Synthetic.PROFESSIONS
    end,
  })
  local builds = { n = 0 }
  ns.Index.OnRebuilt(function()
    builds.n = builds.n + 1
  end)
  advancingClock()
  return ns, db, builds
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

local function runOneTick()
  table.remove(Wow.timers, 1).fn()
end

-- AC 2: the sliced build yields many times and ends with the same index as Index.Build.
local function testSlicedEqualsSync()
  local ns, db, builds = setup()
  ns.Index.RequestRebuild("read")
  Assert.equal(builds.n, 0, "nothing built before the job runs")
  Assert.truthy(ns.Slicer.IsRunning(JOB), "the request starts the index job")
  ns.Slicer.Drain()
  Assert.equal(builds.n, 1)
  Assert.truthy(ns.Index.lastBuildSteps > 1, "the build yielded, steps " .. tostring(ns.Index.lastBuildSteps))
  Assert.equal(type(ns.Index.lastBuildMs), "number")
  Assert.equal(Synthetic.difference(ns.Index.Current(), Synthetic.build(ns, db)), nil, "sliced index equals Index.Build's")
  local shared = Synthetic.sharedNames(ns.Index.Current())
  Assert.equal(shared, 184, "names with two crafters of one profession")
end

-- A request during a build restarts it: the finished index holds the db as of the second
-- request, and only one build swaps in.
local function testSecondRequestRestarts()
  local ns, db, builds = setup()
  ns.Index.RequestRebuild("read")
  runOneTick()
  Assert.truthy(ns.Slicer.IsRunning(JOB), "one tick leaves the build unfinished")
  db.characters["Char1-Realm"].recipes[1] = { item = 100001, name = "Restart Belt", prof = Synthetic.PROFESSIONS[1], bind = 1 }
  ns.Index.RequestRebuild("mute")
  ns.Slicer.Drain()
  Assert.equal(builds.n, 1, "the first build is dropped")
  Assert.equal(ns.Index.lastReason, "mute")
  Assert.equal(ns.Index.Current().size, 2001)
  Assert.truthy(ns.Index.Current().nameIndex.restart, "the second request's recipe is indexed")
end

-- A subscriber that requests a rebuild inside the job's last step gets that build: the
-- finishing job doesn't remove its replacement.
local function testSubscriberRequestRuns()
  local ns, _, builds = setup()
  local requested = false
  ns.Index.OnRebuilt(function()
    if not requested then
      requested = true
      ns.Index.RequestRebuild("again")
    end
  end)
  ns.Index.RequestRebuild("read")
  ns.Slicer.Drain()
  Assert.equal(builds.n, 2, "the requested build ran")
  Assert.falsy(ns.Slicer.IsRunning(JOB))
end

-- A raising step cancels the job and reports with the coroutine's stack; the old index stays.
local function testRaisingStepKeepsOldIndex()
  local ns, db, builds = setup()
  local old = ns.Index.Rebuild()
  local reported = captureErrors()
  Wow.stub("debugstack", function(thread)
    return type(thread) == "thread" and "build stack" or "caller stack"
  end)
  db.characters["Char5-Realm"].recipes[7] = { item = 100007, prof = Synthetic.PROFESSIONS[5], bind = 1 } -- no name
  ns.Index.RequestRebuild("read")
  ns.Slicer.Drain()
  Assert.equal(#reported, 1)
  Assert.truthy(string.find(tostring(reported[1]), "\nbuild stack", 1, true), "the error carries the build's stack")
  Assert.falsy(ns.Slicer.IsRunning(JOB))
  Assert.truthy(rawequal(ns.Index.Current(), old), "the old index stays")
  Assert.equal(builds.n, 1, "only the sync build swapped in")
end

-- Login's Rebuild() cancels a running job and builds in one call (1 step).
local function testRebuildCancelsJob()
  local ns, _, builds = setup()
  ns.Index.RequestRebuild("read")
  runOneTick()
  Assert.truthy(ns.Slicer.IsRunning(JOB))
  local index = ns.Index.Rebuild()
  Assert.falsy(ns.Slicer.IsRunning(JOB), "Rebuild cancels the job")
  Assert.equal(ns.Index.lastBuildSteps, 1)
  ns.Slicer.Drain()
  Wow.runTimers()
  Assert.equal(builds.n, 1)
  Assert.truthy(rawequal(ns.Index.Current(), index))
end

-- Pause takes a weight, the loop body's work: eight heavy words in a row (1 ms each, a list of
-- 64 entries) yield once the budget is spent, rather than after the eighth pause call.
local function testHeavyWordsYieldOnBudget()
  local ns = setup()
  Wow.stub("debugprofilestop", function()
    return Wow.clock.profile
  end)
  local wordGroupsBuild = ns.WordGroups.Build
  ns.WordGroups.Build = function(index, pause)
    for _ = 1, 8 do
      Wow.clock.profile = Wow.clock.profile + 1
      pause(64)
    end
    return wordGroupsBuild(index, pause)
  end
  ns.Slicer.ResetStats()
  ns.Index.RequestRebuild("read")
  Wow.runTimers()
  ns.WordGroups.Build = wordGroupsBuild
  Assert.falsy(ns.Slicer.IsRunning(JOB), "the sliced build finished")
  local longest = ns.Slicer.stats.longestTickMs
  Assert.truthy(longest <= ns.Slicer.BUDGET_MS + 1, "a tick holds at most one heavy word past the budget, longest " .. longest)
end

-- WordGroups pauses inside one word list's work, not only between words: the longest list's
-- entries are read a few walks' worth at most between two pauses, never all its walks at once.
local function testWordGroupsPausesWithinList()
  local ns, db = setup()
  local index = Synthetic.build(ns, db)
  local longest = {}
  for _, list in pairs(index.wordIndex) do
    if #list > #longest then
      longest = list
    end
  end
  local reads, most, heavy = 0, 0, 0
  for k, entry in ipairs(longest) do
    longest[k] = setmetatable({}, {
      __index = function(_, key)
        reads = reads + 1
        return entry[key]
      end,
    })
  end
  ns.WordGroups.Build(index, function(weight)
    most, reads = math.max(most, reads), 0
    if weight == #longest then
      heavy = heavy + 1
    end
  end)
  most = math.max(most, reads)
  Assert.truthy(#longest > 64, "the fixture has a long list, " .. #longest)
  Assert.truthy(most <= 4 * #longest, "entry reads between two pauses, " .. most .. " of a " .. #longest .. "-entry list")
  -- buildGroupWords and the word-info loop each weigh the word by its list's length.
  Assert.truthy(heavy >= 2, "pauses weighted by the longest list, " .. heavy)
end

-- byProfession splits a list of several professions with a pause every 64 entries: the pauses
-- right after reads of such a list weigh 64, which no whole-list pause of it does.
local function testWordGroupsChunksProfessionSplit()
  local ns, db = setup()
  local index = Synthetic.build(ns, db)
  local split = {}
  for _, list in pairs(index.wordIndex) do
    local first = list[1] and list[1].prof
    for _, entry in ipairs(list) do
      if entry.prof ~= first and #list > #split then
        split = list
        break
      end
    end
  end
  local touched, chunks = false, 0
  for k, entry in ipairs(split) do
    split[k] = setmetatable({}, {
      __index = function(_, key)
        touched = true
        return entry[key]
      end,
    })
  end
  ns.WordGroups.Build(index, function(weight)
    if touched and weight == 64 then
      chunks = chunks + 1
    end
    touched = false
  end)
  Assert.truthy(#split > 128 and #split % 64 ~= 0, "the fixture has a long split list, " .. #split)
  Assert.truthy(chunks >= math.floor(#split / 64), "chunk pauses in the split, " .. chunks .. " for " .. #split .. " entries")
end

-- StatSlot.Finish pauses after each stat list it sorts, weighed by the list's length: with
-- several enchanters the sorts alone outlast a tick.
local function testStatSlotSortsPause()
  local ns, db = setup()
  local finish, sorting, weights = ns.StatSlot.Finish, false, {}
  ns.StatSlot.Finish = function(...)
    sorting = true
    finish(...)
    sorting = false
  end
  local index = ns.Index.Build(db, db.settings, {
    ownKey = "Me-Realm",
    professionOrder = function()
      return Synthetic.PROFESSIONS
    end,
    pause = function(weight)
      if sorting then
        weights[#weights + 1] = weight
      end
    end,
  })
  ns.StatSlot.Finish = finish
  local lists, entries, paused = 0, 0, 0
  for _, byStat in pairs(index.statSlotIndex) do
    for _, list in pairs(byStat) do
      lists, entries = lists + 1, entries + #list
    end
  end
  for _, weight in ipairs(weights) do
    paused = paused + weight
  end
  Assert.truthy(lists > 1, "the fixture has stat lists, " .. lists)
  Assert.equal(#weights, lists, "one pause per sorted list")
  Assert.equal(paused, entries, "pauses weighted by the list lengths")
end

-- Before Configure a request starts nothing (Rebuild returns nil there too).
local function testNoJobBeforeConfigure()
  local ns = Fixture.load()
  ns.Index.RequestRebuild("read")
  Assert.equal(ns.Index.lastReason, "read")
  Assert.falsy(ns.Slicer.IsRunning(JOB))
  Assert.equal(#Wow.timers, 0)
  Assert.equal(ns.Index.Current(), nil)
end

return function()
  testSlicedEqualsSync()
  testSecondRequestRestarts()
  testSubscriberRequestRuns()
  testRaisingStepKeepsOldIndex()
  testRebuildCancelsJob()
  testNoJobBeforeConfigure()
  testHeavyWordsYieldOnBudget()
  testWordGroupsPausesWithinList()
  testWordGroupsChunksProfessionSplit()
  testStatSlotSortsPause()
  Wow.reset()
end
