local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- A list row repaints only when something it shows changed (UI/LeadRowPaint.lua): the same lead
-- again sets no text, while every painted field, the clock's age text included, still repaints.
local ITEM_ICON = 132891
local LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
local WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
local MUTED, WHITE = { 1, 1, 1, 0.55 }, { 1, 1, 1, 1 }

-- The fixture with one lead (Bob-Draenor, 30 s old) of an unknown class, shown in a fresh row.
-- → ns, the row, the lead, sets() (SetText calls on the row's texts since the first paint).
local function load()
  local ns = UiFixture.load({
    db = function(accountDb)
      local lead = UiFixture.lead(1, "Bob-Draenor")
      lead.time = UiFixture.T0 - 30
      lead.guid = "Player-1-0001"
      accountDb.leads[1] = lead
    end,
  })
  Wow.stub("RAID_CLASS_COLORS", { WARRIOR = WARRIOR })
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      if itemID == 4305 then
        return 4305, "Tradeskill", "Cloth", "", ITEM_ICON
      end
    end,
  })
  local row = ns.LeadRow.Create(_G["CreateFrame"]("Frame"), 1, function() end)
  local lead = ns.Leads.List()[1]
  ns.LeadRow.Show(row, lead)
  local calls = 0
  for _, text in ipairs({ row.name, row.age, row.what }) do
    local setText = text.SetText
    text.SetText = function(...)
      calls = calls + 1
      return setText(...)
    end
  end
  return ns, row, lead, function()
    return calls
  end
end

local function testSameLeadSetsNoText()
  local ns, row, lead, sets = load()
  ns.LeadRow.Show(row, lead)
  Assert.equal(sets(), 0)
end

-- The age text changes with the clock alone.
local function testAgeFollowsTheClock()
  local ns, row, lead = load()
  Assert.equal(row.age:GetText(), "30s")
  Wow.clock.time = Wow.clock.time + 60
  ns.LeadRow.Show(row, lead)
  Assert.equal(row.age:GetText(), "1m")
end

-- The client learns the customer's class after the first paint: the name takes its colour.
local function testClassColourArrives()
  local ns, row, lead = load()
  Assert.same(row.name.textColor, { 1, 1, 1, 1 }, "unknown class: white")
  Wow.stub("GetPlayerInfoByGUID", function()
    return "Warrior", "WARRIOR"
  end)
  ns.LeadRow.Show(row, lead)
  Assert.same(row.name.textColor, { WARRIOR.r, WARRIOR.g, WARRIOR.b, 1 })
end

-- A field of the same lead table changed in place repaints it.
local function testChangedFieldsRepaint()
  local ns, row, lead = load()
  lead.itemID, lead.itemLink, lead.customer = 4305, LINK_TEXT, "Cy-Draenor"
  ns.LeadRow.Show(row, lead)
  Assert.same({ row.icon.texture, row.what:GetText(), row.name:GetText() }, { ITEM_ICON, LINK_TEXT, ns.LeadText.Customer(lead) })
  lead.greeted = true
  ns.LeadRow.Show(row, lead)
  Assert.equal(row.greetedIcon:IsShown(), true, "greeted mark")
end

-- A reply alone repaints the replied tag; an unread whisper holds the dot pink, so nothing else
-- the row shows changes.
local function testReplyAloneRepaints()
  local ns, row, lead = load()
  ns.LeadRowPaint.SetUnreadSource(function()
    return 1
  end)
  ns.LeadRow.Show(row, lead)
  lead.replied = true
  ns.LeadRow.Show(row, lead)
  Assert.equal(row.repliedTag:IsShown(), true)
end

-- The whisper pink is read from ChatTypeInfo at each paint into one table, never a new one.
local function testWhisperPinkBuildsNoTable()
  local ns, _, lead = load()
  ns.LeadRowPaint.SetUnreadSource(function()
    return 1
  end)
  Wow.stub("ChatTypeInfo", { WHISPER = { r = 1, g = 0.5, b = 0.9 } })
  local first, second = {}, {}
  ns.LeadRowPaint.Read(lead, first)
  _G["ChatTypeInfo"].WHISPER.b = 0.8
  ns.LeadRowPaint.Read(lead, second)
  Assert.same({ rawequal(first.dot, second.dot), first.dotB, second.dot }, { true, 0.9, { 1, 0.5, 0.8, 1 } })
end

-- A cleared row shows and repaints on the next Show; the second line's colour follows the
-- selection, set only when it changes.
local function testClearRepaints()
  local ns, row, lead, sets = load()
  ns.LeadRow.SetSelected(row, true)
  Assert.same(row.what.textColor, WHITE)
  row.what.textColor = nil
  ns.LeadRow.SetSelected(row, true)
  Assert.equal(row.what.textColor, nil, "same selection: the colour is not set again")
  ns.LeadRow.Clear(row)
  ns.LeadRow.Show(row, lead)
  ns.LeadRow.SetSelected(row, false)
  Assert.same({ row:IsShown(), row.what.textColor }, { true, MUTED })
  Assert.equal(sets(), 3, "repainted after Clear")
end

return function()
  testSameLeadSetsNoText()
  testAgeFollowsTheClock()
  testClassColourArrives()
  testChangedFieldsRepaint()
  testReplyAloneRepaints()
  testWhisperPinkBuildsNoTable()
  testClearRepaints()
  Wow.reset()
end
