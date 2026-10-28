local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")

-- Spec 2026-10-22-crafter-quality-rank §4.1: named jobs { step = fn() -> done, onCancel } run
-- a little per frame on one C_Timer.After(0) chain. A step over BUDGET_MS becomes debt that
-- idle ticks pay back, so the average stays at BUDGET_MS per frame.
local Slicer = {}

local pcall = pcall
local max = math.max

local BUDGET_MS = 2

Slicer.BUDGET_MS = BUDGET_MS
Slicer.stats = { ticks = 0, steps = 0, longestTickMs = 0 }

local entries = {} -- { name, job } in start order; names are unique
local cursor = 1 -- the entry that runs next, so a slow job can't starve the one after it
local debt = 0
local tickPending = false
local waitingForCombat = false

local function indexOf(name)
  for i = 1, #entries do
    if entries[i].name == name then
      return i
    end
  end
  return nil
end

local function remove(index)
  table.remove(entries, index)
  if index < cursor then
    cursor = cursor - 1
  end
  if cursor > #entries then
    cursor = 1
  end
end

function Slicer.IsRunning(name)
  return indexOf(name) ~= nil
end

function Slicer.Cancel(name)
  local index = indexOf(name)
  if index == nil then
    return
  end
  local job = entries[index].job
  remove(index)
  if job.onCancel then
    job.onCancel()
  end
end

local function runStep()
  local entry = entries[cursor]
  cursor = cursor % #entries + 1
  Slicer.stats.steps = Slicer.stats.steps + 1
  local ok, result = pcall(entry.job.step)
  local index = indexOf(entry.name)
  -- A step that cancelled or restarted its own job leaves its replacement (or nothing) here.
  local ownEntry = index ~= nil and entries[index] == entry
  if not ok then
    if ownEntry then
      Slicer.Cancel(entry.name)
    end
    EventRouter.ReportError(result)
  elseif ownEntry and result == true then
    remove(index)
  end
end

local function runSteps()
  local clock = _G["debugprofilestop"]
  local started = clock()
  local spent
  repeat
    runStep()
    spent = clock() - started
  until #entries == 0 or spent >= BUDGET_MS
  return spent
end

local tick

local function schedule()
  if not tickPending then
    tickPending = true
    _G["C_Timer"].After(0, tick)
  end
end

local function onRegenEnabled()
  EventRouter.Off("PLAYER_REGEN_ENABLED", onRegenEnabled)
  waitingForCombat = false
  if #entries > 0 then
    schedule()
  end
end

tick = function()
  tickPending = false
  if #entries == 0 then
    return
  end
  local lockdown = _G["InCombatLockdown"]
  if type(lockdown) == "function" and lockdown() == true then
    waitingForCombat = true
    EventRouter.On("PLAYER_REGEN_ENABLED", onRegenEnabled)
    return
  end
  local stats = Slicer.stats
  stats.ticks = stats.ticks + 1
  if debt > 0 then
    debt = max(0, debt - BUDGET_MS)
  else
    local spent = runSteps()
    debt = max(0, spent - BUDGET_MS)
    stats.longestTickMs = max(stats.longestTickMs, spent)
  end
  if #entries > 0 then
    schedule()
  end
end

function Slicer.Start(name, job)
  Slicer.Cancel(name)
  entries[#entries + 1] = { name = name, job = job }
  if not waitingForCombat then
    schedule()
  end
end

-- A job that runs work(pause) in a coroutine, as Index's sliced build does: pause(weight) yields
-- once BUDGET_MS has passed since the step began (the clock is read when the weights add up to
-- PAUSE_EVERY). When work returns, onDone gets what it returned; it may start a job of the
-- same name, which runs on. Pause only in plain Lua loop bodies: never in a sort comparator, a
-- gsub callback or under pcall (Lua 5.1 cannot yield across those). A cancelled job is never
-- resumed; onCancel (optional) runs instead. → { ms, steps }: the CPU ms spent in the work and
-- the steps it took so far, final by the time onDone runs.
local PAUSE_EVERY = 8

function Slicer.Run(name, work, onDone, onCancel)
  local clock = _G["debugprofilestop"]
  local resumedAt, weightSum = 0, 0
  local run = { ms = 0, steps = 0 }
  local function pause(weight)
    weightSum = weightSum + (weight or 1)
    if weightSum >= PAUSE_EVERY then
      weightSum = 0
      if clock() - resumedAt >= BUDGET_MS then
        coroutine.yield()
      end
    end
  end
  local thread = coroutine.create(function()
    return work(pause)
  end)
  local function finish(ok, ...)
    run.ms, run.steps = run.ms + (clock() - resumedAt), run.steps + 1
    if not ok then
      local stack = _G["debugstack"]
      local err = ...
      error(type(stack) == "function" and tostring(err) .. "\n" .. stack(thread) or err, 0)
    end
    if coroutine.status(thread) ~= "dead" then
      return false
    end
    onDone(...)
    return true
  end
  Slicer.Start(name, {
    step = function()
      resumedAt = clock()
      return finish(coroutine.resume(thread))
    end,
    onCancel = onCancel,
  })
  return run
end

-- The pause for work that runs outside a sliced job: never yields.
function Slicer.NoPause() end

-- Tests and tools/sim.lua only: runs every job to the end, ignoring budget and debt.
function Slicer.Drain()
  while #entries > 0 do
    runStep()
  end
end

function Slicer.ResetStats()
  Slicer.stats.ticks, Slicer.stats.steps, Slicer.stats.longestTickMs = 0, 0, 0
end

ns.Slicer = Slicer
return Slicer
