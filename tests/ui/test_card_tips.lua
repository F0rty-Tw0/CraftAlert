local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Lead-cards spec §2, §2.1: the tooltip zones over a card's name, what line, Matched row and Crafters
-- row, the Greet button's tooltip, and the latest-chat-line tooltip over the bare card (no OnUpdate).
local LINK = "item:4305"
local LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
local MAGE = { r = 0.25, g = 0.78, b = 0.92 }
local WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GREEN = { 0.1, 1, 0.1 }
local GREY = { 0.5, 0.5, 0.5 }

local function tip()
  return rawget(_G, "GameTooltip")
end

-- The shown card frames of the window, top to bottom.
local function cards()
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

-- The window over `leads` (records, oldest first, given ids 1..n); Me-Realm is a mage; every
-- customer is a warrior. → ns, the sends (UiFixture's calls).
local function load(leads)
  local ns, _, calls = UiFixture.load({
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = { class = "MAGE", professions = { [164] = { name = "Blacksmithing" } } }
      for id, lead in ipairs(leads) do
        lead.id = id
        accountDb.leads[id] = lead
      end
    end,
  })
  ns.Leads.On("change", ns.LeadsWindow.Refresh)
  Wow.stub("RAID_CLASS_COLORS", { MAGE = MAGE, WARRIOR = WARRIOR })
  Wow.stub("LOCALIZED_CLASS_NAMES_MALE", { MAGE = "Mage", WARRIOR = "Warrior" })
  Wow.stub("GetPlayerInfoByGUID", function()
    return "Warrior", "WARRIOR"
  end)
  return ns, calls
end

local function itemLead(id)
  local lead = UiFixture.lead(id or 1, "Buyer-Realm")
  lead.kind, lead.itemID, lead.itemLink = "item", 4305, LINK_TEXT
  lead.why, lead.profName, lead.message = "lf + bolt", "Tailoring", "LF bolt of silk"
  lead.guid = "Player-1-0001"
  lead.crafters = {
    { key = "Me-Realm", rank = 3, byConc = true },
    { key = "Bob-Realm" },
    { key = "Alt-Other", rank = 2 },
  }
  lead.time = UiFixture.T0 - 30
  return lead
end

-- A recipe lead: no link in its what line.
local function recipeLead(id)
  local lead = itemLead(id)
  lead.itemLink, lead.recipeName = nil, "Bolt of Silk"
  return lead
end

local function strip(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The cursor comes onto `frame` (a card or a child of one) of `card`.
local function enter(card, frame)
  card.mouseOver = true
  Widgets.fire(frame or card, "OnEnter")
end

-- The cursor leaves `frame`; stillOver: it is still somewhere on the card.
local function leave(card, frame, stillOver)
  card.mouseOver = stillOver == true
  Widgets.fire(frame or card, "OnLeave")
end

local function open(leads)
  local ns, calls = load(leads)
  ns.LeadsWindow.Toggle()
  return ns, calls, cards()[1]
end

local function testCustomerZone()
  local lead = itemLead()
  lead.greeted, lead.replied = true, true
  local _, _, card = open({ lead })
  local zone = card.zones.name
  enter(card, zone)
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { zone, "ANCHOR_RIGHT", true })
  Assert.same(tip().lines, { "Buyer-Realm", "Warrior", "Greeted", "Replied" })
  Assert.same(tip().colors, { { WARRIOR.r, WARRIOR.g, WARRIOR.b }, WHITE, WHITE, WHITE })
  leave(card, zone, false)
  -- A customer of unknown class and not greeted: the name in gold, no more lines.
  Wow.reset()
  local plain = itemLead()
  plain.guid = nil
  local _, _, other = open({ plain })
  enter(other, other.zones.name)
  Assert.same(tip().lines, { "Buyer-Realm" })
  Assert.same(tip().colors, { GOLD })
end

local function testWhatZone()
  local _, _, card = open({ UiFixture.lead(1, "Buyer-Realm") })
  enter(card, card.zones.what)
  Assert.same(tip().lines, { "Blacksmithing", "Profession request" })
  Assert.same(tip().colors, { GOLD, WHITE })
  Assert.equal(tip().owner, card.zones.what)
  Wow.reset()
  local _, _, recipeCard = open({ recipeLead() })
  enter(recipeCard, recipeCard.zones.what)
  Assert.same(tip().lines, { "Bolt of Silk", "Item request" })
end

-- A link in the what line hovers through LinkHover, so no zone covers it; none covers the Request.
local function testNoZoneOverLinks()
  local older = UiFixture.lead(1, "Ann-Realm")
  older.time = UiFixture.T0 - 100
  local ns, _, card = open({ older, itemLead(2) })
  Assert.equal(card.lead.itemLink, LINK_TEXT)
  Assert.equal(card.zones.what:IsShown(), false)
  Assert.same({ card.zones.name:IsShown(), card.zones.matched:IsShown(), card.zones.crafters:IsShown() }, { true, true, true })
  for name, zone in pairs(card.zones) do
    Assert.same({ zone.frameType, zone.parent, zone.mouseEnabled, #zone.regions }, { "Button", card, true, 0 }, name)
    for _, point in ipairs(zone.points) do
      Assert.truthy(point[2] ~= card.values.request and point[2] ~= card.labels.request, name .. " is anchored over the Request")
    end
  end
  Assert.equal(card.zones.what.points[1][2], card.what)
  -- The same card then shows a lead without a link: the zone comes back.
  ns.Leads.Dismiss(card.lead.id)
  Assert.equal(card.lead.customer, "Ann-Realm")
  Assert.equal(card.zones.what:IsShown(), true)
end

local function testMatchedZone()
  local _, _, card = open({ itemLead() })
  enter(card, card.zones.matched)
  Assert.same(tip().lines, { "Matched", "lf", "bolt", "Tailoring" })
  Assert.same(tip().colors, { GOLD, WHITE, WHITE, GOLD })
  Assert.equal(tip().owner, card.zones.matched)
  -- Profession only.
  card.lead.why = nil
  enter(card, card.zones.matched)
  Assert.same(tip().lines, { "Matched", "Tailoring" })
end

local function testMatchedZoneHidesWithRow()
  local bare = UiFixture.lead(1, "Bob-Realm")
  bare.why, bare.profName = nil, nil
  local ns, _, card = open({ UiFixture.lead(2, "Ann-Realm"), bare })
  Assert.equal(card.lead.customer, "Bob-Realm")
  Assert.equal(card.zones.matched:IsShown(), false)
  ns.Leads.Dismiss(card.lead.id)
  Assert.equal(card.zones.matched:IsShown(), true)
end

local function testCraftersZone()
  local lead = itemLead()
  lead.cannotOrder = true
  local _, _, card = open({ lead })
  local zone = card.zones.crafters
  enter(card, zone)
  Assert.equal(tip().owner, zone)
  Assert.same(tip().lines, { "Crafters", "Me", "Alt-Other", "Bob", "Picked for this lead: Me", "Can't send an order (realm)" })
  Assert.same(tip().colors[1], GOLD)
  Assert.same(tip().colors[2], { MAGE.r, MAGE.g, MAGE.b })
  -- Alt-Other has no saved class and Bob no rank: white names, an empty right half.
  Assert.same(tip().colors[3], WHITE)
  Assert.same(tip().rights, {
    [2] = { "R3 (conc)", GREY[1], GREY[2], GREY[3] },
    [3] = { "R2", GREY[1], GREY[2], GREY[3] },
    [4] = { "", GREY[1], GREY[2], GREY[3] },
  })
  -- A customer who can be ordered from: no realm line.
  card.lead.cannotOrder = nil
  enter(card, zone)
  Assert.equal(tip().lines[#tip().lines], "Picked for this lead: Me")
  -- No crafter was picked: no "Picked" line.
  card.lead.crafter = nil
  enter(card, zone)
  Assert.same(tip().lines, { "Crafters", "Alt-Other", "Bob", "Me" })
end

local function testGreetTip()
  local _, _, card = open({ itemLead() })
  local greet = card.buttons.greet
  enter(card, greet)
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { greet, "ANCHOR_RIGHT", true })
  Assert.same(tip().lines, { "Greet", "Click: greet", "Shift-click: edit first", "Ctrl-click: empty whisper" })
  Assert.same(tip().colors, { GOLD, GREEN, GREEN, GREEN })
  leave(card, greet, true)
  Assert.equal(tip().shown, false)
  -- The other buttons have no tooltip.
  enter(card, card.buttons.whisper)
  Assert.equal(tip().shown, false)
end

local function testLeaveHidesOwnedOnly()
  local _, _, card = open({ itemLead() })
  local zone = card.zones.name
  enter(card, zone)
  tip().owner = card.buttons.whisper
  leave(card, zone, true)
  Assert.equal(tip().shown, true)
  tip().owner = zone
  leave(card, zone, true)
  Assert.equal(tip().shown, false)
end

local function testZoneClicks()
  local ns, calls, card = open({ UiFixture.lead(1, "Ann-Realm"), UiFixture.lead(2, "Buyer-Realm") })
  local zone = card.zones.name
  Assert.same(zone.clickButtons, { "LeftButtonUp", "RightButtonUp" })
  Assert.equal(zone.dragButtons, nil)
  Wow.clock.gettime = Wow.clock.gettime + 1
  Widgets.click(zone, "LeftButton")
  local chats = UiFixture.callsTo(calls, "chat")
  Assert.same({ #chats, chats[1][5], card.lead.greeted }, { 1, "Buyer-Realm", true })
  Widgets.click(card.zones.crafters, "RightButton")
  Assert.same({ #ns.Leads.List(), ns.Leads.List()[1].customer }, { 1, "Ann-Realm" })
end

local function testTipFollowsLead()
  local old = UiFixture.lead(1, "Ann-Realm")
  old.crafter = "Bob-Realm"
  local ns, _, card = open({ old, UiFixture.lead(2, "Buyer-Realm") })
  enter(card, card.zones.crafters)
  Assert.same(tip().lines, { "Crafters", "Me", "Picked for this lead: Me" })
  ns.Leads.Dismiss(card.lead.id)
  Assert.equal(card.lead.customer, "Ann-Realm")
  enter(card, card.zones.crafters)
  Assert.same(tip().lines, { "Crafters", "Bob", "Picked for this lead: Bob" })
end

local function testLeadChangeHidesZoneTip()
  local leads = {}
  for id = 1, 4 do
    leads[id] = UiFixture.lead(id)
  end
  local ns, _, card = open(leads)
  -- A zone, a button and the card itself (the chat tooltip) each own the tip, then the card shows another lead.
  for _, owner in ipairs({ card.zones.crafters, card.buttons.greet, card }) do
    enter(card, owner)
    Assert.equal(tip():IsOwned(owner), true)
    ns.Leads.Dismiss(card.lead.id)
    Assert.equal(tip().shown, false)
  end
  -- The last lead dismissed: the card hides, and the tip it owns with it.
  enter(card, card.zones.name)
  Assert.equal(tip():IsOwned(card.zones.name), true)
  ns.Leads.Dismiss(card.lead.id)
  Assert.equal(card:IsShown(), false)
  Assert.equal(tip().shown, false)
end

local function testCloseHidesZoneTip()
  local ns, _, card = open({ itemLead() })
  enter(card, card.zones.matched)
  Assert.equal(tip().shown, true)
  ns.LeadsWindow.Toggle()
  Assert.equal(tip().shown, false)
  ns.LeadsWindow.Toggle()
  enter(card, card.buttons.greet)
  Assert.equal(tip().shown, true)
  _G["UIParent"]:Hide()
  Assert.equal(tip().shown, false)
  _G["UIParent"]:Show()
  enter(card, card.zones.name)
  Widgets.click(_G["CraftAlertLeadsWindow"].gear)
  Assert.equal(tip().shown, false)
end

local function testZonesKeepButtons()
  local _, _, card = open({ itemLead() })
  local function look()
    local b = card.buttons
    return { b.greet:IsShown(), b.whisper:IsShown(), b.dismiss:IsShown(), card.highlightLocked == true }
  end
  enter(card)
  -- The cursor moves from the card onto a zone: the card is left, still under the cursor.
  leave(card, card, true)
  enter(card, card.zones.crafters)
  Assert.same(look(), { true, true, true, true })
  leave(card, card.zones.crafters, true)
  Assert.same(look(), { true, true, true, true })
  enter(card, card.zones.name)
  leave(card, card.zones.name, false)
  Assert.same(look(), { false, false, false, false })
  -- A zone entered on its own shows them too.
  enter(card, card.zones.matched)
  Assert.same(look(), { true, true, true, true })
end

local function testChatTip()
  local _, _, card = open({ itemLead() })
  enter(card)
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { card, "ANCHOR_RIGHT", true })
  Assert.equal(#tip().lines, 4)
  Assert.same({ tip().lines[1], tip().colors[1] }, { "Chat with Buyer-Realm", { WARRIOR.r, WARRIOR.g, WARRIOR.b } })
  local line = strip(tip().lines[2])
  Assert.truthy(string.find(line, "^%[%d%d:%d%d%] %[Trade%] %[.*Buyer%-Realm.*%]: LF bolt of silk$"), line)
  Assert.truthy(string.find(tip().lines[2], "|cff", 1, true), "the name is coloured")
  Assert.equal(string.sub(line, 2, 6), os.date("%H:%M", UiFixture.T0 - 30))
  Assert.same(tip().colors[2], WHITE)
  Assert.same({ tip().lines[3], tip().lines[4] }, { "Click: greet", "Right-click: dismiss" })
  Assert.same({ tip().colors[3], tip().colors[4] }, { GREEN, GREEN })
end

local function testChatTipKeepsLinks()
  local lead = itemLead()
  lead.message = "LF " .. LINK_TEXT .. " crafter"
  local _, _, card = open({ lead })
  enter(card)
  Assert.truthy(string.find(tip().lines[2], LINK_TEXT, 1, true), tip().lines[2])
end

-- A lead without a message has nothing to show.
local function testChatTipNoMessage()
  local lead = itemLead()
  lead.message = nil
  local _, _, card = open({ lead })
  enter(card)
  Assert.equal(tip().shown, false)
end

local function testChatTipHidesOnLeave()
  local _, _, card = open({ itemLead() })
  enter(card)
  Assert.equal(tip().shown, true)
  leave(card, card, false)
  Assert.equal(tip().shown, false)
  -- Not the card's tooltip: left alone.
  enter(card)
  tip().owner = card.zones.name
  leave(card, card, false)
  Assert.equal(tip().shown, true)
end

-- The cursor goes from the bare card onto a zone (the card is left, the zone shows its own tip) and
-- back (the card is entered again).
local function testZoneThenBackToCard()
  local _, _, card = open({ itemLead() })
  local zone = card.zones.name
  enter(card)
  Assert.equal(tip().lines[1], "Chat with Buyer-Realm")
  leave(card, card, true)
  Assert.equal(tip().shown, false)
  enter(card, zone)
  Assert.same({ tip().owner, tip().lines[1] }, { zone, "Buyer-Realm" })
  leave(card, zone, true)
  Assert.equal(tip().shown, false)
  enter(card)
  Assert.same({ tip().owner, tip().shown, tip().lines[1] }, { card, true, "Chat with Buyer-Realm" })
end

local function testChatTipYieldsToLink()
  local lead = itemLead()
  lead.message = "LF " .. LINK_TEXT .. " crafter"
  local _, _, card = open({ lead })
  enter(card)
  Widgets.fire(card, "OnHyperlinkEnter", LINK, LINK_TEXT)
  Assert.same({ tip().hyperlinks, tip().owner, tip().anchor, tip().shown }, { { LINK }, card, "ANCHOR_CURSOR", true })
  -- Off the link, still over the card: the chat tooltip is back.
  Widgets.fire(card, "OnHyperlinkLeave", LINK, LINK_TEXT)
  Assert.same({ tip().owner, tip().anchor, tip().shown, tip().lines[1] }, { card, "ANCHOR_RIGHT", true, "Chat with Buyer-Realm" })
  -- Off the link and off the card: nothing shows.
  Widgets.fire(card, "OnHyperlinkEnter", LINK, LINK_TEXT)
  card.mouseOver = false
  Widgets.fire(card, "OnHyperlinkLeave", LINK, LINK_TEXT)
  Assert.equal(tip().shown, false)
end

-- The customer tooltip reads the class once; without a colour table the chat tooltip reads none.
local function testClassReads()
  local _, _, card = open({ itemLead() })
  local reads = 0
  Wow.stub("GetPlayerInfoByGUID", function()
    reads = reads + 1
    return "Warrior", "WARRIOR"
  end)
  enter(card, card.zones.name)
  Assert.same({ reads, tip().lines[2] }, { 1, "Warrior" })
  leave(card, card.zones.name, true)
  Wow.stub("RAID_CLASS_COLORS", nil)
  reads = 0
  enter(card)
  Assert.same({ reads, tip().owner, tip().colors[1] }, { 0, card, GOLD })
end

-- A repeat from the same customer edits the lead in place (Model/Leads.lua:368) and the window repaints
-- the card with that lead: the shown tooltip gets the newest line, with no new OnEnter.
local function testChatTipLatestLine()
  local ns, _, card = open({ itemLead() })
  enter(card)
  tip().lines[#tip().lines + 1] = "marker"
  -- Nothing changed: no rebuild, so no flicker.
  ns.LeadsWindow.Refresh()
  Assert.equal(tip().lines[#tip().lines], "marker")
  local lead = card.lead
  lead.message, lead.channel, lead.time = "LF bolt of silk, 20", "guild", UiFixture.T0 + 3600
  ns.LeadsWindow.Refresh()
  Assert.equal(card.lead, lead)
  local line = strip(tip().lines[2])
  Assert.truthy(string.find(line, "^%[%d%d:%d%d%] %[Guild%] %[.*Buyer%-Realm.*%]: LF bolt of silk, 20$"), line)
  Assert.equal(string.sub(line, 2, 6), os.date("%H:%M", UiFixture.T0 + 3600))
  Assert.equal(#tip().lines, 4)
end

-- A repeat repaints only a chat tooltip the card is showing: a zone's tip and a link's tip stay.
local function testRepeatLeavesOtherTips()
  local lead = itemLead()
  lead.message = "LF " .. LINK_TEXT .. " crafter"
  local ns, _, card = open({ lead })
  enter(card, card.zones.name)
  lead.message = "LF bolt of silk, 30"
  ns.LeadsWindow.Refresh()
  Assert.same({ tip().owner, tip().lines[1] }, { card.zones.name, "Buyer-Realm" })
  leave(card, card.zones.name, true)
  enter(card)
  Widgets.fire(card, "OnHyperlinkEnter", LINK, LINK_TEXT)
  lead.message = "LF bolt of silk, 40"
  ns.LeadsWindow.Refresh()
  Assert.same({ tip().hyperlinks[#tip().hyperlinks], tip().anchor }, { LINK, "ANCHOR_CURSOR" })
end

local function testChatTipChannelNames()
  local lead = itemLead()
  local _, _, card = open({ lead })
  local expected = { trade = "Trade", services = "Services", general = "General", lfg = "LFG", guild = "Guild", communities = "Community" }
  for key, name in pairs(expected) do
    lead.channel = key
    enter(card)
    Assert.truthy(string.find(strip(tip().lines[2]), "] [" .. name .. "] [", 1, true), name)
  end
  lead.channel = "mystery"
  enter(card)
  Assert.truthy(string.find(strip(tip().lines[2]), "] [mystery] [", 1, true), tip().lines[2])
  lead.channel = nil
  enter(card)
  Assert.truthy(string.find(strip(tip().lines[2]), "] [nil] [", 1, true), tip().lines[2])
end

local function testChatTipHidesOnLeadChange()
  local ns, _, card = open({ itemLead(1), itemLead(2) })
  enter(card)
  Assert.equal(tip():IsOwned(card), true)
  ns.Leads.Dismiss(card.lead.id)
  Assert.equal(tip().shown, false)
  enter(card)
  Assert.equal(tip().shown, true)
  card:Hide()
  Assert.equal(tip().shown, false)
end

-- Lead-cards spec 2.1 / runtime rule 1: no OnUpdate on a card, a zone or a button, ever.
local function testNoOnUpdate()
  local _, _, card = open({ itemLead(1), itemLead(2) })
  local function check()
    for _, frame in ipairs(Wow.frames) do
      Assert.equal(frame.scripts.OnUpdate, nil, "OnUpdate on a frame")
    end
  end
  check()
  enter(card)
  check()
  enter(card, card.zones.crafters)
  check()
  leave(card, card.zones.crafters, true)
  enter(card, card.buttons.greet)
  check()
  leave(card, card.buttons.greet, false)
  leave(card, card, false)
  check()
  card:Hide()
  check()
end

return function()
  testCustomerZone()
  testWhatZone()
  testNoZoneOverLinks()
  testMatchedZone()
  testMatchedZoneHidesWithRow()
  testCraftersZone()
  testGreetTip()
  testLeaveHidesOwnedOnly()
  testZoneClicks()
  testTipFollowsLead()
  testLeadChangeHidesZoneTip()
  testCloseHidesZoneTip()
  testZonesKeepButtons()
  testChatTip()
  testChatTipKeepsLinks()
  testChatTipNoMessage()
  testChatTipHidesOnLeave()
  testZoneThenBackToCard()
  testChatTipYieldsToLink()
  testClassReads()
  testChatTipLatestLine()
  testRepeatLeavesOtherTips()
  testChatTipChannelNames()
  testChatTipHidesOnLeadChange()
  testNoOnUpdate()
  Wow.reset()
end
