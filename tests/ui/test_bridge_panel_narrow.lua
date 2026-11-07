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

return function()
  testBuildOptsInToCompact()
  testRegisteredPanelCarriesCompact()
  testThreshold()
  testSizeChangedRedecides()
  testHiddenPanelIsLeftAlone()
  testOldWmNarrowThenWide()
  testSplitCappedAtHostLessDetails()
  Wow.reset()
end
