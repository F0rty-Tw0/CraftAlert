local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Activate names Craft Alert to WM through Connect("CraftAlert") when the shared table has it and the
-- handle is usable; every later call goes through the handle. Anything else keeps the shared table.

local function boot(fakeOpts)
  local ns = UiFixture.load({ leads = 1 })
  local api, wm = FakeWm.install(fakeOpts)
  return ns, api, wm
end

local function testConnectedUsesHandle()
  local ns, _, wm = boot({ connect = true })
  Assert.equal(ns.WhisperBridge.Activate(), true)
  Assert.same(wm.connects, { "CraftAlert" }, "Connect called once with the addon name")
  Assert.equal(#wm.handleCallsTo("RegisterPanel"), 1, "panel registered through the handle")
  ns.WhisperBridge.ShowLead(ns.Leads.List()[1])
  Assert.equal(#wm.handleCallsTo("ShowPreview"), 1)
  for _, name in ipairs({ "RegisterPanel", "ShowPreview", "RefreshPanelBadge", "SetContactInfo" }) do
    Assert.equal(#wm.callsTo(name), #wm.handleCallsTo(name), name .. " only via the handle")
  end
  ns.WhisperBridge.Look()
  Assert.equal(#wm.handleCallsTo("GetLook") > 0, true, "GetLook asked through the handle")
end

local function testNoConnectUsesSharedTable()
  local ns, _, wm = boot()
  Assert.equal(ns.WhisperBridge.Activate(), true)
  Assert.equal(wm.connects, nil)
  Assert.equal(#wm.callsTo("RegisterPanel"), 1)
end

local function testConnectFallsBack()
  local cases = {
    ["nil"] = function()
      return nil
    end,
    ["raises"] = function()
      error("boom")
    end,
    ["version 2"] = function()
      return { version = 2 }
    end,
    ["not a table"] = function()
      return "x"
    end,
  }
  for label, connect in pairs(cases) do
    local ns, api, wm = boot({ connect = true })
    api.Connect = connect
    Assert.equal(ns.WhisperBridge.Activate(), true, label)
    Assert.equal(#wm.callsTo("RegisterPanel"), 1, label)
    Assert.equal(#wm.handleCalls, 0, label .. ": shared table used")
  end

  local ns, api, wm = boot({ connect = true })
  local real = api.Connect
  local function withoutShowPreview(name)
    local handle = real(name)
    handle.ShowPreview = nil
    return handle
  end
  api.Connect = withoutShowPreview
  Assert.equal(ns.WhisperBridge.Activate(), true, "handle missing ShowPreview")
  Assert.equal(#wm.callsTo("RegisterPanel"), 1)
  Assert.equal(#wm.handleCalls, 0, "handle missing ShowPreview: shared table used")
end

local function testUnusableSharedTableNeverConnects()
  local ns, _, wm = boot({ connect = true, version = 2 })
  Assert.equal(ns.WhisperBridge.Activate(), false)
  Assert.same(wm.connects, {}, "Connect not called on a table CraftAlert refuses")
end

return function()
  testConnectedUsesHandle()
  testNoConnectUsesSharedTable()
  testConnectFallsBack()
  testUnusableSharedTableNeverConnects()
  Wow.reset()
end
