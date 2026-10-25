local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- The addon's one tooltip (UI/Tooltip.lua) is shared by every frame: leaving a frame hides it only
-- while that frame owns it. One another frame took since (the client sends OnLeave late, or after
-- the next frame's OnEnter) stays.

-- Enters `frame`, hands the tooltip to another frame, then leaves `frame`. → the tooltip, the other
local function leaveAfterAnotherTook(ns, frame)
  local tooltip = ns.Tooltip.Get()
  local other = _G["CreateFrame"]("Button", nil, _G["UIParent"])
  Widgets.fire(frame, "OnEnter")
  tooltip:SetOwner(other, "ANCHOR_RIGHT")
  tooltip:Show()
  Widgets.fire(frame, "OnLeave")
  return tooltip, other
end

local function testHideIfOwned()
  local ns = UiFixture.load()
  local tooltip = ns.Tooltip.Get()
  local mine, other = _G["CreateFrame"]("Button"), _G["CreateFrame"]("Button")
  tooltip:SetOwner(other, "ANCHOR_RIGHT")
  tooltip:Show()
  ns.Tooltip.HideIfOwned(mine)
  Assert.equal(tooltip:IsShown(), true, "another owner: kept")
  ns.Tooltip.HideIfOwned(other)
  Assert.equal(tooltip:IsShown(), false, "its owner: hidden")
end

local function testSettingsGearLeave()
  local ns = UiFixture.load()
  ns.LeadsWindow.Toggle()
  local tooltip, other = leaveAfterAnotherTook(ns, rawget(_G, "CraftAlertLeadsWindow").gear)
  Assert.same({ tooltip:IsShown(), tooltip.owner }, { true, other })
end

local function testToastLeave()
  local ns = UiFixture.load({ leads = 1 })
  ns.AlertToast.Show(ns.Leads.Latest())
  local tooltip, other = leaveAfterAnotherTook(ns, rawget(_G, "CraftAlertToast"))
  Assert.same({ tooltip:IsShown(), tooltip.owner }, { true, other })
end

local function testLauncherLeave()
  local ns = UiFixture.load({ leads = 1 })
  local tooltip, other = leaveAfterAnotherTook(ns, ns.Launcher.Create())
  Assert.same({ tooltip:IsShown(), tooltip.owner }, { true, other })
end

return function()
  testHideIfOwned()
  testSettingsGearLeave()
  testToastLeave()
  testLauncherLeave()
  Wow.reset()
end
