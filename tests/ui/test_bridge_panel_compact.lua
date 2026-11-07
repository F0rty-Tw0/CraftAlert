local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Compact-window API, State x event: when WM says its window is compact the panel shows one screen
-- at any host width; otherwise today's rule (narrow below 520, a host not laid out yet is wide).
local function boot(fakeOpts)
  local ns = UiFixture.load({ leads = 3 })
  local _, wm = FakeWm.install(fakeOpts)
  ns.WhisperBridge.Activate()
  return ns, wm
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

local function showWith(wm, width)
  local host = newHost(width)
  wm.showPanel("CraftAlert", host)
  return host
end

local function resize(host, width)
  host:SetSize(width, 400)
  Widgets.fire(host, "OnSizeChanged", width, 400)
  Widgets.nextFrame() -- the panel lays out on the next frame
end

-- The leads' screen and which panes show: split = both panes and the divider; list = the list alone.
local function look(ns, view)
  return { ns.LeadsView.Screen(view), view.listPane:IsShown(), view.detailsPane:IsShown(), view.divider:IsShown() }
end

local SPLIT = { "split", true, true, true }
local LIST = { "list", true, false, false }

-- One run: WM's compact answer and the host width, shown once; the result is what the panel did.
local function run(compact, width, fakeOpts)
  local ns, wm = boot(fakeOpts)
  wm.compact = compact
  local captured = capture(ns)
  local calls = spyNarrow(ns)
  showWith(wm, width)
  return ns, captured.view, calls
end

-- Row "compact | host 600 (wide) | show": the list alone; a tap opens the details with the back arrow.
local function testCompactWideHostShowsTheListAlone()
  local ns, view = run(true, 600)
  Assert.same(look(ns, view), LIST)
  Widgets.click(view.list.rows[1], "LeftButton")
  ns.ScreenSlide.FinishNow()
  Assert.same({ ns.LeadsView.Screen(view), view.details.back:IsShown() }, { "details", true })
end

-- Row "compact | host 0 (not laid out) | show": narrow at once, no split flash.
local function testCompactUnlaidHostIsNarrowAtOnce()
  local _, _, calls = run(true, 0)
  Assert.same(calls, { true })
end

local function testCompactNarrowHostIsNarrow()
  local ns, view, calls = run(true, 300)
  Assert.same({ calls, look(ns, view) }, { { true }, LIST })
end

-- Rows "regular | 600 split, 300 narrow, 0 split": the width rule as before.
local function testRegularWindowFollowsTheWidth()
  local ns, view = run(false, 600)
  Assert.same(look(ns, view), SPLIT, "600")
  local ns2, view2 = run(false, 300)
  Assert.same(look(ns2, view2), LIST, "300")
  local ns3, view3 = run(false, 0)
  Assert.same(look(ns3, view3), SPLIT, "0")
end

-- Row "older WM (no call)": the width rule, though the fake WM would say compact.
local function testOlderWmFollowsTheWidth()
  local ns, view = run(true, 600, { without = { "IsCompactWindow" } })
  Assert.same(look(ns, view), SPLIT, "600")
  local ns2, view2 = run(true, 300, { without = { "IsCompactWindow" } })
  Assert.same(look(ns2, view2), LIST, "300")
end

-- Review Focus 2: a raising call is the width rule, with no Lua error.
local function testRaisingCallFollowsTheWidth()
  local ns, wm = boot()
  wm.compact = true
  wm.raise.IsCompactWindow = true
  local captured = capture(ns)
  showWith(wm, 600)
  Assert.same(look(ns, captured.view), SPLIT)
end

-- Review Focus 3: the answer is read at every show. The same host, so a read-once panel keeps its
-- first answer (a new host would rebuild and hide that).
local function testAnswerIsReadAtEveryShow()
  local ns, wm = boot()
  wm.compact = true
  local captured = capture(ns)
  local host = showWith(wm, 600)
  Assert.same(look(ns, captured.view), LIST, "compact at the first show")
  wm.hidePanel("CraftAlert")
  wm.compact = false
  wm.showPanel("CraftAlert", host)
  Assert.same(look(ns, captured.view), SPLIT, "regular at the second")
  wm.hidePanel("CraftAlert")
  wm.compact = true
  wm.showPanel("CraftAlert", host)
  Assert.same(look(ns, captured.view), LIST, "compact again")
end

-- Row "compact | host grows": still one screen.
local function testCompactHostStaysNarrowWhenDraggedWider()
  local ns, wm = boot()
  wm.compact = true
  local captured = capture(ns)
  local calls = spyNarrow(ns)
  local host = showWith(wm, 600)
  resize(host, 800)
  Assert.same({ calls, look(ns, captured.view) }, { { true }, LIST })
end

-- Row "compact | settings": the nav first, as in a narrow host.
local function testCompactWideHostOpensSettingsOnTheNav()
  local ns, wm = boot()
  wm.compact = true
  local host = showWith(wm, 600)
  Widgets.click(SettingsFixture.button(host, "Settings"))
  Assert.same({ ns.BridgePanel.InSettings(), ns.SettingsPane.Screen() }, { true, "nav" })
end

return function()
  testCompactWideHostShowsTheListAlone()
  testCompactUnlaidHostIsNarrowAtOnce()
  testCompactNarrowHostIsNarrow()
  testRegularWindowFollowsTheWidth()
  testOlderWmFollowsTheWidth()
  testRaisingCallFollowsTheWidth()
  testAnswerIsReadAtEveryShow()
  testCompactHostStaysNarrowWhenDraggedWider()
  testCompactWideHostOpensSettingsOnTheNav()
  Wow.reset()
end
