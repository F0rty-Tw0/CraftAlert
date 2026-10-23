local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec §4: in list mode the leads window shows its rows in a left column and the details of one
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
  Widgets.fire(row, "OnEnter")
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
  row.mouseOver = true
  Widgets.fire(row, "OnEnter")
  Assert.equal(shown(ns), pinned)
  window().scripts.OnMouseWheel(window(), -1)
  Assert.equal(row.lead.customer, "Customer9-Draenor", "another lead sits under the cursor")
  Assert.equal(shown(ns), pinned)
end

local function testPinnedRemovedFallsBack()
  local ns = load({ "Ann-Draenor", "Bob-Draenor", "Cid-Draenor" })
  ns.LeadsWindow.Toggle()
  local ann = byCustomer(ns, "Ann-Draenor")
  Widgets.fire(rowOf(ann), "OnEnter")
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
  Widgets.fire(rowOf(ann), "OnEnter")
  Assert.equal(shown(ns), ann)
  ns.LeadsWindow.Toggle()
  ns.LeadsWindow.Toggle()
  Assert.equal(shown(ns), bob, "reopened: no pin")
  -- The same after the gear's round trip through the settings.
  Widgets.fire(rowOf(ann), "OnEnter")
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

-- Spec §4 items 1-5, the picked crafter first, then the rest by the name the greeting uses.
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
  Widgets.fire(rowOf(byCustomer(ns, "Ann-Draenor")), "OnEnter")
  Assert.equal(pane().crafters:GetText(), "Crafters: none known")
end

local function testAgeRefreshes()
  local ns = load({ "Ann-Draenor" })
  ns.LeadsWindow.Toggle()
  Assert.equal(pane().age:GetText(), "0s")
  Wow.clock.time = UiFixture.T0 + 120
  ns.LeadsWindow.Refresh()
  Assert.equal(pane().age:GetText(), "2m")
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
  testAgeRefreshes()
  Wow.reset()
end
