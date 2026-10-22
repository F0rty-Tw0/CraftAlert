local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local ChatPrint = ns.ChatPrint or require("CraftAlert.Core.ChatPrint")
local Index = ns.Index or require("CraftAlert.Model.Index")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local Slicer = ns.Slicer or require("CraftAlert.Core.Slicer")
local ModernReader = ns.ModernReader or require("CraftAlert.Professions.ModernReader")

-- Spec §4.4 `/ca perf`: times each chat line through a handler that replaces ScanGate's
-- (ScanGate.SetHandler), so with perf off the hot path holds no timing call at all. The
-- periodic report is printed from inside the timed handler (no timer, §4.3 rule 1).
local Perf = {}

-- Milliseconds of login work, the saved-variable load and the PLAYER_LOGIN installs (Bootstrap
-- sets it), shown in every report.
Perf.loginMs = nil

local ADDON = "CraftAlert"
local REPORT_INTERVAL_MS = 60000
local MICROSECONDS_PER_MS = 1000
-- Matcher.lastStop before each line: the Matcher is not reached for a channel the gate drops,
-- and a stale "match" would count that line as a matched one.
local NO_MATCH = "nomatch"
local MATCH = "match"

local running = false
---@type fun(): number
local clock = nil -- debugprofilestop, read when perf starts
local lastReportAt = 0
local startMemory = nil
-- Lines that stopped before a lead (the hot path, steps 1-4) and lines that matched
-- (steps 5-7 included): count, total and longest, in ms.
local lines, linesTotal, linesMax = 0, 0, 0
local matched, matchedTotal, matchedMax = 0, 0, 0

-- "Lines 2, mean 20.0 us, max 30.0 us"; the counts alone for no lines. Times arrive in ms.
local function timing(countOnly, withTimes, count, total, longest)
  if count == 0 then
    return Localization.Text(countOnly, 0)
  end
  return Localization.Text(withTimes, count, total / count * MICROSECONDS_PER_MS, longest * MICROSECONDS_PER_MS)
end

local function millis(value)
  return value and Localization.Text("%.1f ms", value) or Localization.Text("n/a")
end

-- "Login 42.0 ms, index build 12.5 ms, last read 12.5 ms in 4 steps, background 7 steps in 10
-- ticks, longest 9.3 ms." — shown in every report. No read yet (or Classic): "last read n/a in 0 steps".
local function setupText()
  local read = ModernReader.lastRead
  local stats = Slicer.stats
  return Localization.Text(
    "Login %s, index build %s, last read %s in %d steps, background %d steps in %d ticks, longest %s.",
    millis(Perf.loginMs),
    millis(Index.lastBuildMs),
    millis(read and read.ms),
    read and read.steps or 0,
    stats.steps,
    stats.ticks,
    millis(stats.longestTickMs)
  )
end

local function linesText()
  local hotPath = timing("Lines %d", "Lines %d, mean %.1f us, max %.1f us", lines, linesTotal, linesMax)
  local matches = timing("Matched %d", "Matched %d, mean %.1f us, max %.1f us", matched, matchedTotal, matchedMax)
  return Localization.Text("%s. %s.", hotPath, matches)
end

local function report()
  ChatPrint.Line(Localization.Text("Perf: %s %s", linesText(), setupText()))
end

-- The timed stand-in for ScanGate.HandleChat. No table or closure is made per line.
local function timedHandler(event, ...)
  Matcher.lastStop = NO_MATCH
  local started = clock()
  ScanGate.HandleChat(event, ...)
  local finished = clock()
  local elapsed = finished - started
  if Matcher.lastStop == MATCH then
    matched, matchedTotal = matched + 1, matchedTotal + elapsed
    matchedMax = elapsed > matchedMax and elapsed or matchedMax
  else
    lines, linesTotal = lines + 1, linesTotal + elapsed
    linesMax = elapsed > linesMax and elapsed or linesMax
  end
  if finished - lastReportAt >= REPORT_INTERVAL_MS then
    lastReportAt = finished
    report()
  end
end

function Perf.IsRunning()
  return running
end

-- Starts timing (no-op while running): swaps the chat handler, prints one notice. The memory is
-- read first: if that raises, perf stays off with HandleChat in place.
function Perf.Start()
  if running then
    return
  end
  startMemory = FlavorCompat.GetAddOnMemoryUsage(ADDON)
  clock = _G["debugprofilestop"]
  lastReportAt = clock()
  lines, linesTotal, linesMax = 0, 0, 0
  matched, matchedTotal, matchedMax = 0, 0, 0
  Slicer.ResetStats()
  running = true
  ScanGate.SetHandler(timedHandler)
  local notice = Localization.Text("Perf on: timing each chat line, a report every 60 s. /ca perf again stops it.")
  if startMemory then
    notice = notice .. " " .. Localization.Text("Memory %.1f KB.", startMemory)
  end
  ChatPrint.Line(notice)
end

-- Stops timing (no-op when off): HandleChat is back, the totals and the memory change print.
function Perf.Stop()
  if not running then
    return
  end
  running = false
  ScanGate.SetHandler(nil)
  local endMemory = FlavorCompat.GetAddOnMemoryUsage(ADDON)
  local text = Localization.Text("Perf off: %s %s", linesText(), setupText())
  if startMemory and endMemory then
    text = text .. " " .. Localization.Text("Memory %.1f KB to %.1f KB.", startMemory, endMemory)
  end
  ChatPrint.Line(text)
end

ns.Perf = Perf
return Perf
