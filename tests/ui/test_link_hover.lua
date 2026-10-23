local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local ITEM, TRADE = "item:19019::::::::60", "trade:Player-1-0A:2018:164"

local function setup(withBody)
  local ns = UiFixture.load()
  local frame = rawget(_G, "CreateFrame")("Button", nil, rawget(_G, "UIParent"))
  local body = {}
  local function record(f)
    body[#body + 1] = f
  end
  ns.LinkHover.Attach(frame, withBody and record or nil)

  return ns, frame, rawget(_G, "GameTooltip"), body
end

local function enter(frame, link)
  frame.scripts.OnHyperlinkEnter(frame, link, "[text]")
end

local function testEnterLeave()
  local ns, frame, tip, body = setup(true)
  Assert.equal(frame.hyperlinksEnabled, true)
  enter(frame, ITEM)
  Assert.equal(ns.LinkHover.IsOverLink(frame), true)
  Assert.same({ tip.owner, tip.anchor, tip.shown, tip.hyperlinks }, { frame, "ANCHOR_CURSOR", true, { ITEM } })
  -- Leave with the cursor still on the frame brings the body tooltip back.
  frame.mouseOver = true
  frame.scripts.OnHyperlinkLeave(frame)
  Assert.same({ ns.LinkHover.IsOverLink(frame), tip.shown, body }, { false, false, { frame } })
  -- Leave with the cursor gone does not.
  enter(frame, ITEM)
  frame.mouseOver = false
  frame.scripts.OnHyperlinkLeave(frame)
  Assert.equal(#body, 1)
end

-- Off a link after another frame took the tooltip (a client's leave can come after the next enter):
-- that frame's tooltip stays.
local function testLeaveKeepsOtherTip()
  local ns, frame, tip = setup(false)
  enter(frame, ITEM)
  tip:SetOwner(rawget(_G, "UIParent"), "ANCHOR_TOP")
  tip:Show()
  frame.scripts.OnHyperlinkLeave(frame)
  Assert.same({ ns.LinkHover.IsOverLink(frame), tip.shown }, { false, true })
end

local function testTradeAndFailure()
  local _, frame, tip = setup(false)
  enter(frame, TRADE)
  Assert.same({ frame.hoveredLink, tip.shown, tip.hyperlinks }, { TRADE, false, {} })
  -- SetHyperlink raising: the tooltip shows the link text.
  tip.badLinks = { [ITEM] = true }
  enter(frame, ITEM)
  Assert.same({ tip.shown, tip.lines }, { true, { ITEM } })
  frame.scripts.OnHyperlinkLeave(frame)
  Assert.equal(tip.shown, false)
end

local function testClickAndClear()
  local ns, frame, tip = setup(false)
  frame.scripts.OnHyperlinkClick(frame, ITEM, "[Belt]", "LeftButton")
  Assert.same(Wow.itemRefs, { { ITEM, "[Belt]", "LeftButton", frame } })
  Wow.stub("SetItemRef", nil)
  frame.scripts.OnHyperlinkClick(frame, ITEM, "[Belt]", "LeftButton") -- no function: no error
  -- OnLeave and OnHide hooks clear the hovered link and the tooltip the frame owns.
  enter(frame, ITEM)
  Widgets.fire(frame, "OnLeave")
  Assert.same({ ns.LinkHover.IsOverLink(frame), tip.shown }, { false, false })
  enter(frame, ITEM)
  frame:Hide()
  Assert.same({ ns.LinkHover.IsOverLink(frame), tip.shown }, { false, false })
  -- A tooltip another frame owns stays up.
  enter(frame, ITEM)
  tip:SetOwner(rawget(_G, "UIParent"), "ANCHOR_TOP")
  tip:Show()
  ns.LinkHover.Clear(frame)
  Assert.same({ frame.hoveredLink, tip.shown }, { nil, true })
end

return function()
  testEnterLeave()
  testLeaveKeepsOtherTip()
  testTradeAndFailure()
  testClickAndClear()
  Wow.reset()
end
