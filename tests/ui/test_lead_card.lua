local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- Lead-cards spec §1, §1.1: each lead is one full-width card, its customer and what matched on the
-- left, the Request / Matched / Crafters rows on the right. No side pane, no hover delay.
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
-- The window is subscribed to lead changes as Bootstrap does it.
local function load(leads, edit)
  local ns = UiFixture.load({
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
  return ns
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
  Wow.reset()
end
