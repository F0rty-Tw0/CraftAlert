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

-- Open (the away summary's left-click, spec §7.6): the window on the list, never closed by it;
-- SetOpenRouter (WhisperMessenger's ShowPanel) goes first; nothing in an instance.
local function testOpen()
  local ns = UiFixture.load({ leads = 1 })
  local routed = 0
  ns.LeadsWindow.SetOpenRouter(function()
    routed = routed + 1
    return true
  end)
  ns.LeadsWindow.Open()
  Assert.equal(routed, 1)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "handled: no own window made")
  ns.LeadsWindow.SetOpenRouter(nil)
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.LeadsWindow.Open()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "nothing in an instance")
  Wow.stub("IsInInstance", nil)
  ns.LeadsWindow.Open()
  local frame = rawget(_G, "CraftAlertLeadsWindow")
  Assert.equal(frame:IsShown(), true)
  ns.LeadsWindow.Open()
  Assert.equal(frame:IsShown(), true, "open, never a toggle")
  ns.LeadsWindow.ToggleSettings()
  ns.LeadsWindow.Open()
  Assert.same({ frame:IsShown(), frame:GetTitleText():GetText() }, { true, "Craft Alert — Leads" }, "from the settings to the list")
  Wow.reset()
end

return function()
  testToggleRouter()
  testSettingsRouter()
  testOpen()
end
