local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec A.2, A.3, assumption 2: the split view in a bare host the size of the default window's
-- content frame (840 x 560 less the 4 / 6 sides and the 60 / 4 top and bottom). The list pane
-- with 48 px rows on the left, the details pane on the right, each over its own inset art, and
-- the selection rules: newest first, kept by id across refreshes, moved to the lead now at its
-- place when it leaves.
local WIDTH, HEIGHT = 830, 496
local LIST_ATLAS, DETAILS_ATLAS = "Professions-background-summarylist", "auctionhouse-background-index"

-- The fixture with `count` leads (ids 1..count, newest last) and a view over a bare host; the
-- host's height and list width are read through `size`. → ns, the view, the sends, size.
local function open(count)
  local ns, _, calls = UiFixture.load({ leads = count })
  local host = _G["CreateFrame"]("Frame")
  host:SetSize(WIDTH, HEIGHT)
  local size = { height = HEIGHT, listWidth = 260 }
  local view = ns.LeadsView.New(host, {
    getHeight = function()
      return size.height
    end,
    getListWidth = function()
      return size.listWidth
    end,
  })
  return ns, view, calls, size
end

local function shownRows(view)
  local shown = {}
  for _, row in ipairs(view.list.rows) do
    if row:IsShown() then
      shown[#shown + 1] = row
    end
  end
  return shown
end

local function ids(leads)
  local list = {}
  for _, lead in ipairs(leads) do
    list[#list + 1] = lead.id
  end
  return list
end

-- Leads newest first, as Leads.List() gives them: ids from `from` down to 1.
local function leadsDown(from)
  local list = {}
  for id = from, 1, -1 do
    list[#list + 1] = UiFixture.lead(id)
  end
  return list
end

local function testStructure()
  local ns, view = open(0)
  local list, details = view.listPane, view.detailsPane
  Assert.same({ list.bg.atlas, list.bg.blendMode, list.bg.layer }, { LIST_ATLAS, "BLEND", "BACKGROUND" })
  Assert.same({ details.bg.atlas, details.bg.blendMode }, { DETAILS_ATLAS, "BLEND" })
  Assert.same(list.bg.points, { { "ALL", list } })
  Assert.equal(list:GetWidth(), 260)
  Assert.same(list.points, { { "TOPLEFT", view.frame:GetParent(), "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", view.frame:GetParent(), "BOTTOMLEFT", 0, 0 } })
  Assert.same(details.points, { { "TOPLEFT", list, "TOPRIGHT", 1, 0 }, { "BOTTOMRIGHT", view.frame:GetParent(), "BOTTOMRIGHT", 0, 0 } })
  Assert.same(view.frame.points, { { "ALL", view.frame:GetParent() } })
  for _, pane in ipairs({ list, details }) do
    Assert.same({ pane.art.template, pane.art.parent, pane.art.points }, { "InsetFrameTemplate", pane, { { "ALL", pane } } })
    Assert.equal(pane.art:GetFrameLevel(), pane:GetFrameLevel() + 1, "the inset art above the pane's background")
    Assert.equal(pane.art.Bg.shown, false, "the inset's marble hidden so the atlas shows")
  end
  Assert.equal(view.details.frame:GetFrameLevel(), details:GetFrameLevel() + 2, "the details above the inset art")
  Assert.same({ view.list.empty.parent, view.list.empty:GetFrameLevel() }, { list, list:GetFrameLevel() + 2 })
  -- The divider sits in the 1 px gap between the panes, on the root (the panes' insets would cover it).
  local divider = view.divider
  Assert.same({ divider.parent, divider.layer, divider:GetWidth(), divider.color }, { view.frame, "BORDER", 1, ns.Theme.COLORS.divider })
  Assert.same(divider.points, { { "TOPLEFT", list, "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", list, "BOTTOMRIGHT", 0, 0 } })
  -- Rows over the inset art too.
  ns.LeadsView.Refresh(view, leadsDown(2))
  Assert.equal(view.list.rows[1]:GetFrameLevel(), list:GetFrameLevel() + 2)
  Assert.equal(view.frame.scripts.OnUpdate, nil)
end

-- Classic flavors: the atlases are unknown, the panes keep no fill and the inset's own Bg.
local function testNoAtlas()
  local ns, _, calls = UiFixture.load({ leads = 0 })
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      return nil
    end,
  })
  local host = _G["CreateFrame"]("Frame")
  host:SetSize(WIDTH, HEIGHT)
  local view = ns.LeadsView.New(host, {
    getHeight = function()
      return HEIGHT
    end,
    getListWidth = function()
      return 260
    end,
  })
  for _, pane in ipairs({ view.listPane, view.detailsPane }) do
    Assert.equal(pane.bg.atlas, nil)
    Assert.equal(pane.art.Bg.shown ~= false, true, "the inset's Bg kept when no atlas paints")
  end
  ns.LeadsView.Refresh(view, leadsDown(3))
  Assert.same({ #shownRows(view), ns.LeadsView.Selected(view).id }, { 3, 3 })
  Assert.equal(#calls, 0)
end

local function testLayout()
  local ns, view, _, size = open(0)
  local before = view.detailsPane.points
  Assert.equal(view.details.buttons.greet:GetWidth(), 100)
  size.listWidth = 180
  ns.LeadsView.Layout(view)
  Assert.equal(view.listPane:GetWidth(), 180)
  Assert.same(view.detailsPane.points, before)
  -- An unsized host (GetWidth 0) leaves the details' buttons at full width.
  view.frame:GetParent():SetSize(0, 0)
  ns.LeadsView.Layout(view)
  Assert.equal(view.details.buttons.greet:GetWidth(), 100)
  -- A narrow host: (300 - 180 - 1 - 32 - 16) / 3.
  view.frame:GetParent():SetSize(300, HEIGHT)
  ns.LeadsView.Layout(view)
  Assert.equal(view.details.buttons.greet:GetWidth(), (300 - 180 - 1 - 48) / 3)
end

local function testFit()
  local ns, view, _, size = open(0)
  Assert.same({ ns.LeadsList.Fit(496), ns.LeadsList.Fit(356), ns.LeadsList.Fit(0), ns.LeadsList.Fit(-50) }, { 10, 7, 0, 0 })
  local leads = leadsDown(12)
  ns.LeadsView.Refresh(view, leads)
  local rows = shownRows(view)
  Assert.equal(#rows, 10)
  Assert.same(rows[2].points, { { "TOPLEFT", view.listPane, "TOPLEFT", 2, -52 }, { "TOPRIGHT", view.listPane, "TOPRIGHT", -4, -52 } })
  Assert.same(rows[1].points[1], { "TOPLEFT", view.listPane, "TOPLEFT", 2, -4 })
  Assert.same({ rows[1].lead, rows[10].lead }, { leads[1], leads[10] })
  size.height = 356
  ns.LeadsView.Refresh(view, leads)
  Assert.equal(#shownRows(view), 7)
  size.height = 0
  ns.LeadsView.Refresh(view, leads)
  Assert.equal(#shownRows(view), 0)
  -- A huge height is bounded by the leads, not looped over.
  size.height = 1e300
  ns.LeadsView.Refresh(view, leadsDown(2))
  Assert.same({ #shownRows(view), #view.list.rows }, { 2, 10 })
end

local function testEmpty()
  local ns, view = open(0)
  ns.LeadsView.Refresh(view, leadsDown(2))
  ns.LeadsView.Refresh(view, {})
  local empty = view.list.empty
  Assert.same({ empty:IsShown(), empty.text:GetText() }, { true, "No leads right now. Requests you can craft show up here." })
  Assert.same({ empty.text.font, empty.text.textColor }, { ns.Theme.FONTS.body, ns.Theme.COLORS.textSecondary })
  Assert.same(empty.text.points, { { "CENTER", empty, "CENTER", 0, 0 } })
  Assert.same({ view.details.frame:IsShown(), view.details.lead }, { false, nil })
  Assert.same({ ns.LeadsView.TopRow(view), ns.LeadsView.Selected(view), #shownRows(view) }, { nil, nil, 0 })
  ns.LeadsView.Refresh(view, leadsDown(1))
  Assert.equal(empty:IsShown(), false)
end

-- Selection starts on the newest lead and the details show it.
local function testNewestSelected()
  local ns, view = open(0)
  local leads = leadsDown(3)
  ns.LeadsView.Refresh(view, leads)
  Assert.same({ ns.LeadsView.Selected(view), view.selectedId, view.details.lead }, { leads[1], 3, leads[1] })
  Assert.same({ view.list.rows[1].selected:IsShown(), view.list.rows[2].selected:IsShown() }, { true, false })
end

-- Review Focus 1: a lead arriving while another is selected keeps the selection on that lead (by
-- id); the new lead takes the top row and the details keep their look time.
local function testArrivalKeepsSelection()
  local ns, view = open(0)
  local leads = leadsDown(3)
  ns.LeadsView.Refresh(view, leads)
  local selected = ns.LeadsView.Selected(view)
  Wow.clock.gettime = 60
  local arrived = UiFixture.lead(4)
  ns.LeadsView.Refresh(view, { arrived, leads[1], leads[2], leads[3] })
  Assert.same({ ns.LeadsView.Selected(view), view.details.lead, view.details.shownAt }, { selected, selected, 50 })
  Assert.equal(ns.LeadsView.TopRow(view).lead, arrived)
  local rows = shownRows(view)
  Assert.same({ rows[1].selected:IsShown(), rows[2].selected:IsShown(), rows[2].lead }, { false, true, selected })
  -- By id, not by record: a fresh copy of the selected lead keeps it selected.
  ns.LeadsView.Refresh(view, leadsDown(4))
  Assert.equal(ns.LeadsView.Selected(view).id, 3)
end

-- Review Focus 2: the selected lead leaves (dismissed, expired) → the lead now at its place, else
-- the new last, else none; the action bar never acts on the gone lead.
local function testSelectedLeaves()
  local ns, view, calls = open(5)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Widgets.click(view.list.rows[2], "LeftButton")
  local gone = ns.LeadsView.Selected(view)
  Assert.same({ ids(ns.Leads.List()), gone.id }, { { 5, 4, 3, 2, 1 }, 4 })
  ns.Leads.Dismiss(gone.id)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Assert.same({ ns.LeadsView.Selected(view).id, view.details.lead.id }, { 3, 3 })
  Assert.equal(view.list.rows[2].selected:IsShown(), true)
  -- Greet right after the switch: the look rule refuses the send and prefills the new lead's
  -- customer, never the gone one.
  Widgets.click(view.details.buttons.greet)
  local prefills = UiFixture.callsTo(calls, "prefill")
  Assert.same({ #UiFixture.callsTo(calls, "chat"), #prefills, prefills[1][2], gone.greeted }, { 0, 1, "Customer3-Draenor", false })
  -- The last lead selected and dismissed: the new last.
  Widgets.click(view.list.rows[4], "LeftButton")
  Assert.equal(ns.LeadsView.Selected(view).id, 1)
  ns.Leads.Dismiss(1)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Assert.equal(ns.LeadsView.Selected(view).id, 2)
  -- All gone: nothing selected, the details empty, Greet and Dismiss do nothing.
  for _, lead in ipairs(ns.Leads.List()) do
    ns.Leads.Dismiss(lead.id)
  end
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Assert.same({ ns.LeadsView.Selected(view), view.selectedId, view.details.lead, view.details.frame:IsShown() }, { nil, nil, nil, false })
  Wow.clock.gettime = 60
  local sent = #calls
  Widgets.click(view.details.buttons.greet)
  Widgets.click(view.details.buttons.dismiss)
  Assert.equal(#calls, sent)
  -- A lead arriving after that is selected as the newest.
  ns.LeadsView.Refresh(view, leadsDown(1))
  Assert.equal(ns.LeadsView.Selected(view).id, 1)
end

-- The wheel scrolls by one row and clamps; a selected row scrolled away stays selected.
local function testScroll()
  local ns, view = open(0)
  local leads = leadsDown(12)
  ns.LeadsView.Refresh(view, leads)
  ns.LeadsView.Scroll(view, -3)
  Assert.same({ view.list.offset, shownRows(view)[1].lead.id }, { 2, 10 })
  Assert.same({ ns.LeadsView.Selected(view).id, view.details.lead.id, ns.LeadsView.TopRow(view) }, { 12, 12, nil })
  for _, row in ipairs(shownRows(view)) do
    Assert.equal(row.selected:IsShown(), false)
  end
  ns.LeadsView.ResetTop(view)
  ns.LeadsView.Refresh(view, leads)
  local wheel = view.frame.scripts.OnMouseWheel
  wheel(view.frame, -1)
  Assert.same({ view.list.offset, shownRows(view)[1].lead.id }, { 1, 11 })
  wheel(view.frame, -1)
  wheel(view.frame, -1)
  Assert.equal(view.list.offset, 2, "clamped at the oldest")
  for _ = 1, 4 do
    wheel(view.frame, 1)
  end
  Assert.same({ view.list.offset, ns.LeadsView.TopRow(view).lead.id }, { 0, 12 }, "clamped at the top")
  -- Scrolling back brings the selected row's mark back.
  Assert.equal(view.list.rows[1].selected:IsShown(), true)
end

-- A left click selects the row's lead (no send); the right click is the row's own dismiss.
local function testClicks()
  local ns, view, calls = open(5)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Wow.clock.gettime = 55
  local row = view.list.rows[3]
  Widgets.click(row, "LeftButton")
  Assert.same({ ns.LeadsView.Selected(view), view.details.lead, view.details.shownAt }, { row.lead, row.lead, 55 })
  Assert.same({ row.selected:IsShown(), view.list.rows[1].selected:IsShown(), #calls }, { true, false, 0 })
  local id = row.lead.id
  Wow.clock.gettime = 56
  Widgets.click(row, "RightButton")
  Assert.equal(ns.Leads.IsActive(id), false)
end

-- Reopen: ResetTop, Clear, Refresh → the newest selected at the top, every time fresh.
local function testReopen()
  local ns, view = open(5)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Widgets.click(view.list.rows[3], "LeftButton")
  ns.LeadsView.Scroll(view, -1)
  ns.LeadsView.Clear(view)
  Assert.same({ #shownRows(view), view.list.empty:IsShown(), view.details.frame:IsShown(), view.selectedId }, { 0, false, false, 3 })
  ns.LeadsView.ResetTop(view)
  Assert.same({ view.list.offset, view.selectedId }, { 0, nil })
  Wow.clock.gettime = 70
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Assert.same({ ns.LeadsView.Selected(view).id, view.list.offset, view.details.shownAt }, { 5, 0, 70 })
  for _, row in ipairs(shownRows(view)) do
    Assert.equal(row.shownAt, 70)
  end
  Assert.equal(ns.LeadsView.TopRow(view), view.list.rows[1])
end

local function testNoOnUpdate()
  local ns, view = open(5)
  ns.LeadsView.Refresh(view, ns.Leads.List())
  Widgets.click(view.list.rows[2], "LeftButton")
  view.frame.scripts.OnMouseWheel(view.frame, -1)
  ns.LeadsView.Clear(view)
  for _, frame in ipairs(Wow.frames) do
    Assert.equal(frame.scripts.OnUpdate, nil)
  end
end

return function()
  testStructure()
  testNoAtlas()
  testLayout()
  testFit()
  testEmpty()
  testNewestSelected()
  testArrivalKeepsSelection()
  testSelectedLeaves()
  testScroll()
  testClicks()
  testReopen()
  testNoOnUpdate()
  Wow.reset()
end
