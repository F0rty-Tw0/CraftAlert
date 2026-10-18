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

  -- Without an error handler (bare tests) the error surfaces.
  Wow.stub("geterrorhandler", nil)
  Assert.raises(function()
    EventRouter.Dispatch("PLAYER_LOGIN")
  end, "boom")
end

return function()
  testRegistersOnlyWhileHandlersExist()
  testDispatchOrderAndArguments()
  testSameHandlerRegistersOnce()
  testChangesDuringDispatch()
  testFailingHandlerDoesNotBlockOthers()
  Wow.reset()
end
