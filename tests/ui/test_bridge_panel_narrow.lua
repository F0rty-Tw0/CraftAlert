local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Phone-style slide spec: Craft Alert opts in to WM's narrow window and decides narrow vs wide from
-- its host's width (narrow below LIST_MIN_WIDTH + DETAILS_MIN_WIDTH = 520).
local function boot(opts)
  local ns, db, calls = UiFixture.load(opts or { leads = 3 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, db, calls, wm
end

local function testBuildOptsInToCompact()
  local ns = boot()
  Assert.equal(ns.BridgePanel.Build().compact, true)
end

local function testRegisteredPanelCarriesCompact()
  local _, _, _, wm = boot()
  Assert.equal(wm.registered[1][2].compact, true, "WM is handed the flag at RegisterPanel")
end

return function()
  testBuildOptsInToCompact()
  testRegisteredPanelCarriesCompact()
  Wow.reset()
end
