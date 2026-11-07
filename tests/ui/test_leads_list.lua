local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- The list half of the split view (UI/LeadsList.lua): rows and bar sit two frame levels above
-- the pane they live in, wherever the pane is when they are made or drawn (a narrow
-- WhisperMessenger window lifts the host, and the pane with it, after the list was built).
local PANE_LEVEL, LIFTED_LEVEL, ABOVE_PANE = 7, 66, 2
local FIT = 5

-- A list on a pane at PANE_LEVEL, and one lead to show. → ns, list, pane
local function open()
  local ns = UiFixture.load({ leads = 1 })
  local pane = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  pane:SetSize(300, 400)
  pane:SetFrameLevel(PANE_LEVEL)
  local list = ns.LeadsList.New(pane, function() end, function() end)
  return ns, list, pane
end

local function testRowsMadeAfterThePaneMovedSitTwoAboveIt()
  local ns, list, pane = open()
  pane:SetFrameLevel(LIFTED_LEVEL)
  ns.LeadsList.Refresh(list, ns.Leads.List(), FIT, nil)
  Assert.equal(list.rows[1]:GetFrameLevel(), LIFTED_LEVEL + ABOVE_PANE, "a row made after the lift")
end

local function testRowsMadeBeforeThePaneMovedFollowIt()
  local ns, list, pane = open()
  ns.LeadsList.Refresh(list, ns.Leads.List(), FIT, nil)
  Assert.equal(list.rows[1]:GetFrameLevel(), PANE_LEVEL + ABOVE_PANE, "a row made before the lift")
  pane:SetFrameLevel(LIFTED_LEVEL)
  ns.LeadsList.Refresh(list, ns.Leads.List(), FIT, nil)
  Assert.equal(list.rows[1]:GetFrameLevel(), LIFTED_LEVEL + ABOVE_PANE, "the same row after the lift")
end

local function testBarFollowsThePane()
  local ns, list, pane = open()
  pane:SetFrameLevel(LIFTED_LEVEL)
  ns.LeadsList.Refresh(list, ns.Leads.List(), FIT, nil)
  Assert.equal(list.bar:GetFrameLevel(), LIFTED_LEVEL + ABOVE_PANE, "the bar after the lift")
end

return function()
  testRowsMadeAfterThePaneMovedSitTwoAboveIt()
  testRowsMadeBeforeThePaneMovedFollowIt()
  testBarFollowsThePane()
  Wow.reset()
end
