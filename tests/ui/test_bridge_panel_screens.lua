local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Phone-style slide spec: the leads' List and Details screens through the real panel in a narrow host.
local function boot(opts)
  local ns, db, calls = UiFixture.load(opts or { leads = 3 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, db, calls, wm
end

local function newHost(width)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, 400)
  return host
end

-- Records the LeadsView the panel builds: captured.view.
local function capture(ns)
  local captured = {}
  local new = ns.LeadsView.New
  ns.LeadsView.New = function(...)
    captured.view = new(...)
    return captured.view
  end
  return captured
end

local function showWith(wm, width, listWidth)
  local host = newHost(width)
  wm.showPanel("CraftAlert", host, listWidth)
  return host
end

-- The host grows or shrinks: WM's size event reaches the panel's hook.
local function resize(host, width)
  host:SetSize(width, 400)
  Widgets.fire(host, "OnSizeChanged", width, 400)
  Widgets.nextFrame() -- the panel lays out on the next frame
end

-- Every show starts on the List: scrolled to the top, nothing selected, nothing marked seen.
local function testShowStartsOnTheList()
  local ns, _, _, wm = boot({ leads = 12 })
  local captured = capture(ns)
  local host = showWith(wm, 360)
  local view = captured.view
  Assert.same({ ns.LeadsView.Screen(view), view.selectedId, view.list.offset }, { "list", nil, 0 })
  Assert.equal(wm.panels.CraftAlert.badge(), 12, "no lead was marked seen by opening the tab")
  ns.LeadsView.Scroll(view, -2)
  Widgets.click(view.list.rows[1], "LeftButton")
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert", host)
  Assert.same({ ns.LeadsView.Screen(view), view.selectedId, view.list.offset }, { "list", nil, 0 }, "the second show starts over")
end

-- Review Focus 2: new / expired / greeted leads while the List shows mark nothing seen.
local function testBadgeSurvivesListRefreshes()
  local ns, db, _, wm = boot({ leads = 3 })
  showWith(wm, 360)
  local badge = wm.panels.CraftAlert.badge
  Assert.equal(badge(), 3)
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(badge(), 2, "an expiry")
  -- Not a greeting: MarkGreeted -> "greeted" -> OpenConversation -> the fake hides the panel.
  -- A new lead instead: the UI fixture has no recipe index for Matcher.Match, so the lead goes
  -- straight into the bound list and the panel refreshes as a lead change refreshes it.
  db.leads[#db.leads + 1] = UiFixture.lead(4)
  ns.BridgePanel.Refresh()
  Assert.equal(badge(), 3, "a new lead")
  for _, lead in ipairs(ns.Leads.List()) do
    Assert.equal(lead.seen, nil)
  end
end

-- Review Focus 1: while Details shows, the panel reports no top row; back on the List it reports
-- the newest lead with a fresh look time.
local function testTopRowIsNilOnDetails()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  showWith(wm, 360)
  Assert.same({ ns.BridgePanel.TopRow() }, { ns.Leads.Latest(), 50 })
  Widgets.click(captured.view.list.rows[2], "LeftButton")
  Assert.equal(ns.BridgePanel.TopRow(), nil)
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "the look rule counts no off-screen row")
  Wow.clock.gettime = 60
  ns.LeadsView.Back(captured.view)
  Assert.same({ ns.BridgePanel.TopRow() }, { ns.Leads.Latest(), 60 })
end

-- Host grows to 520+: the split view; a lead in Details stays selected, else the newest is.
local function testGrowingKeepsTheDetailsLeadElseSelectsNewest()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  local host = showWith(wm, 360)
  local view = captured.view
  Widgets.click(view.list.rows[2], "LeftButton")
  resize(host, 600)
  Assert.same({ ns.LeadsView.Screen(view), view.selectedId, view.details.lead.id, view.listPane:GetWidth() }, { "split", 2, 2, 260 })
  resize(host, 360)
  Assert.same({ ns.LeadsView.Screen(view), view.selectedId, view.listPane:GetWidth() }, { "list", nil, 360 }, "shrinking: List, selection cleared")
  resize(host, 600)
  Assert.same({ view.selectedId, ns.Leads.Latest().seen }, { ns.Leads.Latest().id, true }, "from the List: the newest, seen")
end

-- onSplit while narrow is stored but changes nothing; the stored split applies once wide.
local function testSplitIsIgnoredWhileNarrow()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 400, 220)
  Assert.equal(captured.view.listPane:GetWidth(), 400, "narrow: the list takes the host")
  resize(host, 600)
  Assert.equal(captured.view.listPane:GetWidth(), 220, "wide: the stored split")
end

return function()
  testShowStartsOnTheList()
  testBadgeSurvivesListRefreshes()
  testTopRowIsNilOnDetails()
  testGrowingKeepsTheDetailsLeadElseSelectsNewest()
  testSplitIsIgnoredWhileNarrow()
  Wow.reset()
end
