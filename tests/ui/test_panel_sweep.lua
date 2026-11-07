local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Meter = require("tests.helpers.sweep_meter")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Phase 5 sweep: a refresh creates nothing, a slide creates and retains nothing, every slide ends
-- with no group playing and every screen at rest, and each user action repaints once.
local LEADS, REFRESHES, CYCLES, SLIDES = 30, 100, 50, 1000
local RETAINED_KB, SLIDE_KB, LEDGER_KB, LIST_KB = 1, 0.5, 0.5, 100

local MODES = {
  { "wide", 600, false },
  { "narrow list", 360, false },
  { "narrow details", 360, true },
}

local function refreshTimes(p, count)
  for _ = 1, count do
    p.ns.BridgePanel.Refresh()
  end
end

local function enter(mode)
  local p = Meter.panel(mode[2], LEADS)
  if mode[3] then
    Widgets.click(p.view.list.rows[1], "LeftButton")
    Meter.settle(p.ns)
  end
  refreshTimes(p, 20) -- rows and caches exist from here on
  return p
end

-- B1
local function testRefreshCreatesNoFramesOrRegions()
  for _, mode in ipairs(MODES) do
    local p = enter(mode)
    local before = Meter.objects(p.ns)
    refreshTimes(p, REFRESHES)
    Assert.same(Meter.objects(p.ns), before, mode[1] .. ": nothing made per refresh")
  end
end

-- B2: a leak grows with the refresh count; a one-off cache does not.
local function testRefreshRetainsNothing()
  for _, mode in ipairs(MODES) do
    local p = enter(mode)
    refreshTimes(p, REFRESHES)
    local settled = Meter.settled()
    refreshTimes(p, REFRESHES)
    local grown = Meter.settled() - settled
    Assert.truthy(grown <= RETAINED_KB, string.format("%s: %.2f KB retained by %d refreshes", mode[1], grown, REFRESHES))
  end
end

-- B3: the groups and the clip parent's hook are made by the first slide and reused after it.
local function testSlidesCreateNothing()
  for _, kind in ipairs({ "leads", "settings" }) do
    local p = Meter.panel(360, LEADS)
    local cycle = Meter.leadsCycle
    if kind == "settings" then
      Meter.openSettings(p)
      cycle = Meter.settingsCycle
    end
    cycle(p) -- warm-up
    local before = Meter.objects(p.ns)
    Assert.truthy(before.groups >= 2, kind .. ": the warm-up slid (a pair of groups exists)")
    for _ = 1, CYCLES do
      cycle(p)
    end
    Assert.same(Meter.objects(p.ns), before, kind .. ": " .. CYCLES .. " cycles made no frame, region, group or hook")
  end
end

-- B4: no closure or table per slide.
local function testSlideAllocatesNothing()
  local ns, _, from, to = Meter.slideRig()
  local S = ns.ScreenSlide
  local function pair()
    S.Show(from, to, 1)
    S.Group(from):Finish()
    S.Group(to):Finish()
    S.Show(to, from, -1)
    S.Group(to):Finish()
    S.Group(from):Finish()
  end
  pair() -- warm-up: the groups exist from here on
  Assert.truthy(S.Group(from) and S.Group(to), "the rig slides (groups exist)")
  Meter.silence(ns)
  local kb = Meter.garbage(function()
    for _ = 1, SLIDES / 2 do
      pair()
    end
  end)
  Assert.truthy(kb <= SLIDE_KB, string.format("%.3f KB over %d slides", kb, SLIDES))
end

-- B4: a finished slide keeps nothing alive (an onDone closure, a saved anchor table).
local function testSlideCyclesRetainNothing()
  local p = Meter.panel(360, LEADS)
  for _ = 1, 20 do
    Meter.leadsCycle(p)
  end
  Meter.silence(p.ns)
  local settled = Meter.settled()
  for _ = 1, REFRESHES do
    Meter.leadsCycle(p)
  end
  local grown = Meter.settled() - settled
  Assert.truthy(grown <= RETAINED_KB, string.format("%.2f KB retained by %d cycles", grown, REFRESHES))
end

-- B6 helpers: the state every ended slide must reach.
local function ended(p, clip, label)
  Assert.same({ #Meter.playing(p.ns), p.ns.ScreenSlide.IsSliding(), clip.clipsChildren }, { 0, false, false }, label .. ": no group playing, no clip")
end

-- B6: the client finishes the groups, in either order: the list is hidden, the details at rest.
local function testFinishInEitherOrderEndsAtRest()
  for _, reverse in ipairs({ false, true }) do
    local p = Meter.panel(360, LEADS)
    local view = p.view
    local list, details = Meter.anchors(view.listPane), Meter.anchors(view.detailsPane)
    Widgets.click(view.list.rows[1], "LeftButton")
    Assert.equal(#Meter.playing(p.ns), 2, "a pair of groups plays")
    Meter.settle(p.ns, reverse)
    local label = reverse and "reverse order" or "creation order"
    ended(p, view.frame, label)
    Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { false, true }, label .. ": leaving screen hidden")
    Assert.same({ Meter.anchors(view.listPane), Meter.anchors(view.detailsPane) }, { list, details }, label .. ": anchors at rest")
  end
end

-- B6: hiding the panel mid-slide ends it; the next show starts on the List with nothing playing.
local function testHideMidLeadsSlideLeavesNothingPlaying()
  local p = Meter.panel(360, LEADS)
  local view = p.view
  local details = Meter.anchors(view.detailsPane)
  Widgets.click(view.list.rows[1], "LeftButton")
  Assert.equal(#Meter.playing(p.ns), 2, "mid-slide")
  p.wm.hidePanel("CraftAlert")
  ended(p, view.frame, "hidden mid-slide")
  Assert.same({ view.listPane:IsShown(), view.detailsPane:IsShown() }, { false, true }, "leaving screen hidden")
  Assert.same(Meter.anchors(view.detailsPane), details, "details at rest")
  p.wm.showPanel("CraftAlert", p.host)
  Assert.same(
    { p.ns.LeadsView.Screen(view), #Meter.playing(p.ns), view.listPane:IsShown(), view.detailsPane:IsShown() },
    { "list", 0, true, false },
    "the next show: List, nothing playing"
  )
end

local function testHideMidSettingsSlideLeavesNothingPlaying()
  local p = Meter.panel(360, LEADS)
  local container = Meter.openSettings(p)
  local nav = SettingsFixture.navButton("General").parent
  local right = assert(SettingsFixture.pageHeader(), "no page header").parent
  local rest = Meter.anchors(right)
  Widgets.click(SettingsFixture.navButton("Alerts"), "LeftButton")
  Assert.equal(#Meter.playing(p.ns), 2, "mid-slide")
  p.wm.hidePanel("CraftAlert")
  ended(p, container, "hidden mid-slide on the settings")
  Assert.same({ nav:IsShown(), right:IsShown() }, { false, true }, "leaving screen hidden")
  Assert.same(Meter.anchors(right), rest, "page at rest")
end

-- B6: a click during a running slide ends it and starts the reverse one: one pair playing, no new group.
local function testBackToBackSlidesLeaveNothingPlaying()
  local p = Meter.panel(360, LEADS)
  Meter.leadsCycle(p) -- warm-up
  local groups = Meter.objects(p.ns).groups
  Widgets.click(p.view.list.rows[1], "LeftButton")
  p.ns.LeadsView.Back(p.view)
  Assert.same({ #Meter.playing(p.ns), p.ns.LeadsView.Screen(p.view) }, { 2, "list" }, "one pair playing, heading to the List")
  Meter.settle(p.ns)
  ended(p, p.view.frame, "back to back")
  Assert.same(
    { p.view.listPane:IsShown(), p.view.detailsPane:IsShown(), Meter.objects(p.ns).groups },
    { true, false, groups },
    "ends on the List, no group added"
  )
end

-- B5: one repaint per user action, a frame's burst of size events, a lead change or a wheel notch
-- that moves the list; none for a wheel notch that moves nothing, a wheel on the details, or a
-- hidden panel.
local EXPECTED = {
  { "wheel up at the top", 0 },
  { "wheel down", 1 },
  { "wheel down at the end", 0 },
  { "row click", 1 },
  { "wheel on the details", 0 },
  { "back", 1 },
  { "lead change", 1 },
  { "ten size events", 1 },
  { "narrow to wide", 1 },
  { "wide to narrow", 1 },
  { "size event while hidden", 0 },
}

local function testRefreshesPerAction()
  local rows = Meter.actionCounts()
  Assert.equal(#rows, #EXPECTED, "every action measured")
  for index, want in ipairs(EXPECTED) do
    Assert.equal(rows[index][1], want[1], "row " .. index)
    Assert.equal(rows[index][2], want[2], want[1])
  end
end

-- B5: a refresh with today's counters unchanged leaves the ledger line alone: no text set, no
-- table or string built.
local function testLedgerRefreshSkipsUnchangedCounters()
  local p = enter(MODES[1])
  local strip = p.view.strip
  local sets = Meter.count(strip.text, "SetText")
  local kb = Meter.garbage(function()
    for _ = 1, REFRESHES do
      p.ns.LedgerStrip.Refresh(strip)
    end
  end)
  Assert.equal(sets(), 0, "text set by unchanged refreshes")
  Assert.truthy(kb <= LEDGER_KB, string.format("%.2f KB garbage by %d ledger refreshes", kb, REFRESHES))
end

-- Counters for every setter a list row paints with; → total() (calls so far, all rows).
local function rowSetters(rows)
  local counters = {}
  for _, row in ipairs(rows) do
    for _, setter in ipairs({
      { row.name, "SetText" },
      { row.name, "SetTextColor" },
      { row.age, "SetText" },
      { row.what, "SetText" },
      { row.what, "SetTextColor" },
      { row.icon, "SetTexture" },
      { row.dot.texture, "SetVertexColor" },
      { row.repliedTag, "ClearAllPoints" },
    }) do
      counters[#counters + 1] = Meter.count(setter[1], setter[2])
    end
  end
  return function()
    local total = 0
    for _, calls in ipairs(counters) do
      total = total + calls()
    end
    return total
  end
end

-- B5: a list refresh where no row's lead, painted field or selection changed repaints no row.
local function testListRefreshSkipsUnchangedRows()
  local p = enter(MODES[1])
  local view, LeadsList = p.view, p.ns.LeadsList
  local fit = LeadsList.Fit(view.getHeight() - p.ns.Theme.LAYOUT.LEDGER_HEIGHT)
  local painted = rowSetters(view.list.rows)
  local kb = Meter.garbage(function()
    for _ = 1, REFRESHES do
      LeadsList.Refresh(view.list, view.leads, fit, view.selectedId)
    end
  end)
  Assert.equal(painted(), 0, "row setters run by unchanged list refreshes")
  Assert.truthy(kb <= LIST_KB, string.format("%.2f KB garbage by %d list refreshes", kb, REFRESHES))
end

return function()
  testRefreshCreatesNoFramesOrRegions()
  testRefreshRetainsNothing()
  testSlidesCreateNothing()
  testSlideAllocatesNothing()
  testSlideCyclesRetainNothing()
  testFinishInEitherOrderEndsAtRest()
  testHideMidLeadsSlideLeavesNothingPlaying()
  testHideMidSettingsSlideLeavesNothingPlaying()
  testBackToBackSlidesLeaveNothingPlaying()
  testRefreshesPerAction()
  testLedgerRefreshSkipsUnchangedCounters()
  testListRefreshSkipsUnchangedRows()
  Wow.reset()
end
