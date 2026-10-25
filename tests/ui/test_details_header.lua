local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local DetailsFixture = require("tests.helpers.details_fixture")

-- Spec A.4 and details spec A.1-A.2: the details pane's 62 px header (round icon with a status
-- dot, the customer, class / status / age and channel / time lines) and its 24 px info strip
-- (what was asked for), built by UI/DetailsHeader.lua.
local LINK_TEXT, ITEM_ICON = DetailsFixture.LINK_TEXT, DetailsFixture.ITEM_ICON
local WARRIOR, MAGE_CODE = DetailsFixture.WARRIOR, DetailsFixture.MAGE_CODE
-- The name starts right of the 36 px icon and a 10 px gap.
local PAD = DetailsFixture.PAD
local NAME_LEFT = PAD + 36 + 10
local SEP = "  -  "
local load, open = DetailsFixture.load, DetailsFixture.open
local itemLead, gold = DetailsFixture.itemLead, DetailsFixture.gold

local function testHeader()
  local ns, d, _, lead = open({ itemLead() })
  local header, colors = d.header, ns.Theme.COLORS
  Assert.equal(header:GetHeight(), 62)
  Assert.same(header.points, { { "TOPLEFT", d.frame, "TOPLEFT", 0, -2 }, { "TOPRIGHT", d.frame, "TOPRIGHT", 0, -2 } })
  Assert.same({ d.fill.layer, d.fill.color }, { "BACKGROUND", colors.headerFill })
  -- A round 36 px icon (RowArt's holder), the status dot on its bottom-right corner.
  Assert.same({ d.icon.width, d.icon.height, d.icon.parent, d.icon.clipsChildren }, { 36, 36, header, true })
  Assert.same(d.icon.points[1], { "LEFT", header, "LEFT", PAD, 0 })
  Assert.same(d.dot.points[1], { "BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", 2, -2 })
  -- Icon: the profession's, else the item's, else the bell.
  Assert.equal(d.icon.texture.texture, ITEM_ICON, "no profession icon: the item's")
  Wow.stub("C_TradeSkillUI", {
    GetTradeSkillTexture = function()
      return 777
    end,
  })
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.icon.texture.texture, 777)
  Wow.stub("C_TradeSkillUI", nil)
  lead.itemID = nil
  ns.LeadDetails.Show(d, lead)
  Assert.equal(d.icon.texture.texture, ns.Theme.ICON)
  -- The name: the customer in class colour; GameFontNormalLarge's file at 17 px when the client
  -- has it, else GameFontNormal as it is.
  Assert.same({ d.name:GetText(), d.name.textColor, d.name.font }, { "Buyer-Realm", { WARRIOR.r, WARRIOR.g, WARRIOR.b, 1 }, "GameFontNormal" })
  Assert.same({ d.name.points[1], d.name.fontSize }, { { "TOPLEFT", header, "TOPLEFT", NAME_LEFT, -8 }, nil })
  Wow.stub("GameFontNormalLarge", {})
  local large = ns.LeadDetails.New(_G["CreateFrame"]("Frame")).name
  Assert.same({ large.font, large.fontSize }, { "GameFontNormalLarge", 17 })
  -- Lines 1 and 2 in 55 % white under the name: class, status and age; channel and time.
  local at = os.date("%H:%M", lead.time)
  Assert.same(
    { d.lineOne:GetText(), d.lineOne.font, d.lineOne.textColor },
    { "Warrior" .. SEP .. "New lead" .. SEP .. "30s", "GameFontHighlightSmall", colors.textSecondary }
  )
  Assert.same({ d.lineTwo:GetText(), d.lineTwo.font, d.lineTwo.textColor }, { "Trade" .. SEP .. at, "GameFontHighlightSmall", colors.textSecondary })
  Assert.same(
    { d.lineOne.points[1], d.lineTwo.points[1] },
    { { "TOPLEFT", d.name, "BOTTOMLEFT", 0, -3 }, { "TOPLEFT", d.lineOne, "BOTTOMLEFT", 0, -3 } }
  )
  -- The dot by status: grey new, green greeted, accent replied.
  Assert.same({ d.dot:IsShown(), d.dot.texture.vertexColor }, { true, colors.grey })
  lead.greeted = true
  ns.LeadDetails.Show(d, lead)
  Assert.same({ d.dot.texture.vertexColor, d.lineOne:GetText() }, { colors.greeted, "Warrior" .. SEP .. "Greeted" .. SEP .. "30s" })
  lead.replied = true
  ns.LeadDetails.Show(d, lead)
  Assert.same({ d.dot.texture.vertexColor, d.lineOne:GetText() }, { colors.accent, "Warrior" .. SEP .. "Greeted, replied" .. SEP .. "30s" })
  for _, text in ipairs({ d.name, d.lineOne, d.lineTwo }) do
    Assert.equal(text.parent, header, "header texts are the header's regions")
  end
end

-- The pure line builders: an unknown class leaves its part out, no channel leaves the time alone.
local function testHeaderLines()
  local ns = load({})
  local Header = ns.DetailsHeader
  local lead = itemLead()
  Assert.equal(Header.LineOne(lead), "Warrior" .. SEP .. "New lead" .. SEP .. "30s")
  lead.guid = nil
  Assert.equal(Header.LineOne(lead), "New lead" .. SEP .. "30s")
  Wow.stub("LOCALIZED_CLASS_NAMES_MALE", nil)
  lead.guid = "Player-1-0001"
  Assert.equal(Header.LineOne(lead), "New lead" .. SEP .. "30s", "no class name table")
  local at = os.date("%H:%M", lead.time)
  Assert.equal(Header.LineTwo(lead), "Trade" .. SEP .. at)
  lead.channel = nil
  Assert.equal(Header.LineTwo(lead), at)
  Wow.reset()
end

-- Details spec A.2: what the lead wants, its profession in gold and the crafter in their class
-- colour (white unknown), " · " apart, each part left out when missing; a profession lead wants
-- "a" (or "an") crafter of its profession.
local function testStrip()
  local ns = load({})
  local Strip, db = ns.DetailsHeader.Strip, _G["CraftAlertDB"]
  local lead = itemLead()
  Assert.equal(Strip(lead, db), "Wants " .. LINK_TEXT .. " · " .. gold("Tailoring") .. " · " .. MAGE_CODE .. "Me|r")
  lead.crafter = "Bob-Realm"
  Assert.equal(Strip(lead, db), "Wants " .. LINK_TEXT .. " · " .. gold("Tailoring") .. " · |cffffffffBob|r", "a crafter not in the db: white")
  db.characters["Bob-Realm"] = {}
  Assert.equal(Strip(lead, db), "Wants " .. LINK_TEXT .. " · " .. gold("Tailoring") .. " · |cffffffffBob|r", "no class saved: white")
  lead.profName, lead.crafter = nil, nil
  Assert.equal(Strip(lead, db), "Wants " .. LINK_TEXT)
  lead.itemLink, lead.recipeName, lead.crafter = nil, "Bolt of Silk", "Me-Realm"
  Assert.equal(Strip(lead, db), "Wants Bolt of Silk · " .. MAGE_CODE .. "Me|r")
  local profession = UiFixture.lead(1)
  profession.profName = "Jewelcrafting"
  Assert.equal(Strip(profession, db), "Wants a " .. gold("Jewelcrafting") .. " crafter")
  for _, name in ipairs({ "Alchemy", "Enchanting", "Engineering", "Inscription" }) do
    profession.profName = name
    Assert.equal(Strip(profession, db), "Wants an " .. gold(name) .. " crafter")
  end
  Wow.reset()
end

-- The strip: a 24 px mouse-enabled Button under the header, its text PAD in from the left and
-- wrapped to the pane less PAD a side (testStripWraps), 55 % white for the plain words.
local function testStripFrame()
  local ns, d = open({ itemLead() })
  local strip, text = d.strip, d.stripText
  Assert.same({ strip.frameType, strip:GetHeight(), strip.parent }, { "Button", 24, d.frame })
  Assert.same(strip.points, { { "TOPLEFT", d.header, "BOTTOMLEFT", 0, 0 }, { "TOPRIGHT", d.header, "BOTTOMRIGHT", 0, 0 } })
  Assert.same({ text.parent, text.font, text.wordWrap, text.maxLines }, { strip, "GameFontHighlightSmall", true, 2 })
  Assert.same({ text.points, text:GetWidth() }, { { { "LEFT", strip, "LEFT", PAD, 0 } }, 449 - 2 * PAD })
  local dim = ns.Theme.COLORS.textSecondary[4]
  Assert.same(text.textColor, { dim, dim, dim, 1 })
  Assert.equal(text:GetText(), ns.DetailsHeader.Strip(d.lead, _G["CraftAlertDB"]))
  -- The header's fill, and a 1 px divider above and below (the mock's borders).
  local fills = {}
  for _, region in ipairs(strip.regions) do
    if region.color then
      fills[#fills + 1] = { region.layer, region.color, region.height }
    end
  end
  local colors = ns.Theme.COLORS
  Assert.same(fills, { { "BACKGROUND", colors.headerFill, 0 }, { "BORDER", colors.divider, 1 }, { "BORDER", colors.divider, 1 } })
end

-- The strip's text takes up to 2 lines (the client cuts the rest with "…"): the strip grows by
-- the second line, keeping its padding, and the body box under it follows. Re-measured on each
-- width and each paint. Widths: 6 px a character, 12 px a line; the text shows 37 characters.
local Layout = require("tests.helpers.layout")
local function testStripWraps()
  local ns, d, _, lead = open({ itemLead() })
  local text = d.stripText
  local function layout(width)
    d.frame:SetWidth(width)
    ns.LeadDetails.Layout(d, width)
    return { d.strip:GetHeight(), text:GetNumLines(), (Layout.ys(d.scroll.box)) }
  end
  Assert.equal(text:GetText(), "Wants " .. LINK_TEXT .. " · " .. gold("Tailoring") .. " · " .. MAGE_CODE .. "Me|r")
  Assert.same(layout(449), { 24, 1, -(2 + 62 + 24) }, "a short text: one line, 24 px")
  Assert.same(layout(200), { 36, 2, -(2 + 62 + 36) }, "narrow: two lines, the strip and the box under it follow")
  Assert.same(layout(100), { 36, 2, -(2 + 62 + 36) }, "narrower: still two lines at most")
  Assert.same(layout(449), { 24, 1, -(2 + 62 + 24) }, "wide again: one line")
  layout(200)
  lead.itemLink, lead.profName, lead.recipeName = nil, nil, "Silk"
  ns.LeadDetails.Show(d, lead)
  Assert.same({ d.strip:GetHeight(), text:GetNumLines() }, { 24, 1 }, "a shorter text on the next paint")
  Assert.same(layout(0), { 24, 1, -(2 + 62 + 24) }, "width not known: one line")
end

-- The name is cut with an ellipsis so it ends before the right padding (or the inset a host
-- reserves, e.g. for its gear), at any width. Widths: 6 px a character.
local function testHeaderLineFits()
  local Layout = require("tests.helpers.layout")
  local ns, d, _, lead = open({ itemLead() })
  local function nameRight()
    local _, right = Layout.edges(d.name)
    return right
  end
  local function layout(width)
    d.frame:SetWidth(width)
    ns.LeadDetails.Layout(d, width)
  end
  layout(449)
  Assert.equal(nameRight(), NAME_LEFT + 66, "a short name: as wide as its text")
  lead.customer = "Telchiness-Kazzak"
  ns.LeadDetails.Show(d, lead)
  Assert.equal(nameRight(), NAME_LEFT + 102, "a long name fits a wide header")
  layout(150)
  Assert.equal(nameRight(), 150 - PAD, "a narrow header: the name ends at its padding")
  Assert.equal(d.name:GetText(), "Telchiness-Kazzak", "the name is cut by width, not shortened")
  ns.LeadDetails.SetRightInset(d, 32)
  Assert.equal(nameRight(), 150 - 32, "a reserved inset: the name ends before it")
  layout(240)
  Assert.equal(nameRight(), NAME_LEFT + 102, "wider again: the whole name")
  layout(70)
  Assert.truthy(d.name:GetWidth() > 0, "no room left: a sliver, not an unset (unbounded) width")
  layout(0)
  Assert.equal(d.name:GetWidth(), 0, "width not known: the name is as wide as its text")
  layout(150)
  lead.customer = "Bob-Realm"
  ns.LeadDetails.Show(d, lead)
  Assert.equal(nameRight(), NAME_LEFT + 54, "the next lead refits the name")
end

return function()
  testHeader()
  testHeaderLines()
  testStrip()
  testStripFrame()
  testHeaderLineFits()
  testStripWraps()
  Wow.reset()
end
