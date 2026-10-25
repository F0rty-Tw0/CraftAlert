local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Spec B, C.2: the WhisperMessenger panel's count and the leads it marks seen. The tab's count is
-- the visible leads neither greeted nor seen; a lead is seen once the details show it while the
-- panel is shown, or on WM's Mark all read.
local function boot(opts)
  local ns, db, calls = UiFixture.load(opts or { leads = 2 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, db, calls, wm
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

-- Each row's dot: true while it shows the unseen gold, false for the state colour of a seen lead.
local function golds(ns, rows, count)
  local gold, out = ns.Theme.COLORS.gold, {}
  for index = 1, count do
    local color = rows[index].dot.texture.vertexColor
    out[index] = rows[index].dot:IsShown() and color ~= nil and color[1] == gold[1] and color[3] == gold[3]
  end
  return out
end

local function showWith(wm)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(600, 400)
  wm.showPanel("CraftAlert", host)
  return host
end

-- The tab's count is the unanswered leads: a greeted lead leaves it, an instance shows none.
local function testBadgeCountsUnansweredLeads()
  local ns, _, _, wm = boot({ leads = 3 })
  local badge = wm.panels.CraftAlert.badge
  Assert.equal(badge(), 3)
  ns.Leads.MarkGreeted(ns.Leads.Latest().id)
  Assert.equal(badge(), 2, "one greeted")
  Assert.equal(badge(), 2, "reading it twice changes nothing")
  Assert.equal(#ns.Leads.List(), 3, "the leads stay")
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  Assert.equal(badge(), 0, "an instance")
end

-- Greeting asks WM to refresh the count, and the count drops by one.
local function testGreetingRefreshesBadge()
  local ns, _, _, wm = boot({ leads = 2 })
  local before = #wm.callsTo("RefreshPanelBadge")
  ns.Leads.MarkGreeted(ns.Leads.Latest().id)
  Assert.truthy(#wm.callsTo("RefreshPanelBadge") > before, "WM asked to refresh")
  Assert.equal(wm.panels.CraftAlert.badge(), 1)
end

-- WM's Mark all read clears the count only: every lead is seen, none greeted, all still listed.
local function testMarkAllReadClearsBadge()
  local ns, _, _, wm = boot({ leads = 3 })
  local panel = wm.panels.CraftAlert
  Assert.equal(panel.badge(), 3)
  panel.onMarkAllRead()
  Assert.equal(panel.badge(), 0)
  Assert.equal(#ns.Leads.List(), 3, "the leads stay")
  for _, lead in ipairs(ns.Leads.List()) do
    Assert.same({ lead.seen, lead.greeted }, { true, false })
  end
end

-- One Mark all read asks WM for one badge refresh, not one per lead: each rebuilds WM's contacts.
local function testMarkAllReadRefreshesBadgeOnce()
  local _, _, _, wm = boot({ leads = 3 })
  local before = #wm.callsTo("RefreshPanelBadge")
  wm.panels.CraftAlert.onMarkAllRead()
  Assert.equal(#wm.callsTo("RefreshPanelBadge") - before, 1)
end

-- A lead shown in the details is seen: the newest on show, then a clicked row; a listed lead is not.
local function testShownLeadIsSeen()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  local badge = wm.panels.CraftAlert.badge
  local before = #wm.callsTo("RefreshPanelBadge")
  showWith(wm)
  local leads = ns.Leads.List()
  Assert.same({ leads[1].seen, leads[2].seen, leads[3].seen }, { true, nil, nil }, "the newest is shown")
  Assert.equal(badge(), 2)
  Assert.truthy(#wm.callsTo("RefreshPanelBadge") > before, "WM asked to refresh")
  local rows = captured.view.list.rows
  Assert.same(golds(ns, rows, 2), { false, true }, "the newest was seen before the rows painted")
  local row = rows[2]
  row.scripts.OnClick(row, "LeftButton")
  Assert.same({ leads[2].seen, leads[3].seen }, { true, nil }, "the clicked row's lead")
  Assert.equal(badge(), 1)
  Assert.same(golds(ns, rows, 2), { false, false }, "the clicked row's dot leaves gold on the same refresh")
end

-- Mark all read with the panel shown repaints the rows: every dot leaves gold at once.
local function testMarkAllReadHidesDots()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  showWith(wm)
  local rows = captured.view.list.rows
  Assert.same(golds(ns, rows, 3), { false, true, true })
  wm.panels.CraftAlert.onMarkAllRead()
  Assert.same(golds(ns, rows, 3), { false, false, false })
end

-- The panel left in settings, then hidden; its selected lead dismissed; the standalone window takes
-- the settings pane, which hands the panel back its leads. The hidden panel does not refresh, so no
-- lead is selected, and none seen, behind the player's back.
local function testHiddenPanelGivenBackItsLeadsMarksNoneSeen()
  local ns, _, _, wm = boot({ leads = 3 })
  local captured = capture(ns)
  showWith(wm)
  local panelView = captured.view -- the standalone window builds its own view later
  ns.BridgePanel.ToggleSettings()
  wm.hidePanel("CraftAlert")
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  local refreshed = 0
  local refresh = ns.LeadsView.Refresh
  ns.LeadsView.Refresh = function(view, ...)
    refreshed = refreshed + (view == panelView and 1 or 0)
    return refresh(view, ...)
  end
  ns.LeadsWindow.SetSettingsRouter(nil) -- the own window, as when WM refuses
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(ns.BridgePanel.InSettings(), false, "the panel is back on its leads")
  Assert.equal(refreshed, 0, "the hidden panel's view is not refreshed")
  Assert.equal(ns.Leads.Latest().seen, nil, "the next lead is not seen")
end

return function()
  testBadgeCountsUnansweredLeads()
  testGreetingRefreshesBadge()
  testMarkAllReadClearsBadge()
  testMarkAllReadRefreshesBadgeOnce()
  testShownLeadIsSeen()
  testMarkAllReadHidesDots()
  testHiddenPanelGivenBackItsLeadsMarksNoneSeen()
  Wow.reset()
end
