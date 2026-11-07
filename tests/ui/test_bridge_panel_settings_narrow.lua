local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Compact-window slide spec, settings rows: in a narrow host BridgePanel puts the settings pane in
-- narrow mode (nav, then a page under a back-arrow header) and keeps its mode equal to the host's
-- across width changes.
local function boot()
  local ns = UiFixture.load({ leads = 3 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  local captured = {}
  local new = ns.LeadsView.New
  ns.LeadsView.New = function(...)
    captured.view = new(...)
    return captured.view
  end
  return ns, wm, captured
end

-- A host `width` x 400, shown through WM's fake.
local function show(wm, width, split)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, 400)
  wm.showPanel("CraftAlert", host, split)
  return host
end

local function resize(host, width)
  host:SetSize(width, 400)
  Widgets.fire(host, "OnSizeChanged")
  Widgets.nextFrame() -- the panel lays out on the next frame
end

local function openSettings(host)
  Widgets.click(SettingsFixture.button(host, "Settings"))
end

local function pick(title)
  Widgets.click(SettingsFixture.navButton(title), "LeftButton")
end

local function rowVisible(label)
  local ok, row = pcall(SettingsFixture.row, label)
  return ok and row:IsVisible()
end

-- The pane's screen, whether settings are open, the leads' screen.
local function state(ns, captured)
  return { ns.SettingsPane.Screen(), ns.BridgePanel.InSettings(), ns.LeadsView.Screen(captured.view) }
end

-- Row "List / Details | Settings link | SettingsNav"
local function testSettingsLinkOpensNavInNarrowHost()
  local ns, wm, captured = boot()
  local host = show(wm, 400)
  openSettings(host)
  Assert.same(state(ns, captured), { "nav", true, "list" }, "the link opens the nav")
  local container = SettingsFixture.button(host, "Back to leads").parent.parent
  Assert.same({ container.parent, container:IsVisible(), captured.view.frame:IsShown() }, { host, true, false }, "fills the host, leads hidden")
  Assert.truthy(container:GetFrameLevel() > host:GetFrameLevel() + 50, "over WM's divider handle")
  Assert.equal(container.mouseEnabled, true, "takes the mouse")
end

local function testSettingsLinkFromDetailsThenBackLandsOnList()
  local ns, wm, captured = boot()
  local host = show(wm, 400)
  Widgets.click(captured.view.list.rows[1], "LeftButton")
  Assert.equal(ns.LeadsView.Screen(captured.view), "details", "precondition: a lead is open")
  openSettings(host)
  Assert.same(state(ns, captured), { "nav", true, "list" }, "the link works from Details")
  Widgets.click(SettingsFixture.button(host, "Back to leads"))
  Assert.same({
    ns.BridgePanel.InSettings(),
    ns.LeadsView.Screen(captured.view),
    captured.view.frame:IsShown(),
    captured.view.selectedId,
  }, { false, "list", true, nil }, "Back to leads: the List, nothing selected")
end

-- Rows "SettingsNav | page button | SettingsPage" and "SettingsPage | back arrow | SettingsNav"
local function testPageButtonThenHeaderArrow()
  local ns, wm, captured = boot()
  local host = show(wm, 400)
  openSettings(host)
  pick("Alerts")
  local header = assert(SettingsFixture.pageHeader(), "no page header")
  Assert.same(
    { state(ns, captured)[1], header:IsVisible(), header.title:GetText(), rowVisible("Lead timeout") },
    { "page", true, "Alerts", true },
    "a page, under its title"
  )
  Widgets.click(header.back)
  Assert.same(state(ns, captured), { "nav", true, "list" }, "the arrow goes back to the nav, settings stay open")
end

-- Row "every show starts on the leads" (narrow)
local function testEveryShowStartsOnTheList()
  local ns, wm, captured = boot()
  local host = show(wm, 400)
  openSettings(host)
  pick("Alerts")
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert", host)
  Assert.same({
    ns.BridgePanel.InSettings(),
    ns.LeadsView.Screen(captured.view),
    SettingsFixture.pageHeader().parent:IsVisible(),
  }, { false, "list", false }, "settings are not kept")
end

-- Row "SettingsNav / SettingsPage | enters an instance | List" (Review Focus 5)
local function instanceGate(openPage)
  local ns, wm, captured = boot()
  local host = show(wm, 400)
  openSettings(host)
  if openPage then
    pick("Alerts")
  end
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.WhisperBridge.OnGate()
  Assert.same({
    ns.BridgePanel.InSettings(),
    ns.LeadsView.Screen(captured.view),
    captured.view.frame:IsShown(),
    SettingsFixture.pageHeader().parent:IsVisible(),
  }, { false, "list", true, false }, openPage and "SettingsPage -> List" or "SettingsNav -> List")
  Wow.stub("IsInInstance", nil)
end

local function testInstanceGateLeavesSettingsForTheList()
  instanceGate(true)
  instanceGate(false)
end

-- Rows "host grows to >= 520"
local function testGrowFromPageShowsThatPageBesideTheNav()
  local ns, wm, captured = boot()
  local host = show(wm, 400)
  openSettings(host)
  pick("Alerts")
  resize(host, 520)
  Assert.same({
    state(ns, captured)[1],
    state(ns, captured)[2],
    rowVisible("Lead timeout"),
    SettingsFixture.navButton("Alerts").selected:IsShown(),
    captured.view.frame:IsShown(),
  }, { "split", true, true, true, false }, "same page, side by side, still in settings")
end

local function testGrowFromNavShowsLastPageElseFirst()
  local _, wm = boot()
  local host = show(wm, 400)
  openSettings(host)
  pick("Alerts")
  Widgets.click(SettingsFixture.pageHeader().back)
  resize(host, 520)
  Assert.equal(SettingsFixture.navButton("Alerts").selected:IsShown(), true, "the last page shown")
  local _, wm2 = boot()
  local host2 = show(wm2, 400)
  openSettings(host2)
  resize(host2, 520)
  Assert.equal(SettingsFixture.navButton("General").selected:IsShown(), true, "none shown yet: the first page")
end

-- Row "any wide state | host shrinks below 520" for settings
local function testShrinkGoesToNavAndBackToLeadsToList()
  local ns, wm, captured = boot()
  local host = show(wm, 600)
  openSettings(host)
  pick("Alerts")
  resize(host, 519)
  Assert.same({ state(ns, captured)[1], state(ns, captured)[2], rowVisible("Lead timeout") }, { "nav", true, false }, "SettingsNav")
  Widgets.click(SettingsFixture.button(host, "Back to leads"))
  Assert.same({ ns.LeadsView.Screen(captured.view), captured.view.selectedId }, { "list", nil }, "Back to leads: List, nothing selected")
end

-- 519 narrow, 520 wide, 0 wide (not laid out), for a host with settings open
local function testWidthBoundariesForSettings()
  for _, case in ipairs({ { 600, 519, "nav" }, { 400, 520, "split" }, { 400, 0, "split" } }) do
    local ns, wm = boot()
    local host = show(wm, case[1])
    openSettings(host)
    resize(host, case[2])
    Assert.equal(ns.SettingsPane.Screen(), case[3], case[1] .. " -> " .. case[2])
  end
end

-- Row "onSplit(width) | ignored while narrow"
local function testSplitIgnoredWhileNarrow()
  local _, wm = boot()
  local host = show(wm, 400)
  openSettings(host)
  local nav = SettingsFixture.navButton("General").parent
  local before = { nav.points[1], nav.points[2] }
  wm.split("CraftAlert", 220)
  Assert.same({ nav.points[1], nav.points[2] }, before, "the nav still spans the host")
  resize(host, 600)
  Assert.equal(nav:GetWidth(), 220, "the stored split applies once wide")
end

-- The pane is shared: the standalone window must keep the split, before and after the panel.
local function testStandaloneWindowKeepsTheSplit()
  local ns, wm = boot()
  ns.LeadsWindow.SetSettingsRouter(nil)
  local host = show(wm, 400)
  openSettings(host)
  pick("Alerts")
  ns.LeadsWindow.ToggleSettings() -- the window takes the pane
  Assert.same({ ns.SettingsPane.Screen(), SettingsFixture.navButton("General").parent:IsVisible() }, { "split", true }, "handed over: split")
  resize(host, 600) -- the panel no longer owns the pane: crossing widths leaves it alone
  resize(host, 300)
  Assert.equal(ns.SettingsPane.Screen(), "split", "the panel's resizes leave the window's pane alone")
end

return function()
  testSettingsLinkOpensNavInNarrowHost()
  testSettingsLinkFromDetailsThenBackLandsOnList()
  testPageButtonThenHeaderArrow()
  testEveryShowStartsOnTheList()
  testInstanceGateLeavesSettingsForTheList()
  testGrowFromPageShowsThatPageBesideTheNav()
  testGrowFromNavShowsLastPageElseFirst()
  testShrinkGoesToNavAndBackToLeadsToList()
  testWidthBoundariesForSettings()
  testSplitIgnoredWhileNarrow()
  testStandaloneWindowKeepsTheSplit()
  Wow.reset()
end
