local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Spec §7.6 and plan revision 5.3: with WhisperMessenger the away summary is WM's widget preview
-- (sender "Craft Alert", the summary text; a click opens the panel, never toggles it), hidden after
-- the toast duration, and CraftAlert's own toast when WM refuses. A lead's preview and the summary
-- replace each other, and neither's timer or lead hides the other.
local TEXT = "4 requests you could craft while you were away (1 expired)"

-- → ns, db, calls, wm, with the bridge active.
local function boot(leads)
  local ns, db, calls = UiFixture.load({ leads = leads or 1 })
  local _, wm = FakeWm.install()
  Assert.equal(ns.WhisperBridge.Activate(), true)
  return ns, db, calls, wm
end

local function testPreviewAndClick()
  local ns, _, calls, wm = boot()
  ns.WhisperBridge.ShowSummary(4, 1)
  local preview = wm.preview.CraftAlert
  Assert.same({ preview.sender, preview.text, preview.classTag, preview.pulse }, { "Craft Alert", TEXT, nil, nil })
  Assert.same(calls, {}, "no sound or flash")
  Assert.equal(rawget(_G, "CraftAlertToast"), nil, "no own toast")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "no lead on the widget")
  preview.onClick()
  Assert.same(wm.callsTo("ShowPanel"), { { "ShowPanel", "CraftAlert" } })
  preview.onClick()
  Assert.same({ #wm.callsTo("TogglePanel"), wm.shown.CraftAlert }, { 0, true }, "open, never a toggle")
  -- The open router Activate wired: a refused ShowPanel opens the own window.
  wm.refuse.ShowPanel = true
  ns.LeadsWindow.Open()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true)
end

-- WM's ShowPanel on a panel already shown runs no onShow: a click while the panel shows the
-- settings goes back to the list itself, as the own window's Open does.
local function testClickLeavesSettings()
  local ns, _, _, wm = boot()
  wm.showPanel("CraftAlert")
  ns.BridgePanel.ShowSettings()
  Assert.equal(ns.BridgePanel.InSettings(), true)
  ns.WhisperBridge.ShowSummary(4, 1)
  wm.preview.CraftAlert.onClick()
  Assert.same({ ns.BridgePanel.InSettings(), wm.shown.CraftAlert }, { false, true }, "back on the list, still open")
end

local function testRefusedFallsBackToToast()
  local ns, _, _, wm = boot()
  wm.refuse.ShowPreview = true
  ns.WhisperBridge.ShowSummary(4, 1)
  local toast = rawget(_G, "CraftAlertToast")
  Assert.equal(toast and toast:IsShown(), true, "own toast shown")
  Assert.truthy(string.find(table.concat(Widgets.texts(toast, Wow.frames), " / "), TEXT, 1, true))
end

-- Each preview's timer and lead hide only that preview.
local function testTimersAndLeads()
  local ns, db, _, wm = boot(2)
  local leads = ns.Leads.List()
  ns.WhisperBridge.ShowSummary(2, 0)
  local summaryTimer = Wow.timers[#Wow.timers]
  Assert.equal(summaryTimer.delay, db.settings.toastDuration)
  ns.WhisperBridge.ShowLead(leads[1])
  local leadTimer = Wow.timers[#Wow.timers]
  summaryTimer.fn()
  Assert.equal(wm.preview.CraftAlert.sender, leads[1].customer, "the summary's timer leaves the lead's preview")
  ns.WhisperBridge.ShowSummary(2, 0)
  leadTimer.fn()
  ns.Leads.Dismiss(leads[1].id)
  Assert.equal(wm.preview.CraftAlert.sender, "Craft Alert", "the lead's timer and dismissal leave the summary")
  Wow.timers[#Wow.timers].fn()
  Assert.equal(wm.preview.CraftAlert, nil, "its own timer hides it")
end

local function testInstance()
  local ns, _, _, wm = boot()
  ns.WhisperBridge.ShowSummary(2, 0)
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.WhisperBridge.OnGate()
  Assert.equal(wm.preview.CraftAlert, nil, "entering an instance hides it")
  local before = #wm.calls
  ns.WhisperBridge.ShowSummary(2, 0)
  Assert.equal(#wm.calls, before, "nothing in an instance")
  Wow.stub("IsInInstance", nil)
end

return function()
  testPreviewAndClick()
  testClickLeavesSettings()
  testRefusedFallsBackToToast()
  testTimersAndLeads()
  testInstance()
  Wow.reset()
end
