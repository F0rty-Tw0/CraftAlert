local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

local GREETING = "Hi! I have Blacksmithing, what do you need?"

local function boot(opts, fakeOpts)
  local ns, db, calls = UiFixture.load(opts or { leads = 1 })
  local api, wm = FakeWm.install(fakeOpts)
  return ns, db, calls, api, wm
end

local function newHost(width)
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, 400)
  return host
end

local function inInstance(inside)
  Wow.stub("IsInInstance", inside and function()
    return true, "party"
  end or nil)
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

-- The embedded view's settings gear: the one Button under the host anchored to its TOPRIGHT.
local function gearOf(host)
  local found
  for _, frame in ipairs(Wow.frames) do
    local point = frame.points and frame.points[1]
    if frame.frameType == "Button" and frame.scripts.OnClick and point and point[1] == "TOPRIGHT" and descendantOf(frame, host) then
      Assert.equal(found, nil, "exactly one gear")
      found = frame
    end
  end
  return found
end

local function testStandaloneWhenApiMissingOrIncomplete()
  local ns = UiFixture.load({ leads = 1 })
  Assert.equal(ns.WhisperBridge.Activate(), false)
  local ns2 = boot(nil, { version = 0 })
  Assert.equal(ns2.WhisperBridge.Activate(), false, "version 0")
  for _, missing in ipairs({ "ShowPreview", "OpenConversation", "SetContactInfo" }) do
    local n, _, _, _, wm = boot(nil, { without = { missing } })
    Assert.equal(n.WhisperBridge.Activate(), false, missing .. " missing")
    Assert.same(wm.calls, {}, "no call made while standalone")
  end
end

-- Not activated, the Leads handlers must not reach the API (it may be absent or half there): a
-- wired handler would raise on the missing API, and Leads reports what its listeners raise.
local function testNoApiCallBeforeActivate()
  local ns, _, _, _, wm = boot({ leads = 2 }, { without = { "ShowPreview" } })
  local errors = {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      errors[#errors + 1] = err
    end
  end)
  Assert.equal(ns.WhisperBridge.Activate(), false)
  ns.Leads.MarkGreeted(ns.Leads.Latest().id)
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.same(wm.calls, {}, "change/greeted handlers stay unwired")
  Assert.same(errors, {}, "and raise nothing")
  local ns2, _, _, _, wm2 = boot({ leads = 1 })
  ns2.Leads.Dismiss(ns2.Leads.Latest().id) -- API present, Activate never called
  Assert.same(wm2.calls, {}, "nothing before Activate")
end

local function testActivationPlugsIn()
  local ns, _, _, _, wm = boot()
  Assert.equal(ns.WhisperBridge.Activate(), true)
  Assert.equal(ns.WhisperBridge.Activate(), true, "idempotent")
  Assert.equal(#wm.registered, 1, "RegisterPanel once")
  Assert.same({ wm.panels.CraftAlert.title, wm.panels.CraftAlert.badge() }, { "Craft Alert", 1 })
  ns.Launcher.Create()
  ns.Launcher.Refresh()
  Assert.equal(ns.Launcher.Frame(), nil, "launcher suppressed")
  ns.LeadsWindow.Toggle() -- router -> TogglePanel
  Assert.same(wm.calls[#wm.calls], { "TogglePanel", "CraftAlert" })
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil)
  wm.refuse.TogglePanel = true
  ns.LeadsWindow.Toggle() -- false -> own window
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true)
end

local function testOpenerGoesToWm()
  local ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.GreetAction.Prefill(lead)
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer, GREETING } })
  Assert.same(calls, {}, "Blizzard's box stays closed")
  wm.refuse.OpenConversation = true -- combat or lockdown: today's box
  ns.GreetAction.Empty(lead)
  Assert.same(calls, { { "empty", lead.customer } })
end

local function testShowLeadPreview()
  local ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.WhisperBridge.ShowLead(lead)
  local preview = wm.preview.CraftAlert
  Assert.same({ preview.sender, preview.text, preview.classTag }, { lead.customer, "Blacksmithing", nil })
  Assert.equal(#UiFixture.callsTo(calls, "sound"), 1)
  Assert.equal(#UiFixture.callsTo(calls, "flash"), 1)
  Assert.equal(rawget(_G, "CraftAlertToast"), nil, "no own toast")
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { lead, 50 })
  Wow.clock.gettime = 80
  preview.onShown()
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { lead, 80 }, "onShown restarts the look clock")
  preview.onDismiss() -- right-click / x: hides the preview only
  Assert.equal(ns.Leads.IsActive(lead.id), true)
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
end

local function testShowPreviewRefusedFallsBackToToast()
  local ns, _, calls, _, wm = boot(nil, nil)
  ns.WhisperBridge.Activate()
  ns.Launcher.Create() -- a launcher frame exists (suppressed), so the dock assertion below is not vacuous
  wm.refuse.ShowPreview = true
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Assert.truthy(rawget(_G, "CraftAlertToast"), "own toast shown")
  Assert.equal(#UiFixture.callsTo(calls, "sound"), 1, "alerted once, by the toast")
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 }, "fallback toast counts")
  Assert.same(rawget(_G, "CraftAlertToast").points[1][2], rawget(_G, "UIParent"), "docked at the no-launcher spot")
end

local function testPreviewClick()
  local ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.WhisperBridge.ShowLead(lead)
  Wow.clock.gettime = 51 -- looked at it for a second
  wm.preview.CraftAlert.onClick()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1, "greeting sent")
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer } }, "sent: the chat opens, no draft")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "click clears the remembered preview")
  -- clicked at once: the look rule refuses, the greeting is a draft and nothing else opens
  local ns2, _, calls2, _, wm2 = boot()
  ns2.WhisperBridge.Activate()
  local lead2 = ns2.Leads.Latest()
  ns2.WhisperBridge.ShowLead(lead2)
  wm2.preview.CraftAlert.onClick()
  Assert.same(wm2.callsTo("OpenConversation"), { { "OpenConversation", lead2.customer, GREETING } })
  Assert.same(UiFixture.callsTo(calls2, "chat"), {}, "nothing sent")
end

local function testTimerAndLeadGone()
  local ns, db, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.List()[2])
  local first = Wow.timers[#Wow.timers]
  Assert.equal(first.delay, db.settings.toastDuration)
  ns.WhisperBridge.ShowLead(ns.Leads.List()[1])
  first.fn() -- stale timer
  Assert.truthy(wm.preview.CraftAlert, "older timer must not hide the newer preview")
  Wow.timers[#Wow.timers].fn()
  Assert.equal(wm.preview.CraftAlert, nil, "own timer hides it")
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(wm.preview.CraftAlert, nil, "lead left the list")
end

local function testNoShowInInstance()
  local ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  inInstance(true)
  local before = #wm.calls -- Activate already recorded RegisterPanel
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Assert.same({ #wm.calls, calls }, { before, {} }, "nothing previewed, no sound")
  ns.WhisperBridge.OnGate() -- active: no error
  inInstance(false)
end

local function testOnGateHidesPreviewInInstance()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  ns.WhisperBridge.OnGate() -- outside: nothing to do
  Assert.truthy(wm.preview.CraftAlert, "kept outside an instance")
  inInstance(true)
  ns.WhisperBridge.OnGate()
  Assert.equal(wm.preview.CraftAlert, nil, "preview hidden on entering an instance")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
  inInstance(false)
end

local function testOnGateStandalone()
  local ns = UiFixture.load({ leads = 1 })
  inInstance(true)
  ns.WhisperBridge.OnGate() -- no API, never activated: must not raise
  inInstance(false)
end

local function testInfoStrip()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.Leads.MarkGreeted(lead.id) -- fires greeted + change
  Assert.equal(wm.info.CraftAlert[lead.customer], "|cffffd100Craft Alert:|r Blacksmithing · Me")
  ns.Leads.Dismiss(lead.id)
  Assert.equal(wm.info.CraftAlert[lead.customer], nil, "removed with the lead")
  Assert.same(wm.callsTo("SetContactInfo")[2], { "SetContactInfo", "CraftAlert", lead.customer, nil })
end

local function testInfoStripNamesTheWhat()
  local ns, _, _, _, wm = boot({
    leads = 1,
    db = function(db)
      db.leads[1].recipeName = "Plate Belt"
    end,
  })
  ns.WhisperBridge.Activate()
  ns.Leads.MarkGreeted(ns.Leads.Latest().id)
  Assert.equal(wm.info.CraftAlert[ns.Leads.Latest().customer], "|cffffd100Craft Alert:|r Plate Belt · Blacksmithing · Me")
end

local function testPanel()
  local ns, _, _, _, wm = boot({ leads = 3 })
  ns.WhisperBridge.Activate()
  local captured
  local newView = ns.LeadsView.New
  ns.LeadsView.New = function(parent, opts)
    captured = opts
    return newView(parent, opts)
  end
  local function listWidthFor(width)
    wm.showPanel("CraftAlert", newHost(width))
    return captured.getListWidth()
  end
  local host = newHost(480)
  wm.showPanel("CraftAlert", host)
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 }, "top row of the shown panel")
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.truthy(wm.badgeRefreshes >= 1, "badge refreshed on change")
  Assert.same({ ns.WhisperBridge.VisibleLead() }, { ns.Leads.Latest(), 50 }, "the view followed the change")
  wm.hidePanel("CraftAlert")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "hidden panel shows nothing")
  -- width clamp: 480 - 340 = 140 -> 180; 700 - 340 = 360 -> 260
  Assert.same({ listWidthFor(480), listWidthFor(700) }, { 180, 260 })
  -- the gear opens the own window on Settings
  local gear = gearOf(host)
  Widgets.fire(gear, "OnEnter")
  local tooltip = ns.Tooltip.Get()
  Assert.same(tooltip.lines, { "Settings", " ", "Click: open settings" })
  Widgets.click(gear)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true)
end

local function testPanelRefreshesOnlyWhileShown()
  local ns, _, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  local refreshed = 0
  local refresh = ns.LeadsView.Refresh
  ns.LeadsView.Refresh = function(...)
    refreshed = refreshed + 1
    return refresh(...)
  end
  wm.showPanel("CraftAlert")
  local atShow = refreshed
  Assert.truthy(atShow >= 1, "onShow refreshes")
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.truthy(refreshed > atShow, "refreshed on change while shown")
  wm.hidePanel("CraftAlert")
  local atHide = refreshed
  local badges = wm.badgeRefreshes
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(refreshed, atHide, "no refresh while hidden")
  Assert.equal(wm.badgeRefreshes, badges + 1, "badge still refreshed")
end

local function testPanelHostRules()
  local ns, _, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  local built, laidOut = 0, 0
  local newView, layout = ns.LeadsView.New, ns.LeadsView.Layout
  ns.LeadsView.New = function(...)
    built = built + 1
    return newView(...)
  end
  ns.LeadsView.Layout = function(...)
    laidOut = laidOut + 1
    return layout(...)
  end
  local host = newHost(480)
  wm.showPanel("CraftAlert", host)
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert", host)
  Assert.equal(built, 1, "one view per host")
  wm.showPanel("CraftAlert", newHost(480))
  Assert.equal(built, 2, "a new host gets its own view")
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert", host)
  local before = laidOut
  host:SetSize(700, 400)
  Widgets.fire(host, "OnSizeChanged", 700, 400)
  Assert.truthy(laidOut > before, "a resize of the shown host lays the view out again")
  wm.hidePanel("CraftAlert")
  before = laidOut
  Widgets.fire(host, "OnSizeChanged", 700, 400)
  Assert.equal(laidOut, before, "a hidden panel is left alone")
end

local function testPanelEmptyInInstance()
  local ns, _, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  wm.showPanel("CraftAlert")
  Assert.equal(ns.WhisperBridge.VisibleLead() ~= nil, true, "rows outside an instance")
  inInstance(true)
  ns.WhisperBridge.OnGate() -- entering with the panel open
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "the open view empties")
  Assert.equal(wm.panels.CraftAlert.badge(), 0, "and the badge agrees with the empty list")
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert") -- opening inside
  Assert.equal(ns.Leads.Latest() ~= nil, true, "Leads keeps its leads in an instance")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "the view shows no rows there")
  inInstance(false)
  Assert.equal(wm.panels.CraftAlert.badge(), 2, "badge counts the leads outside")
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(ns.WhisperBridge.VisibleLead() ~= nil, true, "rows are back outside")
end

-- Leaving an instance with the panel open: the rows come back and the badge is refreshed without
-- waiting for a lead change; a preview shown outside stays on a gate change that is not an entry.
local function testLeavingInstanceRefreshesPanel()
  local ns, _, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  wm.showPanel("CraftAlert")
  inInstance(true)
  ns.WhisperBridge.OnGate()
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "empty inside")
  local badges = wm.badgeRefreshes
  inInstance(false)
  ns.WhisperBridge.OnGate() -- leaving: no lead changed
  Assert.equal(ns.WhisperBridge.VisibleLead() ~= nil, true, "rows are back at once")
  Assert.equal(wm.badgeRefreshes, badges + 1, "badge refreshed on leaving")
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  ns.WhisperBridge.OnGate() -- a gate change outside an instance keeps the preview
  Assert.truthy(wm.preview.CraftAlert, "preview kept")
end

-- WM's RegisterPanel answers false (never raises) when it refuses, e.g. the key is taken: the
-- bridge stays off, the launcher and the own window stay, no later event reaches the API.
local function testPanelRefusedStaysStandalone()
  local ns, _, _, _, wm = boot()
  wm.refuse.RegisterPanel = true
  Assert.equal(ns.WhisperBridge.Activate(), false)
  Assert.equal(ns.WhisperBridge.Activate(), false, "the answer sticks")
  local launcher = ns.Launcher.Create()
  Assert.equal(ns.Launcher.Frame(), launcher, "launcher not suppressed")
  ns.LeadsWindow.Toggle()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true, "own window, not TogglePanel")
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  ns.WhisperBridge.OnGate()
  Assert.same(#wm.calls, 1, "RegisterPanel was the only call")
end

local function testNoOnUpdateAnywhere()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  wm.showPanel("CraftAlert", newHost(600))
  for _, frame in ipairs(Wow.frames) do
    Assert.equal(frame.scripts.OnUpdate, nil, "no OnUpdate (UiFixture installs no runtime trap)")
  end
end

return function()
  testStandaloneWhenApiMissingOrIncomplete()
  testNoApiCallBeforeActivate()
  testActivationPlugsIn()
  testOpenerGoesToWm()
  testShowLeadPreview()
  testShowPreviewRefusedFallsBackToToast()
  testPreviewClick()
  testTimerAndLeadGone()
  testNoShowInInstance()
  testOnGateHidesPreviewInInstance()
  testOnGateStandalone()
  testInfoStrip()
  testInfoStripNamesTheWhat()
  testPanel()
  testPanelRefreshesOnlyWhileShown()
  testPanelHostRules()
  testPanelEmptyInInstance()
  testLeavingInstanceRefreshesPanel()
  testPanelRefusedStaysStandalone()
  testNoOnUpdateAnywhere()
  Wow.reset()
end
