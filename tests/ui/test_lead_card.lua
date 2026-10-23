local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Lead-cards spec §1, §1.1: each lead is one full-width card, its customer and what matched on the
-- left, the Request / Matched / Crafters rows on the right. No side pane, no hover delay. §2, §3: the
-- hovered card shows its Greet / Whisper / Dismiss buttons and keeps its highlight lit.
local LINK = "item:4305"
local LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
local ITEM_ICON = 132891
local MAGE = { r = 0.25, g = 0.78, b = 0.92 }
local WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
-- MAGE as the spec's colour code, format("|cff%02x%02x%02x", r * 255, g * 255, b * 255).
local MAGE_CODE = "|cff3fc6ea"
-- The spec's numbers: cards 76 high and 2 apart, PADDING 8; the right column at 230, values 74
-- further; row tops at -4 (Request), -32 (Matched), -50 (Crafters).
local CARD_STEP = 78
local LABEL_LEFT, VALUE_LEFT = 230, 304
local ROW_TOPS = { -4, -32, -50 }

local function window()
  return rawget(_G, "CraftAlertLeadsWindow")
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

-- The window over `leads` (records, oldest first, given ids 1..n); Me-Realm smiths and is a mage.
-- The window is subscribed to lead changes as Bootstrap does it. → ns, the sends (UiFixture's calls).
local function load(leads, edit)
  local ns, _, calls = UiFixture.load({
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = { class = "MAGE", professions = { [164] = { name = "Blacksmithing" } } }
      for id, lead in ipairs(leads) do
        lead.id = id
        accountDb.leads[id] = lead
      end
      if edit then
        edit(accountDb)
      end
    end,
  })
  ns.Leads.On("change", ns.LeadsWindow.Refresh)
  Wow.stub("RAID_CLASS_COLORS", { MAGE = MAGE, WARRIOR = WARRIOR })
  -- Every customer is a warrior: a crafter painted from the customer's GUID would show it.
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

local function field(regions, name)
  local values = {}
  for index, region in ipairs(regions) do
    values[index] = region[name]
  end
  return values
end

local function shownOf(regions)
  local shown = {}
  for index, region in ipairs(regions) do
    shown[index] = region:IsShown()
  end
  return shown
end

local function has(text, part)
  Assert.truthy(string.find(text, part, 1, true), part .. " missing from: " .. tostring(text))
end

local function testCardContent()
  local ns = load({ itemLead() })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  Assert.equal(card:GetHeight(), 76)
  Assert.equal(card.name:GetText(), "Buyer-Realm")
  Assert.same(card.name.textColor, { WARRIOR.r, WARRIOR.g, WARRIOR.b, 1 }, "the customer's class colour")
  Assert.equal(card.name.font, "GameFontNormal")
  Assert.equal(card.age:GetText(), "30s")
  Assert.equal(card.icon.texture, ITEM_ICON)
  Assert.same({ card.icon.width, card.icon.height }, { 32, 32 })
  Assert.same({ card.what:GetText(), card.what.font, card.what.wordWrap }, { LINK_TEXT, "GameFontNormal", false })
  -- Labels as written, never upper-cased.
  Assert.same(field(card.labels, "text"), { "Request", "Matched", "Crafters" })
  Assert.same(field(card.labels, "font"), { "GameFontNormal", "GameFontNormal", "GameFontNormal" })
  local request, matched, crafters = card.values[1], card.values[2], card.values[3]
  Assert.same({ request:GetText(), request.font, request.wordWrap }, { "LF bolt of silk", "GameFontHighlight", true })
  Assert.equal(request.maxLines, 2)
  Assert.same({ matched.font, matched.wordWrap }, { "GameFontHighlightSmall", false })
  has(matched:GetText(), "lf + bolt")
  has(matched:GetText(), "Tailoring")
  -- The picked crafter first, in its own class colour (not the customer's), then its rank and the rest.
  Assert.same({ crafters.font, crafters.wordWrap }, { "GameFontHighlightSmall", false })
  Assert.equal(string.sub(crafters:GetText(), 1, #MAGE_CODE + 2), MAGE_CODE .. "Me", crafters:GetText())
  has(crafters:GetText(), "R3 (conc)")
  has(crafters:GetText(), " +2 more")
  -- Crafters' order: picked first, then by the name the greeting uses.
  local entries = ns.CardBody.Crafters(card.lead)
  Assert.same(field(entries, "name"), { "Me", "Alt-Other", "Bob" })
  Assert.same(field(entries, "rank"), { "R3 (conc)", "R2" })
  Assert.same(entries[1].color, MAGE)
  Assert.same(field(entries, "picked"), { true, false, false })
end

local function testProfessionLeadCard()
  local lead = UiFixture.lead(1, "Buyer-Realm")
  lead.prof, lead.profName = 333, "Enchanting"
  local ns = load({ lead })
  Wow.stub("C_TradeSkillUI", {
    GetTradeSkillTexture = function(prof)
      return "prof-icon-" .. prof
    end,
  })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  Assert.equal(card.icon.texture, "prof-icon-333")
  Assert.equal(card.what:GetText(), "Enchanting")
  Assert.falsy(string.find(card.values[3]:GetText(), "more", 1, true), card.values[3]:GetText())
  has(card.values[3]:GetText(), "Me")
  -- No profession icon either: the addon's own.
  Wow.stub("C_TradeSkillUI", {})
  ns.LeadsWindow.Refresh()
  Assert.equal(card.icon.texture, ns.Theme.ICON)
end

local function testHiddenRows()
  local full, bare = UiFixture.lead(1, "Ann-Draenor"), UiFixture.lead(2, "Bob-Draenor")
  bare.why, bare.profName, bare.message = nil, nil, nil
  local ns = load({ full, bare })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  Assert.equal(card.lead.customer, "Bob-Draenor")
  Assert.same(shownOf(card.labels), { false, false, true })
  Assert.same(shownOf(card.values), { false, false, true })
  -- Rows keep fixed positions: a hidden row leaves its space empty.
  for row = 1, 3 do
    Assert.same(card.labels[row].points[1], { "TOPLEFT", card, "TOPLEFT", LABEL_LEFT, ROW_TOPS[row] })
    Assert.same(card.values[row].points[1], { "TOPLEFT", card, "TOPLEFT", VALUE_LEFT, ROW_TOPS[row] })
    Assert.equal(card.labels[row].width, 74)
  end
  -- The same slot then shows a lead with all three: the rows come back.
  ns.Leads.Dismiss(card.lead.id)
  Assert.equal(cards()[1], card)
  Assert.equal(card.lead.customer, "Ann-Draenor")
  Assert.same(shownOf(card.labels), { true, true, true })
  Assert.same(shownOf(card.values), { true, true, true })
  Assert.equal(card.values[1]:GetText(), "  LF plate belt  ")
  -- Only one of why and profName: the row shows that one.
  ns.Leads.List()[1].why = nil
  ns.LeadsWindow.Refresh()
  Assert.same({ card.values[2]:IsShown(), card.labels[2]:IsShown() }, { true, true })
  has(card.values[2]:GetText(), "Blacksmithing")
  Assert.falsy(string.find(card.values[2]:GetText(), " · ", 1, true), card.values[2]:GetText())
end

-- Saved data from a newer schema keeps crafters as it is: a bad list or entry falls back to the
-- lead's picked crafter.
local function testBadCrafters()
  for _, bad in ipairs({ "x", { { key = 5 } } }) do
    local lead = UiFixture.lead(1, "Buyer-Realm")
    lead.rank, lead.crafters = 2, bad
    local ns = load({ lead })
    ns.LeadsWindow.Toggle()
    local card = cards()[1]
    local entries = ns.CardBody.Crafters(card.lead)
    Assert.same(field(entries, "key"), { "Me-Realm" })
    Assert.same({ entries[1].name, entries[1].rank, entries[1].picked }, { "Me", "R2", true })
    Assert.equal(string.sub(card.values[3]:GetText(), 1, #MAGE_CODE + 2), MAGE_CODE .. "Me")
    has(card.values[3]:GetText(), "R2")
    Assert.falsy(string.find(card.values[3]:GetText(), "more", 1, true))
    Wow.reset()
  end
end

local function testNoCrafters()
  local lead = UiFixture.lead(1, "Buyer-Realm")
  lead.crafter = nil
  local ns = load({ lead })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  Assert.same(ns.CardBody.Crafters(card.lead), {})
  has(card.values[3]:GetText(), "None known")
  Assert.equal(card.values[3]:IsShown(), true)
end

local function testRealmTag()
  local blocked, open = UiFixture.lead(1, "Ann-Draenor"), UiFixture.lead(2, "Bob-Draenor")
  blocked.cannotOrder = true
  local ns = load({ blocked, open })
  ns.LeadsWindow.Toggle()
  local shown = cards()
  Assert.equal(shown[1].realm:IsShown(), false)
  Assert.equal(shown[2].realm:IsShown(), true)
  Assert.equal(shown[2].realm:GetText(), "can't order (realm)")
  Assert.equal(shown[2].realm.font, "GameFontHighlightSmall")
  Assert.same(shown[2].realm.textColor, ns.Theme.COLORS.warning)
end

local function testFiveCardsFit()
  local leads = {}
  for i = 1, 6 do
    leads[i] = UiFixture.lead(i)
  end
  local ns = load(leads)
  ns.LeadsWindow.Toggle()
  -- 600x480: inset 426, minus 16 → floor((410 + 2) / 78) = 5.
  Assert.equal(#cards(), 5)
  Assert.equal(cards()[1].lead.customer, "Customer6-Draenor")
  window().scripts.OnMouseWheel(window(), -1)
  Assert.equal(#cards(), 5)
  Assert.equal(cards()[5].lead.customer, "Customer1-Draenor")
end

local function testFullWidth()
  local ns = load({ UiFixture.lead(1), UiFixture.lead(2) })
  ns.LeadsWindow.Toggle()
  local inset = window().Inset
  local shown = cards()
  Assert.equal(shown[1].parent, inset)
  Assert.same(shown[1].points, {
    { "TOPLEFT", inset, "TOPLEFT", 8, -8 },
    { "TOPRIGHT", inset, "TOPRIGHT", -8, -8 },
  })
  Assert.same(shown[2].points, {
    { "TOPLEFT", inset, "TOPLEFT", 8, -8 - CARD_STEP },
    { "TOPRIGHT", inset, "TOPRIGHT", -8, -8 - CARD_STEP },
  })
end

-- LinkHover only sees the card's own FontStrings, so every text is a region of the card.
local function testLinksStillHover()
  local lead = itemLead()
  lead.message = "LF " .. LINK_TEXT .. " crafter"
  local ns = load({ lead })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  local texts = { card.name, card.age, card.what, card.realm, card.repliedTag }
  for _, list in ipairs({ card.labels, card.values }) do
    for _, text in ipairs(list) do
      texts[#texts + 1] = text
    end
  end
  for _, text in ipairs(texts) do
    Assert.equal(text:GetParent(), card)
  end
  Assert.equal(card.icon:GetParent(), card)
  Assert.equal(card.values[1]:GetText(), "LF " .. LINK_TEXT .. " crafter")
  local tip = rawget(_G, "GameTooltip")
  Assert.equal(card.hyperlinksEnabled, true)
  card.scripts.OnHyperlinkEnter(card, LINK, LINK_TEXT)
  Assert.same({ tip.hyperlinks, tip.owner, tip.shown, card.hoveredLink }, { { LINK }, card, true, LINK })
end

local function testNoPaneLeft()
  local ns = load({ UiFixture.lead(1) })
  ns.LeadsWindow.Toggle()
  Assert.equal(window().details, nil)
  Assert.equal(ns.LeadDetails, nil)
end

local HOVERED = { true, true, true, true }
local IDLE = { false, false, false, false }

-- The three buttons' shown flags, then whether the card's highlight is locked.
local function look(card)
  local b = card.buttons
  return { b[1]:IsShown(), b[2]:IsShown(), b[3]:IsShown(), card.highlightLocked == true }
end

-- The cursor comes onto `frame` (a card or a child of one) of `card`.
local function enter(card, frame)
  card.mouseOver = true
  Widgets.fire(frame or card, "OnEnter")
end

-- The cursor leaves `frame`; stillOver: it is still somewhere on the card (on a child or a shared edge).
local function leave(card, frame, stillOver)
  card.mouseOver = stillOver == true
  Widgets.fire(frame or card, "OnLeave")
end

local function testButtonsHiddenUntilEnter()
  local ns = load({ UiFixture.lead(1), UiFixture.lead(2) })
  ns.LeadsWindow.Toggle()
  local shown = cards()
  Assert.same(look(shown[1]), IDLE)
  Assert.same(look(shown[2]), IDLE)
  local buttons = shown[1].buttons
  Assert.same(field(buttons, "template"), { "UIPanelButtonTemplate", "UIPanelButtonTemplate", "UIPanelButtonTemplate" })
  Assert.same({ buttons[1]:GetText(), buttons[2]:GetText(), buttons[3]:GetText() }, { "Greet", "Whisper", "Dismiss" })
  enter(shown[1])
  Assert.same(look(shown[1]), HOVERED)
  Assert.same(look(shown[2]), IDLE)
  -- Equal widths across the left column minus its padding, 4 apart, 20 high at the card's bottom.
  local widths = field(buttons, "width")
  Assert.same({ widths[1] == widths[2], widths[2] == widths[3], buttons[1].height }, { true, true, 20 })
  Assert.equal(3 * widths[1] + 2 * 4, 230 - 2 * 8)
  Assert.same(buttons[1].points[1], { "BOTTOMLEFT", shown[1], "BOTTOMLEFT", 8, 4 })
  Assert.same(buttons[2].points[1], { "BOTTOMLEFT", shown[1], "BOTTOMLEFT", 8 + widths[1] + 4, 4 })
  Assert.same(field(buttons, "clickButtons")[1], { "LeftButtonUp" })
end

local function testButtonsStayOnChild()
  local ns = load({ UiFixture.lead(1) })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  -- The cursor moves onto the Greet button: the card is left (the cursor still on it), the button entered.
  leave(card, card, true)
  Assert.same(look(card), HOVERED)
  enter(card, card.buttons[1])
  Assert.same(look(card), HOVERED)
  leave(card, card.buttons[1], true)
  Assert.same(look(card), HOVERED)
end

local function testButtonsHideOnLeave()
  local ns = load({ UiFixture.lead(1) })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  leave(card, card, false)
  Assert.same(look(card), IDLE)
  enter(card, card.buttons[2])
  Assert.same(look(card), HOVERED)
  leave(card, card.buttons[2], false)
  Assert.same(look(card), IDLE)
end

local function testOneCardAtATime()
  local ns = load({ UiFixture.lead(1), UiFixture.lead(2) })
  ns.LeadsWindow.Toggle()
  local first, second = cards()[1], cards()[2]
  enter(first)
  -- On the shared edge the first card still reports the cursor when the second is entered.
  enter(second)
  Assert.equal(first.mouseOver, true)
  Assert.same(look(first), IDLE)
  Assert.same(look(second), HOVERED)
  enter(first)
  Assert.same(look(first), HOVERED)
  Assert.same(look(second), IDLE)
end

local function testHideClearsButtons()
  local ns = load({ UiFixture.lead(1) })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  -- Closed with the cursor on it: nothing stale; reopened, only a card under the cursor shows them.
  ns.LeadsWindow.Toggle()
  Assert.same(look(card), IDLE)
  card.mouseOver = false
  ns.LeadsWindow.Toggle()
  Assert.same(look(card), IDLE)
  ns.LeadsWindow.Toggle()
  card.mouseOver = true
  ns.LeadsWindow.Toggle()
  Assert.same(look(card), HOVERED)
  -- Alt+Z hides the whole UI.
  _G["UIParent"]:Hide()
  Assert.same(look(card), IDLE)
  card.mouseOver = false
  _G["UIParent"]:Show()
  Assert.same(look(card), IDLE)
  _G["UIParent"]:Hide()
  card.mouseOver = true
  _G["UIParent"]:Show()
  Assert.same(look(card), HOVERED)
  -- The gear to Settings hides the cards; back, the cursor decides.
  Widgets.click(window().gear)
  Assert.same(look(card), IDLE)
  card.mouseOver = false
  Widgets.click(window().gear)
  Assert.same(look(card), IDLE)
  Widgets.click(window().gear)
  card.mouseOver = true
  Widgets.click(window().gear)
  Assert.same(look(card), HOVERED)
end

local function testGreetButton()
  local ns, calls = load({ UiFixture.lead(1, "Buyer-Realm") })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  Wow.clock.gettime = Wow.clock.gettime + 1
  Widgets.click(card.buttons[1], "LeftButton")
  local chats = UiFixture.callsTo(calls, "chat")
  Assert.equal(#chats, 1)
  Assert.equal(chats[1][5], "Buyer-Realm")
  Assert.equal(ns.Leads.List()[1].greeted, true)
  Assert.same(look(card), HOVERED)
end

local function testGreetModifiers()
  local ns, calls = load({ UiFixture.lead(1, "Buyer-Realm") })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  Wow.clock.gettime = Wow.clock.gettime + 1
  Wow.stub("IsShiftKeyDown", function()
    return true
  end)
  Widgets.click(card.buttons[1], "LeftButton")
  Assert.same({ #UiFixture.callsTo(calls, "prefill"), #UiFixture.callsTo(calls, "chat") }, { 1, 0 })
  Wow.stub("IsShiftKeyDown", function()
    return false
  end)
  Wow.stub("IsControlKeyDown", function()
    return true
  end)
  Widgets.click(card.buttons[1], "LeftButton")
  Assert.same({ #UiFixture.callsTo(calls, "empty"), #UiFixture.callsTo(calls, "chat") }, { 1, 0 })
end

-- A wheel step puts another lead in the hovered card; the look rule counts from then, so an at-once
-- click only prefills, and the card keeps its buttons (the cursor is still on it).
local function testGreetAfterListShifts()
  local leads = {}
  for i = 1, 6 do
    leads[i] = UiFixture.lead(i)
  end
  local ns, calls = load(leads)
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  Wow.clock.gettime = Wow.clock.gettime + 1
  window().scripts.OnMouseWheel(window(), -1)
  Assert.equal(card.lead.customer, "Customer5-Draenor")
  Assert.same(look(card), HOVERED)
  Widgets.click(card.buttons[1], "LeftButton")
  local prefills = UiFixture.callsTo(calls, "prefill")
  Assert.same({ #prefills, #UiFixture.callsTo(calls, "chat") }, { 1, 0 })
  Assert.equal(prefills[1][2], "Customer5-Draenor")
  Assert.same(look(card), HOVERED)
end

local function testWhisperButton()
  local ns, calls = load({ UiFixture.lead(1, "Buyer-Realm") })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  Wow.clock.gettime = Wow.clock.gettime + 1
  Widgets.click(card.buttons[2], "LeftButton")
  local empties = UiFixture.callsTo(calls, "empty")
  Assert.same({ #empties, #UiFixture.callsTo(calls, "chat") }, { 1, 0 })
  Assert.equal(empties[1][2], "Buyer-Realm")
end

local function testDismissButton()
  local ns = load({ UiFixture.lead(1, "Ann-Realm"), UiFixture.lead(2, "Bob-Realm") })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  enter(card)
  Widgets.click(card.buttons[3], "LeftButton")
  Assert.same(field(ns.Leads.List(), "customer"), { "Ann-Realm" })
  -- The card shows the next lead and, the cursor still on it, keeps its buttons.
  Assert.equal(card.lead.customer, "Ann-Realm")
  Assert.same(look(card), HOVERED)
  Widgets.click(card.buttons[3], "LeftButton")
  Assert.same(ns.Leads.List(), {})
  Assert.equal(card:IsShown(), false)
  Assert.same(look(card), IDLE)
end

local function testButtonsDoNotDrag()
  local ns = load({ UiFixture.lead(1) })
  ns.LeadsWindow.Toggle()
  local card = cards()[1]
  Assert.equal(card.dragButtons, nil)
  for _, button in ipairs(card.buttons) do
    Assert.equal(button.dragButtons, nil)
  end
end

return function()
  testCardContent()
  testProfessionLeadCard()
  testHiddenRows()
  testBadCrafters()
  testNoCrafters()
  testRealmTag()
  testFiveCardsFit()
  testFullWidth()
  testLinksStillHover()
  testNoPaneLeft()
  testButtonsHiddenUntilEnter()
  testButtonsStayOnChild()
  testButtonsHideOnLeave()
  testOneCardAtATime()
  testHideClearsButtons()
  testGreetButton()
  testGreetModifiers()
  testGreetAfterListShifts()
  testWhisperButton()
  testDismissButton()
  testButtonsDoNotDrag()
  Wow.reset()
end
