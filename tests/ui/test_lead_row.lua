local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec A.3: one 48 px row of the split view's list pane, WhisperMessenger's contact-row layout
-- (UI/ContactsList/RowView.lua:67-118, WM). Left click selects, right click dismisses with the
-- look rule; the list anchors the row and the details pane shows the selected lead.
local ITEM_ICON = 132891
local LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
local WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
-- WM's row numbers: 6 px edges, 10 px after the icon, 4 px between the marks.
local EDGE, MARK_GAP, MARK_SIZE = 6, 4, 14

-- The fixture with one lead (id 1, Bob-Draenor, 30 s old) and a fresh row built over it, as the
-- list builds it. → ns, the row, the sends, the lead, what onSelect got ({ row } per call).
local function load(edit)
  local ns, _, calls = UiFixture.load({
    db = function(accountDb)
      local lead = UiFixture.lead(1, "Bob-Draenor")
      lead.time = UiFixture.T0 - 30
      lead.guid = "Player-1-0001"
      if edit then
        edit(lead)
      end
      accountDb.leads[1] = lead
    end,
  })
  Wow.stub("RAID_CLASS_COLORS", { WARRIOR = WARRIOR })
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
  local selected = {}
  local parent = _G["CreateFrame"]("Frame")
  local row = ns.LeadRow.Create(parent, 1, function(clicked)
    selected[#selected + 1] = clicked
  end)
  return ns, row, calls, ns.Leads.List()[1], selected
end

local function testGeometry()
  local ns, row, _, lead = load()
  ns.LeadRow.Show(row, lead)
  Assert.equal(row:GetHeight(), 48)
  Assert.same({ row.isLeadRow, row.rowIndex }, { true, 1 })
  Assert.same({ row.icon.width, row.icon.height }, { 34, 34 })
  Assert.same(row.icon.points[1], { "LEFT", row, "LEFT", EDGE, 0 })
  Assert.same(row.name.points[1], { "TOPLEFT", row.icon, "TOPRIGHT", 10, -1 })
  Assert.same(row.name.points[2], { "RIGHT", row.age, "LEFT", -EDGE, 0 }, "the name ends before the age")
  Assert.same(row.age.points[1], { "TOPRIGHT", row, "TOPRIGHT", -EDGE, -4 })
  Assert.same(row.what.points[1], { "BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1 })
  Assert.same({ row.name.font, row.age.font, row.what.font }, { "GameFontNormal", "GameFontDisableSmall", "GameFontHighlightSmall" })
  Assert.same({ row.name.wordWrap, row.what.wordWrap }, { false, false })
  Assert.same(row.age.textColor, ns.Theme.COLORS.textTimestamp)
  Assert.equal(row.realm, nil, "the realm tag is the details header's")
  Assert.equal(row.scripts.OnHyperlinkEnter, nil, "rows get no LinkHover")
end

-- The marks sit at the row's bottom right, the greeted check outermost; the second line ends
-- EDGE short of them.
local function testMarks()
  local ns, row, _, lead = load()
  ns.LeadRow.Show(row, lead)
  Assert.same({ row.greetedIcon:IsShown(), row.repliedTag:IsShown() }, { false, false })
  Assert.same(row.what.points[2], { "RIGHT", row, "RIGHT", -EDGE, 0 })

  lead.greeted = true
  ns.LeadRow.Show(row, lead)
  local greeted = row.greetedIcon
  Assert.same({ greeted:IsShown(), greeted.width, greeted.height }, { true, MARK_SIZE, MARK_SIZE })
  Assert.same(greeted.points[1], { "BOTTOMRIGHT", row, "BOTTOMRIGHT", -EDGE, 4 })
  Assert.equal(greeted.texture, ns.Theme.GREETED_ICON)
  Assert.equal(row.repliedTag:IsShown(), false)
  Assert.same(row.what.points, {
    { "BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1 },
    { "RIGHT", row, "RIGHT", -(EDGE + MARK_SIZE + MARK_GAP), 0 },
  })

  lead.replied = true
  ns.LeadRow.Show(row, lead)
  local tag = row.repliedTag
  local tagWidth = tag:GetStringWidth()
  Assert.truthy(tagWidth > 0, "the tag has a width to make room for")
  Assert.same({ tag:IsShown(), tag:GetText(), tag.textColor }, { true, "replied", ns.Theme.COLORS.accent })
  Assert.same(tag.points, { { "BOTTOMRIGHT", greeted, "BOTTOMLEFT", -MARK_GAP, 0 } })
  Assert.same(row.what.points[2], { "RIGHT", row, "RIGHT", -(EDGE + MARK_SIZE + MARK_GAP + tagWidth + MARK_GAP), 0 })

  lead.greeted = false
  ns.LeadRow.Show(row, lead)
  Assert.equal(greeted:IsShown(), false)
  Assert.same(tag.points, { { "BOTTOMRIGHT", row, "BOTTOMRIGHT", -EDGE, 4 } })
  Assert.same(row.what.points[2], { "RIGHT", row, "RIGHT", -(EDGE + tagWidth + MARK_GAP), 0 })
end

local function testContent()
  local ns, row, _, lead = load()
  ns.LeadRow.Show(row, lead)
  Assert.equal(row:IsShown(), true)
  Assert.same({ row.name:GetText(), row.age:GetText(), row.what:GetText() }, { "Bob-Draenor", "30s", "Blacksmithing" })
  Assert.same(row.name.textColor, { WARRIOR.r, WARRIOR.g, WARRIOR.b, 1 }, "the customer's class colour")
  lead.guid = nil
  ns.LeadRow.Show(row, lead)
  Assert.same(row.name.textColor, ns.Theme.COLORS.textPrimary, "unknown class: the plain text colour")
end

-- The item's icon, else the profession's, else the addon's; the second line shows the link.
local function testIcon()
  local ns, row, _, lead = load(function(lead)
    lead.kind, lead.itemID, lead.itemLink = "item", 4305, LINK_TEXT
  end)
  ns.LeadRow.Show(row, lead)
  Assert.same({ row.icon.texture, row.what:GetText() }, { ITEM_ICON, LINK_TEXT })
  lead.itemID = nil
  Wow.stub("C_TradeSkillUI", {
    GetTradeSkillTexture = function(prof)
      return "prof-icon-" .. prof
    end,
  })
  ns.LeadRow.Show(row, lead)
  Assert.equal(row.icon.texture, "prof-icon-164")
  Wow.stub("C_TradeSkillUI", {})
  ns.LeadRow.Show(row, lead)
  Assert.equal(row.icon.texture, ns.Theme.ICON)
end

local function testHighlights()
  local ns, row, _, lead = load()
  local art = ns.Theme.ART
  Assert.same({ row.hover.layer, row.hover.texture, row.hover.blendMode, row.hover:GetAlpha() }, { "HIGHLIGHT", art.LIST_HOVER, "ADD", 0.18 })
  local selected = row.selected
  Assert.same({ selected.texture, selected.blendMode, selected:GetAlpha(), selected:IsShown() }, { art.LIST_SELECTED, "ADD", 0.45, false })
  Assert.same(selected.points, { { "ALL", row } })
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetSelected(row, true)
  Assert.equal(selected:IsShown(), true)
  ns.LeadRow.SetSelected(row, false)
  Assert.equal(selected:IsShown(), false)
  ns.LeadRow.SetSelected(row, true)
  ns.LeadRow.Clear(row)
  Assert.equal(selected:IsShown(), false, "a cleared row is not selected")
end

-- Left selects whatever the modifier and never sends; right dismisses once the look rule allows.
local function testClicks()
  local ns, row, calls, lead, selected = load()
  ns.LeadRow.Show(row, lead)
  Assert.same(row.clickButtons, { "LeftButtonUp", "RightButtonUp" })
  Wow.stub("IsShiftKeyDown", function()
    return true
  end)
  Widgets.click(row, "LeftButton")
  Wow.stub("IsShiftKeyDown", nil)
  Wow.stub("IsControlKeyDown", function()
    return true
  end)
  Widgets.click(row, "LeftButton")
  Wow.stub("IsControlKeyDown", nil)
  Widgets.click(row, "LeftButton")
  Assert.same(selected, { row, row, row })
  Assert.same({ #UiFixture.callsTo(calls, "chat"), #UiFixture.callsTo(calls, "prefill"), #UiFixture.callsTo(calls, "empty") }, { 0, 0, 0 })
  Widgets.click(row, "MiddleButton")
  Assert.same({ #selected, ns.Leads.IsActive(1) }, { 3, true }, "other buttons do nothing")
  Widgets.click(row, "RightButton")
  Assert.equal(ns.Leads.IsActive(1), true, "GetTime() still 50 = shownAt: the look rule refuses")
  Wow.clock.gettime = 51
  Widgets.click(row, "RightButton")
  Assert.equal(ns.Leads.IsActive(1), false)
  Assert.equal(#selected, 3, "right never selects")
end

-- shownAt: a lead new to the row and the row shown again count from now; the same lead keeps it.
local function testShownAt()
  local ns, row, _, lead = load()
  ns.LeadRow.Show(row, lead)
  Assert.same({ row.lead, row.shownAt }, { lead, 50 })
  Wow.clock.gettime = 55
  ns.LeadRow.Show(row, lead)
  Assert.equal(row.shownAt, 50, "same lead: still shown since 50")
  row:Hide()
  Wow.clock.gettime = 60
  row:Show()
  Assert.equal(row.shownAt, 60, "on screen again: shown from now")
  local other = UiFixture.lead(2)
  Wow.clock.gettime = 62
  ns.LeadRow.Show(row, other)
  Assert.equal(row.shownAt, 62, "a new lead: shown from now")
  ns.LeadRow.Clear(row)
  Assert.same({ row.lead, row.shownAt, row:IsShown() }, { nil, nil, false })
  row:Show()
  Assert.equal(row.shownAt, nil, "no lead, no shownAt")
end

-- Row-chat-tooltip spec: the addon's tooltip on the row while the cursor is on it.
local function tip()
  return rawget(_G, "CraftAlertTooltip")
end

local function tipShown()
  return tip() ~= nil and tip().shown
end

-- The spec's chat line, the name coloured by hand (not FrameKit.ColorCode) so the oracle stands apart.
local function chatLine(lead, channel, message)
  local name = string.format("|cff%02x%02x%02x", WARRIOR.r * 255, WARRIOR.g * 255, WARRIOR.b * 255) .. "Bob-Draenor|r"
  local channelPart = channel and ("[" .. channel .. "] ") or ""
  return "[" .. os.date("%H:%M", lead.time) .. "] " .. channelPart .. "[" .. name .. "]: " .. message
end

local function hovered(edit)
  local ns, row, _, lead = load(edit)
  ns.LeadRow.Show(row, lead)
  Widgets.fire(row, "OnEnter")
  return ns, row, lead
end

local function testChatTooltip()
  local _, row, lead = hovered()
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { row, "ANCHOR_RIGHT", true })
  Assert.same(tip().lines, {
    "Chat with Bob-Draenor",
    chatLine(lead, "Trade", "  LF plate belt  "),
    "Click: select",
    "Right-click: dismiss",
  })
  local green = { 0.1, 1, 0.1 } -- the GREEN_FONT_COLOR stub, as GameTooltip_AddInstructionLine draws
  Assert.same(tip().colors, { { WARRIOR.r, WARRIOR.g, WARRIOR.b }, { 1, 1, 1 }, green, green })
  Widgets.fire(row, "OnLeave")
  Assert.equal(tip().shown, false)
end

-- A customer of unknown class: the title in gold, the name in the chat line in white.
local function testChatTooltipNoClass()
  local _, _, lead = hovered(function(edited)
    edited.guid = nil
  end)
  Assert.same(tip().colors[1], { 1, 0.82, 0 })
  local stamp = "[" .. os.date("%H:%M", lead.time) .. "] [Trade] "
  Assert.equal(tip().lines[2], stamp .. "[|cffffffffBob-Draenor|r]:   LF plate belt  ")
end

-- No channel drops its bracket; no message, no tooltip; a link in the message stays as it came.
local function testChatTooltipLead()
  local _, _, lead = hovered(function(edited)
    edited.channel = nil
  end)
  Assert.equal(tip().lines[2], chatLine(lead, nil, "  LF plate belt  "))
  hovered(function(edited)
    edited.message = nil
  end)
  Assert.equal(tipShown(), false, "no message: no tooltip")
  _, _, lead = hovered(function(edited)
    edited.message = LINK_TEXT
  end)
  Assert.equal(tip().lines[2], chatLine(lead, "Trade", LINK_TEXT))
end

-- A tooltip another frame owns is never hidden or rewritten by the row.
local function testChatTooltipForeignOwner()
  local ns, row, _, lead = load()
  local other = _G["CreateFrame"]("Frame")
  local shared = ns.Tooltip.Get()
  shared:SetOwner(other, "ANCHOR_RIGHT")
  shared:SetText("Other")
  shared:Show()
  Widgets.fire(row, "OnLeave")
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.Clear(row)
  Assert.same({ tip().owner, tip().shown, tip().lines }, { other, true, { "Other" } })
end

-- Show rebuilds an owned tooltip for the row's lead (none without a message) and adds none unhovered.
local function testChatTooltipRepaint()
  local ns, row = hovered()
  ns.LeadRow.Show(row, UiFixture.lead(2))
  Assert.same({ tip().owner, tip().shown, tip().lines[1] }, { row, true, "Chat with Customer2-Draenor" })
  local quiet = UiFixture.lead(3)
  quiet.message = nil
  ns.LeadRow.Show(row, quiet)
  Assert.equal(tip().shown, false, "no message: the tooltip goes")
  local fresh, unhovered, _, lead = load()
  fresh.LeadRow.Show(unhovered, lead)
  Assert.equal(tipShown(), false, "not hovered: Show adds no tooltip")
end

-- Clearing the row or hiding its parent (the window closed) takes the tooltip down.
local function testChatTooltipHide()
  local ns, row = hovered()
  ns.LeadRow.Clear(row)
  Assert.equal(tip().shown, false, "cleared")
  _, row = hovered()
  row:GetParent():Hide()
  Assert.equal(tip().shown, false, "parent hidden")
end

return function()
  testChatTooltip()
  testChatTooltipNoClass()
  testChatTooltipLead()
  testChatTooltipForeignOwner()
  testChatTooltipRepaint()
  testChatTooltipHide()
  testGeometry()
  testMarks()
  testContent()
  testIcon()
  testHighlights()
  testClicks()
  testShownAt()
  Wow.reset()
end
