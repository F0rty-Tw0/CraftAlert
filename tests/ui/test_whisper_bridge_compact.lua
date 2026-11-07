local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- WhisperBridge.IsCompactWindow asks WM's IsCompactWindow on every call; only a true answer counts,
-- so a missing, malformed, refused or raising WM falls back to the width rule (false).

local function boot(setup)
  local ns = UiFixture.load({ leads = 1 })
  local api, wm = FakeWm.install()
  if setup then
    setup(api, wm)
  end
  return ns, api, wm
end

local function testFollowsWmAnswer()
  local ns, _, wm = boot()
  Assert.equal(ns.WhisperBridge.IsCompactWindow(), false, "before Activate: no api")
  Assert.equal(ns.WhisperBridge.Activate(), true)
  Assert.equal(ns.WhisperBridge.IsCompactWindow(), false, "WM answers false")
  wm.compact = true
  Assert.equal(ns.WhisperBridge.IsCompactWindow(), true, "WM answers true, asked again")
  Assert.same(wm.callsTo("IsCompactWindow"), {}, "not recorded in wm.calls")
end

local function testFalseWithoutAnswer()
  local cases = {
    ["no IsCompactWindow"] = function(api)
      api.IsCompactWindow = nil
    end,
    ["IsCompactWindow not a function"] = function(api, wm)
      wm.compact = true
      api.IsCompactWindow = "x"
    end,
    ["raises"] = function(_, wm)
      wm.compact = true
      wm.raise.IsCompactWindow = true
    end,
    ["refused"] = function(_, wm)
      wm.compact = true
      wm.refuse.IsCompactWindow = true
    end,
    ["truthy but not true"] = function(api)
      api.IsCompactWindow = function()
        return "yes"
      end
    end,
  }
  for label, setup in pairs(cases) do
    local ns = boot(function(api, wm)
      wm.compact = true
      setup(api, wm)
    end)
    ns.WhisperBridge.Activate()
    Assert.equal(ns.WhisperBridge.IsCompactWindow(), false, label)
  end
end

return function()
  testFollowsWmAnswer()
  testFalseWithoutAnswer()
  Wow.reset()
end
