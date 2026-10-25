local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec A.4: the split view's details pane. A 56 px header (icon, customer, what, status), the
-- Request / Matched / Crafters / Channel sections in a clipping body, tooltip zones over the
-- header's name and what line and the Matched and Crafters sections, and the Greet / Whisper /
-- Dismiss action bar, which acts on the shown lead with the look rule (details.shownAt).
local LINK = "item:4305"
local LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
local ITEM_ICON = 132891
local MAGE = { r = 0.25, g = 0.78, b = 0.92 }
local WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
-- MAGE as a colour code, format("|cff%02x%02x%02x", r * 255, g * 255, b * 255).
local MAGE_CODE = "|cff3fc6ea"
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GREEN = { 0.1, 1, 0.1 }
local GREY = { 0.5, 0.5, 0.5 }
-- The spec's numbers: 16 px padding, 12 px from the header to the first label and between
-- sections, labels 14 high, a 56 px header 2 below the pane top, a 44 px action bar.
local PAD, GAP = 16, 12

local function tip()
  return rawget(_G, "CraftAlertTooltip")
end

local function strip(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function has(list, value)
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

-- The fixture over `leads` (records, oldest first, given ids 1..n); Me-Realm smiths and is a
-- mage; every customer is a warrior. → ns, the sends (UiFixture's calls).
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
  Wow.stub("RAID_CLASS_COLORS", { MAGE = MAGE, WARRIOR = WARRIOR })
  Wow.stub("LOCALIZED_CLASS_NAMES_MALE", { MAGE = "Mage", WARRIOR = "Warrior" })
  Wow.stub("GetPlayerInfoByGUID", function()
    return "Warrior", "WARRIOR"
  end)
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      if itemID == 4305 then
        return 4305, "Tradeskill", "Cloth", "", ITEM_ICON
      end
    end,
  })
  return ns, calls
end

local function leadOf(ns, id)
  for _, lead in ipairs(ns.Leads.List()) do
    if lead.id == id then
      return lead
    end
  end
  error("no lead " .. tostring(id))
end

-- A details pane in a bare host, laid out at the default size (840 wide: 840 - 4 - 6 - 260 - 1
-- = 569; any width over 348 gives full buttons), showing lead `id` (default 1).
-- → ns, the details, the sends, the lead.
local function open(leads, id)
  local ns, calls = load(leads)
  local d = ns.LeadDetails.New(_G["CreateFrame"]("Frame"))
  ns.LeadDetails.Layout(d, 449)
  local lead = leadOf(ns, id or 1)
  ns.LeadDetails.Show(d, lead)
  return ns, d, calls, lead
end

local function itemLead()
  local lead = UiFixture.lead(1, "Buyer-Realm")
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
local function recipeLead()
  local lead = itemLead()
  lead.itemLink, lead.recipeName = nil, "Bolt of Silk"
  return lead
end

local function gold(text)
  return "|cffffd100" .. text .. "|r"
end

local function testHeader()
  local ns, d, _, lead = open({ itemLead() })
  local header = d.header
  Assert.equal(header:GetHeight(), 56)
  Assert.same(header.points, { { "TOPLEFT", d.frame, "TOPLEFT", 0, -2 }, { "TOPRIGHT", d.frame, "TOPRIGHT", 0, -2 } })
  Assert.same({ d.fill.layer, d.fill.color }, { "BACKGROUND", ns.Theme.COLORS.headerFill })
  Assert.same({ d.icon.width, d.icon.height }, { 32, 32 })
  Assert.same(d.icon.points[1], { "LEFT", header, "LEFT", PAD, 0 })
  -- Icon: the profession's, else the item's, else the bell.
  Assert.equal(d.icon.texture, ITEM_ICON, "no profession icon: the item's")
  Wow.stub("C_TradeSkillUI", {
    GetTradeSkillTexture = function()
      return 777
    end,
  })
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.icon.texture, 777)
  Wow.stub("C_TradeSkillUI", nil)
  lead.itemID = nil
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.icon.texture, ns.Theme.ICON)
  -- Line 1: the customer in class colour, then the age.
  Assert.same({ d.name:GetText(), d.name.textColor, d.name.font }, { "Buyer-Realm", { WARRIOR.r, WARRIOR.g, WARRIOR.b, 1 }, "GameFontNormal" })
  Assert.same({ d.age:GetText(), d.age.textColor }, { "30s", ns.Theme.COLORS.textTimestamp })
  Assert.same(d.age.points[1], { "LEFT", d.name, "RIGHT", 6, 0 })
  Wow.stub("GameFontNormalLarge", {})
  Assert.equal(ns.LeadDetails.New(_G["CreateFrame"]("Frame")).name.font, "GameFontNormalLarge")
  -- Line 2: the link (or recipe), then the profession in gold; a profession lead says it once.
  Assert.same({ d.what:GetText(), d.what.font }, { LINK_TEXT .. " · " .. gold("Tailoring"), "GameFontHighlightSmall" })
  lead.itemLink, lead.recipeName = nil, "Bolt of Silk"
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.what:GetText(), "Bolt of Silk · " .. gold("Tailoring"))
  lead.recipeName, lead.profName = nil, "Tailoring"
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.what:GetText(), "Tailoring")
  -- Line 3: greeted (green, with the check), replied (accent), the realm warning; else empty.
  Assert.equal(d.status:GetText(), "")
  lead.greeted = true
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.status:GetText(), "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t |cff4cd166Greeted|r")
  lead.greeted, lead.replied, lead.cannotOrder = false, true, true
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.status:GetText(), "|cff1eb7f4Replied|r  |cffe5b733can't order (realm)|r")
  Assert.same(d.status.points[1], { "TOPLEFT", d.what, "BOTTOMLEFT", 0, -3 })
  for _, text in ipairs({ d.name, d.age, d.what, d.status }) do
    Assert.equal(text.parent, header, "header texts are the header's regions")
  end
end

local function testBodySections()
  local ns, d, _, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  local sections, body = d.sections, d.body
  Assert.same(body.points, { { "TOPLEFT", d.header, "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", d.bar, "TOPRIGHT", 0, 0 } })
  Assert.same(
    { d.bar:GetHeight(), d.bar.points[1], d.bar.points[2] },
    { 44, { "BOTTOMLEFT", d.frame, "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", d.frame, "BOTTOMRIGHT", 0, 0 } }
  )
  Assert.equal(body.clipsChildren, true)
  Assert.truthy(ns.DetailsBody.HEIGHT <= 242, "the body fits the 420 px window: " .. ns.DetailsBody.HEIGHT)
  local texts = Widgets.texts(body, Wow.frames)
  for _, label in ipairs({ "Request", "Matched", "Crafters", "Channel" }) do
    Assert.truthy(has(texts, label), label)
    Assert.same({ sections.labels[string.lower(label)].font, sections.labels[string.lower(label)].parent }, { "GameFontNormal", body }, label)
  end
  Assert.same(sections.labels.request.points[1], { "TOPLEFT", body, "TOPLEFT", PAD, -GAP })
  local request = sections.values.request
  Assert.same(request.points, { { "TOPLEFT", body, "TOPLEFT", PAD, -GAP - 14 }, { "RIGHT", body, "RIGHT", -PAD, 0 } })
  Assert.same({ request:GetText(), request.font, request.wordWrap, request.maxLines }, { "  LF plate belt  ", "GameFontHighlight", true, 4 })
  -- The next label 4 lines and a gap further down.
  Assert.same(sections.labels.matched.points[1], { "TOPLEFT", body, "TOPLEFT", PAD, -GAP - 14 - 56 - GAP })
  Assert.equal(sections.values.matched:GetText(), "|cfffffffflf + blacksmith|r · " .. gold("Blacksmithing"))
  local channel = sections.values.channel
  Assert.same({ channel:GetText(), channel.textColor }, { "Trade · " .. os.date("%H:%M", UiFixture.T0), ns.Theme.COLORS.textSecondary })
  -- A lead without a message: the Request section hides and leaves its space.
  lead.message = nil
  ns.LeadDetails.Show(d, lead)
  Assert.same({ sections.labels.request:IsShown(), request:IsShown(), sections.labels.matched.points[1][5] }, { false, false, -GAP - 14 - 56 - GAP })
end

local function testCrafters()
  local lead = itemLead()
  lead.crafters[4], lead.crafters[5] = { key = "Cat-Realm" }, { key = "Dan-Realm", rank = 1 }
  local ns, d = open({ lead })
  local lines = d.sections.crafters
  Assert.equal(#lines, 3)
  -- Picked first in its own class colour (not the customer's), then by name; ranks in grey.
  Assert.equal(lines[1]:GetText(), MAGE_CODE .. "Me|r|cff7f7f7f R3 (conc)|r")
  Assert.equal(lines[2]:GetText(), "|cffffffffAlt-Other|r|cff7f7f7f R2|r")
  Assert.equal(lines[3]:GetText(), "|cffffffffBob|r|cff7f7f7f +2 more|r")
  Assert.same({ lines[2].points[1][5] - lines[3].points[1][5], lines[1].font }, { 12, "GameFontHighlightSmall" })
  -- Three or fewer: no "more".
  lead.crafters[4], lead.crafters[5] = nil, nil
  ns.LeadDetails.Show(d, lead)
  Assert.equal(lines[3]:GetText(), "|cffffffffBob|r")
  -- One: the other lines hide.
  lead.crafters = { { key = "Me-Realm" } }
  ns.LeadDetails.Show(d, lead)
  Assert.same({ lines[1]:GetText(), lines[2]:IsShown(), lines[3]:IsShown() }, { MAGE_CODE .. "Me|r", false, false })
  -- None known, in grey.
  lead.crafters, lead.crafter = nil, nil
  ns.LeadDetails.Show(d, lead)
  Assert.same({ lines[1]:GetText(), lines[1]:IsShown(), d.sections.labels.crafters:IsShown() }, { "|cff7f7f7fNone known|r", true, true })
end

-- Saved data from a newer schema keeps crafters as it is: a bad list or entry falls back to the
-- lead's picked crafter.
local function testBadCrafters()
  for _, bad in ipairs({ "x", { { key = 5 } } }) do
    local lead = UiFixture.lead(1, "Buyer-Realm")
    lead.rank, lead.crafters = 2, bad
    local _, d = open({ lead })
    local lines = d.sections.crafters
    Assert.same({ lines[1]:GetText(), lines[2]:IsShown() }, { MAGE_CODE .. "Me|r|cff7f7f7f R2|r", false })
    Wow.reset()
  end
end

local function testLinks()
  local lead = itemLead()
  lead.message = "LF " .. LINK_TEXT .. " crafter"
  local _, d = open({ lead })
  for _, frame in ipairs({ d.header, d.body }) do
    Assert.same({ frame.frameType, frame.hyperlinksEnabled }, { "Button", true })
    for _, script in ipairs({ "OnHyperlinkEnter", "OnHyperlinkLeave", "OnHyperlinkClick" }) do
      Assert.truthy(frame.scripts[script], script)
    end
    Widgets.fire(frame, "OnHyperlinkEnter", LINK, LINK_TEXT)
    Assert.same({ tip().hyperlinks, tip().owner, tip().anchor, tip().shown }, { { LINK }, frame, "ANCHOR_CURSOR", true })
    Widgets.fire(frame, "OnHyperlinkLeave", LINK, LINK_TEXT)
    Assert.equal(tip().shown, false)
    tip().hyperlinks = {}
  end
  -- No zone over the Request: its links hover through the body.
  local request = { d.sections.labels.request, d.sections.values.request }
  for name, zone in pairs(d.zones) do
    Assert.same({ zone.frameType, zone.mouseEnabled, #zone.regions }, { "Button", true, 0 }, name)
    for _, point in ipairs(zone.points) do
      Assert.falsy(has(request, point[2]), name .. " is anchored over the Request")
    end
  end
  Assert.same({ d.zones.name.parent, d.zones.what.parent, d.zones.matched.parent, d.zones.crafters.parent }, { d.header, d.header, d.body, d.body })
  Assert.same({ d.zones.name.points[1][2], d.zones.what.points[1][2] }, { d.name, d.what })
  Assert.same({ d.zones.matched.points[1][2], d.zones.matched.points[2][2] }, { d.sections.labels.matched, d.sections.values.matched })
  Assert.same({ d.zones.crafters.points[1][2], d.zones.crafters.points[2][2] }, { d.sections.labels.crafters, d.sections.crafters[3] })
end

local function testCustomerZone()
  local lead = itemLead()
  lead.greeted, lead.replied = true, true
  local ns, d = open({ lead })
  local zone = d.zones.name
  Widgets.fire(zone, "OnEnter")
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { zone, "ANCHOR_RIGHT", true })
  Assert.same(tip().lines, { "Buyer-Realm", "Warrior", "Greeted", "Replied" })
  Assert.same(tip().colors, { { WARRIOR.r, WARRIOR.g, WARRIOR.b }, WHITE, WHITE, WHITE })
  Widgets.fire(zone, "OnLeave")
  Assert.equal(tip().shown, false)
  -- A customer of unknown class and not greeted: the name in gold, no more lines.
  lead.guid, lead.greeted, lead.replied = nil, false, false
  ns.LeadDetails.Show(d, lead)
  Widgets.fire(zone, "OnEnter")
  Assert.same({ tip().lines, tip().colors }, { { "Buyer-Realm" }, { GOLD } })
  -- Leaving hides only a tooltip the zone owns.
  tip().owner = d.buttons.whisper
  Widgets.fire(zone, "OnLeave")
  Assert.equal(tip().shown, true)
end

local function testWhatZone()
  local ns, d = open({ UiFixture.lead(1, "Buyer-Realm") })
  Assert.equal(d.zones.what:IsShown(), true)
  Widgets.fire(d.zones.what, "OnEnter")
  Assert.same({ tip().owner, tip().lines, tip().colors }, { d.zones.what, { "Blacksmithing", "Profession request" }, { GOLD, WHITE } })
  local lead = recipeLead()
  lead.id = 1
  ns.LeadDetails.Show(d, lead)
  Widgets.fire(d.zones.what, "OnEnter")
  Assert.same(tip().lines, { "Bolt of Silk", "Item request" })
  -- The item link arrives later (the same lead repainted): the link hovers, so the zone goes.
  lead.itemLink = LINK_TEXT
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.zones.what:IsShown(), false)
end

local function testMatchedZone()
  local ns, d, _, lead = open({ itemLead() })
  Widgets.fire(d.zones.matched, "OnEnter")
  Assert.same({ tip().owner, tip().lines, tip().colors }, { d.zones.matched, { "Matched", "lf", "bolt", "Tailoring" }, { GOLD, WHITE, WHITE, GOLD } })
  lead.why = nil
  Widgets.fire(d.zones.matched, "OnEnter")
  Assert.same(tip().lines, { "Matched", "Tailoring" })
  -- Nothing matched to show: the section and its zone hide, and come back with the next lead.
  local bare = UiFixture.lead(2, "Bob-Realm")
  bare.why, bare.profName = nil, nil
  ns.LeadDetails.Show(d, bare)
  Assert.same({ d.zones.matched:IsShown(), d.sections.labels.matched:IsShown() }, { false, false })
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.zones.matched:IsShown(), true)
end

local function testCraftersZone()
  local lead = itemLead()
  lead.cannotOrder = true
  local _, d = open({ lead })
  local zone = d.zones.crafters
  Widgets.fire(zone, "OnEnter")
  Assert.equal(tip().owner, zone)
  Assert.same(tip().lines, {
    "Crafters",
    "Me",
    "Alt-Other",
    "Bob",
    "Picked for this lead: Me",
    "Can't send an order (realm)",
    "Click to choose the main crafter",
  })
  Assert.same({ tip().colors[1], tip().colors[2], tip().colors[3], tip().colors[7] }, { GOLD, { MAGE.r, MAGE.g, MAGE.b }, WHITE, GREEN })
  Assert.same(tip().rights[2], { "R3 (conc)", GREY[1], GREY[2], GREY[3] })
  -- Nobody knows the profession: no menu, no instruction.
  lead.prof, lead.cannotOrder = 999, nil
  Widgets.fire(zone, "OnEnter")
  Assert.same(tip().lines[#tip().lines], "Picked for this lead: Me")
  -- No MenuUtil: no instruction either.
  lead.prof = 164
  Wow.stub("MenuUtil", nil)
  Widgets.fire(zone, "OnEnter")
  Assert.same(tip().lines[#tip().lines], "Picked for this lead: Me")
end

-- The zone reads the shown lead when the cursor comes.
local function testTipFollowsLead()
  local old = UiFixture.lead(1, "Ann-Realm")
  old.crafter = "Bob-Realm"
  local ns, d = open({ old, UiFixture.lead(2, "Buyer-Realm") }, 2)
  Widgets.fire(d.zones.crafters, "OnEnter")
  Assert.same(tip().lines, { "Crafters", "Me", "Picked for this lead: Me", "Click to choose the main crafter" })
  ns.LeadDetails.Show(d, leadOf(ns, 1))
  Widgets.fire(d.zones.crafters, "OnEnter")
  Assert.same(tip().lines, { "Crafters", "Bob", "Picked for this lead: Bob", "Click to choose the main crafter" })
end

-- Main-crafter spec §3: a left-click on the Crafters zone (any modifier) opens the menu. Every other
-- zone click does nothing: no greet, no whisper, no dismiss from the details.
local function testZoneClicks()
  for _, key in ipairs({ "none", "IsShiftKeyDown", "IsControlKeyDown" }) do
    local _, d, calls, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
    if key ~= "none" then
      Wow.stub(key, function()
        return true
      end)
    end
    Wow.clock.gettime = Wow.clock.gettime + 1
    Widgets.click(d.zones.crafters, "LeftButton")
    Assert.same({ Wow.menu.owner, #calls, lead.greeted }, { d.zones.crafters, 0, false }, key)
    Assert.equal(Wow.menu.entries[1].text, "Main crafter for Blacksmithing", key)
    Wow.reset()
  end
  local ns, d, calls, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  Wow.stub("MenuUtil", nil)
  Wow.clock.gettime = Wow.clock.gettime + 1
  for name, zone in pairs(d.zones) do
    Assert.same(zone.clickButtons, { "LeftButtonUp", "RightButtonUp" }, name)
    Widgets.click(zone, "LeftButton")
    Widgets.click(zone, "RightButton")
    Assert.same({ #calls, ns.Leads.IsActive(lead.id) }, { 0, true }, name)
  end
end

-- Choosing a main re-picks only an unanswered lead: a greeted one keeps the crafter it named.
local function testMenuChoiceRepicks()
  for _, greeted in ipairs({ true, false }) do
    local lead = UiFixture.lead(1, "Buyer-Realm")
    lead.crafters = { { key = "Me-Realm", prof = 164 }, { key = "Alt-Realm", prof = 164 } }
    lead.greeted = greeted
    local _, d, _, shown = open({ lead })
    _G["CraftAlertDB"].characters["Alt-Realm"] = { professions = { [164] = { name = "Blacksmithing" } } }
    Widgets.click(d.zones.crafters, "LeftButton")
    Assert.equal(Wow.menu.owner, d.zones.crafters)
    for _, entry in ipairs(Wow.menu.entries) do
      if entry.text == "Alt" then
        entry.setSelected(entry.data)
      end
    end
    Assert.equal(_G["CraftAlertDB"].characters["Alt-Realm"].professions[164].primary, true)
    Assert.equal(shown.crafter, greeted and "Me-Realm" or "Alt-Realm", tostring(greeted))
    Wow.reset()
  end
end

-- A tooltip a zone or a button owns goes when another lead shows and when the pane hides; one
-- another frame owns stays.
local function testTipsFollowAndClose()
  local leads = {}
  for id = 1, 4 do
    leads[id] = UiFixture.lead(id)
  end
  local ns, d = open(leads)
  for index, owner in ipairs({ d.zones.crafters, d.buttons.greet, d.zones.name }) do
    Widgets.fire(owner, "OnEnter")
    Assert.equal(tip():IsOwned(owner), true)
    ns.LeadDetails.Show(d, leadOf(ns, index + 1))
    Assert.equal(tip().shown, false, index)
  end
  tip():SetOwner(_G["UIParent"], "ANCHOR_TOP")
  tip():Show()
  ns.LeadDetails.Show(d, leadOf(ns, 1))
  Assert.equal(tip().shown, true, "not the pane's")
  Widgets.fire(d.zones.matched, "OnEnter")
  d.frame:Hide()
  Assert.equal(tip().shown, false)
  d.frame:Show()
  Widgets.fire(d.body, "OnHyperlinkEnter", LINK, LINK_TEXT)
  Assert.equal(d.body.hoveredLink, LINK)
  ns.LeadDetails.Show(d, leadOf(ns, 2))
  Assert.same({ d.body.hoveredLink, tip().shown }, { nil, false })
end

local function testButtons()
  local ns, d, calls, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  local b = d.buttons
  Assert.same({ b.greet:GetText(), b.whisper:GetText(), b.dismiss:GetText() }, { "Greet", "Whisper", "Dismiss" })
  Assert.same(
    { b.greet.template, b.greet:GetHeight(), b.greet.parent, b.greet.clickButtons },
    { "UIPanelButtonTemplate", 22, d.bar, { "LeftButtonUp" } }
  )
  Assert.same(b.greet.points[1], { "LEFT", d.bar, "LEFT", PAD, 0 })
  Assert.same(b.whisper.points[1], { "LEFT", b.greet, "RIGHT", 8, 0 })
  Assert.same(b.dismiss.points[1], { "LEFT", b.whisper, "RIGHT", 8, 0 })
  for width, expected in pairs({ [449] = 100, [300] = 84, [0] = 100 }) do
    ns.LeadDetails.Layout(d, width)
    Assert.same({ b.greet:GetWidth(), b.whisper:GetWidth(), b.dismiss:GetWidth() }, { expected, expected, expected }, width)
  end
  -- Greet's tooltip; the other buttons have none.
  Widgets.fire(b.greet, "OnEnter")
  Assert.same(
    { tip().owner, tip().anchor, tip().lines },
    { b.greet, "ANCHOR_RIGHT", { "Greet", "Click: greet", "Shift-click: edit first", "Ctrl-click: empty whisper" } }
  )
  Assert.same(tip().colors, { GOLD, GREEN, GREEN, GREEN })
  Widgets.fire(b.greet, "OnLeave")
  Assert.equal(tip().shown, false)
  Widgets.fire(b.whisper, "OnEnter")
  Widgets.fire(b.dismiss, "OnEnter")
  Assert.equal(tip().shown, false)
  -- The actions, once the lead has been up a second.
  Wow.clock.gettime = Wow.clock.gettime + 1
  Widgets.click(b.whisper)
  Assert.same({ #UiFixture.callsTo(calls, "empty"), #UiFixture.callsTo(calls, "chat") }, { 1, 0 })
  Wow.stub("IsShiftKeyDown", function()
    return true
  end)
  Widgets.click(b.greet)
  Assert.same({ #UiFixture.callsTo(calls, "prefill"), #UiFixture.callsTo(calls, "chat") }, { 1, 0 })
  Wow.stub("IsShiftKeyDown", nil)
  Widgets.click(b.greet)
  local chats = UiFixture.callsTo(calls, "chat")
  Assert.same({ #chats, chats[1][5], lead.greeted }, { 1, "Buyer-Realm", true })
  Widgets.click(b.dismiss)
  Assert.equal(ns.Leads.IsActive(lead.id), false)
  -- Cleared: no button acts.
  local count = #calls
  ns.LeadDetails.Clear(d)
  for _, button in pairs(b) do
    Widgets.click(button)
  end
  Assert.equal(#calls, count)
end

-- Review Focus 3: the look rule runs on the details' own shownAt, reset whenever another lead shows.
local function testShownAtAndLookRule()
  local ns, d, calls, leadA = open({ UiFixture.lead(1, "Ann-Realm"), UiFixture.lead(2, "Bob-Realm") })
  Assert.equal(d.shownAt, 50)
  Wow.clock.gettime = 52
  ns.LeadDetails.Show(d, leadA)
  Assert.equal(d.shownAt, 50, "the same lead repainted keeps its time")
  local leadB = leadOf(ns, 2)
  ns.LeadDetails.Show(d, leadB)
  Assert.equal(d.shownAt, 52)
  -- 0.2 s after the pane changed lead: SendGuard's look rule refuses the send and prefills instead.
  Wow.clock.gettime = 52.2
  Widgets.click(d.buttons.greet)
  Assert.same({ #UiFixture.callsTo(calls, "chat"), #UiFixture.callsTo(calls, "prefill"), leadB.greeted }, { 0, 1, false })
  -- A right-click's dismiss is refused the same way.
  Widgets.click(d.buttons.dismiss)
  Assert.equal(ns.Leads.IsActive(leadB.id), true)
  Wow.clock.gettime = 53
  Widgets.click(d.buttons.greet)
  Assert.same({ #UiFixture.callsTo(calls, "chat"), leadB.greeted }, { 1, true })
  -- Shown again (window reopened, Alt+Z back): counts from then.
  d.frame:Hide()
  Wow.clock.gettime = 70
  d.frame:Show()
  Assert.equal(d.shownAt, 70)
  ns.LeadDetails.Clear(d)
  Assert.same({ d.lead, d.shownAt, d.frame:IsShown() }, { nil, nil, false })
  Wow.clock.gettime = 80
  ns.LeadDetails.Show(d, leadA)
  Assert.same({ d.lead, d.shownAt, d.frame:IsShown() }, { leadA, 80, true })
end

-- Runtime rule 1: no OnUpdate on the pane, a zone or a button, ever.
local function testNoOnUpdate()
  local ns, d = open({ itemLead() })
  local function check()
    for _, frame in ipairs(Wow.frames) do
      Assert.equal(frame.scripts.OnUpdate, nil, "OnUpdate on a frame")
    end
  end
  check()
  Widgets.fire(d.zones.crafters, "OnEnter")
  Widgets.fire(d.zones.crafters, "OnLeave")
  Widgets.fire(d.buttons.greet, "OnEnter")
  check()
  ns.LeadDetails.Clear(d)
  check()
end

return function()
  testHeader()
  testBodySections()
  testCrafters()
  testBadCrafters()
  testLinks()
  testCustomerZone()
  testWhatZone()
  testMatchedZone()
  testCraftersZone()
  testTipFollowsLead()
  testZoneClicks()
  testMenuChoiceRepicks()
  testTipsFollowAndClose()
  testButtons()
  testShownAtAndLookRule()
  testNoOnUpdate()
  Wow.reset()
end
