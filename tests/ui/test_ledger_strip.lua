local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec §8 and plan revision R5a/R5b: one ledger line at the top of the shared split view (the
-- leads window and WhisperMessenger's panel both build it), today's counters with `filled` on
-- Retail only, and a tooltip with the last 7 days. Local noon on 2026-10-27, so the day keys do
-- not depend on the machine's time zone.
local NOON = os.time({ year = 2026, month = 10, day = 27, hour = 12 })
local STRIP_HEIGHT = 20
local GOLD, WHITE = { 1, 0.82, 0 }, { 1, 1, 1 }

-- The fixture with today's and the day before's counters and a view over a bare 830 x 496 host.
-- → ns, the view, db.
local function open(flavor)
  local ns, db = UiFixture.load({
    flavor = flavor,
    db = function(db)
      db.ledger["2026-10-27"] = { seen = 3, greeted = 2, replied = 1, filled = 1 }
      db.ledger["2026-10-26"] = { seen = 5, greeted = 0, replied = 0, filled = 2 }
    end,
  })
  Wow.clock.time = NOON
  ns.Ledger.Install(db)
  local host = _G["CreateFrame"]("Frame")
  host:SetSize(830, 496)
  local view = ns.LeadsView.New(host, {
    getHeight = function()
      return 496
    end,
    getListWidth = function()
      return 260
    end,
  })
  ns.LeadsView.Refresh(view, ns.Leads.List())
  return ns, view, db
end

-- One line above both panes; the list fits its rows into the height below it.
local function testLayout()
  local ns, view = open()
  local strip, host = view.strip, view.frame:GetParent()
  Assert.equal(strip.parent, view.frame, "a child of the view: hidden with it while the settings show")
  Assert.same(strip.points, { { "TOPLEFT", host, "TOPLEFT", 0, 0 }, { "TOPRIGHT", host, "TOPRIGHT", 0, 0 } })
  Assert.equal(strip:GetHeight(), STRIP_HEIGHT)
  Assert.same(view.listPane.points[1], { "TOPLEFT", host, "TOPLEFT", 0, -STRIP_HEIGHT })
  Assert.equal(strip.text.font, ns.Theme.FONTS.body)
  -- Bound on both sides, one line: a narrow host cuts the text instead of overflowing.
  local padding = ns.Theme.LAYOUT.PADDING
  Assert.same(strip.text.points, { { "LEFT", strip, "LEFT", padding, 0 }, { "RIGHT", strip, "RIGHT", -padding, 0 } })
  Assert.equal(strip.text.wordWrap, false)
  -- (496 - 20 - 2 * 4) / 48 → 9 rows, not the 10 the whole height holds.
  local leads = {}
  for id = 12, 1, -1 do
    leads[#leads + 1] = UiFixture.lead(id)
  end
  ns.LeadsView.Refresh(view, leads)
  local shown = 0
  for _, row in ipairs(view.list.rows) do
    shown = shown + (row:IsShown() and 1 or 0)
  end
  Assert.equal(shown, 9)
end

local function testTodayLine()
  local _, view = open()
  Assert.equal(view.strip.text:GetText(), "Today: 3 seen · 2 greeted · 1 replied · 1 filled")
  local _, foreverView = open("forever")
  Assert.equal(foreverView.strip.text:GetText(), "Today: 3 seen · 2 greeted · 1 replied", "no orders off Retail")
end

-- A fill fires no leads "change": the shown strip repaints from the ledger itself.
local function testRepaintsOnAdd()
  local ns, view = open()
  ns.Ledger.Add("filled")
  Assert.equal(view.strip.text:GetText(), "Today: 3 seen · 2 greeted · 1 replied · 2 filled")
end

-- WhisperMessenger's panel builds a new view when its host changes: one strip per host repaints,
-- the newest, so the repaint list does not grow with every build.
local function testOneStripPerHost()
  local ns, view = open()
  local host = view.frame:GetParent()
  local rebuilt = ns.LeadsView.New(host, {
    getHeight = function()
      return 496
    end,
    getListWidth = function()
      return 260
    end,
  })
  ns.LeadsView.Refresh(rebuilt, ns.Leads.List())
  ns.Ledger.Add("filled")
  Assert.equal(rebuilt.strip.text:GetText(), "Today: 3 seen · 2 greeted · 1 replied · 2 filled")
  Assert.equal(view.strip.text:GetText(), "Today: 3 seen · 2 greeted · 1 replied · 1 filled", "the replaced strip is dropped")
end

-- Gold title, then one white line per day, today first.
local function testTooltip()
  local ns, view = open()
  local strip, tip = view.strip, ns.Tooltip.Get()
  strip.scripts.OnEnter(strip)
  Assert.same({ tip.owner, tip.shown }, { strip, true })
  Assert.same(tip.lines, {
    "Last 7 days",
    "Today: 3 seen · 2 greeted · 1 replied · 1 filled",
    "2026-10-26: 5 seen · 0 greeted · 0 replied · 2 filled",
    "2026-10-25: 0 seen · 0 greeted · 0 replied · 0 filled",
    "2026-10-24: 0 seen · 0 greeted · 0 replied · 0 filled",
    "2026-10-23: 0 seen · 0 greeted · 0 replied · 0 filled",
    "2026-10-22: 0 seen · 0 greeted · 0 replied · 0 filled",
    "2026-10-21: 0 seen · 0 greeted · 0 replied · 0 filled",
  })
  Assert.same(tip.colors, { GOLD, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE })
  strip.scripts.OnLeave(strip)
  Assert.equal(tip.shown, false)
  local foreverNs, foreverView = open("forever")
  foreverView.strip.scripts.OnEnter(foreverView.strip)
  Assert.equal(foreverNs.Tooltip.Get().lines[3], "2026-10-26: 5 seen · 0 greeted · 0 replied")
end

-- Nothing shows in an instance (WhisperMessenger's panel stays open there, with no leads).
local function testHiddenInInstance()
  local ns, view = open()
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.LeadsView.Refresh(view, {})
  Assert.equal(view.strip:IsShown(), false)
  Wow.stub("IsInInstance", nil)
  ns.LeadsView.Refresh(view, {})
  Assert.equal(view.strip:IsShown(), true)
end

return function()
  testLayout()
  testTodayLine()
  testRepaintsOnAdd()
  testOneStripPerHost()
  testTooltip()
  testHiddenInInstance()
  Wow.reset()
end
