local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Native-HUD spec §7.1–7.2: the settings pane lives in the leads window behind a gear. One
-- window, two modes (List and Settings), one size (min 720x420) and one position shared by both.
local PAGES = { "General", "Alerts", "Greetings", "Keywords", "Crafters", "Linked accounts", "Test" }

local function frame()
  return rawget(_G, "CraftAlertLeadsWindow")
end

local function gear()
  return frame().gear
end

-- The lead row frame at `index` (top first), or nil when the window never made one.
local function row(index)
  for _, candidate in ipairs(Wow.frames) do
    if candidate.isLeadRow and candidate.rowIndex == index then
      return candidate
    end
  end
  return nil
end

local function rowVisible(index)
  local found = row(index)
  return found ~= nil and found:IsVisible()
end

local function anyRowShown()
  for _, candidate in ipairs(Wow.frames) do
    if candidate.isLeadRow and candidate:IsShown() then
      return true
    end
  end
  return false
end

-- The details pane's empty-state frame, once it holds the empty text.
local function emptyText()
  local empty = frame().view.empty
  for _, region in ipairs(empty.regions) do
    if region.GetText and string.find(region:GetText() or "", "No leads", 1, true) then
      return empty
    end
  end
  error("no empty text")
end

local function title()
  return frame():GetTitleText():GetText()
end

local function size()
  return { frame():GetWidth(), frame():GetHeight() }
end

local function navVisible()
  return SettingsFixture.navButton("General"):IsVisible()
end

local function testToggleSettingsFromHidden()
  local ns = UiFixture.load({ leads = 2 })
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(frame():IsShown(), true)
  Assert.equal(title(), "Craft Alert — Settings")
  Assert.same(size(), { 840, 560 }, "default settings size")
  Assert.same({ frame().resizeBounds[1], frame().resizeBounds[2] }, { 720, 420 })
  Assert.equal(gear():GetNormalTexture().atlas, "common-icon-backarrow")
  Assert.equal(navVisible(), true)
  Assert.equal(rowVisible(1), false, "no lead row in Settings")
  Assert.equal(emptyText():IsShown(), false)
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(frame():IsShown(), false, "shown in Settings: ToggleSettings hides")
  ns.LeadsWindow.ToggleSettings()
  ns.LeadsWindow.Toggle()
  Assert.equal(frame():IsShown(), false, "Toggle hides in either mode")
end

local function testGearSwitchesModes()
  local ns = UiFixture.load({
    leads = 2,
    db = function(db)
      db.ui.window = { width = 500, height = 300 }
    end,
  })
  ns.LeadsWindow.Toggle()
  Assert.same(size(), { 720, 420 }, "a saved size under the minimum opens at the minimum")
  Assert.equal(rowVisible(1), true)
  Assert.equal(gear():GetNormalTexture().atlas, "QuestLog-icon-setting", "list: gear art")
  Widgets.click(gear())
  Assert.equal(gear():GetNormalTexture().atlas, "common-icon-backarrow", "settings: back arrow")
  Assert.equal(gear():GetHighlightTexture().atlas, "common-icon-backarrow")
  Assert.equal(gear().highlightLocked, nil, "no highlight lock")
  Assert.same(size(), { 720, 420 })
  Assert.equal(title(), "Craft Alert — Settings")
  Assert.equal(anyRowShown(), false, "no row drawn over the pane")
  Assert.equal(row(1).lead, nil, "rows cleared (LeadRow.Clear), not just hidden")
  Assert.equal(emptyText():IsShown(), false)
  Wow.clock.gettime = 60
  Widgets.click(gear())
  Assert.same(size(), { 720, 420 })
  Assert.same({ frame().resizeBounds[1], frame().resizeBounds[2] }, { 720, 420 })
  Assert.equal(title(), "Craft Alert — Leads")
  Assert.equal(gear():GetNormalTexture().atlas, "QuestLog-icon-setting", "back in the list: gear art")
  Assert.equal(navVisible(), false)
  Assert.equal(rowVisible(1), true)
  Assert.equal(select(2, ns.LeadsWindow.VisibleLatest()), 60, "the row is shown afresh")
end

-- Makes the window's SetSize act like a client that clamps to the resize bounds and then fires
-- OnSizeChanged (the fake does neither).
local function clientSizing()
  local target, setSize = frame(), frame().SetSize
  function target:SetSize(width, height)
    setSize(self, math.max(width, self.resizeBounds[1]), math.max(height, self.resizeBounds[2]))
    self:GetScript("OnSizeChanged")(self, self:GetWidth(), self:GetHeight())
  end
end

local function rowCount()
  local count = 0
  for _, candidate in ipairs(Wow.frames) do
    if candidate.isLeadRow then
      count = count + 1
    end
  end
  return count
end

-- Spec 3b §1: a panel button at the bottom of the nav does what the gear does in Settings.
local function testBackButton()
  local ns = UiFixture.load({
    leads = 2,
    db = function(db)
      db.ui.window = { width = 500, height = 300 }
    end,
  })
  ns.LeadsWindow.ToggleSettings()
  local back = SettingsFixture.button(frame(), "Back to leads")
  local nav = back.parent
  Assert.equal(back:IsVisible(), true)
  Assert.same(back.points[1], { "BOTTOMLEFT", nav, "BOTTOMLEFT", 4, 4 })
  Assert.equal(back:GetHeight(), 28)
  Widgets.click(back)
  Assert.equal(frame():IsShown(), true)
  Assert.equal(title(), "Craft Alert — Leads")
  Assert.same(size(), { 720, 420 })
  Assert.equal(nav:IsVisible(), false)
  Assert.equal(gear():GetNormalTexture().atlas, "QuestLog-icon-setting")
  Assert.equal(gear().highlightLocked, nil)
  Assert.equal(rowVisible(1), true)
  Widgets.click(gear())
  Assert.equal(title(), "Craft Alert — Settings", "the gear still opens Settings")
end

-- Another host attaching the pane takes it from the window: the window falls back to the list,
-- and ToggleSettings brings the pane back.
local function testPaneTakenByAnotherHost()
  local ns = UiFixture.load({ leads = 2 })
  ns.LeadsWindow.ToggleSettings()
  local other = _G["CreateFrame"]("Frame", nil, rawget(_G, "UIParent"))
  ns.SettingsPane.Attach(other, function() end)
  Assert.equal(title(), "Craft Alert — Leads")
  Assert.equal(frame().view.frame:IsShown(), true, "the leads view is back")
  Assert.equal(gear().inSettings, false, "the gear is painted for the list")
  Assert.equal(SettingsFixture.navButton("General").parent.parent.parent, other, "the pane moved to the other host")
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(title(), "Craft Alert — Settings")
  Assert.equal(frame().view.frame:IsShown(), false)
  Assert.equal(gear().inSettings, true)
  Assert.equal(SettingsFixture.navButton("General").parent.parent.parent, frame().content, "re-attached to the window")
  Assert.equal(navVisible(), true)
end

local function testModeSwitchUnderClientSizing()
  local ns = UiFixture.load({ leads = 8 })
  ns.LeadsWindow.Toggle()
  clientSizing()
  local before = rowCount()
  Widgets.click(gear())
  Assert.equal(rowCount(), before, "a mode switch draws no new row")
  Assert.same(size(), { 840, 560 }, "a mode switch does not resize")
  Widgets.click(gear())
  Assert.same(size(), { 840, 560 }, "the same size back in the list")
end

local function testWheelIgnoredInSettings()
  local ns = UiFixture.load({
    leads = 8,
    db = function(db)
      db.ui.window = { width = 360, height = 160 }
    end,
  })
  ns.LeadsWindow.ToggleSettings()
  -- The wheel is the view's, and the view is hidden behind the settings pane.
  Assert.equal(frame():GetScript("OnMouseWheel"), nil)
  Assert.equal(frame().view.frame:IsShown(), false)
  Widgets.click(gear())
  Assert.equal(row(1).lead, ns.Leads.Latest(), "the list is still at the top")
end

local function testReopenRefreshesPage()
  local ns, db = UiFixture.load()
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(SettingsFixture.row("Guild").input:GetChecked(), false)
  frame():Hide()
  db.settings.channels.guild = true
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(SettingsFixture.row("Guild").input:GetChecked(), true, "the page reads the db on reopen")
end

local function testCloseReturnsToList()
  local ns = UiFixture.load()
  ns.LeadsWindow.ToggleSettings()
  frame():Hide()
  ns.LeadsWindow.Toggle()
  Assert.same(size(), { 840, 560 })
  Assert.equal(title(), "Craft Alert — Leads")
  Assert.equal(navVisible(), false)
  frame():Hide()
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(title(), "Craft Alert — Settings")
  Assert.equal(navVisible(), true)
  frame():Hide()
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(frame():IsShown(), true)
  Assert.equal(title(), "Craft Alert — Settings", "a window hidden in Settings reopens there")
  Assert.same(size(), { 840, 560 })
end

local function selectedPage()
  local general, alerts = SettingsFixture.navButton("General"), SettingsFixture.navButton("Alerts")
  return { general = general.selected:IsShown(), alerts = alerts.selected:IsShown() }
end

local function testReopenKeepsPage()
  local ns = UiFixture.load()
  SettingsFixture.open(ns, "Alerts")
  frame():Hide()
  ns.LeadsWindow.ToggleSettings()
  Assert.same(selectedPage(), { general = false, alerts = true }, "reopens on the page last shown")
  Widgets.click(gear())
  Widgets.click(gear())
  Assert.same(selectedPage(), { general = false, alerts = true }, "List and back keeps the page")
end

local function resizeTo(width, height)
  local grip = frame().resizeGrip
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  grip.ghost:SetSize(width, height)
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
end

local function testSizeSharedByModes()
  local ns, db = UiFixture.load()
  ns.LeadsWindow.Toggle()
  resizeTo(900, 520)
  Assert.same({ db.ui.window.width, db.ui.window.height }, { 900, 520 })
  Assert.equal(db.ui.window.point, "TOPLEFT", "the position is saved beside the size")
  Widgets.click(gear())
  Assert.same(size(), { 900, 520 }, "settings keeps the list size")
  resizeTo(760, 500)
  Assert.same({ db.ui.window.width, db.ui.window.height }, { 760, 500 })
  Widgets.click(gear())
  Assert.same(size(), { 760, 500 }, "list takes the settings resize")
  Assert.equal(db.ui.settings, nil, "no size saved under settings")
  frame():Hide()
  ns.LeadsWindow.ToggleSettings()
  Assert.same(size(), { 760, 500 }, "reopened in settings at the shared size")
end

local function testSavedSizeClampedToScreen()
  local ns = UiFixture.load({
    db = function(db)
      db.ui.window = { width = 1e6, height = 1e6 }
    end,
  })
  ns.LeadsWindow.ToggleSettings()
  local screen = rawget(_G, "UIParent")
  Assert.same(size(), { screen:GetWidth(), screen:GetHeight() }, "no bigger than the screen")
end

local function testSmallSavedSizeClampsUp()
  local ns = UiFixture.load({
    db = function(db)
      db.ui.window = { width = 460, height = 320 } -- a size saved before the minimum grew
    end,
  })
  ns.LeadsWindow.Toggle()
  Assert.same(size(), { 720, 420 }, "no smaller than the minimum")
  ns = UiFixture.load({
    db = function(db)
      db.ui.window = { width = 100, height = 100 }
    end,
  })
  ns.LeadsWindow.ToggleSettings()
  Assert.same(size(), { 720, 420 }, "in settings too")
end

local function testRefreshInSettings()
  local ns, db = UiFixture.load({ leads = 2 })
  db.settings.opacity = 0.5
  ns.LeadsWindow.ToggleSettings()
  ns.LeadsWindow.Refresh()
  Assert.equal(rowVisible(1), false)
  Assert.equal(emptyText():IsShown(), false)
  Assert.equal(frame():GetAlpha(), 0.5)
  frame():GetScript("OnSizeChanged")(frame(), 700, 500)
  Assert.equal(anyRowShown(), false, "a resize in Settings draws no rows")
end

local function testGearTooltip()
  local ns = UiFixture.load()
  ns.LeadsWindow.Toggle()
  local tooltip = ns.Tooltip.Get()
  Widgets.fire(gear(), "OnEnter")
  Assert.equal(tooltip.owner, gear())
  Assert.equal(tooltip.anchor, "ANCHOR_BOTTOMLEFT")
  Assert.same(tooltip.lines, { "Settings", " ", "Click: open settings" })
  Assert.same(tooltip.colors[1], { 1, 0.82, 0 })
  Assert.same(tooltip.colors[3], { 0.1, 1, 0.1 })
  Widgets.click(gear())
  Assert.equal(tooltip.lines[3], "Click: back to leads", "the line follows the click")
  Widgets.fire(gear(), "OnLeave")
  Assert.equal(tooltip.shown, false)
end

local function testGearArtAndPlace()
  local ns = UiFixture.load()
  ns.LeadsWindow.Toggle()
  Assert.same(gear().points[1], { "RIGHT", frame().CloseButton, "LEFT", -2, 0 })
  Assert.same({ gear():GetWidth(), gear():GetHeight() }, { 20, 20 })
  Assert.equal(gear():GetNormalTexture().atlas, "QuestLog-icon-setting")
  Assert.equal(gear():GetHighlightTexture().blendMode, "ADD")
  -- Above the NineSlice border (level 500), or its title strip hides them in game.
  local border = frame().NineSlice:GetFrameLevel()
  Assert.truthy(gear():GetFrameLevel() > border, "the gear sits above the border")
  Assert.truthy(frame().resizeGrip:GetFrameLevel() > border, "the resize grip sits above the border")
  ns = UiFixture.load()
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      return nil
    end,
  })
  ns.LeadsWindow.Toggle()
  Assert.equal(gear():GetNormalTexture().texture, "Interface\\WorldMap\\Gear_64Grey")
  Widgets.click(gear())
  Assert.equal(gear():GetNormalTexture().texture, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
end

-- The module's package.loaded entry under either key: the test runners strip the "CraftAlert."
-- prefix before requiring (scripts/run_test.py), so the module sits under the short one.
local function loaded(path)
  return package.loaded[path] or package.loaded["CraftAlert." .. path]
end

-- Spec §7.1: the pane loads before the pages; a load-time page require would loop.
local function testNoPageAtLoad()
  UiFixture.load()
  Assert.truthy(loaded("UI.Settings.PageGeneral"), "the fixture loaded the pages")
  for _, name in ipairs(PAGES) do
    package.loaded["UI.Settings.Page" .. name] = nil
    package.loaded["CraftAlert.UI.Settings.Page" .. name] = nil
  end
  Fresh.require("UI.Settings.SettingsPane")
  for _, name in ipairs(PAGES) do
    Assert.equal(loaded("UI.Settings.Page" .. name), nil, "Page" .. name .. " loaded with the pane")
  end
end

-- Entering an instance hides the window in either mode; Toggle and ToggleSettings stay silent
-- there; leaving does not reopen it.
local function testHiddenInInstance()
  local ns = UiFixture.load({ leads = 1 })
  local inside = false
  Wow.stub("IsInInstance", function()
    return inside, inside and "party" or "none"
  end)
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(frame():IsShown(), true)
  ns.LeadsWindow.OnGate(false, { reason = "noTrade" })
  Assert.equal(frame():IsShown(), true, "outside an instance the gate leaves it")
  inside = true
  ns.LeadsWindow.OnGate(false, { reason = "instance" })
  Assert.equal(frame():IsShown(), false)
  local chatBefore = #Wow.chat
  ns.LeadsWindow.Toggle()
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(frame():IsShown(), false, "no window in an instance")
  Assert.equal(#Wow.chat, chatBefore, "silent")
  inside = false
  ns.LeadsWindow.OnGate(true, { active = true })
  Assert.equal(frame():IsShown(), false, "not reopened on leaving")
  Wow.stub("IsInInstance", nil)
end

return function()
  testHiddenInInstance()
  testToggleSettingsFromHidden()
  testGearSwitchesModes()
  testBackButton()
  testPaneTakenByAnotherHost()
  testModeSwitchUnderClientSizing()
  testWheelIgnoredInSettings()
  testReopenRefreshesPage()
  testCloseReturnsToList()
  testReopenKeepsPage()
  testSizeSharedByModes()
  testSavedSizeClampedToScreen()
  testSmallSavedSizeClampsUp()
  testRefreshInSettings()
  testGearTooltip()
  testGearArtAndPlace()
  testNoPageAtLoad()
  Wow.reset()
end
