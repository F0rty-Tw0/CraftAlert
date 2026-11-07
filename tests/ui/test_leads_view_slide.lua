local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Compact-window slide spec: the narrow List <-> Details changes slide (UI/ScreenSlide.lua); every
-- other change is the instant swap.
local WIDTH, HEIGHT = 360, 496

local function open(count)
  local ns, _, calls = UiFixture.load({ leads = count })
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(WIDTH, HEIGHT)
  local view = ns.LeadsView.New(host, {
    getHeight = function()
      return HEIGHT
    end,
    getListWidth = function()
      return WIDTH
    end,
  })
  -- The fake does not size an all-points frame; 0 wide would be the instant swap.
  view.frame:SetSize(WIDTH, HEIGHT)
  ns.LeadsView.SetNarrow(view, true)
  ns.LeadsView.Layout(view)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  return ns, view, calls
end

local function refresh(ns, view)
  ns.LeadsView.Layout(view)
  ns.LeadsView.Refresh(view, ns.Leads.List())
end

local function openRow(view, index)
  Widgets.click(view.list.rows[index], "LeftButton")
end

-- The client ends the slide: each pane's group finishes.
local function settle(ns, view)
  for _, pane in ipairs({ view.listPane, view.detailsPane }) do
    local group = ns.ScreenSlide.Group(pane)
    if group and group.playing then
      group:Finish()
    end
  end
end

local function shown(view)
  return { view.listPane:IsShown(), view.detailsPane:IsShown() }
end

local DETAILS_REST = function(view)
  return {
    { "TOPLEFT", view.parent, "TOPLEFT", 0, -20 },
    { "BOTTOMRIGHT", view.parent, "BOTTOMRIGHT", 0, 0 },
  }
end

-- Row click: the list leaves left, the details come in from the right, then the list is hidden.
local function testRowClickSlidesToDetails()
  local ns, view = open(3)
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.ScreenSlide.Group(view.listPane) }, { false }, "opening is instant")
  openRow(view, 2)
  Assert.same({ ns.LeadsView.Screen(view), ns.ScreenSlide.IsSliding(), shown(view) }, { "details", true, { true, true } }, "mid-slide")
  Assert.same(view.detailsPane.points[1], { "TOPLEFT", view.parent, "TOPLEFT", WIDTH, -20 }, "details start at the right")
  settle(ns, view)
  Assert.same({ ns.ScreenSlide.IsSliding(), shown(view), view.frame.clipsChildren }, { false, { false, true }, false })
  Assert.same(view.detailsPane.points, DETAILS_REST(view), "details at rest")
end

-- Back: the details leave right, the list returns from the left at the same offset.
local function testBackSlidesToList()
  local ns, view = open(12)
  ns.LeadsView.Scroll(view, -2)
  openRow(view, 1)
  settle(ns, view)
  ns.LeadsView.Back(view)
  Assert.same({ ns.LeadsView.Screen(view), ns.ScreenSlide.IsSliding(), shown(view) }, { "list", true, { true, true } })
  Assert.same(view.listPane.points[1], { "TOPLEFT", view.parent, "TOPLEFT", -WIDTH, -20 }, "list starts at the left")
  settle(ns, view)
  Assert.same({ shown(view), view.list.offset, view.selectedId }, { { true, false }, 2 })
end

-- Back: the leaving Details keep their lead until the slide ends, then empty.
local function testBackSlidesOutTheShownDetails()
  local ns, view = open(3)
  openRow(view, 2)
  settle(ns, view)
  local lead = view.details.lead
  ns.LeadsView.Back(view)
  refresh(ns, view)
  Assert.same({ view.details.frame:IsShown(), view.details.lead == lead }, { true, true }, "mid-slide")
  settle(ns, view)
  Assert.same({ view.details.frame:IsShown(), view.details.lead }, { false }, "after")
end

-- The leaving Details' buttons do nothing: Greet mid-Back sends nothing and Dismiss keeps the lead.
local function testLeavingDetailsButtonsDoNothing()
  local ns, view, calls = open(3)
  openRow(view, 2)
  settle(ns, view)
  Wow.clock.gettime = 60
  ns.LeadsView.Back(view)
  local sent = #calls
  Widgets.click(view.details.buttons.greet)
  Widgets.click(view.details.buttons.dismiss)
  Assert.same({ #calls - sent, #ns.Leads.List() }, { 0, 3 })
end

-- A row clicked while the Details slide out opens that row's lead; the old slide's end empties nothing.
local function testRowClickMidBackShowsTheClickedLead()
  local ns, view = open(3)
  openRow(view, 2)
  settle(ns, view)
  ns.LeadsView.Back(view)
  openRow(view, 3)
  settle(ns, view)
  Assert.same({ view.details.frame:IsShown(), view.details.lead == view.leads[3] }, { true, true })
end

-- Review Focus 1: no top row during or after the slide to Details; the List counts again on return.
local function testNoTopRowDuringOrAfterTheSlideToDetails()
  local ns, view = open(3)
  Assert.equal(ns.LeadsView.TopRow(view).shownAt, 50)
  openRow(view, 1)
  Assert.equal(ns.LeadsView.TopRow(view), nil, "mid-slide the list rows are still shown")
  settle(ns, view)
  Assert.equal(ns.LeadsView.TopRow(view), nil, "after")
  Wow.clock.gettime = 60
  ns.LeadsView.Back(view)
  Assert.equal(ns.LeadsView.TopRow(view).shownAt, 60, "the rows' OnShow restarted the look time")
end

-- A refresh on the same screen leaves a slide in flight alone.
local function testRefreshMidSlideKeepsIt()
  local ns, view = open(3)
  openRow(view, 2)
  refresh(ns, view)
  Assert.same({ ns.ScreenSlide.IsSliding(), shown(view) }, { true, { true, true } })
end

-- The shown lead leaves: slide back to the List (no jump to the next lead).
local function testShownLeadLeavingSlidesBack()
  local ns, view = open(3)
  openRow(view, 2)
  settle(ns, view)
  ns.Leads.Dismiss(2)
  refresh(ns, view)
  Assert.same({ ns.LeadsView.Screen(view), ns.ScreenSlide.IsSliding(), shown(view) }, { "list", true, { true, true } })
  settle(ns, view)
  Assert.same(shown(view), { true, false })
end

-- Show, width crossings and first paints are never animated; a crossing ends a slide in flight.
local function testResetAndWidthCrossingsAreInstant()
  local ns, view = open(3)
  openRow(view, 2)
  ns.LeadsView.ResetTop(view)
  refresh(ns, view)
  Assert.same({ ns.ScreenSlide.IsSliding(), ns.LeadsView.Screen(view), shown(view) }, { false, "list", { true, false } }, "ResetTop mid-slide")
  openRow(view, 2)
  ns.LeadsView.SetNarrow(view, false)
  refresh(ns, view)
  Assert.same(
    { ns.ScreenSlide.IsSliding(), ns.LeadsView.Screen(view), shown(view), view.frame.clipsChildren },
    { false, "split", { true, true }, false },
    "widening mid-slide"
  )
  Assert.same(view.detailsPane.points, {
    { "TOPLEFT", view.listPane, "TOPRIGHT", 1, 0 },
    { "BOTTOMRIGHT", view.parent, "BOTTOMRIGHT", 0, 0 },
  }, "the details sit right of the list after widening mid-slide")
end

-- A lead arriving on an empty List swaps the empty text for the list at once.
local function testEmptyToLeadsIsInstant()
  local ns, view = open(0)
  ns.LeadsView.Refresh(view, { UiFixture.lead(1) })
  Assert.same({ ns.ScreenSlide.IsSliding(), shown(view), view.empty:IsShown() }, { false, { true, false }, false })
end

-- The last lead leaving the Details slides back to the List, which holds the empty text.
local function testLastLeadLeavingSlidesToTheEmptyList()
  local ns, view = open(1)
  openRow(view, 1)
  settle(ns, view)
  ns.Leads.Dismiss(1)
  refresh(ns, view)
  Assert.same({ ns.LeadsView.Screen(view), ns.ScreenSlide.IsSliding() }, { "list", true })
  settle(ns, view)
  Assert.same({ shown(view), view.empty:IsVisible() }, { { true, false }, true })
end

return function()
  testRowClickSlidesToDetails()
  testBackSlidesToList()
  testBackSlidesOutTheShownDetails()
  testLeavingDetailsButtonsDoNothing()
  testRowClickMidBackShowsTheClickedLead()
  testNoTopRowDuringOrAfterTheSlideToDetails()
  testRefreshMidSlideKeepsIt()
  testShownLeadLeavingSlidesBack()
  testResetAndWidthCrossingsAreInstant()
  testEmptyToLeadsIsInstant()
  testLastLeadLeavingSlidesToTheEmptyList()
  Wow.reset()
end
