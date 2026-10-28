local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Templates = require("tests.helpers.templates")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec A.1-A.3, A.6: the leads window hosts the split view (UI/LeadsView.lua) in its content
-- frame, under the portrait and the status band. Row and details content is tested in
-- test_lead_row.lua and test_lead_details.lua; this file covers the window around them.
local WINDOW_NAME = "CraftAlertLeadsWindow"
local LIST_ATLAS, DETAILS_ATLAS = "Professions-background-summarylist", "auctionhouse-background-index"

local function window()
  return rawget(_G, WINDOW_NAME)
end

local function view()
  return window().view
end

-- The shown row frames of the window, top to bottom.
local function rows()
  local shown = {}
  for _, frame in ipairs(Wow.frames) do
    if frame.isLeadRow and frame:IsShown() then
      shown[#shown + 1] = frame
    end
  end
  table.sort(shown, function(a, b)
    return a.rowIndex < b.rowIndex
  end)
  return shown
end

-- Every text shown in `frame` and its descendants, joined.
local function textOf(frame)
  return table.concat(Widgets.texts(frame, Wow.frames), " / ")
end

-- `n` customer names, Customer1-Draenor (oldest) to Customer<n>-Draenor.
local function customerNames(n)
  local names = {}
  for i = 1, n do
    names[i] = "Customer" .. i .. "-Draenor"
  end
  return names
end

-- A fixture whose leads come from `customers` (oldest first), the window subscribed to
-- lead changes as Bootstrap will do it.
local function load(customers, edit)
  local ns, db, calls = UiFixture.load({
    db = function(accountDb)
      for id, customer in ipairs(customers) do
        accountDb.leads[id] = UiFixture.lead(id, customer)
      end
      if edit then
        edit(accountDb)
      end
    end,
  })
  ns.Leads.On("change", ns.LeadsWindow.Refresh)
  return ns, db, calls
end

local function wheel(delta)
  local frame = view().frame
  frame.scripts.OnMouseWheel(frame, delta)
end

local function resize(width, height)
  window():SetSize(width, height)
  window().scripts.OnSizeChanged(window(), width, height)
end

local function testLazyAndEscape()
  local ns = load({ "Ann-Draenor" })
  -- §4.4 rule 5: nothing exists before the first open; a refresh before it creates nothing.
  ns.LeadsWindow.Refresh()
  Assert.equal(window(), nil)
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  ns.LeadsWindow.Toggle()
  Assert.truthy(window(), "window created on first open")
  Assert.equal(window().template, "ButtonFrameTemplate")
  -- Spec A.1: the portrait shows the bell; the template's own inset gives way to the content frame.
  Assert.equal(window().portraitHidden, nil)
  Assert.equal(window().portraitAsset, ns.Theme.ICON)
  Assert.equal(window().Inset:IsShown(), false)
  Assert.equal(window().scripts.OnMouseWheel, nil, "the view's root takes the wheel, not the window")
  Assert.equal(window():GetTitleText():GetText(), "Craft Alert — Leads")
  Assert.equal(window():IsShown(), true)
  -- ESC closes it: our own frame name in UISpecialFrames, once, however often it opens.
  ns.LeadsWindow.Toggle()
  Assert.equal(window():IsShown(), false)
  ns.LeadsWindow.Toggle()
  Assert.same(rawget(_G, "UISpecialFrames"), { WINDOW_NAME })
  Assert.equal(window().movable, true)
  Assert.equal(window().resizable, true)
  Assert.equal(window().clamped, true)
  -- The close button hides it.
  Widgets.click(window().CloseButton, "LeftButton")
  Assert.equal(window():IsShown(), false)
  -- In combat HideUIPanel returns without hiding (addon code may not call protected functions),
  -- yet the close button still closes the window.
  ns.LeadsWindow.Toggle()
  Wow.stub("HideUIPanel", function() end)
  Widgets.click(window().CloseButton, "LeftButton")
  Assert.equal(window():IsShown(), false, "the close button hides the window in combat")

  -- A template without SetPortraitToAsset (Classic): the portrait texture is set directly.
  Templates.portraitMethod = false
  ns = load({ "Ann-Draenor" })
  ns.LeadsWindow.Toggle()
  Templates.portraitMethod = true
  Assert.equal(window().SetPortraitToAsset, nil)
  Assert.equal(window().PortraitContainer.portrait.texture, ns.Theme.ICON)
end

local function testContentFrameAndBand()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local frame = window()
  Assert.same(frame.content.points, {
    { "TOPLEFT", frame, "TOPLEFT", 4, -60 },
    { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4 },
  })
  Assert.equal(view().frame:GetParent(), frame.content)
  local status = frame.status
  Assert.same({ status.font, status.textColor }, { "GameFontHighlightSmall", ns.Theme.COLORS.textSecondary })
  Assert.same(status.points[1], { "LEFT", frame, "TOPLEFT", 64, -42 })
  Assert.equal(status:GetText(), "2 leads")
  -- The band follows the leads (Bootstrap's change subscription) and is empty in Settings.
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(status:GetText(), "1 lead")
  Widgets.click(frame.gear)
  Assert.equal(status:GetText(), "")
  Widgets.click(frame.gear)
  Assert.equal(status:GetText(), "1 lead")
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(status:GetText(), "")
end

-- AC1: two panes over their atlases under the ledger line, 9 rows at the default size, refit on
-- resize.
local function testPanesAndRows()
  local ns = load(customerNames(12))
  ns.LeadsWindow.Toggle()
  Assert.same({ window():GetWidth(), window():GetHeight() }, { 840, 560 })
  Assert.equal(#rows(), 9) -- floor((560 - 64 - 20 - 8) / 48)
  Assert.equal(rows()[1].parent, view().listPane)
  Assert.same({ view().listPane.bg.atlas, view().detailsPane.bg.atlas }, { LIST_ATLAS, DETAILS_ATLAS })
  Assert.equal(view().details.lead, ns.Leads.Latest())
  -- No footer hint: the details' buttons and the tooltips carry the clicks.
  Assert.falsy(string.find(textOf(window()), "Click: greet", 1, true), "no footer hint: " .. textOf(window()))
  resize(720, 420)
  Assert.equal(#rows(), 6) -- floor((420 - 64 - 20 - 8) / 48)
  -- The client may report 0 for the window's height on an open; no row then, and no error,
  -- until the size arrives.
  ns.LeadsWindow.Toggle()
  local getHeight = window().GetHeight
  window().GetHeight = function()
    return 0
  end
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 0)
  window().GetHeight = getHeight
  resize(840, 560)
  Assert.equal(#rows(), 9)

  -- Classic flavors: no atlas, the rows still draw.
  ns = load(customerNames(12))
  Wow.stub("C_Texture", {
    GetAtlasInfo = function()
      return nil
    end,
  })
  ns.LeadsWindow.Toggle()
  Assert.same({ view().listPane.bg.atlas, view().detailsPane.bg.atlas }, { nil, nil })
  Assert.equal(#rows(), 9)
end

local function testRowFields()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.leads[1].time = UiFixture.T0 - 125
    accountDb.leads[1].greeted = true
    accountDb.leads[1].replied = true
    accountDb.leads[2].time = UiFixture.T0 - 30
    accountDb.leads[2].kind, accountDb.leads[2].itemLink = "item", "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r"
    accountDb.leads[2].cannotOrder = true
  end)
  ns.LeadsWindow.Toggle()
  local shown = rows()
  Assert.equal(#shown, 2)
  -- Newest first, with name, age and what was asked for; the marks on the row.
  Assert.same({ shown[1].name:GetText(), shown[1].age:GetText() }, { "Bob-Draenor", "30s" })
  Assert.same({ shown[2].name:GetText(), shown[2].age:GetText() }, { "Ann-Draenor", "2m" })
  Assert.equal(shown[1].what:GetText(), "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r")
  Assert.equal(shown[2].what:GetText(), "Blacksmithing")
  Assert.same({ shown[1].greetedIcon:IsShown(), shown[1].repliedTag:IsShown() }, { false, false })
  Assert.same({ shown[2].greetedIcon:IsShown(), shown[2].repliedTag:IsShown() }, { true, true })
  -- No realm warning on the row; the details header's line 1 follows the selected lead.
  Assert.equal(shown[1].realm, nil)
  local details = view().details
  Assert.equal(details.lead.customer, "Bob-Draenor")
  Assert.truthy(string.find(details.lineOne:GetText(), "New lead", 1, true), details.lineOne:GetText())
  -- The cross-realm lead's details show the Realm row; the other lead's don't.
  local realmLabel, realm = details.sections.labels.realm, details.sections.lines.realm[1]
  Assert.same({ realmLabel:IsShown(), realm:IsShown(), realm:GetText() }, { true, true, "Can't send an order (other realm)" })
  Widgets.click(shown[2], "LeftButton")
  local status = details.lineOne:GetText()
  Assert.truthy(string.find(status, "Greeted|r, |cff4cd166replied", 1, true), status)
  Assert.same({ realmLabel:IsShown(), realm:IsShown() }, { false, false })
  -- Ages are refreshed on each refresh (window open or lead event), never by a ticker.
  Wow.clock.time = UiFixture.T0 + 60
  ns.LeadsWindow.Refresh()
  Assert.equal(rows()[1].age:GetText(), "1m")

  -- No leads: the empty text in the details pane, no rows, nothing selected.
  ns = load({})
  ns.ScanGate.State = function()
    return { active = true, channels = { "Trade" }, recipeCount = 4, crafterCount = 2 }
  end
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 0)
  Assert.truthy(string.find(textOf(view().detailsPane), "No leads", 1, true), textOf(view().detailsPane))
  Assert.equal(ns.LeadsView.Selected(view()), nil)
  Assert.equal(view().details.frame:IsShown(), false)
end

-- The window follows the gate while empty: the paused line when it is not listening, the old text again when it is.
local function testEmptyFollowsGate()
  local ns = load({})
  ns.LeadsWindow.Toggle()
  local state = { active = false, reason = "noTrade", channels = {}, recipeCount = 0, crafterCount = 0 }
  ns.ScanGate.State = function()
    return state
  end
  ns.LeadsWindow.OnGate(false, state)
  Assert.equal(view().empty.text:GetText(), "Paused — no Trade chat here")
  state = { active = true, channels = { "Trade" }, recipeCount = 4, crafterCount = 2 }
  ns.LeadsWindow.OnGate(true, state)
  Assert.equal(view().empty.text:GetText(), "No leads right now. Requests you can craft show up here.")
end

-- AC2: a left click selects, a right click dismisses with the look rule, the details' buttons
-- act on the selected lead.
local function testClicks()
  local ns, _, calls = load(customerNames(3))
  ns.LeadsWindow.Toggle()
  local details = view().details
  -- A right click within 0.5 s of the row appearing leaves the lead.
  Wow.clock.gettime = 50.2
  Widgets.click(rows()[1], "RightButton")
  Assert.equal(#ns.Leads.List(), 3, "too soon after the row appeared")
  Wow.clock.gettime = 51
  Widgets.click(rows()[2], "LeftButton")
  local second = rows()[2].lead
  Assert.same({ ns.LeadsView.Selected(view()), details.lead, details.shownAt }, { second, second, 51 })
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0, "a left click never greets")
  -- The details' buttons act on the selected lead once it has been up 0.5 s.
  Wow.clock.gettime = 52
  Widgets.click(details.buttons.greet, "LeftButton")
  Assert.same({ #UiFixture.callsTo(calls, "chat"), second.greeted }, { 1, true })
  Widgets.click(details.buttons.whisper, "LeftButton")
  Assert.equal(#UiFixture.callsTo(calls, "empty"), 1)
  Widgets.click(details.buttons.dismiss, "LeftButton")
  Assert.equal(ns.Leads.IsActive(second.id), false)
  Assert.equal(#ns.Leads.List(), 2)
  -- The right click dismisses the row's own lead.
  local top = rows()[1].lead
  Wow.clock.gettime = 60
  Widgets.click(rows()[1], "RightButton")
  Assert.equal(ns.Leads.IsActive(top.id), false)
  Assert.equal(#rows(), 1)
end

local function testWheel()
  local ns = load(customerNames(12))
  ns.LeadsWindow.Toggle()
  wheel(-1)
  Assert.equal(rows()[1].lead.customer, "Customer11-Draenor")
  Assert.equal(ns.LeadsView.Selected(view()), ns.Leads.Latest(), "scrolled off, still selected")
  Widgets.click(window().gear)
  Assert.equal(view().frame:IsShown(), false, "no wheel over the hidden view in Settings")
end

-- AC3: the keybinds read the top row's lead and when it appeared there.
local function testVisibleLatestAndScroll()
  local ns = load(customerNames(12))
  ns.LeadsWindow.Toggle()
  -- The newest lead is in the top row, shown since the window opened (GetTime() 50).
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 50 })
  -- A refresh keeps that time; a lead new to the top row is shown from the refresh.
  Wow.clock.gettime = 55
  ns.LeadsWindow.Refresh()
  Assert.equal(select(2, ns.LeadsWindow.VisibleLatest()), 50)
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 55 })
  Assert.equal(rows()[1].lead.customer, "Customer11-Draenor")
  -- The mouse wheel scrolls; the latest lead is then off screen.
  wheel(-1)
  Assert.equal(rows()[1].lead.customer, "Customer10-Draenor")
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  for _ = 1, 20 do
    wheel(-1)
  end
  Assert.equal(rows()[#rows()].lead.customer, "Customer1-Draenor", "stops at the oldest lead")
  -- Closing and reopening starts at the top again, shown from the new open time.
  ns.LeadsWindow.Toggle()
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  Wow.clock.gettime = 70
  ns.LeadsWindow.Toggle()
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 70 })
end

-- Review Focus 4: every open is the newest lead, selected, at the top, shown from the open.
local function testReopenResetsSelection()
  local ns = load(customerNames(12)) -- more than the 10 that fit, so the list can scroll
  local LeadsView = ns.LeadsView
  local function pickThirdAndScroll()
    Widgets.click(rows()[3], "LeftButton")
    wheel(-1)
    Assert.equal(view().list.offset, 1)
    Assert.truthy(LeadsView.Selected(view()) ~= ns.Leads.Latest())
  end
  local function assertFresh(at)
    Assert.same({ LeadsView.Selected(view()), view().list.offset }, { ns.Leads.Latest(), 0 })
    Assert.same({ view().details.lead, view().details.shownAt }, { ns.Leads.Latest(), at })
    Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), at })
  end
  ns.LeadsWindow.Toggle()
  pickThirdAndScroll()
  ns.LeadsWindow.Toggle()
  Wow.clock.gettime = 70
  ns.LeadsWindow.Toggle()
  assertFresh(70)
  -- Closed by its own Hide (X, Esc) instead of Toggle.
  pickThirdAndScroll()
  window():Hide()
  Wow.clock.gettime = 80
  ns.LeadsWindow.Toggle()
  assertFresh(80)
  -- Alt+Z: the UI comes back with the window; the time under the hidden UI is no look.
  local screen = rawget(_G, "UIParent")
  screen:Hide()
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  Wow.clock.gettime = 90
  screen:Show()
  assertFresh(90)
end

-- Review Focus 5: the ghost grip sizes the window once on release, saves, survives close-and-reopen
-- and reload. The clamp is tested in test_ghost_resize.lua (the fake models no client clamp).
local function testResizeGrip()
  local customers = customerNames(12)
  local ns, db = load(customers)
  ns.LeadsWindow.Toggle()
  local frame = window()
  local grip = frame.resizeGrip
  Assert.truthy(grip, "the ghost grip")
  Assert.equal(frame.resizeButton, nil)
  Assert.equal(#rows(), 9)
  -- Dragging sizes the ghost only: the window and its rows wait for the release.
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  grip.ghost:SetSize(1000, 640)
  Assert.same({ frame:GetWidth(), frame:GetHeight(), #rows() }, { 840, 560, 9 })
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.same({ frame:GetWidth(), frame:GetHeight() }, { 1000, 640 })
  Assert.equal(#rows(), 11) -- floor((640 - 64 - 20 - 8) / 48)
  Assert.same({ db.ui.window.width, db.ui.window.height }, { 1000, 640 })
  -- Closed and reopened: same size, rows refit.
  ns.LeadsWindow.Toggle()
  ns.LeadsWindow.Toggle()
  Assert.same({ frame:GetWidth(), frame:GetHeight(), #rows() }, { 1000, 640, 11 })
  -- After a /reload it opens at the saved size with the rows refit.
  local saved = db.ui.window
  ns = load(customers, function(accountDb)
    accountDb.ui.window = saved
  end)
  ns.LeadsWindow.Toggle()
  Assert.same({ window():GetWidth(), window():GetHeight(), #rows() }, { 1000, 640, 11 })
end

local function testSavedFrameAndOpacity()
  local ns, db = load({ "Ann-Draenor" })
  db.settings.opacity = 0.7
  ns.LeadsWindow.Toggle()
  local frame = window()
  Assert.equal(frame:GetAlpha(), 0.7)
  -- Dragging saves the position; the grip saves the size and re-anchors at the top-left corner.
  frame.scripts.OnDragStart(frame)
  frame:ClearAllPoints()
  frame:SetPoint("LEFT", rawget(_G, "UIParent"), "LEFT", 30, 40)
  frame.scripts.OnDragStop(frame)
  Assert.same({ db.ui.window.point, db.ui.window.x, db.ui.window.y }, { "LEFT", 30, 40 })
  frame.left, frame.top = 30, 600
  local grip = frame.resizeGrip
  Widgets.fire(grip, "OnMouseDown", "LeftButton")
  grip.ghost:SetSize(900, 600)
  Widgets.fire(grip, "OnMouseUp", "LeftButton")
  Assert.same(db.ui.window, { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 30, y = 600, width = 900, height = 600 })

  -- The saved shapes are flat scalars, which the load-time Schema check keeps as they are.
  local Schema = Fresh.require("Persistence.Schema")
  local copy = { ui = { window = {}, toast = { point = "TOP", relativePoint = "TOP", x = 0, y = -160 } } }
  for key, value in pairs(db.ui.window) do
    copy.ui.window[key] = value
  end
  local repaired = Schema.Validate(copy)
  Assert.same(repaired.ui.window, db.ui.window)
  Assert.same(repaired.ui.toast, { point = "TOP", relativePoint = "TOP", x = 0, y = -160 })

  -- After a /reload it opens there, at that size.
  local saved = db.ui.window
  ns = load({ "Ann-Draenor" }, function(accountDb)
    accountDb.ui.window = saved
  end)
  ns.LeadsWindow.Toggle()
  local point, _, relativePoint, x, y = window():GetPoint()
  Assert.same({ point, relativePoint, x, y, window():GetWidth(), window():GetHeight() }, { "TOPLEFT", "BOTTOMLEFT", 30, 600, 900, 600 })
end

-- Runs fn, raising instead of hanging when it loops (a client freeze).
local function bounded(fn)
  debug.sethook(function()
    debug.sethook()
    error("runaway loop")
  end, "", 1e7)
  local ok, err = pcall(fn)
  debug.sethook()
  assert(ok, err)
end

-- A saved size the Schema keeps (any finite number) opens on screen and refreshes at once.
local function testHugeSavedSize()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.ui.window = { width = 1e300, height = 1e300 }
  end)
  bounded(ns.LeadsWindow.Toggle)
  local parent = rawget(_G, "UIParent")
  Assert.equal(window():GetWidth(), parent:GetWidth(), "no wider than the screen")
  Assert.equal(window():GetHeight(), parent:GetHeight(), "no taller than the screen")
  Assert.equal(window().resizeGrip.ghost.resizeBounds[3], parent:GetWidth())
  Assert.equal(#rows(), 2)
  -- Even a frame taller than the screen (the client does not guarantee the clamp) rows only
  -- the leads there are.
  window():SetSize(840, 1e300)
  bounded(ns.LeadsWindow.Refresh)
  Assert.equal(#rows(), 2)
end

-- Review Focus 5: whatever a hand-edited SavedVariables holds, every lead the load-time Schema
-- check keeps renders in the rows and the details and can be greeted.
local function testCorruptedSavedLeads()
  local corrupted = {
    { profName = true },
    { crafter = {} },
    { itemLink = {}, recipeName = 5, why = {}, message = {}, guid = 7, cannotOrder = "yes" },
    { greeted = "no", replied = 1, kind = 5, prof = {}, group = {}, itemID = "501" },
  }
  local ns, _, calls = load({}, function(accountDb)
    for id, fields in ipairs(corrupted) do
      local lead = UiFixture.lead(id)
      for key, value in pairs(fields) do
        lead[key] = value
      end
      accountDb.leads[id] = lead
    end
    Fresh.require("Persistence.Schema").Validate(accountDb)
  end)
  Assert.equal(#ns.Leads.List(), 3, "the lead without a usable crafter is dropped")
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 3)
  for _, row in ipairs(rows()) do
    Widgets.click(row, "LeftButton")
    Assert.equal(view().details.lead, row.lead, "the details draw every kept lead")
  end
  Wow.clock.gettime = 60
  for _, lead in ipairs(ns.Leads.List()) do
    ns.AlertToast.Show(lead)
    ns.GreetAction.Greet(lead, 50)
  end
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 3)
end

return function()
  testLazyAndEscape()
  testContentFrameAndBand()
  testPanesAndRows()
  testRowFields()
  testEmptyFollowsGate()
  testClicks()
  testWheel()
  testVisibleLatestAndScroll()
  testReopenResetsSelection()
  testResizeGrip()
  testSavedFrameAndOpacity()
  testCorruptedSavedLeads()
  testHugeSavedSize()
  Wow.reset()
end
