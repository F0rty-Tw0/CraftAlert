local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Spec C.3, the state x event table of the WhisperMessenger bridge: one function per row, all on
-- the fake API (tests/helpers/fake_wm_api.lua). The oracle is the table's text, not the code.
-- Task 3.2's test_whisper_bridge.lua covers activation, the info strip and the panel host.
local GREETING = "Hi! I have Blacksmithing, what do you need?"

local function boot(opts, fakeOpts)
  local ns, db, calls = UiFixture.load(opts or { leads = 1 })
  local api, wm = FakeWm.install(fakeOpts)
  return ns, db, calls, api, wm
end

local function G(name)
  return rawget(_G, name)
end

local function inInstance(inside)
  Wow.stub("IsInInstance", inside and function()
    return true, "party"
  end or nil)
end

local function modifier(name, down)
  Wow.stub(name, down and function()
    return true
  end or nil)
end

-- Review Focus 5: OpenConversation false (combat) -> the greeting is not lost.
local function testPreviewClickCombatRefusal()
  local ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.WhisperBridge.ShowLead(lead)
  wm.refuse.OpenConversation = true
  Wow.clock.gettime = 51 -- looked at it for more than 0.5 s
  wm.preview.CraftAlert.onClick() -- plain click = Greet, the active lead
  Assert.same(UiFixture.callsTo(calls, "chat")[1][2], GREETING)
  Assert.equal(lead.greeted, true, "greeting went out")
  -- refused greet (look rule: clicked at once) prefills Blizzard's box when WM refuses too
  local ns2, _, calls2, _, wm2 = boot({ leads = 1 })
  ns2.WhisperBridge.Activate()
  ns2.WhisperBridge.ShowLead(ns2.Leads.Latest())
  wm2.refuse.OpenConversation = true
  wm2.preview.CraftAlert.onClick() -- 0 s after showing
  Assert.same(UiFixture.callsTo(calls2, "prefill"), { { "prefill", ns2.Leads.Latest().customer, GREETING } })
  Assert.same(UiFixture.callsTo(calls2, "chat"), {}, "nothing sent")
  Assert.equal(ns2.Leads.Latest().greeted, false)
end

-- "Toast/preview left-click" and "Pane Greet refused, Whisper button, shift/ctrl toast clicks".
local function testPreviewClickRows()
  local function clicked(setup, gettime)
    local ns, _, calls, _, wm = boot()
    ns.WhisperBridge.Activate()
    local lead = ns.Leads.Latest()
    ns.WhisperBridge.ShowLead(lead)
    Wow.clock.gettime = gettime
    setup()
    wm.preview.CraftAlert.onClick()
    modifier("IsShiftKeyDown", false)
    modifier("IsControlKeyDown", false)
    return ns, lead, calls, wm
  end
  -- plain click, looked: chat sent AND OpenConversation(target) with no draft
  local ns, lead, calls, wm = clicked(function() end, 51)
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer } })
  Assert.same(UiFixture.callsTo(calls, "prefill"), {}, "Blizzard's box stays closed")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "the preview is cleared")
  -- plain click, refused by the look rule: the greeting is the draft, no chat call
  ns, lead, calls, wm = clicked(function() end, 50)
  Assert.same(UiFixture.callsTo(calls, "chat"), {})
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer, GREETING } })
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
  -- shift: the greeting as a draft, whatever the look; nothing sent
  ns, lead, calls, wm = clicked(function()
    modifier("IsShiftKeyDown", true)
  end, 51)
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer, GREETING } })
  Assert.same(UiFixture.callsTo(calls, "chat"), {})
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
  -- ctrl: an empty conversation
  ns, lead, calls, wm = clicked(function()
    modifier("IsControlKeyDown", true)
  end, 51)
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer } })
  Assert.same(UiFixture.callsTo(calls, "chat"), {})
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
  -- WM refusing the shift/ctrl conversation: Blizzard's edit box ("only if OpenConversation returns false")
  local _
  ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  wm.refuse.OpenConversation = true
  modifier("IsControlKeyDown", true)
  wm.preview.CraftAlert.onClick()
  modifier("IsControlKeyDown", false)
  Assert.same(UiFixture.callsTo(calls, "empty"), { { "empty", ns.Leads.Latest().customer } })
  -- Preview right-click / x: hides the preview only, the lead stays
  ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Wow.clock.gettime = 60
  wm.preview.CraftAlert.onDismiss()
  Assert.equal(ns.Leads.IsActive(ns.Leads.Latest().id), true, "the lead stays")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
  Assert.same(
    { #UiFixture.callsTo(calls, "chat"), #UiFixture.callsTo(calls, "prefill"), #wm.callsTo("OpenConversation") },
    { 0, 0, 0 },
    "nothing sent or opened"
  )
end

-- "/ca, Toggle keybind" and "/ca config".
local function testToggleAndConfigRows()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  G("CraftAlert_ToggleLeads")()
  Assert.same(wm.callsTo("TogglePanel"), { { "TogglePanel", "CraftAlert" } })
  Assert.equal(wm.shown.CraftAlert, true, "B, not P: shows the panel")
  Assert.equal(G("CraftAlertLeadsWindow"), nil, "no own window")
  G("CraftAlert_ToggleLeads")()
  Assert.equal(wm.shown.CraftAlert, false, "B, P: closes the panel")
  Assert.equal(G("CraftAlertLeadsWindow"), nil)
  wm.refuse.TogglePanel = true
  G("CraftAlert_ToggleLeads")()
  Assert.equal(G("CraftAlertLeadsWindow"):IsShown(), true, "refused: the own window opens")
  G("CraftAlert_ToggleLeads")()
  Assert.equal(G("CraftAlertLeadsWindow"):IsShown(), false, "and closes again")
  -- /ca config: the own window on Settings, WM not asked, with or without the panel up
  wm.refuse.TogglePanel = false
  wm.showPanel("CraftAlert")
  local toggles = #wm.callsTo("TogglePanel")
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(#wm.callsTo("TogglePanel"), toggles, "no TogglePanel")
  Assert.same({ G("CraftAlertLeadsWindow"):IsShown(), G("CraftAlertLeadsWindow"):GetTitleText():GetText() }, { true, "Craft Alert — Settings" })
end

-- "Gear in embedded view": the one Button on the details pane's TOPRIGHT opens the own window on Settings.
local function testGearRow()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(600, 400)
  wm.showPanel("CraftAlert", host)
  local gear
  for _, frame in ipairs(Wow.frames) do
    local point = frame.points and frame.points[1]
    if frame.frameType == "Button" and frame.scripts.OnClick and point and point[1] == "TOPRIGHT" then
      local parent = frame.parent
      while parent and parent ~= host do
        parent = parent.parent
      end
      if parent == host then
        gear = frame
      end
    end
  end
  Assert.truthy(gear, "gear in the embedded view")
  Widgets.click(gear)
  Assert.same({ G("CraftAlertLeadsWindow"):IsShown(), G("CraftAlertLeadsWindow"):GetTitleText():GetText() }, { true, "Craft Alert — Settings" })
  Assert.equal(#wm.callsTo("TogglePanel"), 0)
end

-- "Enter instance": the preview hides, the panel shows its empty text, a new lead adds no preview.
local function testEnterInstanceRow()
  local ns, _, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  local captured
  local newView = ns.LeadsView.New
  ns.LeadsView.New = function(...)
    captured = newView(...)
    return captured
  end
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Assert.truthy(wm.preview.CraftAlert)
  inInstance(true)
  ns.WhisperBridge.OnGate()
  Assert.equal(wm.preview.CraftAlert, nil, "preview hidden on entering an instance")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil)
  wm.showPanel("CraftAlert")
  Assert.equal(captured.list.empty:IsShown(), true, "the embedded view shows its empty text")
  Assert.equal(ns.WhisperBridge.VisibleLead(), nil, "no rows")
  Assert.equal(#ns.Leads.List(), 2, "Leads keeps its leads")
  local previews = #wm.callsTo("ShowPreview")
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Assert.equal(#wm.callsTo("ShowPreview"), previews, "no ShowPreview in the instance")
  inInstance(false)
  -- entering with the panel already open empties the open view
  wm.hidePanel("CraftAlert")
  wm.showPanel("CraftAlert")
  Assert.equal(captured.list.empty:IsShown(), false, "rows outside")
  inInstance(true)
  ns.WhisperBridge.OnGate()
  Assert.equal(captured.list.empty:IsShown(), true, "the open view shows its empty text")
  inInstance(false)
end

-- "WM window hidden": the panel's onHide stops the view refreshing, the badge still follows.
local function testPanelHiddenIgnored()
  local ns, _, _, _, wm = boot({ leads = 3 })
  ns.WhisperBridge.Activate()
  wm.showPanel("CraftAlert")
  local refreshed = 0
  local refresh = ns.LeadsView.Refresh
  ns.LeadsView.Refresh = function(...)
    refreshed = refreshed + 1
    return refresh(...)
  end
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.truthy(refreshed > 0, "refreshed while shown")
  wm.hidePanel("CraftAlert")
  refreshed = 0
  local badges = wm.badgeRefreshes
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(refreshed, 0, "hidden: the view is left alone")
  Assert.equal(wm.badgeRefreshes, badges + 1, "badge still refreshed")
end

-- "Lead change / expire / dismiss": B, P adds the view refresh to the badge, info line and preview.
local function testLeadChangeRow()
  local ns, _, _, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  wm.showPanel("CraftAlert")
  local refreshed = 0
  local refresh = ns.LeadsView.Refresh
  ns.LeadsView.Refresh = function(...)
    refreshed = refreshed + 1
    return refresh(...)
  end
  local lead = ns.Leads.Latest()
  ns.WhisperBridge.ShowLead(lead)
  ns.Leads.MarkGreeted(lead.id)
  Assert.truthy(refreshed > 0, "view refreshed on a change")
  Assert.truthy(wm.badgeRefreshes > 0, "badge refreshed")
  Assert.equal(wm.info.CraftAlert[lead.customer] ~= nil, true, "info line sent")
  Assert.truthy(wm.preview.CraftAlert, "an unchanged-away lead keeps its preview")
  ns.Leads.Dismiss(lead.id)
  Assert.equal(wm.preview.CraftAlert, nil, "preview hides when its lead left")
  Assert.equal(wm.info.CraftAlert[lead.customer], nil, "info line removed")
end

local function testKeybindsBridged()
  local ns, _, calls, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Wow.clock.gettime = 51
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1, "preview counts as shown: greets")

  -- nothing on screen (preview onDismiss'd, no panel, no window): prefill via the opener
  local ns2, _, calls2, _, wm2 = boot({ leads = 2 })
  ns2.WhisperBridge.Activate()
  ns2.WhisperBridge.ShowLead(ns2.Leads.Latest())
  wm2.preview.CraftAlert.onDismiss()
  wm2.preview.CraftAlert = nil -- WM hid it
  Wow.clock.gettime = 60
  G("CraftAlert_GreetLatest")()
  Assert.same(UiFixture.callsTo(calls2, "chat"), {})
  Assert.same(wm2.callsTo("OpenConversation"), { { "OpenConversation", ns2.Leads.Latest().customer, GREETING } })
  Assert.same(UiFixture.callsTo(calls2, "prefill"), {}, "Blizzard's box stays closed")
  -- the preview frame hidden by WM (Alt+Z) while we still remember it: not on screen either
  local ns3, _, calls3, _, wm3 = boot({ leads = 2 })
  ns3.WhisperBridge.Activate()
  ns3.WhisperBridge.ShowLead(ns3.Leads.Latest())
  wm3.preview.CraftAlert = nil
  Wow.clock.gettime = 60
  G("CraftAlert_GreetLatest")()
  Assert.same(UiFixture.callsTo(calls3, "chat"), {})
  Assert.equal(#wm3.callsTo("OpenConversation"), 1)

  -- DismissLatest within 0.5 s of the preview: the lead stays; after: dismissed
  local ns4, _, _, _, wm4 = boot({ leads = 2 })
  ns4.WhisperBridge.Activate()
  ns4.WhisperBridge.ShowLead(ns4.Leads.Latest())
  Wow.clock.gettime = 50.2
  G("CraftAlert_DismissLatest")()
  Assert.equal(ns4.Leads.Latest().id, 2, "shown 0.2 s")
  Wow.clock.gettime = 50.6
  G("CraftAlert_DismissLatest")()
  Assert.equal(ns4.Leads.Latest().id, 1, "shown 0.6 s")
  Assert.equal(wm4.preview.CraftAlert, nil, "and the preview left with its lead")

  -- panel shown and preview hidden: the embedded top row's shownAt is the source
  local ns5, _, calls5, _, wm5 = boot({ leads = 2 })
  ns5.WhisperBridge.Activate()
  wm5.showPanel("CraftAlert")
  Wow.clock.gettime = 50.2
  G("CraftAlert_GreetLatest")()
  Assert.same(UiFixture.callsTo(calls5, "chat"), {}, "row up for 0.2 s")
  Wow.clock.gettime = 51
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls5, "chat"), 1, "row up for 1 s")
  wm5.hidePanel("CraftAlert")
  Wow.clock.gettime = 70
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls5, "chat"), 1, "hidden panel is no source: prefill")
  Assert.equal(#wm5.callsTo("OpenConversation") >= 1, true)

  -- own window top row older than the preview: the earlier shownAt wins
  local ns6, _, calls6, _, wm6 = boot({ leads = 2 })
  ns6.WhisperBridge.Activate()
  wm6.refuse.TogglePanel = true
  ns6.LeadsWindow.Toggle() -- own window, top row since 50
  Wow.clock.gettime = 50.3
  ns6.WhisperBridge.ShowLead(ns6.Leads.Latest()) -- preview since 50.3
  Wow.clock.gettime = 50.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls6, "chat"), 1, "the window's 0.6 s counts, not the preview's 0.3 s")

  -- and the other way round: the preview older than the window
  local ns7, _, calls7, _, wm7 = boot({ leads = 2 })
  ns7.WhisperBridge.Activate()
  ns7.WhisperBridge.ShowLead(ns7.Leads.Latest()) -- preview since 50
  wm7.refuse.TogglePanel = true
  Wow.clock.gettime = 50.3
  ns7.LeadsWindow.Toggle() -- own window since 50.3
  Wow.clock.gettime = 50.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls7, "chat"), 1, "the preview's 0.6 s counts, not the window's 0.3 s")

  -- preview and panel row both up: the earlier of the two, either order
  local ns9, _, calls9, _, wm9 = boot({ leads = 2 })
  ns9.WhisperBridge.Activate()
  wm9.showPanel("CraftAlert") -- row since 50
  Wow.clock.gettime = 50.3
  ns9.WhisperBridge.ShowLead(ns9.Leads.Latest()) -- preview since 50.3
  Wow.clock.gettime = 50.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls9, "chat"), 1, "the row's 0.6 s counts, not the preview's 0.3 s")
  local ns10, _, calls10, _, wm10 = boot({ leads = 2 })
  ns10.WhisperBridge.Activate()
  ns10.WhisperBridge.ShowLead(ns10.Leads.Latest()) -- preview since 50
  Wow.clock.gettime = 50.3
  wm10.showPanel("CraftAlert") -- row since 50.3
  Wow.clock.gettime = 50.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls10, "chat"), 1, "the preview's 0.6 s counts, not the row's 0.3 s")

  -- an older lead's preview does not count for the latest one
  local ns8, _, calls8 = boot({ leads = 2 })
  ns8.WhisperBridge.Activate()
  ns8.WhisperBridge.ShowLead(ns8.Leads.List()[2])
  Wow.clock.gettime = 60
  G("CraftAlert_GreetLatest")()
  Assert.same(UiFixture.callsTo(calls8, "chat"), {})
end

local function testStandaloneUnchanged()
  local ns, _, calls = UiFixture.load({ leads = 2 }) -- no API
  Assert.equal(ns.WhisperBridge.Activate(), false)
  ns.AlertToast.Show(ns.Leads.Latest())
  Wow.clock.gettime = 51
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)
  local ns2, _, calls2 = UiFixture.load({ leads = 2 })
  ns2.WhisperBridge.Activate()
  Wow.clock.gettime = 50
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls2, "prefill"), 1, "nothing on screen: Blizzard's box")
end

return function()
  testPreviewClickCombatRefusal()
  testPreviewClickRows()
  testToggleAndConfigRows()
  testGearRow()
  testEnterInstanceRow()
  testPanelHiddenIgnored()
  testLeadChangeRow()
  testKeybindsBridged()
  testStandaloneUnchanged()
  Wow.reset()
end
