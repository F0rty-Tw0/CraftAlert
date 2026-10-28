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
-- WM's text_secondary (spec D8, D9) and the selected second line's white.
local MUTED, WHITE = { 1, 1, 1, 0.55 }, { 1, 1, 1, 1 }

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
  Assert.same({ row.iconFrame.width, row.iconFrame.height }, { 34, 34 })
  Assert.same(row.iconFrame.points[1], { "LEFT", row, "LEFT", EDGE, 0 })
  Assert.equal(row.icon, row.iconFrame.texture, "the icon is the round holder's texture")
  Assert.equal(row.icon.mask, ns.Theme.ART.CIRCLE_MASK)
  -- Spec D6-D9: WM's text anchors (UI/ContactsList/RowTextAnchors.lua, RowElements.lua:188-193).
  Assert.same(row.name.points[1], { "TOPLEFT", row.iconFrame, "TOPRIGHT", 10, 1 })
  Assert.same(row.name.points[2], { "RIGHT", row.age, "LEFT", -2, 0 }, "the name ends 2 px before the age")
  Assert.same(row.age.points, { { "TOPRIGHT", row, "TOPRIGHT", -EDGE, -2 } }, "the age never anchors to the name")
  Assert.same(row.what.points[1], { "BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 10, -1 })
  Assert.same({ row.name.font, row.age.font, row.what.font }, { "GameFontNormal", "GameFontDisableSmall", "GameFontDisableSmall" })
  Assert.same({ row.name.wordWrap, row.what.wordWrap }, { false, false })
  Assert.same({ row.age.textColor, row.what.textColor }, { MUTED, MUTED })
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
    { "BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 10, -1 },
    { "RIGHT", row, "RIGHT", -(EDGE + MARK_SIZE + MARK_GAP), 0 },
  })

  lead.replied = true
  ns.LeadRow.Show(row, lead)
  local tag = row.repliedTag
  local tagWidth = tag:GetStringWidth()
  Assert.truthy(tagWidth > 0, "the tag has a width to make room for")
  Assert.same({ tag:IsShown(), tag:GetText(), tag.textColor }, { true, "replied", ns.Theme.COLORS.replied })
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
  Assert.same(row.name.textColor, WHITE, "unknown class: white, as WM's rows (spec D6)")
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

-- Spec D1, D2: both overlays on BACKGROUND sublayer 1, under the icon and texts; the selected one
-- gold. The second line turns white while selected and back after a Clear (which hides the
-- selection directly).
local function testHighlights()
  local ns, row, _, lead = load()
  local art = ns.Theme.ART
  local hover, selected = row.hover, row.selected
  Assert.same({ hover.layer, hover.sublevel, hover.texture, hover.blendMode, hover:IsShown() }, { "BACKGROUND", 1, art.LIST_HOVER, "ADD", false })
  Assert.same({ selected.layer, selected.sublevel, selected.texture, selected.blendMode }, { "BACKGROUND", 1, art.LIST_SELECTED, "ADD" })
  Assert.same({ selected.vertexColor, selected:GetAlpha(), selected:IsShown() }, { { 1, 0.82, 0 }, 0.45, false })
  Assert.same(selected.points, { { "ALL", row } })
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetSelected(row, true)
  Assert.same({ selected:IsShown(), row.what.textColor }, { true, WHITE })
  ns.LeadRow.SetSelected(row, false)
  Assert.same({ selected:IsShown(), row.what.textColor }, { false, MUTED })
  ns.LeadRow.SetSelected(row, true)
  ns.LeadRow.Clear(row)
  Assert.equal(selected:IsShown(), false, "a cleared row is not selected")
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetSelected(row, false)
  Assert.same(row.what.textColor, MUTED, "a cleared row reused unselected: muted again")
end

-- A counter of the group's Play calls (its OnPlay script).
local function countPlays(group)
  local counter = { n = 0 }
  group:SetScript("OnPlay", function()
    counter.n = counter.n + 1
  end)
  return counter
end

-- Spec D3, D4: the hover fades in on enter and out on leave, never over the selected row. A hovered
-- row becoming selected drops the hover at once; losing the selection under the cursor fades it in,
-- once however often the list repeats the call.
local function testHover()
  local ns, row, _, lead = load()
  local hover = row.hover
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetSelected(row, false)
  Widgets.fire(row, "OnEnter")
  Assert.same({ hover:IsShown(), hover.fadeIn:IsPlaying() }, { true, true }, "enter: fades in")
  hover.fadeIn:Finish()
  Widgets.fire(row, "OnLeave")
  Assert.equal(hover.fadeOut:IsPlaying(), true, "leave: fades out")
  hover.fadeOut:Finish()
  Assert.equal(hover:IsShown(), false)

  row.mouseOver = true
  Widgets.fire(row, "OnEnter")
  hover.fadeIn:Finish()
  ns.LeadRow.SetSelected(row, true)
  Assert.same({ hover:IsShown(), hover.fadeIn:IsPlaying(), hover.fadeOut:IsPlaying() }, { false, false, false }, "selected: hover gone, no fade")
  Widgets.fire(row, "OnEnter")
  Assert.equal(hover:IsShown(), false, "no hover on the selected row")

  local plays = countPlays(hover.fadeIn)
  ns.LeadRow.SetSelected(row, false)
  Assert.same({ hover:IsShown(), hover.fadeIn:IsPlaying() }, { true, true }, "deselected under the cursor: fades in")
  ns.LeadRow.SetSelected(row, false)
  Assert.equal(plays.n, 1, "a repeated call restarts no fade")

  row.mouseOver = false
  ns.LeadRow.SetSelected(row, true)
  plays = countPlays(hover.fadeIn)
  ns.LeadRow.SetSelected(row, false)
  Assert.same({ plays.n, hover:IsShown() }, { 0, false }, "deselected away from the cursor: no hover")
end

-- The overlay goes with the row: a row hidden while hovered is reused without a stale hover.
local function testHoverHide()
  local ns, row, _, lead = load()
  ns.LeadRow.Show(row, lead)
  Widgets.fire(row, "OnEnter")
  ns.LeadRow.Clear(row)
  Assert.same({ row.hover:IsShown(), row.hover.fadeIn:IsPlaying() }, { false, false })
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
    " ",
    "Click: select",
    "Right-click: dismiss",
  })
  Assert.equal(tip().lines[3], " ", "blank line before the green click lines")
  local green = { 0.1, 1, 0.1 } -- the GREEN_FONT_COLOR stub, as GameTooltip_AddInstructionLine draws
  Assert.same(tip().colors, { { WARRIOR.r, WARRIOR.g, WARRIOR.b }, { 1, 1, 1 }, {}, green, green })
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

-- Spec 6a: icon-only rows on WM's rail. Only the icon shows, centred; nothing of the lead's text or
-- marks, also after a Show. Back to full, the row is as before and the marks follow the lead.
local function testCompact()
  local ns, row, _, lead = load(function(edited)
    edited.greeted, edited.replied = true, true
  end)
  local function fields()
    return { row.name:IsShown(), row.age:IsShown(), row.what:IsShown(), row.greetedIcon:IsShown(), row.repliedTag:IsShown() }
  end
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetCompact(row, true)
  Assert.same(fields(), { false, false, false, false, false })
  Assert.same(row.iconFrame.points, { { "CENTER", row, "CENTER", 0, 0 } })
  ns.LeadRow.Show(row, lead)
  Assert.same(fields(), { false, false, false, false, false }, "Show keeps a compact row icon-only")
  Assert.same({ row.icon:IsShown(), row.icon.texture ~= nil }, { true, true })

  ns.LeadRow.SetCompact(row, false)
  Assert.same(fields(), { true, true, true, true, true })
  Assert.same(row.iconFrame.points, { { "LEFT", row, "LEFT", EDGE, 0 } })
  lead.greeted = false
  ns.LeadRow.Show(row, lead)
  Assert.same(fields(), { true, true, true, false, true }, "the marks follow the lead")

  -- Set before any lead: no error, and the first Show is icon-only.
  local freshNs, fresh, _, other = load()
  freshNs.LeadRow.SetCompact(fresh, true)
  freshNs.LeadRow.SetCompact(fresh, false)
  freshNs.LeadRow.SetCompact(fresh, true)
  freshNs.LeadRow.Show(fresh, other)
  Assert.same({ fresh.name:IsShown(), fresh.what:IsShown(), fresh.greetedIcon:IsShown() }, { false, false, false })
end

-- Every row's icon carries a status dot, as WM's contacts: gold while the lead is unseen and
-- ungreeted (spec B), else the details header's colour: grey new, blue greeted, green replied.
-- The row paints it on every Show, compact or not.
local function testStatusDot()
  local ns, row, _, lead = load()
  local colors = ns.Theme.COLORS
  local function dot()
    return { row.dot:IsShown(), row.dot.texture.vertexColor }
  end
  Assert.equal(row.dot:IsShown(), false, "hidden until a lead is shown")
  ns.LeadRow.Show(row, lead)
  Assert.same(dot(), { true, colors.gold }, "unseen")
  Assert.same(row.dot.points[1], { "BOTTOMRIGHT", row.iconFrame, "BOTTOMRIGHT", 2, -2 })
  lead.seen = true
  ns.LeadRow.Show(row, lead)
  Assert.same(dot(), { true, colors.grey }, "seen, new")
  lead.seen, lead.greeted = nil, true
  ns.LeadRow.Show(row, lead)
  Assert.same(dot(), { true, colors.greeted }, "greeted")
  lead.replied = true
  ns.LeadRow.Show(row, lead)
  Assert.same(dot(), { true, colors.replied }, "replied")
  lead.greeted, lead.replied = nil, nil
  ns.LeadRow.SetCompact(row, true)
  ns.LeadRow.Show(row, lead)
  Assert.same(dot(), { true, colors.gold }, "a compact row shows it too")
  lead.seen = true
  ns.LeadRow.Show(row, lead)
  Assert.same(dot(), { true, colors.grey }, "a compact row: the state colour once seen")
  Assert.same(row.iconFrame.points, { { "CENTER", row, "CENTER", 0, 0 } })
end

-- Unread whispers from the customer (reply-unread-dot spec §2): the source's count > 0 turns the dot
-- whisper pink, before the unseen gold and the state colour, on a greeted lead and on a compact row
-- too. The pink is ChatTypeInfo.WHISPER read at paint time, {1, 0.5, 1, 1} without it; no source,
-- a count of 0 or a non-number leaves today's colours.
local function testUnreadDot()
  local ns, row, _, lead = load()
  local colors = ns.Theme.COLORS
  local function dot()
    return row.dot.texture.vertexColor
  end
  local unread = 2
  local asked = {}
  local function paint()
    ns.LeadRow.Show(row, lead)
    return dot()
  end
  Assert.same(paint(), colors.gold, "no source: unseen gold")
  ns.LeadRow.SetUnreadSource(function(asking)
    asked[#asked + 1] = asking
    return unread
  end)
  Assert.same(paint(), { 1, 0.5, 1, 1 }, "ChatTypeInfo missing: the fallback pink")
  Assert.same(asked, { lead }, "the source gets the lead, once per paint")
  Wow.stub("ChatTypeInfo", { WHISPER = { r = 1, g = 0.5, b = 0.9 } })
  Assert.same(paint(), { 1, 0.5, 0.9, 1 }, "WHISPER colour read at paint time")
  Wow.stub("ChatTypeInfo", { WHISPER = { r = 0.2, g = 0.4, b = 0.6 } })
  Assert.same(paint(), { 0.2, 0.4, 0.6, 1 }, "not cached")
  Wow.stub("ChatTypeInfo", {})
  Assert.same(paint(), { 1, 0.5, 1, 1 }, "no WHISPER entry: the fallback")
  Wow.stub("ChatTypeInfo", { WHISPER = { r = 1, g = 0.5, b = 0.9 } })
  local pink = { 1, 0.5, 0.9, 1 }

  lead.seen, lead.greeted = nil, true
  Assert.same(paint(), pink, "greeted and unread")
  lead.replied = true
  Assert.same(paint(), pink, "replied and unread")
  lead.greeted, lead.replied = nil, nil
  lead.seen = true
  Assert.same(paint(), pink, "seen and unread")
  ns.LeadRow.SetCompact(row, true)
  Assert.same(paint(), pink, "a compact row too")
  ns.LeadRow.SetCompact(row, false)

  unread = 0
  Assert.same(paint(), colors.grey, "0 unread, seen: the state colour")
  lead.seen = nil
  Assert.same(paint(), colors.gold, "0 unread, unseen: gold")
  lead.seen, lead.greeted = nil, true
  Assert.same(paint(), colors.greeted, "0 unread, greeted: its state colour")
  lead.greeted = nil
  for _, answer in ipairs({ "3", false, true }) do
    unread = answer
    Assert.same(paint(), colors.gold, "a non-number counts as 0: " .. tostring(answer))
  end
  unread = 1
  Assert.same(paint(), pink, "1 is enough")
  ns.LeadRow.SetUnreadSource(nil)
  Assert.same(paint(), colors.gold, "cleared: never pink")
end

-- Review Focus 3: a compact row still shows its selection and selects on a left click.
local function testCompactSelect()
  local ns, row, _, lead, selected = load()
  ns.LeadRow.SetCompact(row, true)
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetSelected(row, true)
  Assert.equal(row.selected:IsShown(), true)
  Widgets.click(row, "LeftButton")
  Assert.same(selected, { row })
end

local function compactHovered(edit)
  local ns, row, _, lead = load(edit)
  ns.LeadRow.SetCompact(row, true)
  ns.LeadRow.Show(row, lead)
  Widgets.fire(row, "OnEnter")
  return ns, row, lead
end

-- The compact tooltip names the customer and what they asked for, as the hidden text did; the chat
-- line when there is one, and it shows without one.
local function testCompactTooltip()
  local ns, row, lead = compactHovered()
  local green, white = { 0.1, 1, 0.1 }, { 1, 1, 1 }
  Assert.same({ tip().owner, tip().anchor, tip().shown }, { row, "ANCHOR_RIGHT", true })
  -- Wide enough that the chat line is not a tall column; the next user starts from no minimum.
  Assert.equal(tip().minWidth, ns.Theme.LAYOUT.ROW_TIP_WIDTH, "row tooltip minimum width")
  tip():Hide()
  Assert.equal(tip().minWidth, 0, "hidden: minimum width reset")
  compactHovered()
  Assert.same(
    tip().lines,
    { "Bob-Draenor", "Blacksmithing", chatLine(lead, "Trade", "  LF plate belt  "), " ", "Click: select", "Right-click: dismiss" }
  )
  Assert.same(tip().colors, { { WARRIOR.r, WARRIOR.g, WARRIOR.b }, white, white, {}, green, green })
  compactHovered(function(edited)
    edited.message = nil
  end)
  local lines = { "Bob-Draenor", "Blacksmithing", " ", "Click: select", "Right-click: dismiss" }
  Assert.same({ tip().shown, tip().lines }, { true, lines }, "no message: still a tooltip")
end

-- Review Focus 4: a new chat line while the compact tooltip shows rebuilds it.
local function testCompactTooltipRepaint()
  local ns, row, lead = compactHovered()
  lead.message = "WTB belt"
  ns.LeadRow.Show(row, lead)
  Assert.same({ tip().shown, tip().lines[3] }, { true, chatLine(lead, "Trade", "WTB belt") })
end

return function()
  testCompact()
  testStatusDot()
  testUnreadDot()
  testCompactSelect()
  testCompactTooltip()
  testCompactTooltipRepaint()
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
  testHover()
  testHoverHide()
  testClicks()
  testShownAt()
  Wow.reset()
end
