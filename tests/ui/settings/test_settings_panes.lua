local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")
local PainterLooks = require("tests.helpers.painter_looks")
local LookFixture = require("tests.helpers.look_fixture")

local COLORS = LookFixture.COLORS

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
  Assert.same(nav.points[1], { "TOPLEFT", container, "TOPLEFT", 0, 0 })
  Assert.same(nav.points[2], { "BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0 })
  Assert.equal(nav:GetWidth(), theme.LAYOUT.LIST_WIDTH)
  Assert.same(right.points[1], { "TOPLEFT", nav, "TOPRIGHT", 1, 0 })
  Assert.same(right.points[2], { "BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0 })
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
  -- The page's box is the pane less PANE_PADDING on every side: its scroll bar hugs the right one,
  -- inside the inset border, as WhisperMessenger's; the page's own padding is inside its content.
  local inset = theme.LAYOUT.PANE_PADDING
  Assert.same(page.points[1], { "TOPLEFT", right, "TOPLEFT", inset, -inset })
  Assert.same(page.points[2], { "BOTTOMRIGHT", right, "BOTTOMRIGHT", -inset, inset })
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
  Assert.same(back.points[2], { "BOTTOMRIGHT", nav, "BOTTOMRIGHT", -4, 4 }, "its width is the nav's")
  Assert.equal(back:GetHeight(), 28)
  Assert.truthy(back:GetFrameLevel() > art:GetFrameLevel())
  Assert.equal(right.parent, nav.parent)
end

-- Spec "Looks": the nav button's selected texture and its HIGHLIGHT hover follow the leads-row rows, the native selected one untinted.
local function testNavButtonLooks()
  local ns = SettingsFixture.load()
  panes(ns)
  local RowArt = require("CraftAlert.UI.RowArt")
  local button = SettingsFixture.navButton("General")
  local art = ns.Theme.ART
  Assert.same(
    { button.hover.layer, button.hover.texture, button.hover.blendMode, button.hover.alpha },
    { "HIGHLIGHT", art.LIST_HOVER, "ADD", 0.18 },
    "the nav button keeps its HIGHLIGHT texture"
  )
  local want = PainterLooks.overlays(ns.Theme, nil)
  for _, mode in ipairs(PainterLooks.SEQUENCE) do
    RowArt.ApplyLook(button.hover, button.selected, PainterLooks.look(mode), nil)
    PainterLooks.checkOverlay(button.selected, want.selected[mode], mode .. " nav selected")
    PainterLooks.checkOverlay(button.hover, want.hover[mode], mode .. " nav hover")
    Assert.same(
      { button.selected.alpha, button.hover.alpha, button.selected.shown },
      { want.selected[mode].alpha, want.hover[mode].alpha, false },
      mode .. ": alphas (the highlight keeps its peak, the client shows it while hovered); General is not the selected page"
    )
  end
end

local function testApplyLookFlat()
  local ns = SettingsFixture.load()
  local _, container, nav, right, box = panes(ns)
  local flat = LookFixture.flat()
  local bars = LookFixture.spy(ns.ScrollBar, "ApplyLook")
  ns.SettingsPane.ApplyLook(flat)
  Assert.same(
    { regionOf(nav, "BACKGROUND").color, regionOf(right, "BACKGROUND").color },
    { COLORS.bg_secondary, COLORS.bg_primary },
    "nav bg_secondary, page pane bg_primary"
  )
  Assert.same({ insetArt(nav):IsShown(), insetArt(right):IsShown() }, { false, false }, "borders hidden")
  Assert.same(regionOf(container, "BORDER").color, COLORS.contacts_divider, "divider")
  local button = SettingsFixture.navButton("Alerts")
  Assert.same(
    { button.selected.color, button.selected.blendMode, button.selected.alpha },
    { COLORS.bg_contact_selected, "BLEND", 1 },
    "selected nav button"
  )
  Assert.same({ button.hover.color, button.hover.blendMode }, { COLORS.bg_contact_hover, "BLEND" }, "hovered nav button")
  Assert.equal(LookFixture.saw(bars, SettingsFixture.pageBar(box), flat), true, "a built page's scroll bar")
  -- Built later: a page opened and a nav button added after the look.
  local before = #bars
  Widgets.click(SettingsFixture.navButton("Greetings"), "LeftButton")
  local last = bars[#bars]
  Assert.same({ #bars > before, last[1].parent.parent == right, last[2] == flat }, { true, true, true }, "a page built later: the last look")
  ns.SettingsPane.AddPage({
    id = "extra",
    title = "Extra",
    Create = function()
      return { Refresh = function() end }
    end,
  })
  Assert.same(SettingsFixture.navButton("Extra").selected.color, COLORS.bg_contact_selected, "a nav button built later")
end

local function testApplyLookNativeAfterFlat()
  local ns = SettingsFixture.load()
  local _, container, nav, right = panes(ns)
  ns.SettingsPane.ApplyLook(LookFixture.flat())
  ns.SettingsPane.ApplyLook(LookFixture.NATIVE)
  local art, button = ns.Theme.ART, SettingsFixture.navButton("Alerts")
  Assert.same({ insetArt(nav):IsShown(), insetArt(right):IsShown() }, { true, true }, "borders back")
  Assert.same(regionOf(container, "BORDER").color, ns.Theme.COLORS.divider, "divider back")
  Assert.same(
    { button.selected.texture, button.selected.blendMode, button.selected.alpha },
    { art.LIST_SELECTED, "ADD", art.LIST_SELECTED_ALPHA },
    "nav selected back"
  )
  Assert.equal(button.selected.color, nil, "nav selected: no flat colour left")
  Assert.same({ button.hover.blendMode, button.hover.alpha }, { "ADD", art.LIST_HOVER_ALPHA }, "nav hover back")
end

local function newHost()
  return _G["CreateFrame"]("Frame", nil, rawget(_G, "UIParent"))
end

-- One owner at a time: the last host to attach holds the pane and the earlier one is told.
local function testAttachMovesBetweenHosts()
  local ns = SettingsFixture.load()
  local pane = ns.SettingsPane
  local hostA, hostB = newHost(), newHost()
  local log = {}
  pane.Attach(hostA, function()
    log[#log + 1] = "backA"
  end, function()
    log[#log + 1] = "detachA"
  end)
  pane.Show()
  local nav = SettingsFixture.navButton("General").parent
  local container = nav.parent
  Assert.equal(container.parent, hostA)
  Assert.same(container.points, { { "ALL", hostA } })
  Assert.same(log, {}, "the first attach detaches no one")
  pane.Attach(hostA, function()
    log[#log + 1] = "backA2"
  end, function()
    log[#log + 1] = "detachA"
  end)
  Assert.same(log, {}, "attaching to the same host again detaches no one")
  pane.Attach(hostB, function()
    log[#log + 1] = "backB"
  end)
  Assert.same(log, { "detachA" }, "the previous owner is told once")
  Assert.equal(container.parent, hostB)
  Assert.same(container.points, { { "ALL", hostB } })
  Assert.same(nav.points[1], { "TOPLEFT", container, "TOPLEFT", 0, 0 })
  pane.Show()
  Widgets.click(SettingsFixture.button(hostB, "Back to leads"))
  Assert.same(log, { "detachA", "backB" }, "Back runs the current owner's onBack")
  pane.Attach(hostA, function() end)
  Assert.same(log, { "detachA", "backB" }, "an owner without onDetach is skipped")
end

local function testSetNavWidth()
  local ns = SettingsFixture.load()
  ns.SettingsPane.Attach(newHost(), function() end)
  ns.SettingsPane.Show()
  local nav = SettingsFixture.navButton("General").parent
  ns.SettingsPane.SetNavWidth(200)
  Assert.equal(nav:GetWidth(), 200)
  local back = SettingsFixture.button(nav, "Back to leads")
  Assert.same(back.points[1], { "BOTTOMLEFT", nav, "BOTTOMLEFT", 4, 4 })
  Assert.same(back.points[2], { "BOTTOMRIGHT", nav, "BOTTOMRIGHT", -4, 4 })
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

-- Width a TOPLEFT/BOTTOMRIGHT pair leaves inside a parent `width` wide.
local function innerWidth(frame, width)
  return width - frame.points[1][4] + frame.points[2][4]
end

-- Controls are at most CONTROL_WIDTH wide from the page's left edge: at the window's minimum width
-- the page keeps them at full width, through the real anchors of the content frame, pane and page.
local function testMinimumWidthFitsControls()
  local ns = SettingsFixture.load()
  local window, _, nav, right, page = panes(ns)
  local layout = ns.Theme.LAYOUT
  local content = innerWidth(window.content, layout.WINDOW_MIN_WIDTH)
  local pane = innerWidth(right, content - nav:GetWidth())
  -- The rows sit inside the box less the bar's width, less the page's padding on both sides.
  local bar = SettingsFixture.pageBar(page)
  local padding = layout.PAGE_PADDING
  local rows = innerWidth(page, pane) - bar:GetWidth() - padding.left - padding.right
  Assert.truthy(rows >= layout.CONTROL_WIDTH, "controls fit at the minimum width")
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
  testNavButtonLooks()
  testApplyLookFlat()
  testApplyLookNativeAfterFlat()
  testAttachMovesBetweenHosts()
  testSetNavWidth()
  testNoAtlasNoFill()
  testMinimumWidthFitsControls()
  testBandEmptyInSettings()
  Wow.reset()
end
