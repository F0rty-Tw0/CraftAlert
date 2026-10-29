local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")
local LookFixture = require("tests.helpers.look_fixture")

-- WhisperBridge.Look asks WM's GetLook on every call and maps a missing, refused, raising or
-- malformed answer to the native look.

local function boot(setup)
  local ns = UiFixture.load({ leads = 1 })
  local api = FakeWm.install()
  if setup then
    setup(api)
  end
  return ns, api
end

local function testLookReadsGetLook()
  local answer = LookFixture.answer("off")
  local reads = 0
  local ns = boot(function(api)
    api.GetLook = function()
      reads = reads + 1
      return answer
    end
  end)
  Assert.equal(ns.WhisperBridge.Look(), ns.PanelLook.NATIVE, "before Activate: no api")
  Assert.equal(reads, 0)
  Assert.equal(ns.WhisperBridge.Activate(), true, "a WM with GetLook still activates")
  local look = ns.WhisperBridge.Look()
  Assert.same({ look.mode, look.colors == answer.colors }, { "flat", true })
  ns.WhisperBridge.Look()
  Assert.equal(reads, 2, "asked on every call")
end

local function testNativeWithoutAnswer()
  local cases = {
    ["no GetLook"] = function(api)
      api.GetLook = nil
    end,
    ["GetLook not a function"] = function(api)
      api.GetLook = "x"
    end,
    ["integration off (false)"] = function(api)
      api.GetLook = function()
        return false
      end
    end,
    ["nil answer"] = function(api)
      api.GetLook = function()
        return nil
      end
    end,
    ["raises"] = function(api)
      api.GetLook = function()
        error("boom")
      end
    end,
    ["bad shape"] = function(api)
      api.GetLook = function()
        return { hud = "off" }
      end
    end,
  }
  for label, setup in pairs(cases) do
    local ns = boot(setup)
    ns.WhisperBridge.Activate()
    Assert.equal(ns.WhisperBridge.Look(), ns.PanelLook.NATIVE, label)
  end
end

local function testVersionCheckUnchanged()
  local ns = boot(function(api)
    api.version = 2
    api.GetLook = function()
      return LookFixture.answer("retail")
    end
  end)
  Assert.equal(ns.WhisperBridge.Activate(), false, "GetLook does not lift the version check")
end

return function()
  testLookReadsGetLook()
  testNativeWithoutAnswer()
  testVersionCheckUnchanged()
  Wow.reset()
end
