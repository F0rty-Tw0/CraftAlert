local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Compact-window slide spec: LeadsView in a narrow host shows the List or the Details, one at a time.
local WIDTH, HEIGHT, PADDING = 360, 496, 8

-- A narrow view over `count` leads (ids 1..count, the list newest first), on its List.
-- size.listWidth is what BridgePanel's getListWidth gives: the host's width while narrow.
local function open(count, width)
  local ns = UiFixture.load({ leads = count })
  local host = _G["CreateFrame"]("Frame")
  host:SetSize(width or WIDTH, HEIGHT)
  local size = { listWidth = width or WIDTH }
  local view = ns.LeadsView.New(host, {
    getHeight = function()
      return HEIGHT
    end,
    getListWidth = function()
      return size.listWidth
    end,
  })
  ns.LeadsView.SetNarrow(view, true)
  ns.LeadsView.Layout(view)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  return ns, view, size
end

local function refresh(ns, view)
  ns.LeadsView.Layout(view)
  ns.LeadsView.Refresh(view, ns.Leads.List())
end

local function seenIds(ns)
  local ids = {}
  for _, lead in ipairs(ns.Leads.List()) do
    if lead.seen then
      ids[#ids + 1] = lead.id
    end
  end
  return ids
end

local function openRow(view, index)
  Widgets.click(view.list.rows[index], "LeftButton")
end

local function testStartsOnListWithNothingSelected()
  local ns, view = open(3)
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Assert.equal(view.selectedId, nil)
  Assert.equal(view.details.lead, nil)
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown(), view.divider:IsShown() }, { true, false, false })
  Assert.same({ view.listPane:GetWidth(), view.list.compact }, { WIDTH, false })
  Assert.same(seenIds(ns), {}, "opening the list marks nothing seen")
end

-- Rows stay full-size even when the narrow host is under LIST_MIN_WIDTH.
local function testRowsStayFullInATinyHost()
  local _, view = open(3, 150)
  Assert.same({ view.listPane:GetWidth(), view.list.compact }, { 150, false })
end

-- List + row left-clicked: Details of that lead, full width, that lead seen.
local function testRowClickOpensDetailsAndMarksThatLeadSeen()
  local ns, view = open(3)
  openRow(view, 2)
  Assert.equal(ns.LeadsView.Screen(view), "details")
  Assert.same({ view.selectedId, view.details.lead.id }, { 2, 2 })
  Assert.same(seenIds(ns), { 2 })
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { false, true })
  Assert.equal(view.details.width, WIDTH, "the details take the full width")
  Assert.same(view.detailsPane.points, {
    { "TOPLEFT", view.parent, "TOPLEFT", 0, -20 },
    { "BOTTOMRIGHT", view.parent, "BOTTOMRIGHT", 0, 0 },
  })
end

-- Review Focus 2: List + leads change (a new lead, an expiry, a greeting) refreshes the list and
-- marks no lead seen; the screen stays List.
local function testListRefreshMarksNothingSeen()
  local ns, view = open(3)
  local arrived = { UiFixture.lead(4) }
  for _, lead in ipairs(ns.Leads.List()) do
    arrived[#arrived + 1] = lead
  end
  ns.LeadsView.Refresh(view, arrived)
  Assert.same({ view.list.rows[1].lead.id, ns.LeadsView.Screen(view) }, { 4, "list" })
  ns.Leads.Dismiss(2)
  ns.Leads.MarkGreeted(3)
  refresh(ns, view)
  Assert.same({ seenIds(ns), view.selectedId, view.details.lead }, { {} })
  Assert.equal(ns.Leads.CountUnseen(ns.Leads.List()), 1, "the badge: lead 1 is the only one neither greeted nor seen")
end

-- List + mouse wheel: the list scrolls.
local function testWheelOnTheListScrollsTheList()
  local ns, view = open(12)
  view.frame.scripts.OnMouseWheel(view.frame, -1)
  Assert.same({ view.list.offset, ns.LeadsView.Screen(view) }, { 1, "list" })
end

-- Details + back: List at the same offset, selection cleared. Back elsewhere does nothing.
local function testBackKeepsTheOffsetAndClearsTheSelection()
  local ns, view = open(12)
  ns.LeadsView.Back(view)
  Assert.equal(ns.LeadsView.Screen(view), "list", "Back on the List is a no-op")
  ns.LeadsView.Scroll(view, -2)
  openRow(view, 1)
  Assert.equal(view.selectedId, 10, "the row at offset 2 is lead 10")
  ns.LeadsView.Back(view)
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Assert.equal(view.list.offset, 2)
  Assert.equal(view.selectedId, nil)
  Assert.equal(view.details.lead, nil)
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { true, false })
end

-- Details + the shown lead edited in place: repaint, stay, keep the look time.
local function testEditedInPlaceRepaintsAndStays()
  local ns, view = open(3)
  openRow(view, 1)
  local lead = view.details.lead
  Wow.clock.gettime = 60
  lead.customer = "Renamed-Draenor"
  refresh(ns, view)
  Assert.same({ ns.LeadsView.Screen(view), view.details.shownAt }, { "details", 50 })
  Assert.truthy(string.find(view.details.name:GetText(), "Renamed", 1, true), "the header repainted")
end

-- Details + the shown lead leaves: List, no jump to the next lead, nothing else marked seen.
local function testShownLeadLeavesGoesToList()
  local ns, view = open(3)
  openRow(view, 2)
  ns.Leads.Dismiss(2)
  refresh(ns, view)
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Assert.equal(view.selectedId, nil)
  Assert.equal(view.details.lead, nil)
  Assert.same(seenIds(ns), {}, "the next lead is not marked seen (lead 2 is gone)")
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { true, false })
end

-- Details + other leads change: the details stay as they were.
local function testOtherLeadsChangeIsIgnoredInDetails()
  local ns, view = open(3)
  openRow(view, 2)
  Wow.clock.gettime = 60
  ns.Leads.Dismiss(3)
  refresh(ns, view)
  Assert.same({ ns.LeadsView.Screen(view), view.details.lead.id, view.details.shownAt }, { "details", 2, 50 })
  Assert.same(seenIds(ns), { 2 })
end

-- Review Focus 4: Details + mouse wheel scrolls the details body, not the hidden list; on the List
-- the same wheel scrolls the list.
local function testWheelOnDetailsScrollsTheBody()
  local ns, view = open(12)
  openRow(view, 1)
  local scroll = view.details.scroll
  local boxHeight = view.details.body:GetHeight() - 60
  scroll.box:SetSize(300, boxHeight)
  Widgets.fire(scroll.box, "OnSizeChanged", 300, boxHeight)
  view.frame.scripts.OnMouseWheel(view.frame, -1)
  Assert.same({ scroll.frame:GetVerticalScroll(), view.list.offset }, { 24, 0 })
  ns.LeadsView.Back(view)
  view.frame.scripts.OnMouseWheel(view.frame, -1)
  Assert.equal(view.list.offset, 1, "back on the List the wheel scrolls the list")
end

-- Review Focus 1 (view side): no list row counts as shown on Details; the rows' look time restarts
-- when the List returns.
local function testNoTopRowOnDetailsAndShownAtRestarts()
  local ns, view = open(3)
  Assert.equal(ns.LeadsView.TopRow(view).shownAt, 50)
  openRow(view, 1)
  Assert.equal(ns.LeadsView.TopRow(view), nil)
  Wow.clock.gettime = 60
  ns.LeadsView.Back(view)
  Assert.equal(ns.LeadsView.TopRow(view).shownAt, 60)
end

local function widen(ns, view, size)
  size.listWidth = 260
  ns.LeadsView.SetNarrow(view, false)
  refresh(ns, view)
end

-- Host grows while Details shows a lead: the split view keeps that lead selected.
local function testWideningFromDetailsKeepsTheLead()
  local ns, view, size = open(3)
  openRow(view, 2)
  widen(ns, view, size)
  Assert.equal(ns.LeadsView.Screen(view), "split")
  Assert.same({ view.selectedId, view.details.lead.id }, { 2, 2 })
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown(), view.divider:IsShown() }, { true, true, true })
  Assert.equal(view.listPane:GetWidth(), 260)
  Assert.same(view.detailsPane.points[1], { "TOPLEFT", view.listPane, "TOPRIGHT", 1, 0 })
end

-- Host grows while the List shows: today's rule, the newest lead selected and seen.
local function testWideningFromListSelectsAndSeesTheNewest()
  local ns, view, size = open(3)
  widen(ns, view, size)
  Assert.same({ view.selectedId, view.details.lead.id }, { 3, 3 })
  Assert.same(seenIds(ns), { 3 })
end

-- Host shrinks: List, selection cleared.
local function testNarrowingGoesToListAndClearsTheSelection()
  local ns, view, size = open(3)
  widen(ns, view, size)
  Assert.equal(view.selectedId, 3)
  size.listWidth = WIDTH
  ns.LeadsView.SetNarrow(view, true)
  refresh(ns, view)
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Assert.equal(view.selectedId, nil)
  Assert.equal(view.details.lead, nil)
  Assert.same({ view.listPane:GetWidth(), view.detailsPane:IsShown() }, { WIDTH, false })
end

-- The ledger line spans the full width: counts from the left edge, "Clear all" left of the right
-- end, counts cut before it; wide puts both back.
local function testLedgerAndClearAllPlacement()
  local ns, view, size = open(3)
  local strip, clearAll = view.strip, view.clearAll
  Assert.equal(strip.leftEdge, nil)
  Assert.same(clearAll.points, { { "BOTTOMRIGHT", strip, "BOTTOMRIGHT", -PADDING, 0 } })
  Assert.same(strip.text.points, {
    { "LEFT", strip, "LEFT", PADDING, 0 },
    { "RIGHT", strip, "RIGHT", -(PADDING + clearAll:GetWidth() + PADDING), 0 },
  })
  Assert.equal(clearAll:IsShown(), true)
  widen(ns, view, size)
  Assert.equal(strip.leftEdge, view.listPane)
  Assert.same(clearAll.points, { { "BOTTOMRIGHT", view.listPane, "TOPRIGHT", -PADDING, 0 } })
  Assert.equal(strip.extraInset, 0)
end

-- No leads on the List: the List stays, its pane holding the empty text (not a blank page); a lead
-- swaps the text for its row.
local function testEmptyListSaysSo()
  local ns, view = open(0)
  Assert.equal(ns.LeadsView.Screen(view), "list")
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { true, false })
  Assert.same({ view.empty:GetParent(), view.empty:IsVisible() }, { view.listPane, true })
  local inset = ns.Theme.LAYOUT.PANE_PADDING
  Assert.same(view.empty.text.points, {
    { "LEFT", view.listPane, "LEFT", inset, 0 },
    { "RIGHT", view.listPane, "RIGHT", -inset, 0 },
  })
  ns.LeadsView.Refresh(view, { UiFixture.lead(1) })
  Assert.same({ view.empty:IsShown(), view.listPane:IsShown(), view.detailsPane:IsShown() }, { false, true, false })
end

-- The empty text follows the mode: the details pane while wide, the list pane while narrow.
local function testEmptyTextMovesWithTheMode()
  local ns, view, size = open(0)
  widen(ns, view, size)
  Assert.same({ view.empty:GetParent(), view.empty:GetFrameLevel(), view.empty:IsVisible() }, {
    view.detailsPane,
    view.detailsPane:GetFrameLevel() + 2,
    true,
  })
  size.listWidth = WIDTH
  ns.LeadsView.SetNarrow(view, true)
  refresh(ns, view)
  Assert.same({ view.empty:GetParent(), view.empty:GetFrameLevel(), view.empty:IsVisible() }, {
    view.listPane,
    view.listPane:GetFrameLevel() + 2,
    true,
  })
end

return function()
  testStartsOnListWithNothingSelected()
  testRowsStayFullInATinyHost()
  testRowClickOpensDetailsAndMarksThatLeadSeen()
  testListRefreshMarksNothingSeen()
  testWheelOnTheListScrollsTheList()
  testBackKeepsTheOffsetAndClearsTheSelection()
  testEditedInPlaceRepaintsAndStays()
  testShownLeadLeavesGoesToList()
  testOtherLeadsChangeIsIgnoredInDetails()
  testWheelOnDetailsScrollsTheBody()
  testNoTopRowOnDetailsAndShownAtRestarts()
  testWideningFromDetailsKeepsTheLead()
  testWideningFromListSelectsAndSeesTheNewest()
  testNarrowingGoesToListAndClearsTheSelection()
  testLedgerAndClearAllPlacement()
  testEmptyListSaysSo()
  testEmptyTextMovesWithTheMode()
  Wow.reset()
end
