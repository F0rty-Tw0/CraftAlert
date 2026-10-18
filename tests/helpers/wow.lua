-- Resettable WoW API stubs for plain-Lua tests and tools/sim.lua.
--   Wow.reset()             restore every stubbed global, then install the defaults below
--   Wow.stub(name, value)   set _G[name] (restored by the next reset)
--   Wow.fireEvent(e, ...)   fire e on every stub frame that registered it
--   Wow.runTimers()         run queued C_Timer.After callbacks (lowest delay first)
--   Wow.secret(v)           wrap v so issecretvalue(wrapper) is true
local Wow = {}

local MAX_TIMER_PASSES = 1000

local saved = {}
local secrets = setmetatable({}, { __mode = "k" })

Wow.frames = {}
Wow.timers = {}
Wow.chat = {}
Wow.clock = { gettime = 0, time = 0, profile = 0 }

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

local function newFrame(frameType, name)
  local frame = { frameType = frameType, name = name, events = {}, scripts = {}, hooks = {}, shown = false }

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
    rawset(_G, name, frame)
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

local timerSeq = 0
local function installDefaults()
  Wow.stub("CreateFrame", newFrame)
  Wow.stub("UIParent", newFrame("Frame", nil))
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
  Wow.stub("debugprofilestop", function()
    return Wow.clock.profile
  end)
  Wow.stub("issecretvalue", function(value)
    return secrets[value] == true
  end)
  Wow.stub("DEFAULT_CHAT_FRAME", {
    AddMessage = function(_, text)
      table.insert(Wow.chat, text)
    end,
  })
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
  installDefaults()
end

Wow.reset()

return Wow
