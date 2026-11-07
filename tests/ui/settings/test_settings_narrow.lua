local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Attach the pane to a 400x500 host; SetNarrow(narrow) as the bridge does; Show.
local function open(narrow)
  local ns = SettingsFixture.load()
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(400, 500)
  local calls = { back = 0 }
  ns.SettingsPane.Attach(host, function()
    calls.back = calls.back + 1
  end)
  ns.SettingsPane.SetNarrow(narrow)
  ns.SettingsPane.Show()
  return ns, host, calls
end

local function nav()
  return SettingsFixture.navButton("General").parent
end

local function pageHeader()
  return assert(SettingsFixture.pageHeader(), "no page header")
end

local function pick(title)
  Widgets.click(SettingsFixture.navButton(title), "LeftButton")
end

-- Alerts' "Lead timeout" is on the shown page.
local function rowVisible(label)
  local ok, row = pcall(SettingsFixture.row, label)
  return ok and row:IsVisible()
end

-- The Alerts page's box: the row's ancestor whose parent is the right pane.
local function boxOf(container)
  local box = SettingsFixture.row("Lead timeout")
  while box.parent.parent ~= container do
    box = box.parent
  end
  return box
end

local function divider(container)
  for _, region in ipairs(container.regions) do
    if region.layer == "BORDER" then
      return region
    end
  end
end

local function fill(c)
  return { { "TOPLEFT", c, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0 } }
end

local function testScreenIsSplitBeforeAnyPane()
  local ns = SettingsFixture.load()
  Assert.equal(ns.SettingsPane.Screen(), "split", "no pane yet")
end

local function testWideKeepsBothPanes()
  local ns = open(false)
  local header = pageHeader()
  Assert.same(
    { ns.SettingsPane.Screen(), nav():IsVisible(), header.parent:IsVisible(), header:IsVisible() },
    { "split", true, true, false },
    "wide: nav and page side by side, no header"
  )
end

local function testNarrowShowStartsOnNav()
  local ns = open(true)
  local container = nav().parent
  Assert.equal(ns.SettingsPane.Screen(), "nav", "narrow show: the nav")
  Assert.same(nav().points, fill(container), "the nav spans the pane")
  Assert.same({ pageHeader().parent:IsVisible(), divider(container):IsShown() }, { false, false }, "no page, no divider")
  Assert.equal(SettingsFixture.button(container, "Back to leads"):IsVisible(), true, "Back to leads stays at the nav's bottom")
end

local function testNavButtonOpensPageUnderHeader()
  local ns = open(true)
  pick("Alerts")
  local container, header = nav().parent, pageHeader()
  local right = header.parent
  Assert.equal(ns.SettingsPane.Screen(), "page", "a nav button opens its page")
  Assert.same(right.points, fill(container), "the page pane spans the pane")
  Assert.same(
    { nav():IsVisible(), header:IsVisible(), header.title:GetText(), rowVisible("Lead timeout") },
    { false, true, "Alerts", true },
    "page screen: header with the page title, nav hidden"
  )
  Assert.same(boxOf(container).points[1], { "TOPLEFT", right, "TOPLEFT", 4, -32 }, "the page starts under the header")
end

local function testHeaderArrowReturnsToNav()
  local ns, _, calls = open(true)
  pick("Alerts")
  Widgets.click(pageHeader().back)
  Assert.same(
    { ns.SettingsPane.Screen(), nav():IsVisible(), pageHeader():IsVisible(), calls.back },
    { "nav", true, false, 0 },
    "the arrow goes to the nav, not out of settings"
  )
  Assert.equal(SettingsFixture.navButton("Alerts").selected:IsShown(), false, "no row looks picked on the phone nav")
end

local function testBackToLeadsStillRunsOnBack()
  local _, _, calls = open(true)
  Widgets.click(SettingsFixture.button(nav().parent, "Back to leads"))
  Assert.equal(calls.back, 1, "onBack runs")
end

local function testEachShowStartsOnNav()
  local ns = open(true)
  pick("Alerts")
  ns.SettingsPane.Hide()
  ns.SettingsPane.Show()
  Assert.equal(ns.SettingsPane.Screen(), "nav", "the screen is not kept across shows")
end

local function testGrowFromPageKeepsThatPage()
  local ns = open(true)
  pick("Alerts")
  ns.SettingsPane.SetNarrow(false)
  local container, header = nav().parent, pageHeader()
  Assert.same({
    ns.SettingsPane.Screen(),
    nav():IsVisible(),
    rowVisible("Lead timeout"),
    header:IsVisible(),
    SettingsFixture.navButton("Alerts").selected:IsShown(),
  }, { "split", true, true, false, true }, "page kept beside the nav")
  Assert.same(nav().points, { { "TOPLEFT", container, "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0 } }, "nav back at the left")
  Assert.equal(nav():GetWidth(), ns.Theme.LAYOUT.LIST_WIDTH, "nav at its list width")
  Assert.same(header.parent.points[1], { "TOPLEFT", nav(), "TOPRIGHT", 1, 0 }, "page pane right of the nav")
  Assert.same(boxOf(container).points[1], { "TOPLEFT", header.parent, "TOPLEFT", 4, -4 }, "the page is back at the top")
end

local function testGrowFromNavShowsLastPageElseFirst()
  local ns = open(true)
  pick("Alerts")
  Widgets.click(pageHeader().back)
  ns.SettingsPane.SetNarrow(false)
  Assert.equal(rowVisible("Lead timeout"), true, "the last page shown")
  local freshNs = open(true)
  freshNs.SettingsPane.SetNarrow(false)
  Assert.equal(SettingsFixture.navButton("General").selected:IsShown(), true, "no page yet: the first")
end

local function testShrinkGoesToNavAndKeepsTheLastPage()
  local ns = open(false)
  pick("Alerts")
  ns.SettingsPane.SetNarrow(true)
  Assert.same({ ns.SettingsPane.Screen(), rowVisible("Lead timeout") }, { "nav", false }, "wide to narrow: the nav")
  ns.SettingsPane.SetNarrow(false)
  Assert.equal(rowVisible("Lead timeout"), true, "and back wide: the same page")
end

local function testSetNarrowTwiceKeepsTheScreen()
  local ns = open(true)
  pick("Alerts")
  ns.SettingsPane.SetNarrow(true)
  Assert.equal(ns.SettingsPane.Screen(), "page", "a repeat of the same mode changes nothing")
end

local function testNavWidthWaitsForWide()
  local ns = open(true)
  ns.SettingsPane.SetNavWidth(200)
  Assert.same(nav().points, fill(nav().parent), "ignored while narrow")
  ns.SettingsPane.SetNarrow(false)
  Assert.equal(nav():GetWidth(), 200, "applied once wide")
end

local function testAttachGivesTheNextOwnerTheSplit()
  local ns = open(true)
  pick("Alerts")
  ns.SettingsPane.Attach(_G["CreateFrame"]("Frame", nil, _G["UIParent"]), function() end)
  ns.SettingsPane.Show()
  Assert.same(
    { ns.SettingsPane.Screen(), nav():IsVisible(), pageHeader():IsVisible() },
    { "split", true, false },
    "a host that never asks for narrow gets the split"
  )
end

return function()
  testScreenIsSplitBeforeAnyPane()
  testWideKeepsBothPanes()
  testNarrowShowStartsOnNav()
  testNavButtonOpensPageUnderHeader()
  testHeaderArrowReturnsToNav()
  testBackToLeadsStillRunsOnBack()
  testEachShowStartsOnNav()
  testGrowFromPageKeepsThatPage()
  testGrowFromNavShowsLastPageElseFirst()
  testShrinkGoesToNavAndKeepsTheLastPage()
  testSetNarrowTwiceKeepsTheScreen()
  testNavWidthWaitsForWide()
  testAttachGivesTheNextOwnerTheSplit()
  Wow.reset()
end
