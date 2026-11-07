local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local function build()
  local ns = UiFixture.load()
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  local clicks = 0
  local header = ns.PageHeader.New(parent, function()
    clicks = clicks + 1
  end)
  return ns, header, function()
    return clicks
  end
end

local function testBackArrowHasNoTextAndNoTooltip()
  local ns, header = build()
  local back = header.back
  Assert.equal(back:GetNormalTexture().atlas, ns.Theme.ART.BACK_ATLAS, "the shared back arrow")
  Assert.same({ back:GetWidth(), back:GetHeight(), header:GetHeight() }, { 20, 20, 28 }, "sizes")
  Assert.equal(back:GetScript("OnEnter"), nil, "no tooltip")
  Assert.equal(back.label, nil, "no text")
  Assert.equal(header.pageHeader, true, "marked for SettingsFixture.pageHeader")
end

local function testLayoutAndClick()
  local _, header, clicks = build()
  Assert.same(header.back.points, { { "LEFT", header, "LEFT", 8, 0 } }, "arrow at the left")
  Assert.same(header.title.points[1], { "LEFT", header.back, "RIGHT", 8, 0 }, "title right of the arrow")
  Assert.same(header.title.points[2], { "RIGHT", header, "RIGHT", -8, 0 }, "title ends 8 px before the edge")
  Widgets.click(header.back)
  Assert.equal(clicks(), 1, "the arrow runs onBack once")
end

return function()
  testBackArrowHasNoTextAndNoTooltip()
  testLayoutAndClick()
  Wow.reset()
end
