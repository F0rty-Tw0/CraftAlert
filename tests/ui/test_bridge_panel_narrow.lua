local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")
local Widgets = require("tests.helpers.widgets")

-- Phone-style slide spec: Craft Alert opts in to WM's narrow window and decides narrow vs wide from
-- its host's width (narrow below LIST_MIN_WIDTH + DETAILS_MIN_WIDTH = 520).
local function boot(opts)
  local ns, db, calls = UiFixture.load(opts or { leads = 3 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, db, calls, wm
end

local function testBuildOptsInToCompact()
  local ns = boot()
  Assert.equal(ns.BridgePanel.Build().compact, true)
end

local function testRegisteredPanelCarriesCompact()
  local _, _, _, wm = boot()
  Assert.equal(wm.registered[1][2].compact, true, "WM is handed the flag at RegisterPanel")
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

-- Every LeadsView.SetNarrow(view, narrow) call, in order: calls[i] = narrow.
local function spyNarrow(ns)
  local calls = {}
  local original = ns.LeadsView.SetNarrow
  ns.LeadsView.SetNarrow = function(view, narrow)
    calls[#calls + 1] = narrow
    return original(view, narrow)
  end
  return calls
end

local function callsFor(width)
  local ns, _, _, wm = boot()
  local calls = spyNarrow(ns)
  showWith(wm, width)
  return calls
end

-- 519 is narrow, 520 wide; a host not laid out yet (0) counts as wide.
local function testThreshold()
  Assert.same(callsFor(519), { true }, "519 px")
  Assert.same(callsFor(520), {}, "520 px")
  Assert.same(callsFor(0), {}, "0 px")
end

-- The host's size event re-decides: 0 -> 360 narrow, back to 600 wide; a resize inside one mode
-- calls nothing.
local function testSizeChangedRedecides()
  local ns, _, _, wm = boot()
  local calls = spyNarrow(ns)
  local host = showWith(wm, 0)
  resize(host, 360)
  Assert.same(calls, { true }, "laid out narrow")
  resize(host, 400)
  Assert.same(calls, { true }, "still narrow")
  resize(host, 600)
  resize(host, 700)
  Assert.same(calls, { true, false }, "wide once")
end

-- A hidden panel is not re-decided; the next show decides.
local function testHiddenPanelIsLeftAlone()
  local ns, _, _, wm = boot()
  local calls = spyNarrow(ns)
  local host = showWith(wm, 600)
  wm.hidePanel("CraftAlert")
  resize(host, 360)
  Assert.same(calls, {})
  wm.showPanel("CraftAlert", host)
  Assert.same(calls, { true })
end

-- LeadsView.Refresh calls from now on; → count().
local function countRefreshes(ns)
  local count, refresh = 0, ns.LeadsView.Refresh
  ns.LeadsView.Refresh = function(...)
    count = count + 1
    return refresh(...)
  end
  return function()
    return count
  end
end

-- Size events in one frame (a drag): nothing is laid out until the frame ends, then the host's last
-- size once, through one refresh. Narrow -> wide -> narrow in one frame stays narrow.
local function testBurstLaysOutTheLastSizeOnce()
  local ns, _, _, wm = boot()
  local calls = spyNarrow(ns)
  local host = showWith(wm, 360)
  local refreshes = countRefreshes(ns)
  for _, width in ipairs({ 600, 360, 450, 600, 380 }) do
    host:SetSize(width, 400)
    Widgets.fire(host, "OnSizeChanged", width, 400)
  end
  Assert.same({ calls, refreshes() }, { { true }, 0 }, "nothing before the frame ends")
  Widgets.nextFrame()
  Assert.same({ calls, refreshes() }, { { true }, 1 }, "one refresh, still narrow")
  host:SetSize(600, 400)
  Widgets.fire(host, "OnSizeChanged", 600, 400)
  Widgets.fire(host, "OnSizeChanged", 600, 400)
  Widgets.nextFrame()
  Assert.same({ calls, refreshes() }, { { true, false }, 2 }, "the next frame's burst ends wide")
end

-- A hide drops a pending layout: nothing is laid out while hidden, and after the next show (which
-- lays out the host as it is then) no stale one follows.
local function testHideDropsPendingLayout()
  local ns, _, _, wm = boot()
  local calls = spyNarrow(ns)
  local host = showWith(wm, 600)
  host:SetSize(360, 400)
  Widgets.fire(host, "OnSizeChanged", 360, 400)
  wm.hidePanel("CraftAlert")
  local refreshes = countRefreshes(ns)
  wm.showPanel("CraftAlert", host)
  Widgets.nextFrame()
  Assert.same({ calls, refreshes() }, { { true }, 1 }, "the show's layout only")
end

-- Review Focus 3: old WM (no `compact` support). onShow runs before WM widens the window, so the
-- first decision is narrow; the host then widens and the size event restores today's split view
-- with the newest lead selected and seen.
local function testOldWmNarrowThenWide()
  local ns, _, _, wm = boot({ leads = 3 })
  local calls = spyNarrow(ns)
  local captured = capture(ns)
  local host = showWith(wm, 360)
  resize(host, 600)
  Assert.same(calls, { true, false })
  local leads = ns.Leads.List()
  local view = captured.view
  Assert.same({ view.selectedId, leads[1].seen, leads[2].seen, leads[3].seen }, { leads[1].id, true })
  Assert.equal(view.details.lead, leads[1], "the details show the newest")
  Assert.equal(view.listPane:GetWidth(), 260, "the list is back to the clamp")
end

-- Wide host: the list takes at most host width - 340 (WM's phone window resized past 520 sends a
-- split of about its full width); the rail below the cap is kept.
local function testSplitCappedAtHostLessDetails()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  showWith(wm, 600, 590)
  Assert.equal(captured.view.listPane:GetWidth(), 260, "600 - 340")
  wm.split("CraftAlert", 100)
  Assert.equal(captured.view.listPane:GetWidth(), 100, "the rail is under the cap")
  wm.split("CraftAlert", 300)
  Assert.equal(captured.view.listPane:GetWidth(), 260, "a later split is capped too")
end

-- WM's relayout calls onSplit in the frame of the size event, before the panel's own layout: the
-- split lays out the host's new mode, the narrow List over the whole host.
local function testSplitBeforeTheFrameEndsSeesTheNewMode()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 600, 260)
  host:SetSize(330, 400)
  Widgets.fire(host, "OnSizeChanged", 330, 400)
  wm.split("CraftAlert", 300)
  Assert.same({ ns.LeadsView.Screen(captured.view), captured.view.listPane:GetWidth() }, { "list", 330 })
end

-- A WM drag frame: the host's new size, WM's relayout split (same divider), the host's size event.
-- The split already laid out that size, so the frame's end does not refresh it again.
local function testDragFrameWithSplitRefreshesOnce()
  local ns, _, _, wm = boot()
  local host = showWith(wm, 700, 260)
  local refreshes = countRefreshes(ns)
  host:SetSize(701, 400)
  wm.split("CraftAlert", 260)
  Widgets.fire(host, "OnSizeChanged", 701, 400)
  Widgets.nextFrame()
  Assert.equal(refreshes(), 1)
end

-- A refresh between a size event and the frame's end (a lead change, WM's unread count) does not
-- decide; the frame's end still decides the host's new mode.
local function testRefreshMidFrameStillDecidesAtTheFrameEnd()
  local ns, _, _, wm = boot()
  local calls = spyNarrow(ns)
  local host = showWith(wm, 700)
  host:SetSize(400, 400)
  Widgets.fire(host, "OnSizeChanged", 400, 400)
  ns.BridgePanel.Refresh()
  Widgets.nextFrame()
  Assert.same(calls, { true })
end

-- A refresh at another size, then the host back to the size last decided, in one frame: the frame's
-- end lays the host out again at that size.
local function testRefreshAtAnotherSizeThenBackLaysOutAgain()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 700, 260)
  host:SetSize(560, 400)
  Widgets.fire(host, "OnSizeChanged", 560, 400)
  ns.BridgePanel.Refresh()
  host:SetSize(700, 400)
  Widgets.fire(host, "OnSizeChanged", 700, 400)
  Widgets.nextFrame()
  Assert.equal(captured.view.listPane:GetWidth(), 260)
end

-- A vertical drag: the host grows taller at the same width and WM sends no split; the frame's end
-- still lays the new height out.
local function testHeightOnlyResizeLaysOut()
  local ns, _, _, wm = boot()
  local host = showWith(wm, 700, 260)
  local refreshes = countRefreshes(ns)
  host:SetSize(700, 520)
  Widgets.fire(host, "OnSizeChanged", 700, 520)
  Widgets.nextFrame()
  Assert.equal(refreshes(), 1)
end

return function()
  testBuildOptsInToCompact()
  testRegisteredPanelCarriesCompact()
  testThreshold()
  testSizeChangedRedecides()
  testHiddenPanelIsLeftAlone()
  testBurstLaysOutTheLastSizeOnce()
  testHideDropsPendingLayout()
  testOldWmNarrowThenWide()
  testSplitCappedAtHostLessDetails()
  testSplitBeforeTheFrameEndsSeesTheNewMode()
  testDragFrameWithSplitRefreshesOnce()
  testRefreshMidFrameStillDecidesAtTheFrameEnd()
  testRefreshAtAnotherSizeThenBackLaysOutAgain()
  testHeightOnlyResizeLaysOut()
  Wow.reset()
end
