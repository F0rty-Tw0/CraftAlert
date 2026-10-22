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
  local index = indexOf(entry.name) -- nil when the step cancelled its own job
  if not ok then
    Slicer.Cancel(entry.name)
    EventRouter.ReportError(result)
  elseif index and result == true then
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
