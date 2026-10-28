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

-- Tooltip.ShowHint: gold title, white body, green clicks; the blank line only between a body and
-- clicks. → the tooltip's lines and their colours for (body, clicks).
local function hint(ns, body, clicks)
  local owner = _G["CreateFrame"]("Button", nil, _G["UIParent"])
  ns.Tooltip.ShowHint(owner, "ANCHOR_TOP", "Title", body, clicks)
  local tooltip = ns.Tooltip.Get()
  Assert.same({ tooltip.owner, tooltip.anchor, tooltip:IsShown() }, { owner, "ANCHOR_TOP", true })
  return tooltip.lines, tooltip.colors
end

local function testShowHint()
  local ns = UiFixture.load()
  local gold, white, green = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.1, 1, 0.1 }
  local lines, colors = hint(ns, { "a", "b" }, { "Click: c" })
  Assert.same(lines, { "Title", "a", "b", " ", "Click: c" })
  Assert.same(colors, { gold, white, white, {}, green })
  lines, colors = hint(ns, nil, { "Click: c", "Drag: d" })
  Assert.same(lines, { "Title", "Click: c", "Drag: d" }, "no body: no blank line")
  Assert.same(colors, { gold, green, green })
  lines, colors = hint(ns, { "a" })
  Assert.same(lines, { "Title", "a" }, "no clicks: no blank line")
  Assert.same(colors, { gold, white })
  Assert.same(hint(ns, {}, {}), { "Title" }, "empty lists: title only")
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
  testShowHint()
  testSettingsGearLeave()
  testToastLeave()
  testLauncherLeave()
  Wow.reset()
end
