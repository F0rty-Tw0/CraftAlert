local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Spec C.2, C.4: the leads in WhisperMessenger's panel has a settings mode. The gear swaps the
-- leads view for the settings pane inside the host; Back returns; the mode is never saved.
local function boot(opts)
  local ns, db, calls = UiFixture.load(opts or { leads = 2 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  return ns, db, calls, wm
end

local function newHost(width)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, 400)
  return host
end

local function descendantOf(frame, host)
  local parent = frame.parent
  while parent do
    if parent == host then
      return true
    end
    parent = parent.parent
  end
  return false
end

-- The embedded view's settings gear: the one Button under the host with the gear's art (.normal).
local function gearOf(host)
  local found
  for _, frame in ipairs(Wow.frames) do
    if frame.frameType == "Button" and frame.normal and descendantOf(frame, host) then
      Assert.equal(found, nil, "exactly one gear")
      found = frame
    end
  end
  return found
end

-- The pane's Back button, its nav and its container (the nav's parent), shown or not.
local function backOf(host)
  for _, frame in ipairs(Wow.frames) do
    if frame.label and frame.label:GetText() == "Back to leads" and descendantOf(frame, host) then
      return frame, frame.parent, frame.parent.parent
    end
  end
  error("no Back button under the host")
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
  local host = newHost(width or 600)
  wm.showPanel("CraftAlert", host, listWidth)
  return host
end

-- The list pane's width and the divider's x from the host's left (it anchors to the pane's right).
local function splitOf(view)
  local Layout = require("tests.helpers.layout")
  local dividerX = Layout.edges(view.divider)
  return view.listPane:GetWidth(), dividerX
end

local function testGearOpensSettingsInTheHost()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm)
  Assert.equal(ns.BridgePanel.InSettings(), false)
  Assert.equal(captured.view.frame:IsShown(), true)
  Widgets.click(gearOf(host))
  local back, _, container = backOf(host)
  Assert.equal(captured.view.frame:IsShown(), false, "the leads view is hidden")
  Assert.same({ container.parent, container:IsShown(), back:IsVisible() }, { host, true, true }, "the pane fills the host")
  Assert.equal(ns.BridgePanel.InSettings(), true)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "no standalone window")
  Assert.same(wm.callsTo("TogglePanel"), {}, "WM was not asked to close the panel")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "the leads view shows no rows")
end

local function testBackReturnsToLeads()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm)
  Widgets.click(gearOf(host))
  local back, _, container = backOf(host)
  Widgets.click(back)
  Assert.same({ container:IsShown(), ns.BridgePanel.InSettings(), captured.view.frame:IsShown() }, { false, false, true })
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 }, "the leads view is back, refreshed")
  Widgets.click(gearOf(host))
  Assert.equal(container:IsShown(), true, "the gear opens settings again")
end

local function testToggleSettings()
  local ns, _, _, wm = boot()
  ns.BridgePanel.ToggleSettings()
  ns.BridgePanel.ShowSettings()
  Assert.equal(ns.BridgePanel.InSettings(), false, "no-ops while hidden")
  local host = showWith(wm)
  ns.BridgePanel.ToggleSettings()
  Assert.equal(ns.BridgePanel.InSettings(), true)
  ns.BridgePanel.ShowSettings()
  Assert.equal(ns.BridgePanel.InSettings(), true, "ShowSettings keeps settings")
  ns.BridgePanel.ToggleSettings()
  Assert.equal(ns.BridgePanel.InSettings(), false, "toggle returns")
  ns.BridgePanel.ShowSettings()
  Assert.equal(ns.BridgePanel.InSettings(), true)
  local _, _, container = backOf(host)
  Assert.equal(container:IsShown(), true)
end

-- In an instance the gear does nothing: the panel stays on its (empty) leads.
local function testGearOffInInstance()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  showWith(wm)
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.BridgePanel.ToggleSettings()
  Assert.same({ ns.BridgePanel.InSettings(), captured.view.frame:IsShown() }, { false, true })
  Wow.stub("IsInInstance", nil)
end

-- Settings open when the player enters an instance: the gate goes back to the leads.
local function testInstanceGateLeavesSettings()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm)
  Widgets.click(gearOf(host))
  Assert.equal(ns.BridgePanel.InSettings(), true)
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.WhisperBridge.OnGate()
  local _, _, container = backOf(host)
  Assert.same({ ns.BridgePanel.InSettings(), container:IsShown(), captured.view.frame:IsShown() }, { false, false, true })
  Wow.stub("IsInInstance", nil)
end

-- In an instance the gear still closes settings that are open (it only refuses to open them).
local function testGearClosesSettingsInInstance()
  local ns, _, _, wm = boot()
  local host = showWith(wm)
  Widgets.click(gearOf(host))
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.BridgePanel.ToggleSettings()
  Assert.equal(ns.BridgePanel.InSettings(), false)
  Wow.stub("IsInInstance", nil)
end

local function testModeIsNotSaved()
  local ns, _, _, wm = boot()
  local host = showWith(wm)
  Widgets.click(gearOf(host))
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert", host)
  local _, _, container = backOf(host)
  Assert.same({ ns.BridgePanel.InSettings(), container:IsShown() }, { false, false }, "every show starts on the leads")
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 })
  -- a new host, shown while the old one was left in settings
  Widgets.click(gearOf(host))
  wm.hidePanel("CraftAlert")
  local other = showWith(wm)
  Assert.equal(ns.BridgePanel.InSettings(), false, "a new host starts on the leads too")
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 })
  Assert.equal(gearOf(other) ~= nil, true)
end

local function testRefreshSkippedInSettings()
  local ns, _, _, wm = boot()
  local host = showWith(wm)
  Widgets.click(gearOf(host))
  local refreshed = 0
  local refresh = ns.LeadsView.Refresh
  ns.LeadsView.Refresh = function(...)
    refreshed = refreshed + 1
    return refresh(...)
  end
  ns.BridgePanel.Refresh()
  ns.Leads.Dismiss(ns.Leads.Latest().id) -- a change event reaches BridgePanel.Refresh too
  Assert.equal(refreshed, 0, "settings mode leaves the leads view alone")
  Widgets.click(backOf(host))
  Assert.truthy(refreshed >= 1, "Back refreshes the leads")
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 }, "with the lead dismissed meanwhile")
end

local function testNavWidthInWm()
  local ns, _, _, wm = boot()
  local wide = showWith(wm, 600) -- 600 - 340 = 260
  Widgets.click(gearOf(wide))
  local _, nav = backOf(wide)
  Assert.equal(nav:GetWidth(), 260)
  local narrow = showWith(wm, 500) -- 500 - 340 = 160 -> 180
  Widgets.click(gearOf(narrow))
  _, nav = backOf(narrow)
  Assert.equal(nav:GetWidth(), 180)
end

-- WM's divider sets the list width (onSplit, after onShow and on every relayout); without it the
-- list takes what the host leaves the details, between 180 and 260.
local function testSplitSetsListWidth()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  showWith(wm, 600, 220)
  Assert.same({ splitOf(captured.view) }, { 220, 220 }, "onSplit after onShow: pane and divider")
  wm.split("CraftAlert", 240)
  Assert.same({ splitOf(captured.view) }, { 240, 240 }, "a later onSplit")
  Assert.equal(ns.WhisperBridge.VisibleLead() ~= nil, true, "the leads stay refreshed")
end

local function testNoSplitKeepsTheClamp()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  showWith(wm, 600)
  Assert.same({ splitOf(captured.view) }, { 260, 260 }, "600 - 340 -> 260")
  showWith(wm, 500)
  Assert.same({ splitOf(captured.view) }, { 180, 180 }, "500 - 340 -> 180")
end

local function testSplitFromAnotherHostIsIgnored()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local panel = wm.panels.CraftAlert
  panel.onSplit(newHost(600), 220) -- before any onShow
  Assert.equal(captured.view, nil, "nothing was built")
  local host = showWith(wm, 600)
  panel.onSplit(newHost(600), 220) -- not the host the view is in
  Assert.same({ splitOf(captured.view) }, { 260, 260 }, "another host changes nothing")
  Assert.equal(host, captured.view.parent)
end

-- A width that is not a number (a WM bug) is no split: the list goes back to the clamp.
local function testNonNumberSplitKeepsTheClamp()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  showWith(wm, 600, 220)
  wm.split("CraftAlert", "220")
  Assert.same({ splitOf(captured.view) }, { 260, 260 }, "600 - 340 -> 260")
end

-- A new host starts on the clamp again: the old host's divider width is not its own.
local function testRebuildResetsSplit()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  showWith(wm, 600, 220)
  Assert.equal(splitOf(captured.view), 220)
  showWith(wm, 600)
  Assert.same({ splitOf(captured.view) }, { 260, 260 }, "the clamp until the next onSplit")
  wm.split("CraftAlert", 200)
  Assert.same({ splitOf(captured.view) }, { 200, 200 })
end

-- In settings the nav follows the split, never under 180, and the leads view stays hidden.
local function testSplitInSettings()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 600, 220)
  Widgets.click(gearOf(host))
  local back, nav = backOf(host)
  Assert.equal(nav:GetWidth(), 220, "the gear: the nav takes the split")
  wm.split("CraftAlert", 300)
  Assert.equal(nav:GetWidth(), 300)
  Assert.same(back.points, {
    { "BOTTOMLEFT", nav, "BOTTOMLEFT", 4, 4 },
    { "BOTTOMRIGHT", nav, "BOTTOMRIGHT", -4, 4 },
  }, "the Back button follows through its anchors, 4 px in from each side")
  wm.split("CraftAlert", 50)
  Assert.equal(nav:GetWidth(), 180, "the rail: the nav keeps its minimum")
  Assert.equal(captured.view.frame:IsShown(), false, "the leads view stays hidden")
  Assert.equal(ns.BridgePanel.InSettings(), true)
  Widgets.click(back)
  Assert.equal(captured.view.listPane:GetWidth(), 50, "Back: the list follows the rail")
end

-- The gear after a snap to the rail: the nav is 180, not the rail's width.
local function testGearAfterRailSplit()
  local _, _, _, wm = boot()
  local host = showWith(wm, 600, 50)
  Widgets.click(gearOf(host))
  local _, nav = backOf(host)
  Assert.equal(nav:GetWidth(), 180)
end

-- The gear and its "Settings" label sit at the ledger line's right, centred on it vertically; the
-- counts end before them (8 + 72 + 8). The lead header keeps its default 16 px inset.
local function testLinkOnLedgerLine()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm)
  local link, strip, details = gearOf(host), captured.view.strip, captured.view.details
  Assert.equal(link.parent, strip)
  Assert.same(link.points, { { "RIGHT", strip, "RIGHT", -8, 0 } })
  Assert.same(strip.text.points[2], { "RIGHT", strip, "RIGHT", -88, 0 })
  for _, line in ipairs({ details.lineOne, details.lineTwo }) do
    Assert.same(line.points[2], { "RIGHT", details.header, "RIGHT", -16, 0 })
  end
end

-- WM's divider hairline and its resize handle (above the host's children) run down the host at the
-- split, through the ledger band: the counts start right of the split, on the rail and wide alike,
-- so the bar never crosses them.
local function testCountsStartRightOfSplit()
  local Layout = require("tests.helpers.layout")
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 1000, 50)
  local view = captured.view
  local function check(message)
    local textLeft = Layout.edges(view.strip.text)
    local _, splitX = Layout.edges(view.listPane)
    Assert.equal(textLeft, splitX + ns.Theme.LAYOUT.PADDING, message)
  end
  check("rail")
  wm.split("CraftAlert", 260)
  check("wide")
  Assert.same(
    view.strip.points,
    { { "TOPLEFT", host, "TOPLEFT", 0, 0 }, { "TOPRIGHT", host, "TOPRIGHT", 0, 0 } },
    "the strip itself still spans the host"
  )
end

-- A narrow panel cuts the counts, never the link: the strip text ends before it at any host width.
local function testCountsEndBeforeLink()
  local Layout = require("tests.helpers.layout")
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 340)
  local strip = captured.view.strip
  local function check(message)
    ns.BridgePanel.Refresh()
    local _, textRight = Layout.edges(strip.text)
    local linkLeft = Layout.edges(gearOf(host))
    Assert.truthy(textRight <= linkLeft, message .. ": the counts end before the link")
  end
  check("narrow")
  host:SetSize(600, 400)
  Widgets.fire(host, "OnSizeChanged")
  check("wide")
end

-- A long customer is cut at the header's default inset, and the cut follows the host's width.
-- The age is on line 1, under the name (details spec A.1).
local function testNameCutAtHeaderInset()
  local Layout = require("tests.helpers.layout")
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = showWith(wm, 340) -- the list takes 180, the details 340 - 180 - 1 = 159
  local details = captured.view.details
  details.lead.customer = "Telchiness-Kazzak"
  local function check(width, message)
    details.frame:SetWidth(width) -- the anchors would give it that
    ns.BridgePanel.Refresh()
    local _, nameRight = Layout.edges(details.name)
    local _, headerRight = Layout.edges(details.header)
    Assert.truthy(nameRight <= headerRight - 16, message .. ": the name ends at the header's inset")
  end
  check(159, "narrow")
  local narrowWidth = details.name:GetWidth()
  Assert.truthy(narrowWidth > 0 and narrowWidth < 102, "the name is cut")
  host:SetSize(600, 400) -- the list takes 260, the details 339
  Widgets.fire(host, "OnSizeChanged")
  check(339, "wide")
  Assert.truthy(details.name:GetWidth() > narrowWidth, "the host's width change refits the name")
end

-- WM's divider handle (contactsPane + 50, UI/Theme/Layout.lua:17, WM) draws over the host's
-- frames: in settings the pane sits above it and takes the mouse, so the handle's line is hidden
-- and nothing drags under the pane (image 40). Back hides the pane; the leads view keeps its
-- level, so the divider works over the leads again.
local function testSettingsCoverWmDivider()
  local ns, _, _, wm = boot()
  local captured = capture(ns)
  local host = newHost(600)
  host:SetFrameLevel(5)
  wm.showPanel("CraftAlert", host)
  local viewLevel = captured.view.frame:GetFrameLevel()
  Widgets.click(gearOf(host))
  local back, _, container = backOf(host)
  Assert.truthy(container:GetFrameLevel() > host:GetFrameLevel() + 50, "above WM's handle")
  Assert.equal(container.mouseEnabled, true, "the handle under the pane takes no drag")
  Widgets.click(back)
  Assert.same({ container:IsShown(), captured.view.frame:GetFrameLevel() }, { false, viewLevel })
end

-- The pane belongs to the last host to attach it: the standalone window in Settings falls back to
-- its list when the panel takes the pane, and the panel's settings do not follow the window back.
local function testStandaloneInSettingsThenWmGear()
  local ns, _, _, wm = boot()
  ns.LeadsWindow.SetSettingsRouter(nil) -- the own window, as when WM refuses
  ns.LeadsWindow.ToggleSettings()
  local window = rawget(_G, "CraftAlertLeadsWindow")
  Assert.equal(window:GetTitleText():GetText(), "Craft Alert — Settings")
  local host = showWith(wm)
  Widgets.click(gearOf(host))
  Assert.equal(window:GetTitleText():GetText(), "Craft Alert — Leads", "the window fell back to its list")
  Assert.same({ window.view.frame:IsShown(), window.gear.inSettings }, { true, false })
  local _, _, container = backOf(host)
  Assert.same({ container.parent, container:IsShown() }, { host, true }, "the panel has the pane")
  ns.LeadsWindow.ToggleSettings() -- the window takes it back
  Assert.same({ ns.BridgePanel.InSettings(), window.gear.inSettings }, { false, true }, "the panel is back on its leads")
  Assert.equal(container.parent, window.content)
  Assert.same(
    { container:GetFrameLevel(), container.mouseEnabled },
    { window.content:GetFrameLevel() + 1, false },
    "back in the window: one level up, no mouse"
  )
end

return function()
  testGearOpensSettingsInTheHost()
  testBackReturnsToLeads()
  testToggleSettings()
  testGearOffInInstance()
  testInstanceGateLeavesSettings()
  testGearClosesSettingsInInstance()
  testModeIsNotSaved()
  testRefreshSkippedInSettings()
  testNavWidthInWm()
  testSplitSetsListWidth()
  testNoSplitKeepsTheClamp()
  testSplitFromAnotherHostIsIgnored()
  testNonNumberSplitKeepsTheClamp()
  testRebuildResetsSplit()
  testSplitInSettings()
  testGearAfterRailSplit()
  testLinkOnLedgerLine()
  testCountsStartRightOfSplit()
  testCountsEndBeforeLink()
  testNameCutAtHeaderInset()
  testSettingsCoverWmDivider()
  testStandaloneInSettingsThenWmGear()
  Wow.reset()
end
