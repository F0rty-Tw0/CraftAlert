-- Resettable WoW API stubs for plain-Lua tests and tools/sim.lua.
--   Wow.reset()             restore every stubbed global, then install the defaults below
--   Wow.stub(name, value)   set _G[name] (restored by the next reset)
--   Wow.fireEvent(e, ...)   fire e on every stub frame that registered it
--   Wow.runTimers()         run queued C_Timer.After callbacks (lowest delay first)
--   Wow.pendingTimers(d)    how many queued C_Timer.After callbacks have delay d
--   Wow.secret(v)           wrap v so issecretvalue(wrapper) is true
local Widgets = require("tests.helpers.widgets")

local Wow = {}

local MAX_TIMER_PASSES = 1000

local saved = {}
local secrets = setmetatable({}, { __mode = "k" })

Wow.frames = {}
Wow.timers = {}
Wow.chat = {}
Wow.clock = { gettime = 0, time = 0, profile = 0 }
Wow.combat = false -- what InCombatLockdown() returns

function Wow.stub(name, value)
  if saved[name] == nil then
    saved[name] = { original = rawget(_G, name) }
  end
  rawset(_G, name, value)
end

function Wow.secret(value)
  local wrapper = { value = value }
  secrets[wrapper] = true
  return wrapper
end

-- Frames start shown, as in the client; Widgets adds the region and child-creation methods.
local function newFrame(frameType, name, parent, template)
  local frame = { frameType = frameType, name = name, parent = parent, template = template, events = {}, scripts = {}, hooks = {}, shown = true }
  Widgets.extend(frame)

  function frame:RegisterEvent(event)
    self.events[event] = true
  end

  function frame:UnregisterEvent(event)
    self.events[event] = nil
  end

  function frame:IsEventRegistered(event)
    return self.events[event] == true
  end

  function frame:SetScript(scriptName, fn)
    self.scripts[scriptName] = fn
  end

  function frame:GetScript(scriptName)
    return self.scripts[scriptName]
  end

  function frame:HookScript(scriptName, fn)
    self.hooks[scriptName] = self.hooks[scriptName] or {}
    table.insert(self.hooks[scriptName], fn)
  end

  function frame:Show()
    self.shown = true
  end

  function frame:Hide()
    self.shown = false
  end

  function frame:IsShown()
    return self.shown
  end

  -- Fire(event, ...) runs the OnEvent script as the client would; a no-op unless registered.
  function frame:Fire(event, ...)
    local onEvent = self.scripts.OnEvent
    if self.events[event] and onEvent then
      onEvent(self, event, ...)
    end
  end

  table.insert(Wow.frames, frame)
  if name then
    Wow.stub(name, frame) -- Wow.reset() removes it again
  end
  return frame
end

function Wow.fireEvent(event, ...)
  for _, frame in ipairs(Wow.frames) do
    frame:Fire(event, ...)
  end
end

local function sortedPending()
  table.sort(Wow.timers, function(a, b)
    if a.delay ~= b.delay then
      return a.delay < b.delay
    end
    return a.seq < b.seq
  end)
  return Wow.timers
end

function Wow.runTimers()
  for _ = 1, MAX_TIMER_PASSES do
    local pending = sortedPending()
    if #pending == 0 then
      return
    end
    local timer = table.remove(pending, 1)
    timer.fn()
  end
  error("Wow.runTimers: timers keep re-arming", 2)
end

function Wow.pendingTimers(delay)
  local count = 0
  for _, timer in ipairs(Wow.timers) do
    if timer.delay == delay then
      count = count + 1
    end
  end
  return count
end

local timerSeq = 0
local function installDefaults()
  Wow.stub("CreateFrame", newFrame)
  Wow.stub("UIParent", newFrame("Frame", nil))
  table.remove(Wow.frames) -- UIParent never registers events; keep Wow.frames to the addon's frames
  Wow.stub("C_Timer", {
    After = function(delay, fn)
      timerSeq = timerSeq + 1
      table.insert(Wow.timers, { delay = delay, fn = fn, seq = timerSeq })
    end,
  })
  Wow.stub("GetTime", function()
    return Wow.clock.gettime
  end)
  Wow.stub("time", function()
    return Wow.clock.time
  end)
  Wow.stub("date", os.date) -- WoW's global date() is os.date
  Wow.stub("debugprofilestop", function()
    return Wow.clock.profile
  end)
  Wow.stub("issecretvalue", function(value)
    return secrets[value] == true
  end)
  Wow.stub("InCombatLockdown", function()
    return Wow.combat
  end)
  Wow.stub("DEFAULT_CHAT_FRAME", {
    AddMessage = function(_, text)
      table.insert(Wow.chat, text)
    end,
  })
end

-- Build stubs per flavor key; project ids and TOC numbers come from flavor-choices.md.
local PROJECT_IDS = { mainline = 1, classic = 2, tbc = 5, wrath = 11, cata = 14, mists = 19, camelot = 18 }
local FLAVORS = {
  retail = { project = "mainline", toc = 120105 },
  forever = { project = "camelot", toc = 16001 },
  era = { project = "classic", toc = 11509 },
  tbc = { project = "tbc", toc = 20506 },
  wrath = { project = "wrath", toc = 30403 },
  cata = { project = "cata", toc = 40402 },
  mop = { project = "mists", toc = 50504 },
}

function Wow.isFlavor(key)
  return FLAVORS[key] ~= nil
end

-- Wow.flavor("tbc") stubs WOW_PROJECT_* and GetBuildInfo as that client reports them
-- (WOW_PROJECT_CAMELOT exists on Forever only). Call before loading FlavorCompat.
function Wow.flavor(key)
  local flavor = FLAVORS[key]
  assert(flavor, "unknown flavor " .. tostring(key))
  Wow.stub("WOW_PROJECT_MAINLINE", PROJECT_IDS.mainline)
  Wow.stub("WOW_PROJECT_CLASSIC", PROJECT_IDS.classic)
  Wow.stub("WOW_PROJECT_BURNING_CRUSADE_CLASSIC", PROJECT_IDS.tbc)
  Wow.stub("WOW_PROJECT_WRATH_CLASSIC", PROJECT_IDS.wrath)
  Wow.stub("WOW_PROJECT_CATACLYSM_CLASSIC", PROJECT_IDS.cata)
  Wow.stub("WOW_PROJECT_MISTS_CLASSIC", PROJECT_IDS.mists)
  Wow.stub("WOW_PROJECT_CAMELOT", key == "forever" and PROJECT_IDS.camelot or nil)
  Wow.stub("WOW_PROJECT_ID", PROJECT_IDS[flavor.project])
  Wow.stub("GetBuildInfo", function()
    return "0.0.0", "0", "Jan 1 2026", flavor.toc
  end)
end

function Wow.reset()
  for name, record in pairs(saved) do
    rawset(_G, name, record.original)
  end
  saved = {}
  Wow.frames = {}
  Wow.timers = {}
  Wow.chat = {}
  Wow.clock = { gettime = 0, time = 0, profile = 0 }
  Wow.combat = false
  installDefaults()
end

Wow.reset()

return Wow
