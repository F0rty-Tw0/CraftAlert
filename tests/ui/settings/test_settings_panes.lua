local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")

local function regionOf(owner, layer)
  for _, region in ipairs(owner.regions) do
    if region.layer == layer then
      return region
    end
  end
end

local function insetArt(owner)
  for _, candidate in ipairs(Wow.frames) do
    if candidate.template == "InsetFrameTemplate" and candidate.parent == owner then
      return candidate
    end
  end
end

-- window, container, nav, right (content pane), page (the Alerts page frame)
local function panes(ns)
  SettingsFixture.open(ns, "Alerts")
  local nav = SettingsFixture.navButton("General").parent
  local container = nav.parent
  local page = SettingsFixture.row("Lead timeout")
  while page.parent.parent ~= container do
    page = page.parent
  end
  return SettingsFixture.window(), container, nav, page.parent, page
end

local function testPaneFrames()
  local ns = SettingsFixture.load({ leads = 2 })
  local window, container, nav, right, page = panes(ns)
  local theme = ns.Theme
  Assert.equal(container.parent, window.content, "the pane builds into the content frame, not the Inset")
  Assert.equal(nav.template, nil, "nav is a plain Frame")
  Assert.same(nav.points[1], { "TOPLEFT", window.content, "TOPLEFT", 0, 0 })
  Assert.same(nav.points[2], { "BOTTOMLEFT", window.content, "BOTTOMLEFT", 0, 0 })
  Assert.equal(nav:GetWidth(), theme.LAYOUT.LIST_WIDTH)
  Assert.same(right.points[1], { "TOPLEFT", nav, "TOPRIGHT", 1, 0 })
  Assert.same(right.points[2], { "BOTTOMRIGHT", window.content, "BOTTOMRIGHT", 0, 0 })
  Assert.equal(regionOf(nav, "BACKGROUND").atlas, theme.ART.PANEL_BACKGROUND)
  Assert.equal(regionOf(right, "BACKGROUND").atlas, theme.ART.WIDE_PANEL_BACKGROUND)
  for _, pane in ipairs({ nav, right }) do
    local art = insetArt(pane)
    Assert.truthy(art, "an InsetFrameTemplate art frame per pane")
    Assert.equal(art:GetFrameLevel(), pane:GetFrameLevel() + 1)
    Assert.equal(art.Bg.shown, false, "inset Bg hidden under the atlas")
  end
  local divider = regionOf(container, "BORDER")
  Assert.same(divider.color, { 1, 1, 1, 0.08 })
  Assert.equal(divider:GetWidth(), 1)
  Assert.same(divider.points[1], { "TOPLEFT", nav, "TOPRIGHT", 0, 0 })
  Assert.same(divider.points[2], { "BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 0 })
  Assert.same(page.points[1], { "TOPLEFT", right, "TOPLEFT", 16, -12 })
  Assert.truthy(page:GetFrameLevel() >= right:GetFrameLevel() + 2, "page above the art")
end

local function testNavButtonsAndBack()
  local ns = SettingsFixture.load()
  local _, _, nav, right = panes(ns)
  local art = insetArt(nav)
  local general, alerts = SettingsFixture.navButton("General"), SettingsFixture.navButton("Alerts")
  Assert.equal(general:GetHeight(), 28)
  Assert.same(general.points[1], { "TOPLEFT", nav, "TOPLEFT", 2, -4 })
  Assert.same(general.points[2], { "TOPRIGHT", nav, "TOPRIGHT", -2, -4 })
  Assert.same(alerts.points[1], { "TOPLEFT", nav, "TOPLEFT", 2, -32 })
  Assert.equal(general.label.font, "GameFontNormal")
  Assert.same(general.label.points[1], { "LEFT", general, "LEFT", 12, 0 })
  Assert.truthy(general:GetFrameLevel() > art:GetFrameLevel(), "buttons draw above the inset art")
  local back = SettingsFixture.button(SettingsFixture.window(), "Back to leads")
  Assert.equal(back.parent, nav)
  Assert.same(back.points[1], { "BOTTOMLEFT", nav, "BOTTOMLEFT", 4, 4 })
  Assert.equal(back:GetHeight(), 28)
  Assert.equal(back:GetWidth(), ns.Theme.LAYOUT.LIST_WIDTH - 8)
  Assert.truthy(back:GetFrameLevel() > art:GetFrameLevel())
  Assert.equal(right.parent, nav.parent)
end

-- Classic flavors lack the atlases: no fill, no error (the same guard as the leads view).
local function testNoAtlasNoFill()
  local ns = SettingsFixture.load()
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      return nil
    end,
  })
  local _, _, nav, right = panes(ns)
  Assert.equal(regionOf(nav, "BACKGROUND").atlas, nil)
  Assert.equal(regionOf(right, "BACKGROUND").atlas, nil)
end

local function testMinimumWidthFitsControls()
  local ns = UiFixture.load()
  local layout = ns.Theme.LAYOUT
  local content = layout.WINDOW_MIN_WIDTH - 4 - 6 - layout.LIST_WIDTH - 1
  Assert.truthy(content >= layout.CONTROL_WIDTH + 2 * layout.PADDING, "controls fit at the minimum width")
end

local function bandTexts(window)
  local texts = {}
  for _, region in ipairs(window.regions) do
    local text = region.GetText and region:GetText() or ""
    if string.find(text, "%d+ lead") then
      texts[#texts + 1] = text
    end
  end
  return texts
end

local function testBandEmptyInSettings()
  local ns = UiFixture.load({ leads = 2 }) -- not SettingsFixture: it spies LeadsWindow.Refresh (settings_fixture.lua:29-37), which writes the band
  ns.LeadsWindow.Toggle()
  local window = SettingsFixture.window()
  Assert.same(bandTexts(window), { "2 leads" })
  Widgets.click(window.gear)
  Assert.same(bandTexts(window), {}, "nothing in the band in Settings")
end

return function()
  testPaneFrames()
  testNavButtonsAndBack()
  testNoAtlasNoFill()
  testMinimumWidthFitsControls()
  testBandEmptyInSettings()
  Wow.reset()
end
