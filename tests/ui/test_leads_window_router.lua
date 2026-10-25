local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- SetRouter (WhisperMessenger's panel replaces the own window): a router returning true handles
-- the toggle; false or nil falls through to the own window.
return function()
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
