local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Layout = require("tests.helpers.layout")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Every settings page scrolls (UI/ScrollView.lua, both windows) and fits WhisperMessenger's
-- ~240 px page. The fakes do not lay out: a test sizes the page's box as the client would, fires
-- its OnSizeChanged, then the child's, which the client fires after the child's SetWidth.

local PAGE = 240
local TITLES = { "General", "Alerts", "Greetings", "Keywords", "Crafters", "Linked accounts", "Test" }

local function crafters(accountDb)
  local recipes = {}
  for id = 1, 12 do
    recipes[9000 + id] = { item = 500 + id, name = "A recipe with a rather long name " .. id, prof = 164 }
  end
  accountDb.characters["Me-Realm"] = {
    source = "local",
    enabled = true,
    realms = { "Realm" },
    professions = { [164] = { name = "Blacksmithing", primary = false, read = true } },
    recipes = recipes,
  }
end

-- The shown page's scroll frame and scroll child (the rows' parent).
local function shownPage(label)
  local child = SettingsFixture.row(label).parent
  return child.parent, child
end

-- The box 300 px tall and `width` wide for the content, plus the bar's width, always kept free.
local function resize(scroll, child, width)
  local box = scroll.parent
  local room = SettingsFixture.pageBar(box):GetWidth()
  box:SetSize(width + room, 300)
  Widgets.fire(box, "OnSizeChanged", width + room, 300)
  Widgets.fire(child, "OnSizeChanged", child:GetWidth(), child:GetHeight())
end

local function isUnder(frame, ancestor)
  while frame do
    if frame == ancestor then
      return true
    end
    frame = frame.parent
  end
  return false
end

-- The visible frames under `child` and their anchored regions, the child's own (section labels,
-- notes) included.
local function regionsUnder(child)
  local regions = {}
  for _, frame in ipairs(Wow.frames) do
    if isUnder(frame, child) and SettingsFixture.visible(frame) then
      if frame ~= child then
        regions[#regions + 1] = frame
      end
      for _, region in ipairs(frame.regions) do
        if region.shown and #region.points > 0 and region.points[1][1] ~= "ALL" then
          regions[#regions + 1] = region
        end
      end
    end
  end
  return regions
end

-- A label on each page, to find the page by.
local LABELS = {
  General = "Enable Craft Alert",
  Alerts = "Alert sound",
  Greetings = "Note for",
  Keywords = "Intent words",
  Crafters = "Search recipes",
  ["Linked accounts"] = "Export string",
  Test = "Test a line",
}

-- Each page: a plain scroll frame, its child as wide as it and as tall as the content plus the
-- page's padding, the first row PAGE_PADDING in from the child's top left, and every control
-- inside the page's 240 px less the padding.
local function testPagesScrollAndFit()
  local ns = SettingsFixture.load({ db = crafters })
  local padding = ns.Theme.LAYOUT.PAGE_PADDING
  for _, title in ipairs(TITLES) do
    SettingsFixture.open(ns, title)
    local scroll, child = shownPage(LABELS[title])
    Assert.equal(scroll.frameType, "ScrollFrame", title .. ": the page scrolls")
    Assert.equal(scroll.template, nil, title .. ": no template")
    Assert.equal(scroll:GetScrollChild(), child, title .. ": the rows draw on the scroll child")
    -- Without these the client left most rows undrawn (2026-10-25, /caprobe: no rect).
    Assert.same(child.points[1], { "TOPLEFT", scroll, "TOPLEFT", 0, 0 }, title .. ": child anchored")
    Assert.equal(scroll.clipsChildren, true, title .. ": the frame clips its rows")
    resize(scroll, child, PAGE)
    Assert.equal(child:GetWidth(), PAGE, title .. ": the child follows the frame's width")
    -- Measured from the child's top-left: the child is anchored into the window.
    local childLeft = Layout.edges(child)
    local childTop = Layout.ys(child)
    local lowest, leftmost, highest = 0, PAGE, -300
    for _, region in ipairs(regionsUnder(child)) do
      -- A region without anchors is a fake's own unplaced part; the client places it with its frame.
      if #region.points > 0 then
        local left, right = Layout.edges(region)
        left, right = left - childLeft, right - childLeft
        local inside = left >= padding.left and right <= PAGE - padding.right
        Assert.truthy(inside, title .. ": a region runs from " .. left .. " to " .. right)
        local top, bottom = Layout.ys(region)
        lowest = math.min(lowest, bottom - childTop)
        leftmost = math.min(leftmost, left)
        highest = math.max(highest, top - childTop)
      end
    end
    local corner = title .. ": the first row's corner at " .. leftmost .. ", " .. highest
    Assert.same({ leftmost, highest }, { padding.left, -padding.top }, corner)
    local content = -lowest + padding.bottom
    Assert.truthy(child:GetHeight() >= content, title .. ": child " .. child:GetHeight() .. " < content " .. content)
  end
end

-- The bar shows only while the page is taller than its frame: a short page has none, a long
-- page in a short box shows it, with the overflow for its range.
local function testScrollBarHides()
  local ns = SettingsFixture.load({ db = crafters })
  SettingsFixture.open(ns, "Crafters")
  local scroll, child = shownPage("Search recipes")
  local bar = SettingsFixture.pageBar(scroll.parent)
  resize(scroll, child, PAGE)
  Assert.truthy(child:GetHeight() > 300, "the Crafters page is taller than 300 px")
  Assert.equal(bar:IsShown(), true, "a long page shows the bar")
  local _, top = bar:GetMinMaxValues()
  Assert.equal(top, child:GetHeight() - 300)
  scroll.parent:SetSize(PAGE + bar:GetWidth(), child:GetHeight() + 100)
  Widgets.fire(scroll.parent, "OnSizeChanged")
  Assert.equal(bar:IsShown(), false, "a page shorter than its frame has no bar")
end

-- Inside the scrolling page the recipe list still pages its rows with the wheel; Mute all and
-- Unmute all share the row, half each less a gap, in the column inside the page's padding.
local function testRecipeListInScroll()
  local ns = SettingsFixture.load({ db = crafters })
  SettingsFixture.open(ns, "Crafters")
  local scroll, child = shownPage("Search recipes")
  local list
  for _, frame in ipairs(Wow.frames) do
    if frame.mouseWheelEnabled and frame.scripts.OnMouseWheel and isUnder(frame, child) then
      list = frame
    end
  end
  Assert.truthy(list, "the list frame takes the wheel")
  local function firstName()
    for _, frame in ipairs(Wow.frames) do
      if frame.item and frame.parent == list and SettingsFixture.visible(frame) then
        return frame.item.text
      end
    end
  end
  local before = firstName()
  Widgets.fire(list, "OnMouseWheel", -1)
  Assert.truthy(firstName() ~= before, "a notch down pages the list")
  local layout, window = ns.Theme.LAYOUT, SettingsFixture.window()
  for _, width in ipairs({ PAGE, 600 }) do
    resize(scroll, child, width)
    local column = math.min(width - layout.PAGE_PADDING.left - layout.PAGE_PADDING.right, layout.CONTROL_WIDTH)
    local half = (column - layout.PADDING) / 2
    for _, label in ipairs({ "Mute all", "Unmute all" }) do
      local left, right = Layout.edges(SettingsFixture.button(window, label))
      Assert.equal(right - left, half, width .. ": " .. label .. " is half the row less the gap")
    end
    local muteLeft = Layout.edges(SettingsFixture.button(window, "Mute all"))
    local _, unmuteRight = Layout.edges(SettingsFixture.button(window, "Unmute all"))
    Assert.equal(unmuteRight - muteLeft, column, width .. ": the pair spans the row")
  end
end

return function()
  testPagesScrollAndFit()
  testScrollBarHides()
  testRecipeListInScroll()
  Wow.reset()
end
