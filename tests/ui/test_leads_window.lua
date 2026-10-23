local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local WINDOW_NAME = "CraftAlertLeadsWindow"
local LINK = "item:190001"
local LINK_TEXT = "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r"

local function window()
  return rawget(_G, WINDOW_NAME)
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

local function testLazyAndEscape()
  local ns = load({ "Ann-Draenor" })
  -- §4.4 rule 5: nothing exists before the first open; a refresh before it creates nothing.
  ns.LeadsWindow.Refresh()
  Assert.equal(window(), nil)
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  ns.LeadsWindow.Toggle()
  Assert.truthy(window(), "window created on first open")
  Assert.equal(window().template, "ButtonFrameTemplate")
  Assert.equal(window().portraitHidden, true)
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
end

local function testRowFields()
  local ns, db = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
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
  -- §7.3: newest first, with age, customer, item/profession, crafter, greeted and replied.
  local first, second = textOf(shown[1]), textOf(shown[2])
  for _, part in ipairs({ "Bob-Draenor", "30s", "[Sim Plate Belt]", "Me-Realm", "can't order (realm)" }) do
    Assert.truthy(string.find(first, part, 1, true), part .. " missing from: " .. first)
  end
  for _, part in ipairs({ "Ann-Draenor", "2m", "Blacksmithing", "Me-Realm" }) do
    Assert.truthy(string.find(second, part, 1, true), part .. " missing from: " .. second)
  end
  Assert.falsy(string.find(first, "R2", 1, true), "no rank, no R part: " .. first)
  Assert.equal(shown[1].greetedIcon:IsShown(), false)
  Assert.equal(shown[1].repliedTag:IsShown(), false)
  Assert.equal(shown[2].greetedIcon:IsShown(), true)
  Assert.equal(shown[2].repliedTag:IsShown(), true)
  -- Ages are refreshed on each refresh (window open or lead event), never by a ticker.
  Wow.clock.time = UiFixture.T0 + 60
  ns.LeadsWindow.Refresh()
  Assert.truthy(string.find(textOf(rows()[1]), "1m", 1, true), textOf(rows()[1]))
  Assert.equal(#db.leads, 2)

  -- No leads: an empty-state line, no rows.
  ns = load({})
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 0)
  Assert.truthy(string.find(textOf(window()), "No leads", 1, true))
end

-- §4.5: the rank sits between the crafter and the realm tag.
local function testRowRank()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.leads[1].rank, accountDb.leads[1].rankConc = 2, false
    accountDb.leads[2].rank, accountDb.leads[2].rankConc, accountDb.leads[2].cannotOrder = 2, true, true
  end)
  ns.LeadsWindow.Toggle()
  local shown = rows()
  local conc, plain = textOf(shown[1]), textOf(shown[2])
  Assert.truthy(string.find(conc, "by Me-Realm · R2 (conc) · can't order (realm)", 1, true), conc)
  Assert.truthy(string.find(plain, "by Me-Realm · R2", 1, true), plain)
  Assert.falsy(string.find(plain, "(conc)", 1, true), plain)
end

local function testRowClicks()
  local ns, _, calls = load({ "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local left = rows()
  Assert.equal(#left, 1)
  Assert.truthy(string.find(textOf(left[1]), "Bob-Draenor", 1, true))
  -- With no button on the right, the replied tag sits at the row's right edge, inset by PADDING.
  local point, relativeTo, relativePoint, x, y = left[1].repliedTag:GetPoint()
  Assert.equal(point, "RIGHT")
  Assert.equal(relativeTo, left[1], "anchored to the row")
  Assert.equal(relativePoint, "RIGHT")
  Assert.equal(x, -ns.Theme.LAYOUT.PADDING)
  Assert.equal(y, 0)

  -- Rows take the toast's clicks: left greets once the row has been up 0.5 s, right dismisses.
  Wow.clock.gettime = 51
  Widgets.click(left[1], "LeftButton")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)
  Assert.equal(ns.Leads.Latest().greeted, true)
  Widgets.click(rows()[1], "RightButton")
  Assert.equal(ns.Leads.HasActive(), false)
  Assert.equal(#rows(), 0)
end

-- native-HUD spec §6: no fill on a row; the quest-log hover texture lights it.
local function testRowHighlight()
  local ns = load({ "Ann-Draenor" })
  ns.LeadsWindow.Toggle()
  local row = rows()[1]
  local fills = 0
  for _, region in ipairs(row.regions) do
    if region.color then
      fills = fills + 1
    end
  end
  local hover = assert(row.hover, "the row's hover texture")
  Assert.equal(hover.layer, "HIGHLIGHT")
  Assert.equal(hover.texture, ns.Theme.ART.LIST_HOVER)
  Assert.equal(hover.blendMode, "ADD")
  Assert.equal(hover:GetAlpha(), ns.Theme.ART.LIST_HOVER_ALPHA)
  Assert.equal(fills, 0, "no colour fill on the row")
end

-- native-HUD spec §6, §4.5, §4.6: the item link in the detail line hovers, clicks through SetItemRef, and guards the row's clicks.
local function testRowLinkHover()
  local ns, _, calls = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.leads[2].kind, accountDb.leads[2].itemLink = "item", LINK_TEXT
  end)
  local tip = rawget(_G, "GameTooltip")
  ns.LeadsWindow.Toggle()
  local row = rows()[1] -- Bob, the newest lead, holds the item link
  Assert.truthy(row.scripts.OnHyperlinkEnter and row.scripts.OnHyperlinkLeave and row.scripts.OnHyperlinkClick)

  row.scripts.OnHyperlinkEnter(row, LINK, LINK_TEXT)
  Assert.equal(row.hoveredLink, LINK)
  Assert.same({ tip.hyperlinks, tip.owner, tip.shown }, { { LINK }, row, true })

  -- While a link is hovered no click greets or dismisses.
  local bobId = row.lead.id
  Wow.clock.gettime = 51
  Widgets.click(row, "LeftButton")
  Widgets.click(row, "RightButton")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0, "a click on a link never greets")
  Assert.equal(ns.Leads.IsActive(bobId), true, "a right-click on a link never dismisses")
  Assert.equal(row.lead.customer, "Bob-Draenor")

  row.scripts.OnHyperlinkClick(row, LINK, LINK_TEXT, "LeftButton")
  Assert.same(Wow.itemRefs, { { LINK, LINK_TEXT, "LeftButton", row } })

  -- After the link is left, a plain click greets.
  row.scripts.OnHyperlinkLeave(row, LINK)
  Assert.same({ row.hoveredLink, tip.shown }, { nil, false })
  Widgets.click(row, "LeftButton")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)

  -- A refresh that puts another lead in the row clears the hovered link and its tooltip.
  row.scripts.OnHyperlinkEnter(row, LINK, LINK_TEXT)
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.equal(rows()[1], row)
  Assert.equal(row.lead.customer, "Ann-Draenor")
  Assert.same({ row.hoveredLink, tip.shown }, { nil, false })

  -- Closing and reopening the window clears it too.
  row.scripts.OnHyperlinkEnter(row, LINK, LINK_TEXT)
  ns.LeadsWindow.Toggle()
  ns.LeadsWindow.Toggle()
  Assert.equal(row.hoveredLink, nil)
end

-- Rows sit in the inset and fit its height (480 high: inset 480 - 28 - 26 = 426; floor((426 - 16 + 2) / 38) = 10).
local function testRowsFitTheInset()
  local ns = load(customerNames(12))
  ns.LeadsWindow.Toggle()
  local frame = window()
  Assert.equal(#rows(), 10)
  Assert.equal(rows()[1].parent, frame.Inset)
  Assert.same({ rows()[1]:GetPoint() }, { "TOPLEFT", frame.Inset, "TOPLEFT", 8, -8 })
  Assert.same({ rows()[2]:GetPoint() }, { "TOPLEFT", frame.Inset, "TOPLEFT", 8, -46 })
  -- No footer hint under the list: the clicks are the toast's, and its tooltip lists them.
  Assert.falsy(string.find(textOf(frame), "Click: greet", 1, true), "no footer hint: " .. textOf(frame))
  -- The client sizes the inset from its anchors only, which may be unresolved (0 high) on the
  -- first open; the fit still comes out of the frame's own height.
  ns.LeadsWindow.Toggle()
  frame.Inset.GetHeight = function()
    return 0
  end
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 10, "rows fit before the inset is laid out")
  ns = load({})
  ns.LeadsWindow.Toggle()
  Assert.truthy(string.find(textOf(window().Inset), "No leads", 1, true), "empty text is in the inset")
end

-- Review Focus 5: resize wrapping, minimum, save, close-and-reopen, reload.
local function testResizeButton()
  local customers = customerNames(12)
  local ns, db = load(customers)
  ns.LeadsWindow.Toggle()
  local frame, screen = window(), rawget(_G, "UIParent")
  local button = frame.resizeButton
  Assert.equal(button.template, "PanelResizeButtonTemplate")
  Assert.same(
    { button.target == frame, button.minWidth, button.minHeight, button.maxWidth, button.maxHeight },
    { true, 600, 480, screen:GetWidth(), screen:GetHeight() }
  )
  Assert.equal(#rows(), 10)
  -- Dragging: the client resizes and fires OnSizeChanged. Init wrapped our refresh, so rows refit.
  button.scripts.OnMouseDown(button, "LeftButton")
  Assert.equal(frame.sizing, "BOTTOMRIGHT")
  frame:SetSize(700, 520)
  frame.scripts.OnSizeChanged(frame, 700, 520)
  Assert.equal(#rows(), 11) -- 520 - 54 = 466; floor((466 - 16 + 2) / 38) = 11
  -- Below the minimum, the button's wrapper pulls the size back (it only works if our script was set before Init).
  frame:SetSize(100, 100)
  frame.scripts.OnSizeChanged(frame, 100, 100)
  Assert.same({ frame:GetWidth(), frame:GetHeight() }, { 600, 480 })
  frame:SetSize(700, 520)
  frame.scripts.OnSizeChanged(frame, 700, 520)
  button.scripts.OnMouseUp(button, "LeftButton")
  Assert.equal(frame.sizing, nil)
  Assert.same({ db.ui.window.width, db.ui.window.height }, { 700, 520 })
  -- Closed and reopened: same size, rows refit.
  ns.LeadsWindow.Toggle()
  ns.LeadsWindow.Toggle()
  Assert.same({ frame:GetWidth(), frame:GetHeight(), #rows() }, { 700, 520, 11 })
  -- After a /reload it opens at the saved size with the rows refit.
  local saved = db.ui.window
  ns = load(customers, function(accountDb)
    accountDb.ui.window = saved
  end)
  ns.LeadsWindow.Toggle()
  Assert.same({ window():GetWidth(), window():GetHeight(), #rows() }, { 700, 520, 11 })
end

local function testVisibleLatestAndScroll()
  local ns = load(customerNames(12))
  ns.LeadsWindow.Toggle()
  -- The newest lead is in the top row, shown since the window opened (GetTime() 50).
  local lead, shownAt = ns.LeadsWindow.VisibleLatest()
  Assert.equal(lead, ns.Leads.Latest())
  Assert.equal(shownAt, 50)
  -- A refresh keeps that time; a lead new to the top row is shown from the refresh.
  Wow.clock.gettime = 55
  ns.LeadsWindow.Refresh()
  Assert.equal(select(2, ns.LeadsWindow.VisibleLatest()), 50)
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 55 })
  Assert.truthy(string.find(textOf(rows()[1]), "Customer11-Draenor", 1, true), textOf(rows()[1]))
  local visibleRows = #rows()
  Assert.truthy(visibleRows > 0 and visibleRows < 11, "only the rows that fit are shown")
  -- The mouse wheel scrolls; the latest lead is then off screen.
  window().scripts.OnMouseWheel(window(), -1)
  Assert.truthy(string.find(textOf(rows()[1]), "Customer10-Draenor", 1, true), textOf(rows()[1]))
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  for _ = 1, 20 do
    window().scripts.OnMouseWheel(window(), -1)
  end
  Assert.truthy(string.find(textOf(rows()[#rows()]), "Customer1-Draenor", 1, true), "stops at the oldest lead")
  -- Closing and reopening starts at the top again, shown from the new open time.
  ns.LeadsWindow.Toggle()
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  Wow.clock.gettime = 70
  ns.LeadsWindow.Toggle()
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 70 })
end

local function testSavedFrameAndOpacity()
  local ns, db = load({ "Ann-Draenor" })
  db.settings.opacity = 0.7
  ns.LeadsWindow.Toggle()
  local frame = window()
  Assert.equal(frame:GetAlpha(), 0.7)
  -- Dragging saves the position; the resize button saves the size.
  frame.scripts.OnDragStart(frame)
  frame:ClearAllPoints()
  frame:SetPoint("LEFT", rawget(_G, "UIParent"), "LEFT", 30, 40)
  frame.scripts.OnDragStop(frame)
  local button = frame.resizeButton
  button.scripts.OnMouseDown(button, "LeftButton")
  Assert.equal(frame.sizing, "BOTTOMRIGHT")
  frame:SetSize(700, 560)
  button.scripts.OnMouseUp(button, "LeftButton")
  Assert.same(db.ui.window, { point = "LEFT", relativePoint = "LEFT", x = 30, y = 40, width = 700, height = 560 })

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
  Assert.same({ point, relativePoint, x, y, window():GetWidth(), window():GetHeight() }, { "LEFT", "LEFT", 30, 40, 700, 560 })
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
  Assert.equal(window().resizeButton.maxWidth, parent:GetWidth())
  Assert.equal(#rows(), 2)
  -- Even a frame taller than the screen (the client does not guarantee the clamp) rows only
  -- the leads there are.
  window():SetSize(600, 1e300)
  bounded(ns.LeadsWindow.Refresh)
  Assert.equal(#rows(), 2)
end

-- Review Focus 5: whatever a hand-edited SavedVariables holds, every lead the load-time Schema
-- check keeps renders on the toast and in the window and can be greeted.
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
  Wow.clock.gettime = 60
  for _, lead in ipairs(ns.Leads.List()) do
    ns.AlertToast.Show(lead)
    ns.GreetAction.Greet(lead, 50)
  end
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 3)
end

return function()
  testLazyAndEscape()
  testRowFields()
  testRowRank()
  testRowClicks()
  testRowHighlight()
  testRowLinkHover()
  testRowsFitTheInset()
  testResizeButton()
  testVisibleLatestAndScroll()
  testSavedFrameAndOpacity()
  testCorruptedSavedLeads()
  testHugeSavedSize()
  Wow.reset()
end
