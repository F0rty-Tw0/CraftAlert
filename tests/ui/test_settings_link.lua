local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- The gold "Settings" link WhisperMessenger's panel puts on its ledger line: the label alone, no
-- gear; the label turns white on hover.

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
  Assert.same({ link:GetWidth(), link:GetHeight() }, { 48, 20 }, "label width only: 8 characters * 6 px")
  Assert.same(link.label.points, { { "LEFT", link, "LEFT", 0, 0 } })
end

local function testNoGearArt()
  local ns, link = build()
  Assert.equal(link.normal, nil)
  Assert.equal(link.highlight, nil)
  Assert.equal(link:GetNormalTexture(), nil)
  Assert.equal(link:GetHighlightTexture(), nil)
  for _, region in ipairs(link.regions) do
    Assert.equal(region.SetAtlas, nil, "only the label is drawn")
  end
  -- The standalone title-bar gear keeps its art.
  local gear = ns.SettingsGear.Build(_G["CreateFrame"]("Frame", nil, _G["UIParent"]), function() end)
  Assert.equal(gear:GetNormalTexture().atlas, "QuestLog-icon-setting")
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
  testNoGearArt()
  testHoverAndClick()
  Wow.reset()
end
