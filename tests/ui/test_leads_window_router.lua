local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- SetRouter (WhisperMessenger's panel replaces the own window): a router returning true handles
-- the toggle; false or nil falls through to the own window.
local function testToggleRouter()
  local ns = UiFixture.load({ leads = 1 })
  local routed = 0
  ns.LeadsWindow.SetRouter(function()
    routed = routed + 1
    return true
  end)
  ns.LeadsWindow.Toggle()
  Assert.equal(routed, 1)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "handled: no own window made")
  ns.LeadsWindow.SetRouter(function()
    return false
  end)
  ns.LeadsWindow.Toggle()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true, "false falls through to the own toggle")
  ns.LeadsWindow.SetRouter(nil)
  ns.LeadsWindow.Toggle() -- closes
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), false)
  Wow.reset()
end

-- SetSettingsRouter: the same for /ca config.
local function testSettingsRouter()
  local ns = UiFixture.load({ leads = 1 })
  local routed = 0
  ns.LeadsWindow.SetSettingsRouter(function()
    routed = routed + 1
    return true
  end)
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(routed, 1)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "handled: no own window made")
  ns.LeadsWindow.SetSettingsRouter(function()
    return false
  end)
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true, "false falls through to the own settings")
  ns.LeadsWindow.SetSettingsRouter(nil)
  ns.LeadsWindow.ToggleSettings() -- closes
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), false)
  Wow.reset()
end

return function()
  testToggleRouter()
  testSettingsRouter()
end
