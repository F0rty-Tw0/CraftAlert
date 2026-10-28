local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function newRouter()
  Wow.reset()
  return Fresh.require("Core.EventRouter")
end

local function routerFrame()
  return Wow.frames[#Wow.frames]
end

local function testRegistersOnlyWhileHandlersExist()
  local EventRouter = newRouter()
  Assert.equal(#Wow.frames, 0, "no frame before the first handler")

  local function first() end
  local function second() end
  EventRouter.On("PLAYER_LOGIN", first)
  EventRouter.On("PLAYER_LOGIN", second)
  Assert.equal(#Wow.frames, 1)
  Assert.truthy(routerFrame():IsEventRegistered("PLAYER_LOGIN"))
  Assert.falsy(routerFrame():IsEventRegistered("PLAYER_UPDATE_RESTING"))

  EventRouter.Off("PLAYER_LOGIN", first)
  Assert.truthy(routerFrame():IsEventRegistered("PLAYER_LOGIN"), "one handler left")
  EventRouter.Off("PLAYER_LOGIN", second)
  Assert.falsy(routerFrame():IsEventRegistered("PLAYER_LOGIN"), "last Off unregisters")

  EventRouter.Off("PLAYER_LOGIN", second) -- already gone: no error
  EventRouter.Off("NEVER_SEEN", first)
end

local function testDispatchOrderAndArguments()
  local EventRouter = newRouter()
  local seen = {}
  EventRouter.On("CHAT_MSG_SYSTEM", function(...)
    seen[#seen + 1] = "a:" .. table.concat({ ... }, ",")
  end)
  EventRouter.On("CHAT_MSG_SYSTEM", function(...)
    seen[#seen + 1] = "b:" .. table.concat({ ... }, ",")
  end)

  EventRouter.Dispatch("CHAT_MSG_SYSTEM", "x", "y")
  Assert.same(seen, { "a:x,y", "b:x,y" })

  seen = {}
  Wow.fireEvent("CHAT_MSG_SYSTEM", "from", "frame")
  Assert.same(seen, { "a:from,frame", "b:from,frame" }, "the frame's OnEvent dispatches")

  EventRouter.Dispatch("UNHANDLED_EVENT", 1) -- no handlers: nothing happens
end

local function testSameHandlerRegistersOnce()
  local EventRouter = newRouter()
  local calls = 0
  local function handler()
    calls = calls + 1
  end
  EventRouter.On("PLAYER_LOGIN", handler)
  EventRouter.On("PLAYER_LOGIN", handler)
  EventRouter.Dispatch("PLAYER_LOGIN")
  Assert.equal(calls, 1)
end

local function testChangesDuringDispatch()
  local EventRouter = newRouter()
  local seen = {}
  local function late()
    seen[#seen + 1] = "late"
  end
  local function second()
    seen[#seen + 1] = "second"
  end
  local function first()
    seen[#seen + 1] = "first"
    EventRouter.Off("ZONE_CHANGED", first)
    EventRouter.On("ZONE_CHANGED", late)
  end
  EventRouter.On("ZONE_CHANGED", first)
  EventRouter.On("ZONE_CHANGED", second)

  EventRouter.Dispatch("ZONE_CHANGED")
  Assert.same(seen, { "first", "second" }, "removing or adding mid-dispatch skips nobody and runs nothing new")
  seen = {}
  EventRouter.Dispatch("ZONE_CHANGED")
  Assert.same(seen, { "second", "late" })
end

local function testFailingHandlerDoesNotBlockOthers()
  local EventRouter = newRouter()
  local reported = {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      reported[#reported + 1] = err
    end
  end)
  local ran = false
  EventRouter.On("PLAYER_LOGIN", function()
    error("boom", 0)
  end)
  EventRouter.On("PLAYER_LOGIN", function()
    ran = true
  end)

  EventRouter.Dispatch("PLAYER_LOGIN")
  Assert.truthy(ran)
  Assert.same(reported, { "boom" })
  -- Bootstrap reports its own failed steps the same way.
  EventRouter.ReportError("step failed")
  Assert.same(reported, { "boom", "step failed" })

  -- Without an error handler (bare tests) the error surfaces.
  Wow.stub("geterrorhandler", nil)
  Assert.raises(function()
    EventRouter.Dispatch("PLAYER_LOGIN")
  end, "boom")
  Assert.raises(function()
    EventRouter.ReportError("step failed")
  end, "step failed")
end

-- CallAll (Leads, Ledger, Index and ScanGate listeners): every function gets the arguments, in
-- order; one that raises is reported and the rest still run.
local function testCallAll()
  local EventRouter = newRouter()
  local reported, seen = {}, {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      reported[#reported + 1] = err
    end
  end)
  local list = {
    function(a, b)
      seen[#seen + 1] = "first " .. a .. b
    end,
    function()
      error("listener broke", 0)
    end,
    function(a, b)
      seen[#seen + 1] = "third " .. a .. b
    end,
  }

  EventRouter.CallAll(list, "x", "y")
  Assert.same(seen, { "first xy", "third xy" })
  Assert.same(reported, { "listener broke" })
  EventRouter.CallAll({})
  Assert.same(reported, { "listener broke" }, "an empty list calls nothing")

  -- A nil in the middle and no arguments at all (Leads' "change", Ledger) pass through as given.
  local counts = {}
  local countArgs = {
    function(...)
      counts[#counts + 1] = select("#", ...)
    end,
  }
  EventRouter.CallAll(countArgs, nil, "b")
  EventRouter.CallAll(countArgs)
  Assert.same(counts, { 2, 0 })
end

local function testFailedRegisterKeepsNoHandler()
  local EventRouter = newRouter()
  local failing = true
  local createFrame = rawget(_G, "CreateFrame")
  Wow.stub("CreateFrame", function(...)
    local frame = createFrame(...)
    local register = frame.RegisterEvent
    function frame:RegisterEvent(event)
      if failing then
        error('Attempt to register unknown event "' .. event .. '"')
      end
      return register(self, event)
    end
    return frame
  end)
  local function handler() end

  Assert.raises(function()
    EventRouter.On("CLUB_STREAM_ADDED", handler)
  end, "unknown event")
  failing = false
  EventRouter.On("CLUB_STREAM_ADDED", handler)
  Assert.truthy(routerFrame():IsEventRegistered("CLUB_STREAM_ADDED"), "retry registers")
end

return function()
  testRegistersOnlyWhileHandlersExist()
  testFailedRegisterKeepsNoHandler()
  testDispatchOrderAndArguments()
  testSameHandlerRegistersOnce()
  testChangesDuringDispatch()
  testFailingHandlerDoesNotBlockOthers()
  testCallAll()
  Wow.reset()
end
