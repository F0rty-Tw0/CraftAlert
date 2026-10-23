local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Leads-details spec §4: in list mode the leads window shows its rows in a left column and the details of one
-- lead on the right. One pinned lead: a row's hover pins it; leaving, scrolling or a new lead
-- changes nothing; no pin (or the pinned lead gone) shows the newest.
local LINK = "item:4305"
local LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
-- A Blacksmithing profession word, as the Matcher reports it.
local SMITH = { kind = "profession", prof = 164, entries = {}, entryCount = 0, why = { "lf", "blacksmith" }, whyCount = 2 }

local function window()
  return rawget(_G, "CraftAlertLeadsWindow")
end

local function pane()
  return window().details
end

local function shown(ns)
  return ns.LeadDetails.Shown(pane())
end

-- The shown row frame holding `lead`.
local function rowOf(lead)
  for _, frame in ipairs(Wow.frames) do
    if frame.isLeadRow and frame:IsShown() and frame.lead == lead then
      return frame
    end
  end
  error("no row for " .. tostring(lead.customer))
end

-- Runs the timers pending now with a delay of 0.2 s or less (the hover dwell), as if that much
-- time had passed. Not Wow.runTimers: the lead-expiry timer re-arms.
local function runDwell()
  local due, kept = {}, {}
  for _, timer in ipairs(Wow.timers) do
    table.insert(timer.delay <= 0.2 and due or kept, timer)
  end
  Wow.timers = kept
  for _, timer in ipairs(due) do
    timer.fn()
  end
end

-- The cursor on `row` for the dwell: enters, rests, the pane follows.
local function hover(row)
  row.mouseOver = true
  Widgets.fire(row, "OnEnter")
  runDwell()
end

local function byCustomer(ns, customer)
  for _, lead in ipairs(ns.Leads.List()) do
    if lead.customer == customer then
      return lead
    end
  end
  error("no lead from " .. customer)
end

-- Leads from `customers` (oldest first); the player's Me-Realm smiths, so a new SMITH line makes
-- a lead. The window is subscribed to lead changes as Bootstrap does it.
local function load(customers, edit)
  local ns = UiFixture.load({
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = { professions = { [164] = { name = "Blacksmithing" } } }
      for id, customer in ipairs(customers) do
        accountDb.leads[id] = UiFixture.lead(id, customer)
      end
      if edit then
        edit(accountDb)
      end
    end,
  })
  ns.Leads.On("change", ns.LeadsWindow.Refresh)
  return ns
end

local function testShowsNewestFirst()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  Assert.equal(shown(ns), byCustomer(ns, "Bob-Draenor"))
  Assert.equal(pane():IsShown(), true)
  Assert.equal(pane().name:GetText(), "Bob-Draenor")
end

local function testHoverPins()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann = byCustomer(ns, "Ann-Draenor")
  local row = rowOf(ann)
  hover(row)
  Assert.equal(shown(ns), ann)
  Assert.equal(pane().name:GetText(), "Ann-Draenor")
  -- The cursor leaving the rows changes nothing.
  Widgets.fire(row, "OnLeave")
  Assert.equal(shown(ns), ann)
  -- Nor does a new lead.
  local _, isNew = ns.Leads.OnMatch(SMITH, "Cid-Draenor", "LF blacksmith", "trade")
  Assert.equal(isNew, true)
  Assert.equal(ns.Leads.Latest().customer, "Cid-Draenor")
  Assert.equal(shown(ns), ann)
end

-- Never follow the lead that scrolls under a still cursor.
local function testScrollKeepsPin()
  local customers = {}
  for i = 1, 12 do
    customers[i] = "Customer" .. i .. "-Draenor"
  end
  local ns = load(customers)
  ns.LeadsWindow.Toggle()
  local pinned = byCustomer(ns, "Customer10-Draenor")
  local row = rowOf(pinned)
  hover(row)
  Assert.equal(shown(ns), pinned)
  window().scripts.OnMouseWheel(window(), -1)
  Assert.equal(row.lead.customer, "Customer9-Draenor", "another lead sits under the cursor")
  Assert.equal(shown(ns), pinned)
end

local function testPinnedRemovedFallsBack()
  local ns = load({ "Ann-Draenor", "Bob-Draenor", "Cid-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann = byCustomer(ns, "Ann-Draenor")
  hover(rowOf(ann))
  Assert.equal(shown(ns), ann)
  ns.Leads.Dismiss(ann.id)
  Assert.equal(shown(ns), byCustomer(ns, "Cid-Draenor"))
end

local function testDuplicateUpdateWhileUnpinned()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann = byCustomer(ns, "Ann-Draenor")
  Assert.equal(shown(ns), byCustomer(ns, "Bob-Draenor"))
  -- Ann asks again: her lead moves to the top and, unpinned, the pane follows the newest.
  local lead, isNew = ns.Leads.OnMatch(SMITH, "Ann-Draenor", "LF blacksmith again", "trade")
  Assert.same({ lead, isNew }, { ann, false })
  Assert.equal(shown(ns), ann)
  Assert.equal(pane().message:GetText(), "LF blacksmith again")
end

local function testEmptyList()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  for _, lead in ipairs(ns.Leads.List()) do
    ns.Leads.Dismiss(lead.id)
  end
  Assert.equal(shown(ns), nil)
  Assert.equal(pane():IsShown(), false, "pane texts hidden")
  local inset = table.concat(Widgets.texts(window().Inset, Wow.frames), " / ")
  Assert.truthy(string.find(inset, "No leads", 1, true), "the list's empty hint shows: " .. inset)
end

local function testReopenUnpins()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann, bob = byCustomer(ns, "Ann-Draenor"), byCustomer(ns, "Bob-Draenor")
  hover(rowOf(ann))
  Assert.equal(shown(ns), ann)
  ns.LeadsWindow.Toggle()
  ns.LeadsWindow.Toggle()
  Assert.equal(shown(ns), bob, "reopened: no pin")
  -- The same after the gear's round trip through the settings.
  hover(rowOf(ann))
  Assert.equal(shown(ns), ann)
  Widgets.click(window().gear)
  Widgets.click(window().gear)
  Assert.equal(shown(ns), bob, "back from the settings: no pin")
end

local function testSettingsHidesPane()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann, bob = byCustomer(ns, "Ann-Draenor"), byCustomer(ns, "Bob-Draenor")
  Widgets.click(window().gear)
  Assert.equal(pane():IsShown(), false)
  Assert.equal(shown(ns), nil)
  -- A pin made while the settings show is gone when the list comes back.
  ns.LeadDetails.Pin(pane(), ann.id)
  ns.LeadsWindow.Refresh()
  Assert.equal(pane():IsShown(), false)
  Widgets.click(window().gear)
  Assert.equal(pane():IsShown(), true)
  Assert.equal(shown(ns), bob)
  -- /ca config hides it too.
  ns.LeadsWindow.ToggleSettings()
  Assert.equal(pane():IsShown(), false)
end

-- Leads-details spec §4 items 1-5, the picked crafter first, then the rest by the name the
-- greeting uses.
local function testDetailsContent()
  local ns = load({}, function(accountDb)
    local lead = UiFixture.lead(1, "Buyer-Realm")
    lead.guid = "Player-1-0001"
    lead.message = "LF " .. LINK_TEXT .. " crafter"
    lead.why = "Bolt of Silk"
    lead.profName = "Tailoring"
    lead.crafters = {
      { key = "Me-Realm", rank = 3 },
      { key = "Bob-Realm" },
      { key = "Alt-Other", rank = 2, byConc = true },
    }
    lead.rank = 3
    lead.time = UiFixture.T0 - 30
    accountDb.leads[1] = lead
  end)
  Wow.stub("GetPlayerInfoByGUID", function()
    return "Mage", "MAGE"
  end)
  Wow.stub("RAID_CLASS_COLORS", { MAGE = { r = 0.25, g = 0.78, b = 0.92 } })
  ns.LeadsWindow.Toggle()
  local details = pane()
  Assert.equal(details.name:GetText(), "Buyer-Realm")
  Assert.same(details.name.textColor, { 0.25, 0.78, 0.92, 1 }, "class-coloured, as the row paints it")
  Assert.equal(details.age:GetText(), "30s")
  Assert.equal(details.message:GetText(), "LF " .. LINK_TEXT .. " crafter")
  Assert.equal(details.message.wordWrap, true)
  Assert.equal(details.why:GetText(), "Matched: Bolt of Silk")
  Assert.equal(details.profession:GetText(), "Tailoring")
  Assert.equal(details.crafters:GetText(), "Crafters:\nMe · R3\nAlt-Other · R2 (conc)\nBob")
  -- The message's link hovers.
  local tip = rawget(_G, "GameTooltip")
  Assert.equal(details.hyperlinksEnabled, true)
  details.scripts.OnHyperlinkEnter(details, LINK, LINK_TEXT)
  Assert.same({ tip.hyperlinks, tip.owner, tip.shown }, { { LINK }, details, true })
end

local function testDetailsFallbacks()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.leads[2].rank = 1
    accountDb.leads[1].crafter = nil
  end)
  ns.LeadsWindow.Toggle()
  -- A restored lead has no crafters list: the picked crafter alone.
  Assert.equal(pane().crafters:GetText(), "Crafters:\nMe · R1")
  hover(rowOf(byCustomer(ns, "Ann-Draenor")))
  Assert.equal(pane().crafters:GetText(), "Crafters: none known")
end

-- A lead with no why or profession shows neither line, even after a lead that had both.
local function testMissingFieldsHideLines()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.leads[2].why = nil
    accountDb.leads[2].profName = nil
  end)
  ns.LeadsWindow.Toggle()
  Assert.equal(shown(ns), byCustomer(ns, "Bob-Draenor"))
  Assert.same({ pane().why:IsShown(), pane().profession:IsShown() }, { false, false })
  local annRow = rowOf(byCustomer(ns, "Ann-Draenor"))
  hover(annRow)
  Assert.same({ pane().why:IsShown(), pane().profession:IsShown() }, { true, true })
  annRow.mouseOver = false
  hover(rowOf(byCustomer(ns, "Bob-Draenor")))
  Assert.same({ pane().why:IsShown(), pane().profession:IsShown() }, { false, false })
end

-- Saved data from a newer schema keeps crafters as it is: a bad list or entry falls back to the
-- lead's picked crafter.
local function testBadCrafters()
  for _, bad in ipairs({ "bad", { 5, { key = "Me-Realm", rank = "x" }, { key = 7 } } }) do
    local ns = load({}, function(accountDb)
      local lead = UiFixture.lead(1, "Buyer-Realm")
      lead.rank = 2
      lead.crafters = bad
      accountDb.leads[1] = lead
    end)
    ns.LeadsWindow.Toggle()
    Assert.equal(pane().crafters:GetText(), "Crafters:\nMe · R2")
    Wow.reset()
  end
end

-- A drag that starts on the pane moves the window and saves its position like a drag on the frame.
local function testPaneDragMovesWindow()
  local ns = load({ "Ann-Draenor" })
  ns.LeadsWindow.Toggle()
  local frame, details = window(), pane()
  Assert.equal(details.dragButtons[1], "LeftButton")
  details.scripts.OnDragStart(details)
  Assert.equal(frame.moving, true)
  frame:ClearAllPoints()
  frame:SetPoint("LEFT", rawget(_G, "UIParent"), "LEFT", 30, 40)
  details.scripts.OnDragStop(details)
  Assert.equal(frame.moving, false)
  local saved = rawget(_G, "CraftAlertDB").ui.window
  Assert.same({ saved.point, saved.x, saved.y }, { "LEFT", 30, 40 })
end

-- The link under the cursor belonged to the old lead: a lead change clears it and its tooltip.
local function testLeadChangeClearsLinkHover()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local details, tip = pane(), rawget(_G, "GameTooltip")
  details.scripts.OnHyperlinkEnter(details, LINK, LINK_TEXT)
  Assert.same({ tip.owner, tip.shown, details.hoveredLink }, { details, true, LINK })
  hover(rowOf(byCustomer(ns, "Ann-Draenor")))
  Assert.same({ tip.shown, details.hoveredLink }, { false, nil })
end

local function testAgeRefreshes()
  local ns = load({ "Ann-Draenor" })
  ns.LeadsWindow.Toggle()
  Assert.equal(pane().age:GetText(), "0s")
  Wow.clock.time = UiFixture.T0 + 120
  ns.LeadsWindow.Refresh()
  Assert.equal(pane().age:GetText(), "2m")
end

-- Spec §5a: a row pins its lead after the cursor rests 0.2 s on it, not at once.
local function testDwellPins()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann = byCustomer(ns, "Ann-Draenor")
  local row = rowOf(ann)
  row.mouseOver = true
  Widgets.fire(row, "OnEnter")
  Assert.equal(shown(ns), byCustomer(ns, "Bob-Draenor"))
  Assert.equal(Wow.pendingTimers(0.2), 1)
  runDwell()
  Assert.equal(shown(ns), ann)
end

-- The cursor crossing a row on its way elsewhere pins nothing.
local function testDiagonalKeepsLead()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann, bob = byCustomer(ns, "Ann-Draenor"), byCustomer(ns, "Bob-Draenor")
  local annRow, bobRow = rowOf(ann), rowOf(bob)
  hover(annRow)
  Assert.equal(shown(ns), ann)
  annRow.mouseOver = false
  bobRow.mouseOver = true
  Widgets.fire(bobRow, "OnEnter")
  bobRow.mouseOver = false
  runDwell()
  Assert.equal(shown(ns), ann)
end

local function testDwellScrollCancels()
  local customers = {}
  for i = 1, 12 do
    customers[i] = "Customer" .. i .. "-Draenor"
  end
  local ns = load(customers)
  ns.LeadsWindow.Toggle()
  local row = rowOf(byCustomer(ns, "Customer10-Draenor"))
  row.mouseOver = true
  Widgets.fire(row, "OnEnter")
  window().scripts.OnMouseWheel(window(), -1)
  runDwell()
  Assert.equal(shown(ns), byCustomer(ns, "Customer12-Draenor"))
end

local function testDwellAfterClose()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local row = rowOf(byCustomer(ns, "Ann-Draenor"))
  row.mouseOver = true
  Widgets.fire(row, "OnEnter")
  ns.LeadsWindow.Toggle()
  runDwell()
  ns.LeadsWindow.Toggle()
  Assert.equal(shown(ns), byCustomer(ns, "Bob-Draenor"))
end

-- The pane and the rows redraw together, so their ages agree.
local function testRowEnterRefreshesRows()
  local ns = load({ "Ann-Draenor", "Bob-Draenor" })
  ns.LeadsWindow.Toggle()
  local row = rowOf(byCustomer(ns, "Ann-Draenor"))
  Wow.clock.time = Wow.clock.time + 10
  hover(row)
  Assert.equal(row.age:GetText(), "10s")
  Assert.equal(pane().age:GetText(), "10s")
end

return function()
  testShowsNewestFirst()
  testHoverPins()
  testScrollKeepsPin()
  testPinnedRemovedFallsBack()
  testDuplicateUpdateWhileUnpinned()
  testEmptyList()
  testReopenUnpins()
  testSettingsHidesPane()
  testDetailsContent()
  testDetailsFallbacks()
  testMissingFieldsHideLines()
  testBadCrafters()
  testPaneDragMovesWindow()
  testLeadChangeClearsLinkHover()
  testAgeRefreshes()
  testDwellPins()
  testDiagonalKeepsLead()
  testDwellScrollCancels()
  testDwellAfterClose()
  testRowEnterRefreshesRows()
  Wow.reset()
end
