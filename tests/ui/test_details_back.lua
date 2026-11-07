local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local DetailsFixture = require("tests.helpers.details_fixture")

local PAD = DetailsFixture.PAD
local NAME_LEFT = PAD + 36 + 10
local BACK_SIZE, BACK_LEFT = 32, 8 -- SPACE.XXL, SPACE.S
local open, itemLead = DetailsFixture.open, DetailsFixture.itemLead

-- A copy of a region's anchors (SetPoint rewrites the entries in place).
local function pts(region)
  local out = {}
  for index, anchor in ipairs(region.points) do
    out[index] = { unpack(anchor) }
  end
  return out
end

local function headerLayout(d)
  return { pts(d.icon), pts(d.name), pts(d.lineOne), pts(d.lineTwo), d.name:GetWidth() }
end

local function testNoButtonByDefault()
  local ns, d = open({ itemLead() })
  Assert.equal(d.back, nil, "no button until asked")
  Assert.same(pts(d.icon), { { "LEFT", d.header, "LEFT", PAD, 0 } })
  Assert.same(pts(d.name), { { "TOPLEFT", d.header, "TOPLEFT", NAME_LEFT, -8 } })
  local before = headerLayout(d)
  ns.LeadDetails.SetBack(d, nil)
  Assert.same(headerLayout(d), before, "SetBack(nil) on a fresh pane changes nothing")
  Assert.equal(d.back, nil, "and builds nothing")
end

local function testBackShiftsTheHeader()
  local ns, d = open({ itemLead() })
  local clicks = 0
  ns.LeadDetails.SetBack(d, function()
    clicks = clicks + 1
  end)
  local back = d.back
  Assert.same({ back.parent, back:IsShown(), back:GetWidth(), back:GetHeight() }, { d.header, true, BACK_SIZE, BACK_SIZE })
  Assert.same(pts(back), { { "LEFT", d.header, "LEFT", BACK_LEFT, 0 } })
  Assert.same(pts(d.icon)[1], { "LEFT", d.header, "LEFT", PAD + BACK_SIZE, 0 })
  Assert.same(pts(d.name)[1], { "TOPLEFT", d.header, "TOPLEFT", NAME_LEFT + BACK_SIZE, -8 })
  Assert.same(pts(d.lineOne)[1], { "TOPLEFT", d.name, "BOTTOMLEFT", 0, -3 }, "the lines follow the name")
  Widgets.click(back)
  Assert.equal(clicks, 1)
  -- Art only: the shared back arrow, no tooltip, no text (so no new string).
  Assert.equal(back.normal.atlas, ns.Theme.ART.BACK_ATLAS)
  Assert.equal(back:GetNormalTexture(), back.normal)
  Assert.equal(back.scripts.OnEnter, nil, "no tooltip")
  Assert.equal(back.label, nil, "no text")
end

local function testNilRestoresTodaysHeader()
  local ns, d, _, lead = open({ itemLead() })
  local before = headerLayout(d)
  local clicks = 0
  ns.LeadDetails.SetBack(d, function()
    clicks = clicks + 1
  end)
  local back = d.back
  ns.LeadDetails.SetBack(d, nil)
  Assert.same(headerLayout(d), before, "icon, name and lines back where they were")
  Assert.equal(back:IsShown(), false)
  Widgets.click(back)
  Assert.equal(clicks, 0, "a hidden arrow's callback is gone")
  ns.LeadDetails.SetBack(d, function() end)
  Assert.equal(d.back, back, "the button is reused")
  ns.LeadDetails.Show(d, lead)
  Assert.same(pts(d.name)[1], { "TOPLEFT", d.header, "TOPLEFT", NAME_LEFT + BACK_SIZE, -8 }, "a later Show keeps the shift")
end

local function testNameFitsBesideBack()
  local ns, d, _, lead = open({ itemLead() })
  lead.customer = "Telchiness-Kazzak" -- 102 px of text
  ns.LeadDetails.Show(d, lead)
  ns.LeadDetails.Layout(d, 150)
  Assert.equal(d.name:GetWidth(), 150 - NAME_LEFT - PAD, "without the arrow")
  ns.LeadDetails.SetBack(d, function() end)
  Assert.equal(d.name:GetWidth(), 150 - NAME_LEFT - BACK_SIZE - PAD, "the arrow takes its room from the name")
  ns.LeadDetails.SetBack(d, nil)
  Assert.equal(d.name:GetWidth(), 150 - NAME_LEFT - PAD, "and gives it back")
end

-- Narrow Details: the arrow is Back to the List; wide again: gone.
local function testNarrowDetailsArrowReturnsToList()
  local ns = UiFixture.load({ leads = 3 })
  local host = _G["CreateFrame"]("Frame")
  host:SetSize(360, 496)
  local view = ns.LeadsView.New(host, {
    getHeight = function()
      return 496
    end,
    getListWidth = function()
      return 360
    end,
  })
  ns.LeadsView.SetNarrow(view, true)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Widgets.click(view.list.rows[2], "LeftButton")
  Assert.equal(ns.LeadsView.Screen(view), "details")
  Assert.equal(view.details.back:IsShown(), true, "the arrow shows on Details")
  Widgets.click(view.details.back)
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Assert.equal(view.selectedId, nil, "Back clears the selection")
  ns.LeadsView.SetNarrow(view, false)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Assert.equal(view.details.back:IsShown(), false, "the split view has no arrow")
  Assert.same(pts(view.details.icon), { { "LEFT", view.details.header, "LEFT", PAD, 0 } }, "and today's header")
end

return function()
  testNoButtonByDefault()
  testBackShiftsTheHeader()
  testNilRestoresTodaysHeader()
  testNameFitsBesideBack()
  testNarrowDetailsArrowReturnsToList()
  Wow.reset()
end
