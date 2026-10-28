local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local DetailsFixture = require("tests.helpers.details_fixture")

-- Spec A.4 and details spec A.3-A.5: the split view's details pane below its header (the header
-- and the strip: tests/ui/test_details_header.lua). A clipping body (the Request bubble, the
-- Matched / Crafters / Quality / Realm grid, the Greet sends bubble, as tall as what shows),
-- tooltip zones over the name, the strip and the Matched and Crafters rows, and the Greet /
-- Whisper / Dismiss action bar, which acts on the shown lead with the look rule (details.shownAt).
local LINK, LINK_TEXT = DetailsFixture.LINK, DetailsFixture.LINK_TEXT
local MAGE, WARRIOR, MAGE_CODE = DetailsFixture.MAGE, DetailsFixture.WARRIOR, DetailsFixture.MAGE_CODE
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GREEN = { 0.1, 1, 0.1 }
local GREY = { 0.5, 0.5, 0.5 }
-- The spec's numbers: 16 px padding. The body (details spec A.3): 18 between blocks, labels 14
-- high and 5 above their bubble, bubbles 10 / 12 padding, an 84 px grid label column and 12 to
-- its values, 14 a grid line, 9 between rows, a 12 px hint line.
local PAD = DetailsFixture.PAD
local BLOCK, LABEL, LABEL_GAP, PAD_Y, PAD_X = 18, 14, 5, 10, 12
local VALUE_LEFT, LINE, ROW_GAP, HINT = PAD + 84 + 12, 14, 9, 12
local REQUEST_CENTER, REQUEST_BORDER = { 0.17, 0.14, 0.09, 0.9 }, { 0.35, 0.29, 0.19, 1 }
local GREET_CENTER, GREET_BORDER = { 0.14, 0.13, 0.11, 0.9 }, { 0.24, 0.22, 0.19, 1 }
local open, leadOf, gold = DetailsFixture.open, DetailsFixture.leadOf, DetailsFixture.gold
local itemLead, recipeLead = DetailsFixture.itemLead, DetailsFixture.recipeLead

local function tip()
  return rawget(_G, "CraftAlertTooltip")
end

local function has(list, value)
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

-- A bubble's height: its text's, wrapped to at most 4 lines, and PAD_Y above and below.
local function bubbleHeight(text)
  return text:GetStringHeight() + 2 * PAD_Y
end

-- The body's width in a `width` (default 449) wide pane: less the box's 4 px right inset and the
-- scroll bar.
local function bodyWidth(d, width)
  return (width or 449) - 4 - d.scroll.bar:GetWidth()
end

-- The vertical distance of `region`'s first anchor below the body's top.
local function top(region)
  return -region.points[1][5]
end

local function testBodySections()
  local ns, d, _, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  local s, body = d.sections, d.body
  Assert.same(body.points, { { "TOPLEFT", d.scroll.frame, "TOPLEFT", 0, 0 } }, "the body scrolls in the details' view")
  Assert.same(
    { d.bar:GetHeight(), d.bar.points[1], d.bar.points[2] },
    { 44, { "BOTTOMLEFT", d.frame, "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", d.frame, "BOTTOMRIGHT", 0, 0 } }
  )
  Assert.equal(body.clipsChildren, true)
  -- The labels in gold on the body; no Channel section (the header's line 2 carries it).
  local texts = Widgets.texts(body, Wow.frames)
  for key, label in pairs({ request = "Request", matched = "Matched", crafters = "Crafters", greet = "Greet sends" }) do
    Assert.truthy(has(texts, label), label)
    Assert.same({ s.labels[key].font, s.labels[key].parent }, { "GameFontNormal", body }, label)
  end
  Assert.falsy(has(texts, "Channel"), "no Channel section")
  -- The Request: its label at the padding, the bubble 5 under it; the text is the bubble's region.
  local bubble, request = s.bubbles.request, s.texts.request
  Assert.same(s.labels.request.points[1], { "TOPLEFT", body, "TOPLEFT", PAD, -PAD })
  Assert.same(bubble.points[1], { "TOPLEFT", body, "TOPLEFT", PAD, -PAD - LABEL - LABEL_GAP })
  Assert.same({ bubble.frameType, bubble.template, bubble.parent, bubble.mouseEnabled }, { "Button", "TooltipBackdropTemplate", body, true })
  Assert.same({ bubble.NineSlice.centerColor, bubble.NineSlice.borderColor }, { REQUEST_CENTER, REQUEST_BORDER })
  Assert.same(
    { request.parent, request:GetText(), request.font, request.wordWrap, request.maxLines },
    { bubble, "  LF plate belt  ", "GameFontHighlight", true, 4 }
  )
  Assert.same(request.points[1], { "TOPLEFT", bubble, "TOPLEFT", PAD_X, -PAD_Y })
  local width = bodyWidth(d)
  Assert.same({ bubble:GetWidth(), request:GetWidth(), bubble:GetHeight() }, { width - 2 * PAD, width - 2 * PAD - 2 * PAD_X, bubbleHeight(request) })
  -- The grid a block gap under the bubble: labels at the padding, values 84 + 12 further right.
  local gridTop = PAD + LABEL + LABEL_GAP + bubble:GetHeight() + BLOCK
  Assert.same(s.labels.matched.points[1], { "TOPLEFT", body, "TOPLEFT", PAD, -gridTop })
  local matched = s.lines.matched[1]
  Assert.same(matched.points, { { "TOPLEFT", body, "TOPLEFT", VALUE_LEFT, -gridTop }, { "RIGHT", body, "RIGHT", -PAD, 0 } })
  Assert.same({ matched:GetText(), matched.font }, { "|cfffffffflf + blacksmith|r · " .. gold("Blacksmithing"), "GameFontHighlight" })
  Assert.equal(top(s.labels.crafters), gridTop + LINE + ROW_GAP)
  Assert.equal(top(s.lines.crafters[1]), gridTop + LINE + ROW_GAP)
  -- A lead without a message: the Request block hides and the grid moves up to the padding.
  lead.message = nil
  ns.LeadDetails.Show(d, lead)
  Assert.same({ s.labels.request:IsShown(), bubble:IsShown(), top(s.labels.matched) }, { false, false, PAD })
end

-- Details spec A.3-A.4: a grid row shows only when the lead has a value for it, and a hidden row
-- takes no space. Quality: LeadText.Quality's 1-2 lines; Realm: only for a cannotOrder lead.
local function testGrid()
  local lead = itemLead()
  lead.recipeKey = 9001
  local ns, d = open({ lead })
  local s, db = d.sections, _G["CraftAlertDB"]
  Assert.same({ s.labels.quality:IsShown(), s.labels.realm:IsShown(), s.lines.realm[1]:IsShown() }, { false, false, false })
  local greetTop = top(s.labels.greet)
  db.characters["Me-Realm"].recipes = {
    [9001] = { name = "Bolt", prof = 197, ranks = { 1, 2, 3 }, reachRank = 2, reachCost = 120, reachConc = 3168 },
  }
  db.characters["Me-Realm"].concentration = { [3168] = { amount = 960, at = 0, cycleMs = 345600, perCycle = 1, max = 1000 } }
  ns.LeadDetails.Show(d, lead)
  local quality = ns.LeadText.Quality(lead, db)
  Assert.equal(#quality, 2)
  Assert.same(
    { s.labels.quality:GetText(), s.lines.quality[1]:GetText(), s.lines.quality[2]:GetText(), s.lines.quality[1].font },
    { "Quality", quality[1], quality[2], "GameFontHighlight" }
  )
  Assert.equal(top(s.labels.quality), top(s.labels.crafters) + 3 * LINE + ROW_GAP, "under the three crafter lines")
  Assert.same({ top(s.lines.quality[1]), top(s.lines.quality[2]) }, { top(s.labels.quality), top(s.labels.quality) + LINE })
  Assert.equal(top(s.labels.greet), greetTop + 2 * LINE + ROW_GAP, "the blocks below move down")
  -- An order can't go to the customer's realm: the Realm row under Quality, in the warning colour.
  lead.cannotOrder = true
  ns.LeadDetails.Show(d, lead)
  local realm = s.lines.realm[1]
  Assert.same(
    { s.labels.realm:GetText(), realm:GetText(), realm.textColor, realm:IsShown() },
    { "Realm", "Can't send an order (other realm)", ns.Theme.COLORS.warning, true }
  )
  Assert.equal(top(s.labels.realm), top(s.labels.quality) + 2 * LINE + ROW_GAP)
  Assert.equal(top(s.labels.greet), greetTop + 2 * LINE + ROW_GAP + LINE + ROW_GAP)
  -- The top rank reached: one Quality line, the Realm row a line further up.
  db.characters["Me-Realm"].recipes[9001].reachRank = 3
  ns.LeadDetails.Show(d, lead)
  Assert.same({ s.lines.quality[1]:GetText(), s.lines.quality[2]:IsShown() }, { ns.LeadText.Quality(lead, db)[1], false })
  Assert.equal(top(s.labels.realm), top(s.labels.quality) + LINE + ROW_GAP)
  -- Neither: both rows hide and the blocks below move back up.
  lead.cannotOrder, lead.recipeKey = nil, nil
  ns.LeadDetails.Show(d, lead)
  Assert.same({ s.labels.quality:IsShown(), s.lines.quality[1]:IsShown(), s.labels.realm:IsShown(), realm:IsShown() }, { false, false, false, false })
  Assert.equal(top(s.labels.greet), greetTop)
end

-- Details spec A.5: what Greet would send to an ungreeted lead. The label, "to" the whisper target
-- on its right (55 % white folded opaque, so a class colour code keeps its own), the greeting in
-- its own bubble, and the green Shift-click hint under it; built on each paint; hidden once
-- greeted or when the template is empty.
local function testGreetSends()
  local ns, d, _, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  local s, db = d.sections, _G["CraftAlertDB"]
  local bubble, text, target, hint = s.bubbles.greet, s.texts.greet, s.texts.target, s.texts.hint
  local greeting = ns.Greeting.Build(lead, db.settings)
  Assert.truthy(greeting ~= "", "the default template says something")
  Assert.same({ text:GetText(), text.parent, text.font, text.wordWrap, text.maxLines }, { greeting, bubble, "GameFontHighlight", true, 4 })
  Assert.same({ bubble.frameType, bubble.template, bubble.parent, bubble.mouseEnabled }, { "Button", "TooltipBackdropTemplate", d.body, true })
  Assert.same({ bubble.NineSlice.centerColor, bubble.NineSlice.borderColor }, { GREET_CENTER, GREET_BORDER })
  Assert.same(bubble.points[1], { "TOPLEFT", d.body, "TOPLEFT", PAD, -(top(s.labels.greet) + LABEL + LABEL_GAP) })
  Assert.same(
    { s.labels.greet:GetText(), target:GetText(), target.font, target.textColor, target:IsShown() },
    { "Greet sends", "to Buyer-Realm", "GameFontHighlightSmall", ns.FrameKit.Opaque(ns.Theme.COLORS.textSecondary), true }
  )
  Assert.same(target.points, { { "TOP", s.labels.greet, "TOP", 0, 0 }, { "RIGHT", d.body, "RIGHT", -PAD, 0 } })
  Assert.same(
    { hint:GetText(), hint.font, hint.textColor, hint.parent, hint:IsShown() },
    { "Shift-click Greet to edit first", "GameFontHighlightSmall", { GREEN[1], GREEN[2], GREEN[3], 1 }, d.body, true }
  )
  Assert.same(hint.points[1], { "TOPLEFT", bubble, "BOTTOMLEFT", 0, -LABEL_GAP })
  -- A template edit shows on the next paint.
  db.settings.templates.profession = "hi {customer}"
  ns.LeadDetails.Show(d, lead)
  Assert.equal(text:GetText(), ns.Greeting.Build(lead, db.settings))
  -- No whisper target: no "to …"; the block stays.
  local targetOf = ns.GreetAction.Target
  ns.GreetAction.Target = function() end
  ns.LeadDetails.Show(d, lead)
  Assert.same({ target:IsShown(), s.labels.greet:IsShown(), bubble:IsShown(), hint:IsShown() }, { false, true, true, true })
  ns.GreetAction.Target = targetOf
  -- An empty template: the whole block hides.
  db.settings.templates.profession = ""
  ns.LeadDetails.Show(d, lead)
  Assert.same({ s.labels.greet:IsShown(), target:IsShown(), bubble:IsShown(), hint:IsShown() }, { false, false, false, false })
  -- Greeted: hidden too, whatever the template says.
  db.settings.templates.profession = "hi"
  lead.greeted = true
  ns.LeadDetails.Show(d, lead)
  Assert.same({ s.labels.greet:IsShown(), target:IsShown(), bubble:IsShown(), hint:IsShown() }, { false, false, false, false })
end

-- The target's name in the customer's class colour (the header name's source, image 46); "to" and
-- a customer of unknown class keep the label's own colour.
local function testGreetTargetClassColour()
  local lead = UiFixture.lead(1, "Buyer-Realm")
  lead.guid = "Player-1-0001"
  local ns, d = open({ lead })
  local target = d.sections.texts.target
  Assert.equal(target:GetText(), "to " .. ns.FrameKit.ColorCode("Buyer-Realm", WARRIOR.r, WARRIOR.g, WARRIOR.b))
  lead.guid = nil
  ns.LeadDetails.Show(d, lead)
  Assert.equal(target:GetText(), "to Buyer-Realm", "unknown class: plain")
end

-- A chat line of only spaces leaves the Request bubble nothing to show: it hides with its label.
local function testRequestHidesBlankMessage()
  local lead = UiFixture.lead(1, "Buyer-Realm")
  lead.message = "  "
  local _, d = open({ lead })
  local s = d.sections
  Assert.same({ s.labels.request:IsShown(), s.bubbles.request:IsShown() }, { false, false })
end

-- A greeting of only spaces is nothing to say (GreetAction opens an empty whisper): the block hides.
local function testGreetSendsHidesBlankGreeting()
  local ns, d, _, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  local s = d.sections
  _G["CraftAlertDB"].settings.templates.profession = "   "
  ns.LeadDetails.Show(d, lead)
  Assert.same(
    { s.labels.greet:IsShown(), s.texts.target:IsShown(), s.bubbles.greet:IsShown(), s.texts.hint:IsShown() },
    { false, false, false, false }
  )
end

-- Details spec A.3: the body is as tall as what it shows (the padding, the blocks, the gaps
-- between them), re-measured on each paint and on each Layout, where a narrower pane wraps the
-- bubbles to more lines; the scroll range follows.
local function testBodyHeight()
  local ns, d, _, lead = open({ UiFixture.lead(1, "Buyer-Realm") })
  local s, body, scroll = d.sections, d.body, d.scroll
  local function greetBlock()
    return BLOCK + LABEL + LABEL_GAP + bubbleHeight(s.texts.greet) + LABEL_GAP + HINT
  end
  -- Request, the grid (Matched, one crafter), then Greet sends while it shows.
  local function expected()
    local height = PAD + LABEL + LABEL_GAP + bubbleHeight(s.texts.request) + BLOCK + LINE + ROW_GAP + LINE
    if s.bubbles.greet:IsShown() then
      height = height + greetBlock()
    end
    return height + PAD
  end
  Assert.equal(body:GetHeight(), expected())
  local full, greet = body:GetHeight(), greetBlock()
  lead.greeted = true
  ns.LeadDetails.Show(d, lead)
  Assert.equal(body:GetHeight(), full - greet, "Greet sends hidden: its block and gap go")
  lead.greeted, lead.message = false, string.rep("long words ", 12)
  ns.LeadDetails.Show(d, lead)
  scroll.box:SetSize(300, 100)
  Widgets.fire(scroll.box, "OnSizeChanged", 300, 100)
  local wide, lines = body:GetHeight(), s.texts.request:GetStringHeight()
  Assert.equal(wide, expected())
  ns.LeadDetails.Layout(d, 250)
  Assert.same(
    { s.bubbles.request:GetWidth(), s.texts.request:GetWidth(), s.texts.greet:GetWidth() },
    { bodyWidth(d, 250) - 2 * PAD, bodyWidth(d, 250) - 2 * PAD - 2 * PAD_X, bodyWidth(d, 250) - 2 * PAD - 2 * PAD_X }
  )
  Assert.truthy(s.texts.request:GetStringHeight() > lines, "narrower: the request wraps to more lines")
  Assert.same({ body:GetHeight(), select(2, scroll.bar:GetMinMaxValues()) }, { expected(), expected() - 100 })
  Assert.truthy(body:GetHeight() > wide)
end

-- Scroll bars spec §4: the body scrolls in a box between the fixed header and action bar, its
-- height the blocks', the bar PANE_PADDING in from the pane's right; the bar shows and the view
-- takes the wheel only while the box is shorter than the body. Another lead starts at the top, the
-- same lead repainted keeps its place. The fakes do not lay out: the test sizes the box.
local function testBodyScrolls()
  local ns, d = open({ UiFixture.lead(1, "Ann-Realm"), UiFixture.lead(2, "Bob-Realm") })
  local scroll, body = d.scroll, d.body
  local height = body:GetHeight()
  local function size(boxHeight)
    scroll.box:SetSize(300, boxHeight)
    Widgets.fire(scroll.box, "OnSizeChanged", 300, boxHeight)
  end
  Assert.same({ scroll.content, body:GetParent() }, { body, scroll.frame })
  Assert.same(scroll.box.points, { { "TOPLEFT", d.strip, "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", d.bar, "TOPRIGHT", -4, 0 } })
  size(height + 50)
  Assert.same({ scroll.bar:IsShown(), scroll.frame.mouseWheelEnabled }, { false, false }, "a body that fits: the wheel falls through")
  size(height - 60)
  Assert.same({ scroll.bar:IsShown(), scroll.frame.mouseWheelEnabled, select(2, scroll.bar:GetMinMaxValues()) }, { true, true, 60 })
  ns.ScrollView.ScrollTo(scroll, 40)
  ns.LeadDetails.Show(d, leadOf(ns, 1))
  Assert.equal(scroll.frame:GetVerticalScroll(), 40, "the same lead repainted keeps its place")
  ns.LeadDetails.Show(d, leadOf(ns, 2))
  Assert.same({ scroll.frame:GetVerticalScroll(), scroll.bar:GetValue() }, { 0, 0 }, "another lead starts at the top")
end

local function testCrafters()
  local lead = itemLead()
  lead.crafters[4], lead.crafters[5] = { key = "Cat-Realm" }, { key = "Dan-Realm", rank = 1 }
  local ns, d = open({ lead })
  local lines = d.sections.lines.crafters
  Assert.equal(#lines, 3)
  -- Picked first in its own class colour (not the customer's), then by name; ranks in grey.
  Assert.equal(lines[1]:GetText(), MAGE_CODE .. "Me|r|cff7f7f7f R3 (conc)|r")
  Assert.equal(lines[2]:GetText(), "|cffffffffAlt-Other|r|cff7f7f7f R2|r")
  Assert.equal(lines[3]:GetText(), "|cffffffffBob|r|cff7f7f7f +2 more|r")
  Assert.same({ lines[2].points[1][5] - lines[3].points[1][5], lines[1].font }, { LINE, "GameFontHighlight" })
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
    local lines = d.sections.lines.crafters
    Assert.same({ lines[1]:GetText(), lines[2]:IsShown() }, { MAGE_CODE .. "Me|r|cff7f7f7f R2|r", false })
    Wow.reset()
  end
end

local function testLinks()
  local lead = itemLead()
  lead.message = "LF " .. LINK_TEXT .. " crafter"
  local _, d = open({ lead })
  local bubbles = d.sections.bubbles
  -- The strip, the body (its grid texts) and both bubbles, each hovering its own texts' links.
  for _, frame in ipairs({ d.strip, d.body, bubbles.request, bubbles.greet }) do
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
  -- No zone over the Request: its links hover through its bubble.
  local request = { d.sections.labels.request, bubbles.request, d.sections.texts.request }
  for name, zone in pairs(d.zones) do
    Assert.same({ zone.frameType, zone.mouseEnabled, #zone.regions }, { "Button", true, 0 }, name)
    for _, point in ipairs(zone.points) do
      Assert.falsy(has(request, point[2]), name .. " is anchored over the Request")
    end
  end
  Assert.same({ d.zones.name.parent, d.zones.what.parent, d.zones.matched.parent, d.zones.crafters.parent }, { d.header, d.strip, d.body, d.body })
  Assert.same({ d.zones.name.points[1][2], d.zones.name.points[2][2] }, { d.name, d.name })
  local lines = d.sections.lines
  Assert.same({ d.zones.matched.points[1][2], d.zones.matched.points[2][2] }, { d.sections.labels.matched, lines.matched[1] })
  Assert.same({ d.zones.crafters.points[1][2], d.zones.crafters.points[2][2] }, { d.sections.labels.crafters, lines.crafters[3] })
end

local function testCustomerZone()
  local lead = itemLead()
  lead.greeted, lead.replied = true, true
  local ns, d = open({ lead })
  local zone = d.zones.name
  Widgets.fire(zone, "OnEnter")
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { zone, "ANCHOR_RIGHT", true })
  Assert.same(tip().lines, { "Buyer-Realm", "Warrior", "Greeted", "Replied" })
  local greeted, replied = ns.Theme.COLORS.greeted, ns.Theme.COLORS.replied
  Assert.same(tip().colors, {
    { WARRIOR.r, WARRIOR.g, WARRIOR.b },
    WHITE,
    { greeted[1], greeted[2], greeted[3] },
    { replied[1], replied[2], replied[3] },
  })
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

-- The What zone covers the whole strip, shown only while the strip holds no link to hover.
local function testWhatZone()
  local ns, d = open({ UiFixture.lead(1, "Buyer-Realm") })
  Assert.same(d.zones.what.points, { { "TOPLEFT", d.strip, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", d.strip, "BOTTOMRIGHT", 0, 0 } })
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
    "Can't send an order (other realm)",
    " ",
    "Click: choose the main crafter",
  })
  Assert.same(
    { tip().colors[1], tip().colors[2], tip().colors[3], tip().colors[7], tip().colors[8] },
    { GOLD, { MAGE.r, MAGE.g, MAGE.b }, WHITE, {}, GREEN }
  )
  Assert.same(tip().rights[2], { "R3 (conc)", GREY[1], GREY[2], GREY[3] })
  -- Nobody knows the profession: no menu, no instruction.
  lead.prof, lead.cannotOrder = 999, nil
  Widgets.fire(zone, "OnEnter")
  Assert.same(tip().lines[#tip().lines], "Picked for this lead: Me")
  Assert.falsy(tip().lines[#tip().lines] == " ", "no instruction: no dangling blank line")
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
  Assert.same(tip().lines, { "Crafters", "Me", "Picked for this lead: Me", " ", "Click: choose the main crafter" })
  ns.LeadDetails.Show(d, leadOf(ns, 1))
  Widgets.fire(d.zones.crafters, "OnEnter")
  Assert.same(tip().lines, { "Crafters", "Bob", "Picked for this lead: Bob", " ", "Click: choose the main crafter" })
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
  local bubbles = d.sections.bubbles
  for index, host in ipairs({ d.body, d.strip, bubbles.request, bubbles.greet }) do
    Widgets.fire(host, "OnHyperlinkEnter", LINK, LINK_TEXT)
    Assert.equal(host.hoveredLink, LINK)
    ns.LeadDetails.Show(d, leadOf(ns, index % 4 + 1))
    Assert.same({ host.hoveredLink, tip().shown }, { nil, false }, index)
  end
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
  Assert.same(b.dismiss.points[1], { "RIGHT", d.bar, "RIGHT", -PAD, 0 })
  for width, expected in pairs({ [449] = 100, [300] = 84, [0] = 100 }) do
    ns.LeadDetails.Layout(d, width)
    Assert.same({ b.greet:GetWidth(), b.whisper:GetWidth(), b.dismiss:GetWidth() }, { expected, expected, expected }, width)
  end
  -- Greet's tooltip; the other buttons have none.
  Widgets.fire(b.greet, "OnEnter")
  Assert.same(
    { tip().owner, tip().anchor, tip().lines },
    { b.greet, "ANCHOR_RIGHT", { "Greet", " ", "Click: greet", "Shift-click: edit first", "Ctrl-click: empty whisper" } }
  )
  Assert.same(tip().colors, { GOLD, {}, GREEN, GREEN, GREEN })
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
  testBodySections()
  testGrid()
  testGreetSends()
  testGreetTargetClassColour()
  testGreetSendsHidesBlankGreeting()
  testRequestHidesBlankMessage()
  testBodyHeight()
  testBodyScrolls()
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
