local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- The gear with a gold "Settings" label WhisperMessenger's panel puts on its ledger line: the gear's
-- art and ADD highlight stay 20 x 20 at the left (the client stretches a state texture over the
-- whole button on assignment), the label turns white on hover.

local function build()
  local ns = UiFixture.load()
  local clicked = false
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  local link = ns.SettingsGear.BuildLabeled(parent, function()
    clicked = true
  end)
  return ns, link, function()
    return clicked
  end
end

local function testLayout()
  local ns, link = build()
  Assert.equal(link.label:GetText(), "Settings")
  Assert.same(link.label.textColor, ns.Theme.COLORS.gold)
  Assert.same({ link:GetWidth(), link:GetHeight() }, { 72, 20 }, "20 + 4 + 8 characters * 6 px")
  Assert.same(link.normal.points, { { "LEFT", link, "LEFT", 0, 0 } })
  Assert.same(link.highlight.points, { { "LEFT", link, "LEFT", 0, 0 } })
  Assert.same({ link.normal:GetWidth(), link.normal:GetHeight() }, { 20, 20 })
  Assert.same({ link.highlight:GetWidth(), link.highlight:GetHeight() }, { 20, 20 }, "lights the gear only")
  Assert.equal(link:GetHighlightTexture().blendMode, "ADD")
  Assert.equal(link:GetNormalTexture().atlas, "QuestLog-icon-setting")
  Assert.same(link.label.points, { { "LEFT", link.normal, "RIGHT", 4, 0 } })
end

local function testHoverAndClick()
  local ns, link, clicked = build()
  Widgets.fire(link, "OnEnter")
  Assert.same(link.label.textColor, ns.Theme.COLORS.white)
  Assert.equal(ns.Tooltip.Get().owner, link)
  Widgets.fire(link, "OnLeave")
  Assert.same(link.label.textColor, ns.Theme.COLORS.gold)
  Assert.equal(ns.Tooltip.Get():IsShown(), false)
  Widgets.click(link)
  Assert.equal(clicked(), true)
end

return function()
  testLayout()
  testHoverAndClick()
  Wow.reset()
end
