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

local function testStandaloneWhenApiMissingOrIncomplete()
  local ns = UiFixture.load({ leads = 1 })
  Assert.equal(ns.WhisperBridge.Activate(), false)
  local ns2 = boot(nil, { version = 0 })
  Assert.equal(ns2.WhisperBridge.Activate(), false, "version 0")
  local ns3 = boot(nil, { version = 2 })
  Assert.equal(ns3.WhisperBridge.Activate(), false, "a version this bridge was not written for")
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
  ns.LeadsWindow.Toggle() -- router -> TogglePanel (the shown newest lead is seen: RefreshPanelBadge)
  Assert.same(wm.callsTo("TogglePanel"), { { "TogglePanel", "CraftAlert" } })
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
  Assert.equal(preview.pulse, true, "a new lead pulses WM's widget (spec 7)")
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

local MAGE = { r = 1, g = 0.5, b = 0 }

-- The crafter's name in the info line wears the class colour; an unknown class stays plain.
local function testInfoStripColoursTheCrafter()
  local ns, _, _, _, wm = boot({
    leads = 1,
    db = function(db)
      db.characters = { ["Me-Realm"] = { class = "MAGE" } }
    end,
  })
  Wow.stub("RAID_CLASS_COLORS", { MAGE = MAGE })
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.Leads.MarkGreeted(lead.id)
  Assert.equal(wm.info.CraftAlert[lead.customer], "|cffffd100Craft Alert:|r Blacksmithing · |cffff7f00Me|r")
end

-- A lead with why, profession, two crafters (Me: class, rank) and a channel; the tooltip lines
-- WM shows on hovering the info line.
local function tooltipLead(db)
  db.characters = { ["Me-Realm"] = { class = "MAGE" } }
  db.leads[1].message = "LF plate belt"
  db.leads[1].crafters = { { key = "Me-Realm", rank = 2, byConc = true }, { key = "Bob-Realm" } }
end

local function tooltipFixture()
  local ns, _, _, _, wm = boot({ leads = 1, db = tooltipLead })
  Wow.stub("RAID_CLASS_COLORS", { MAGE = MAGE })
  Wow.stub("date", function()
    return "12:34"
  end)
  return ns, wm
end

local function testInfoLines()
  local ns = tooltipFixture()
  local customer = ns.Leads.Latest().customer
  Assert.same(ns.CardTipText.InfoLines(ns.Leads.Latest()), {
    "|cffffd100Wants Blacksmithing — you have it|r",
    "Matched: |cfffffffflf + blacksmith|r · |cffffd100Blacksmithing|r",
    "|cffff7f00Me|r |cff7f7f7fR2 (conc)|r",
    "Bob",
    "[12:34] [Trade] [|cffffffff" .. customer .. "|r]: LF plate belt",
  })
end

-- At most 7 crafter lines, so the 10 WM accepts are never passed; no why and no profession, no Matched.
local function testInfoLinesCapAndMatched()
  local ns = tooltipFixture()
  local lead = ns.Leads.Latest()
  lead.crafters = {}
  for index = 1, 9 do
    lead.crafters[index] = { key = "Alt" .. index .. "-Realm" }
  end
  Assert.equal(#ns.CardTipText.InfoLines(lead), 10, "headline, matched, 7 crafters, chat")
  lead.why, lead.profName = nil, nil
  local lines = ns.CardTipText.InfoLines(lead)
  Assert.equal(#lines, 9, "no Matched line")
  for _, line in ipairs(lines) do
    Assert.equal(string.find(line, "Matched", 1, true), nil, line)
  end
  lead.message = nil
  Assert.equal(#ns.CardTipText.InfoLines(lead), 8, "a saved lead whose message the schema dropped: no chat line")
end

-- The sync sends the lines with the text, and again only when text or lines changed.
local function testSyncSendsTooltipLines()
  local ns, wm = tooltipFixture()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.Leads.MarkGreeted(lead.id)
  local call = wm.callsTo("SetContactInfo")[1]
  Assert.same({ call[2], call[3], call[4] }, { "CraftAlert", lead.customer, wm.info.CraftAlert[lead.customer] })
  Assert.same(call[5], ns.CardTipText.InfoLines(lead))
  Assert.same(wm.tips.CraftAlert[lead.customer], ns.CardTipText.InfoLines(lead))
  ns.WhisperBridge.SyncInfo()
  Assert.equal(#wm.callsTo("SetContactInfo"), 1, "nothing changed: nothing sent")
  lead.message = "LF plate belt, thanks"
  ns.WhisperBridge.SyncInfo()
  Assert.equal(#wm.callsTo("SetContactInfo"), 2, "a new chat message goes out again")
  Assert.equal(wm.tips.CraftAlert[lead.customer][5], "[12:34] [Trade] [|cffffffff" .. lead.customer .. "|r]: LF plate belt, thanks")
  ns.Leads.Dismiss(lead.id)
  Assert.equal(wm.tips.CraftAlert[lead.customer], nil, "removal clears the tooltip")
end

-- The fake guards WM's cap: 11 lines, an empty line or a hole is refused and changes nothing.
local function testFakeRefusesBadTooltips()
  local api, wm = FakeWm.install()
  local eleven = {}
  for index = 1, 11 do
    eleven[index] = "line"
  end
  Assert.equal(api.SetContactInfo("K", "N", "text", eleven), false, "11 lines")
  Assert.equal(api.SetContactInfo("K", "N", "text", { "a", "" }), false, "empty line")
  Assert.equal(api.SetContactInfo("K", "N", "text", {}), false, "no line")
  Assert.same({ wm.info.K, wm.tips.K }, {}, "nothing changed")
  Assert.equal(api.SetContactInfo("K", "N", "text", { "a" }), true)
end

-- The preview carries the customer's class token when the guid's class is known.
local function testPreviewCarriesClassTag()
  local guid = "Player-0-CRAFTALERTTEST1"
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  lead.guid = guid
  ns.FlavorCompat.SetTestClass(guid, "SHAMAN")
  ns.WhisperBridge.ShowLead(lead)
  Assert.equal(wm.preview.CraftAlert.classTag, "SHAMAN")
  ns.FlavorCompat.SetTestClass(guid, nil)
  ns.WhisperBridge.ShowLead(lead)
  Assert.equal(wm.preview.CraftAlert.classTag, nil, "unknown class")
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
  -- the gear opens Settings inside the panel's host, not the own window
  local current = newHost(600)
  wm.showPanel("CraftAlert", current)
  local gear = gearOf(current)
  Widgets.fire(gear, "OnEnter")
  local tooltip = ns.Tooltip.Get()
  Assert.same(tooltip.lines, { "Settings", " ", "Click: open settings" })
  Widgets.click(gear)
  Assert.equal(ns.BridgePanel.InSettings(), true)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "no own window")
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

-- The rows the shown panel paints, by lead: wraps LeadRow.Show before the panel is shown.
-- → a function giving the colour of that lead's dot, nil when its row was never painted.
local function dotColors(ns)
  local rows = {}
  local show = ns.LeadRow.Show
  ns.LeadRow.Show = function(row, lead)
    show(row, lead)
    rows[lead] = row
  end
  return function(lead)
    return rows[lead] and rows[lead].dot.texture.vertexColor
  end
end

-- Reply-unread dot (spec §2-§5): WM with GetUnreadCount gets onUnreadChanged on the panel, the
-- customer's count paints the row pink and a change repaints the shown panel. WM is asked on
-- paint only.
local function testUnreadDot()
  local ns, _, _, _, wm = boot({ leads = 2 })
  Wow.stub("ChatTypeInfo", { WHISPER = { r = 1, g = 0.5, b = 0.9 } })
  local dotOf = dotColors(ns)
  Assert.equal(ns.WhisperBridge.Activate(), true)
  local panel = wm.panels.CraftAlert
  Assert.equal(type(panel.onUnreadChanged), "function", "the panel asks WM for unread changes")
  -- The details pane marks the selected (latest) lead seen, so its dot is the state colour.
  local lead, other = ns.Leads.Latest(), ns.Leads.List()[2]
  wm.showPanel("CraftAlert")
  local gold, grey = ns.Theme.COLORS.gold, ns.Theme.COLORS.grey
  Assert.same({ dotOf(lead), dotOf(other) }, { grey, gold }, "no unread: the seen lead's state colour, the unseen gold")
  local asks = #wm.callsTo("GetUnreadCount")
  wm.unread[lead.customer] = 2
  Assert.equal(#wm.callsTo("GetUnreadCount"), asks, "WM is not asked before a paint")
  wm.unreadChanged("CraftAlert")
  Assert.same({ dotOf(lead), dotOf(other) }, { { 1, 0.5, 0.9, 1 }, gold }, "the customer with unread turns pink, seen or not")
  Assert.same(wm.callsTo("GetUnreadCount")[asks + 1], { "GetUnreadCount", lead.customer })
  wm.unread[lead.customer] = 0
  wm.unread[other.customer] = 4
  wm.unreadChanged("CraftAlert")
  Assert.same({ dotOf(lead), dotOf(other) }, { grey, { 1, 0.5, 0.9, 1 } }, "an unseen lead with unread: pink over gold")
  wm.unread[other.customer] = 0
  wm.unreadChanged("CraftAlert")
  Assert.same(dotOf(other), gold, "read in WM: back to gold")
  -- A hidden panel is not repainted by the change; onShow does it.
  wm.hidePanel("CraftAlert")
  wm.unread[lead.customer] = 1
  local before = #wm.callsTo("GetUnreadCount")
  wm.unreadChanged("CraftAlert")
  Assert.equal(#wm.callsTo("GetUnreadCount"), before, "hidden: nothing asked")
  wm.showPanel("CraftAlert")
  Assert.same(dotOf(lead), { 1, 0.5, 0.9, 1 }, "onShow repaints")
end

-- WM without GetUnreadCount (an older one): no onUnreadChanged, the rows never go pink, the
-- bridge still activates.
local function testUnreadDotOlderWm()
  local ns, _, _, _, wm = boot({ leads = 1 }, { without = { "GetUnreadCount" } })
  local dotOf = dotColors(ns)
  Assert.equal(ns.WhisperBridge.Activate(), true)
  Assert.equal(wm.panels.CraftAlert.onUnreadChanged, nil)
  wm.showPanel("CraftAlert")
  Assert.same(dotOf(ns.Leads.Latest()), ns.Theme.COLORS.grey)
  Assert.same(wm.callsTo("GetUnreadCount"), {})
end

-- A GetUnreadCount that raises, refuses or answers a non-number counts as 0: no pink, no error out
-- of the paint.
local function testUnreadDotRaisingWm()
  for _, mode in ipairs({ "raise", "refuse" }) do
    local ns, _, _, _, wm = boot({ leads = 1 })
    local dotOf = dotColors(ns)
    Assert.equal(ns.WhisperBridge.Activate(), true)
    local lead = ns.Leads.Latest()
    wm.unread[lead.customer] = 5
    wm[mode].GetUnreadCount = true
    wm.showPanel("CraftAlert")
    wm.unreadChanged("CraftAlert")
    Assert.same(dotOf(lead), ns.Theme.COLORS.grey, mode)
    Assert.truthy(#wm.callsTo("GetUnreadCount") >= 1, mode .. ": asked")
  end
  local ns, _, _, _, wm = boot({ leads = 1 })
  local dotOf = dotColors(ns)
  ns.WhisperBridge.Activate()
  wm.unread[ns.Leads.Latest().customer] = "many"
  wm.showPanel("CraftAlert")
  Assert.same(dotOf(ns.Leads.Latest()), ns.Theme.COLORS.grey, "a non-number")
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
  Assert.equal(wm.panels.CraftAlert.badge(), 1, "badge counts the leads outside, less the newest the first show saw")
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

-- The click opens the conversation after a greeting it sent, and only then: a lead already greeted
-- got its draft from the greet itself (one conversation, not two), and a `/ca test` lead stays a
-- dry run (nothing sent, nothing opened).
local function testPreviewClickOpensOnce()
  local ns, _, calls, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.Leads.MarkGreeted(lead.id)
  ns.WhisperBridge.ShowLead(lead)
  Wow.clock.gettime = 51
  wm.preview.CraftAlert.onClick()
  Assert.same(wm.callsTo("OpenConversation"), { { "OpenConversation", lead.customer, GREETING } }, "greeted: the draft, once")
  Assert.same(UiFixture.callsTo(calls, "chat"), {}, "not sent again")
  local ns2, _, calls2, _, wm2 = boot()
  ns2.WhisperBridge.Activate()
  local test = ns2.Leads.Latest()
  test.test = true
  ns2.WhisperBridge.ShowLead(test)
  Wow.clock.gettime = 51
  wm2.preview.CraftAlert.onClick()
  Assert.same({ #wm2.callsTo("OpenConversation"), #UiFixture.callsTo(calls2, "chat") }, { 0, 0 }, "test lead: dry run only")
end

-- A raising WM API is a refusal: the click, the keybind and the alert still reach today's path.
local function testRaisingApiIsARefusal()
  local ns, _, calls, _, wm = boot({ leads = 2 })
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  wm.raise.OpenConversation = true
  ns.GreetAction.Empty(lead)
  Assert.same(calls, { { "empty", lead.customer } }, "the Blizzard box opens")
  wm.raise.TogglePanel = true
  ns.LeadsWindow.Toggle()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true, "own window")
  wm.raise.ShowPreview = true
  ns.WhisperBridge.ShowLead(lead)
  Assert.truthy(rawget(_G, "CraftAlertToast"), "own toast")
  local ns2, _, _, _, wm2 = boot()
  ns2.WhisperBridge.Activate()
  ns2.WhisperBridge.ShowLead(ns2.Leads.Latest())
  wm2.showPanel("CraftAlert")
  Assert.equal(ns2.WhisperBridge.VisibleLead() ~= nil, true, "shown when the API answers")
  wm2.raise.IsPreviewShown, wm2.raise.IsPanelShown = true, true
  Assert.equal(ns2.WhisperBridge.VisibleLead(), nil, "neither shows when it raises, and nothing raised")
  wm2.raise.IsPreviewShown, wm2.raise.IsPanelShown = nil, nil
  wm2.raise.OpenConversation = true
  Wow.clock.gettime = 51
  wm2.preview.CraftAlert.onClick() -- sent, then the chat open raises
  Assert.equal(ns2.Leads.Latest().greeted, true, "the click still greeted")
end

-- The side calls too: a raising HidePreview or RefreshPanelBadge does not stop the info line going.
local function testRaisingSideCallsKeepTheRest()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  ns.Leads.MarkGreeted(lead.id)
  ns.WhisperBridge.ShowLead(lead)
  wm.raise.HidePreview, wm.raise.RefreshPanelBadge = true, true
  ns.Leads.Dismiss(lead.id)
  Assert.equal(wm.info.CraftAlert[lead.customer], nil, "the line still goes")
  inInstance(true)
  ns.WhisperBridge.OnGate()
  inInstance(false)
end

-- A refused or raising SetContactInfo (WM full, or broken) is not remembered as sent: the next sync
-- tries again, for a new line and for a removal.
local function testRefusedInfoLineIsRetried()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  local lead = ns.Leads.Latest()
  wm.refuse.SetContactInfo = true
  ns.Leads.MarkGreeted(lead.id)
  Assert.equal(wm.info.CraftAlert, nil, "refused")
  wm.refuse.SetContactInfo, wm.raise.SetContactInfo = nil, true
  ns.WhisperBridge.SyncInfo()
  wm.raise.SetContactInfo = nil
  ns.WhisperBridge.SyncInfo()
  Assert.equal(wm.info.CraftAlert[lead.customer], "|cffffd100Craft Alert:|r Blacksmithing · Me", "sent on retry")
  wm.refuse.SetContactInfo = true
  ns.Leads.Dismiss(lead.id)
  wm.refuse.SetContactInfo = nil
  ns.WhisperBridge.SyncInfo()
  Assert.equal(wm.info.CraftAlert[lead.customer], nil, "removal retried")
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

-- /ca config with the bridge on: WM's panel on settings; shown in settings closes it; refused or
-- raising WM falls back to the own window; nothing in an instance.
local function testConfigRoutesToPanel()
  local ns, _, _, _, wm = boot()
  ns.WhisperBridge.Activate()
  ns.LeadsWindow.ToggleSettings()
  Assert.same(wm.callsTo("ShowPanel"), { { "ShowPanel", "CraftAlert" } })
  Assert.equal(wm.shown.CraftAlert, true, "hidden: the panel opens")
  Assert.equal(ns.BridgePanel.InSettings(), true, "on settings")
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "no own window")
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(wm.shown.CraftAlert, false, "shown in settings: closes")
  wm.showPanel("CraftAlert")
  Assert.equal(ns.BridgePanel.InSettings(), false, "reopened on the leads")
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(ns.BridgePanel.InSettings(), true, "shown on leads: switches to settings")
  Assert.equal(wm.shown.CraftAlert, true)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil)
  wm.hidePanel("CraftAlert")
  wm.refuse.ShowPanel = true
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true, "refused: the own window opens")
  rawget(_G, "CraftAlertLeadsWindow"):Hide()
  inInstance(true)
  wm.refuse.ShowPanel = false
  local calls = #wm.calls
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(#wm.calls, calls, "instance: WM not asked")
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), false, "nothing opens")
  Assert.equal(wm.shown.CraftAlert, false)
end

return function()
  testConfigRoutesToPanel()
  testStandaloneWhenApiMissingOrIncomplete()
  testNoApiCallBeforeActivate()
  testActivationPlugsIn()
  testOpenerGoesToWm()
  testShowLeadPreview()
  testShowPreviewRefusedFallsBackToToast()
  testInfoStripColoursTheCrafter()
  testInfoLines()
  testInfoLinesCapAndMatched()
  testSyncSendsTooltipLines()
  testFakeRefusesBadTooltips()
  testPreviewCarriesClassTag()
  testPreviewClick()
  testTimerAndLeadGone()
  testNoShowInInstance()
  testOnGateHidesPreviewInInstance()
  testOnGateStandalone()
  testInfoStrip()
  testInfoStripNamesTheWhat()
  testPanel()
  testPanelRefreshesOnlyWhileShown()
  testUnreadDot()
  testUnreadDotOlderWm()
  testUnreadDotRaisingWm()
  testPanelHostRules()
  testPanelEmptyInInstance()
  testLeavingInstanceRefreshesPanel()
  testPanelRefusedStaysStandalone()
  testPreviewClickOpensOnce()
  testRaisingApiIsARefusal()
  testRaisingSideCallsKeepTheRest()
  testRefusedInfoLineIsRetried()
  testNoOnUpdateAnywhere()
  Wow.reset()
end
