local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local TOAST_SECONDS = 20 -- the default toast duration

local function toastFrame()
  return rawget(_G, "CraftAlertToast")
end

local function texts()
  return table.concat(Widgets.texts(toastFrame(), Wow.frames), " / ")
end

-- The toast's font string showing exactly `text`.
local function fontStringWith(text)
  for _, region in ipairs(toastFrame().regions) do
    if region.text == text then
      return region
    end
  end
  error("no font string shows " .. text)
end

-- Runs the timers pending now with a delay of `seconds` or less (the toast's), as if that much
-- time had passed; timers they arm stay pending. The 601 s lead expiry is left alone.
local function runTimersUpTo(seconds)
  local due, kept = {}, {}
  for _, timer in ipairs(Wow.timers) do
    table.insert(timer.delay <= seconds and due or kept, timer)
  end
  Wow.timers = kept
  for _, timer in ipairs(due) do
    timer.fn()
  end
end

local function pendingUpTo(seconds)
  local count = 0
  for _, timer in ipairs(Wow.timers) do
    if timer.delay <= seconds then
      count = count + 1
    end
  end
  return count
end

local function testLazyFrameAndContent()
  local ns, db, calls = UiFixture.load({ leads = 1 })
  local lead = ns.Leads.Latest()
  -- §4.4 rule 5: no frame until the first alert, and asking about it creates none.
  Assert.equal(ns.AlertToast.VisibleLead(), nil)
  Assert.equal(toastFrame(), nil)
  local framesBefore = #Wow.frames

  ns.AlertToast.Show(lead)
  local frame = toastFrame()
  Assert.truthy(frame, "frame CraftAlertToast created on the first alert")
  Assert.truthy(#Wow.frames > framesBefore)
  Assert.equal(frame:IsShown(), true)
  Assert.equal(frame.clamped, true)
  Assert.equal(frame.movable, true)
  -- Customer, the trimmed message, what matched, the crafter and the why line.
  local shown = texts()
  for _, part in ipairs({ "Customer1-Draenor", "LF plate belt", "Blacksmithing", "Me-Realm", "lf + blacksmith" }) do
    Assert.truthy(string.find(shown, part, 1, true), part .. " missing from: " .. shown)
  end
  Assert.falsy(string.find(shown, "  LF", 1, true), "message is trimmed")
  Assert.falsy(string.find(shown, "more", 1, true), "no badge for the first lead")
  -- Sound on the Master channel (default kit) and the taskbar flash.
  Assert.same(UiFixture.callsTo(calls, "sound"), { { "sound", db.settings.sound, "Master" } })
  Assert.equal(#UiFixture.callsTo(calls, "flash"), 1)
  local visible, shownAt = ns.AlertToast.VisibleLead()
  Assert.equal(visible, lead)
  Assert.equal(shownAt, 50)
  Assert.equal(frame:GetAlpha(), 1.0)

  -- Sound "none", flash off and a lower opacity are honoured.
  ns, db, calls = UiFixture.load({ leads = 1 })
  db.settings.sound, db.settings.flash, db.settings.opacity = 0, false, 0.6
  ns.AlertToast.Show(ns.Leads.Latest())
  Assert.same(calls, {})
  Assert.equal(toastFrame():GetAlpha(), 0.6)

  -- An item lead shows its link; a lead whose customer cannot order says so (§7.2).
  ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      local record = accountDb.leads[1]
      record.kind, record.itemLink, record.cannotOrder = "item", "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r", true
    end,
  })
  ns.AlertToast.Show(ns.Leads.Latest())
  shown = texts()
  Assert.truthy(string.find(shown, "[Sim Plate Belt]", 1, true), shown)
  Assert.truthy(string.find(shown, "can't order (realm)", 1, true), shown)
  Assert.falsy(string.find(shown, "R2", 1, true), "no rank, no R part: " .. shown)

  -- §4.5: the rank follows the crafter.
  ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.leads[1].rank, accountDb.leads[1].rankConc = 2, true
    end,
  })
  ns.AlertToast.Show(ns.Leads.Latest())
  shown = texts()
  Assert.truthy(string.find(shown, "by Me-Realm · R2 (conc) · lf + blacksmith", 1, true), shown)
end

local function testNewerLeadAndAutoHide()
  local ns = UiFixture.load({ leads = 3 })
  local leads = ns.Leads.List() -- newest first
  ns.AlertToast.Show(leads[3])
  Wow.clock.gettime = 60
  ns.AlertToast.Show(leads[2])
  -- The newer lead replaces the shown one and the badge counts the one it replaced.
  Assert.equal(ns.AlertToast.VisibleLead(), leads[2])
  Assert.equal(select(2, ns.AlertToast.VisibleLead()), 60)
  Assert.truthy(string.find(texts(), "+1 more", 1, true), texts())
  ns.AlertToast.Show(leads[1])
  Assert.truthy(string.find(texts(), "+2 more", 1, true), texts())
  Assert.equal(ns.AlertToast.more, 2)
  -- One auto-hide timer, however many alerts: it waits the toast duration from the last one.
  Assert.equal(pendingUpTo(TOAST_SECONDS), 1)
  Wow.clock.gettime = 50 + TOAST_SECONDS
  runTimersUpTo(TOAST_SECONDS)
  Assert.equal(toastFrame():IsShown(), true, "the last alert came at 60: 10 s left")
  Wow.clock.gettime = 60 + TOAST_SECONDS
  runTimersUpTo(TOAST_SECONDS)
  Assert.equal(toastFrame():IsShown(), false)
  Assert.equal(ns.AlertToast.VisibleLead(), nil)
  Assert.equal(ns.AlertToast.more, 0)
  -- The lead stays listed; the next alert starts a fresh badge.
  Assert.equal(ns.Leads.IsActive(leads[1].id), true)
  ns.AlertToast.Show(leads[1])
  Assert.falsy(string.find(texts(), "more", 1, true), texts())

  -- A lead dismissed elsewhere (keybind, leads window, expiry) takes its toast with it.
  ns.Leads.Dismiss(leads[1].id)
  Assert.equal(toastFrame():IsShown(), false)
  Assert.equal(ns.AlertToast.VisibleLead(), nil)
end

local function testClicks()
  -- §7.1 on the toast: left greets (shown 1 s, so §7.5 rule 3 lets it send), then the toast goes.
  local ns, _, calls = UiFixture.load({ leads = 1 })
  local lead = ns.Leads.Latest()
  ns.AlertToast.Show(lead)
  Wow.clock.gettime = 51
  Widgets.click(toastFrame(), "LeftButton")
  Assert.equal(UiFixture.callsTo(calls, "addon")[1][5], "Customer1-Draenor")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)
  Assert.equal(lead.greeted, true)
  Assert.equal(toastFrame():IsShown(), false)

  -- A left-click under 0.5 s after the toast appeared prefills instead (look before send).
  ns, _, calls = UiFixture.load({ leads = 1 })
  ns.AlertToast.Show(ns.Leads.Latest())
  Wow.clock.gettime = 50.2
  Widgets.click(toastFrame(), "LeftButton")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0)
  Assert.equal(#UiFixture.callsTo(calls, "prefill"), 1)

  -- Shift prefills, ctrl opens an empty whisper, right dismisses the lead.
  local keys = { shift = false, ctrl = false }
  local function withKeys()
    Wow.stub("IsShiftKeyDown", function()
      return keys.shift
    end)
    Wow.stub("IsControlKeyDown", function()
      return keys.ctrl
    end)
  end
  ns, _, calls = UiFixture.load({ leads = 1 })
  withKeys()
  lead = ns.Leads.Latest()
  keys.shift = true
  ns.AlertToast.Show(lead)
  Widgets.click(toastFrame(), "LeftButton")
  keys.shift, keys.ctrl = false, true
  ns.AlertToast.Show(lead)
  Widgets.click(toastFrame(), "LeftButton")
  Assert.same(UiFixture.callsTo(calls, "prefill"), { { "prefill", "Customer1-Draenor", "Hi! I have Blacksmithing, what do you need?" } })
  Assert.same(UiFixture.callsTo(calls, "empty"), { { "empty", "Customer1-Draenor" } })
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0)
  keys.ctrl = false
  ns.AlertToast.Show(lead)
  Widgets.click(toastFrame(), "RightButton")
  Assert.equal(ns.Leads.IsActive(lead.id), false)
  Assert.equal(toastFrame():IsShown(), false)
end

-- `/ca test` makes a real lead now: there is no separate test toast, and the message line is the
-- lead's own message (trimmed), never a greeting.
local function testNoTestToast()
  local ns = UiFixture.load({ leads = 1 })
  Assert.equal(ns.AlertToast.ShowTest, nil)
  local lead = ns.Leads.Latest()
  ns.AlertToast.Show(lead)
  Assert.truthy(string.find(texts(), "LF plate belt", 1, true), texts())
  Assert.falsy(string.find(texts(), "Hi!", 1, true), texts())
  Assert.equal(fontStringWith("LF plate belt").text, "LF plate belt", "the message is the trimmed lead.message")
  Assert.equal(ns.AlertToast.VisibleLead(), lead)
end

local function loadTestLeads(count)
  local ns, _, calls = UiFixture.load({ leads = count })
  local leads = ns.Leads.List() -- newest first
  for _, lead in ipairs(leads) do
    lead.test = true
  end
  return ns, leads, calls
end

local function testRealPathTestLead()
  -- A lead flagged `test` by Leads.OnMatch is badged "Test" and clicks through ClickRouter.
  local ns, leads, calls = loadTestLeads(1)
  ns.AlertToast.Show(leads[1])
  Assert.truthy(string.find(texts(), "Test", 1, true), texts())
  Wow.clock.gettime = 51
  Widgets.click(toastFrame(), "LeftButton")
  Assert.equal(leads[1].greeted, true)
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0, "a test lead never reaches a send API")
  Assert.equal(toastFrame():IsShown(), false)

  -- Replacements keep the badge and count: "Test · +2 more".
  ns, leads = loadTestLeads(3)
  ns.AlertToast.Show(leads[3])
  ns.AlertToast.Show(leads[2])
  ns.AlertToast.Show(leads[1])
  Assert.truthy(string.find(texts(), "Test · +2 more", 1, true), texts())
  Assert.equal(ns.AlertToast.more, 2)

  -- A real lead after a test lead shows "+1 more" and no "Test".
  ns, leads = loadTestLeads(2)
  leads[1].test = nil
  ns.AlertToast.Show(leads[2])
  ns.AlertToast.Show(leads[1])
  Assert.truthy(string.find(texts(), "+1 more", 1, true), texts())
  Assert.falsy(string.find(texts(), "Test", 1, true), texts())
end

local function testClassColor()
  local looked = {}
  local function withGuid(guid, noColors)
    local ns = UiFixture.load({
      leads = 1,
      db = function(accountDb)
        accountDb.leads[1].guid = guid
      end,
    })
    Wow.stub("GetPlayerInfoByGUID", function(value)
      looked[#looked + 1] = value
      return "Warrior", "WARRIOR"
    end)
    Wow.stub("RAID_CLASS_COLORS", not noColors and { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } } or nil)
    ns.AlertToast.Show(ns.Leads.Latest())
    return fontStringWith("Customer1-Draenor").textColor
  end
  Assert.same(withGuid("Player-1-0001"), { 0.78, 0.61, 0.43, 1 })
  Assert.same(looked, { "Player-1-0001" })
  -- Leads already drop a secret GUID; the toast guards again and never passes one on.
  local plain = withGuid(Wow.secret("Player-1-0002"))
  Assert.same(looked, { "Player-1-0001" })
  Assert.same(plain, { 0.92, 0.92, 0.95, 1.0 })
  Assert.same(withGuid(nil), plain)
  -- No colour table: plain name, and the class API is not called at all.
  Assert.same(withGuid("Player-1-0003", true), plain)
  Assert.same(looked, { "Player-1-0001" })
end

local function testSavedPosition()
  local ns, db = UiFixture.load({ leads = 1 })
  ns.AlertToast.Show(ns.Leads.Latest())
  local frame = toastFrame()
  frame.scripts.OnDragStart(frame)
  Assert.equal(frame.moving, true)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", rawget(_G, "UIParent"), "TOPLEFT", 100, -50)
  frame.scripts.OnDragStop(frame)
  Assert.same(db.ui.toast, { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -50 })

  -- After a /reload the toast opens where it was dropped.
  local saved = db.ui.toast
  ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.ui.toast = saved
    end,
  })
  ns.AlertToast.Show(ns.Leads.Latest())
  local point, _, relativePoint, x, y = toastFrame():GetPoint()
  Assert.same({ point, relativePoint, x, y }, { "TOPLEFT", "TOPLEFT", 100, -50 })
end

return function()
  testLazyFrameAndContent()
  testNewerLeadAndAutoHide()
  testClicks()
  testNoTestToast()
  testRealPathTestLead()
  testClassColor()
  testSavedPosition()
  Wow.reset()
end
