local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local TOAST_SECONDS = 20 -- the default toast duration

-- A real Trade line from CraftAlertProbe.lua (runs[*].chat[*].text): 254 visible characters,
-- 3 item: and 6 trade: links.
local CORPUS =
  [=[LFW All Items Crafting MAX Rank R5 Guarantee 100% [PVP 276-344 PVE 292-331 ]  |cffffd000|Htrade:Player-1305-0D49F592:2018:164|h[Blacksmithing]|h|r |cffffd000|Htrade:Player-3391-0CF6BD98:25229:755|h[Jewelcrafting]|h|r |cffffd000|Htrade:Player-1305-0D72650B:2108:165|h[Leatherworking]|h|r |cffffd000|Htrade:Player-3391-0CC42D6C:45357:773|h[Inscription]|h|r |cffffd000|Htrade:Player-1403-0B312ED9:3908:197|h[Tailoring]|h|r |cffffd000|Htrade:Player-1403-0B312ED9:4036:202|h[Engineering]|h|r |cnIQ4:|Hitem:245770::::::::70:62::13:1:3524:2:40:2907:38:8:::::|h[Aln'hara Cane |A:Professions-ChatIcon-Quality-Tier5:17:15::1|a]|h|r|cnIQ4:|Hitem:240949::::::::70:62::13:1:3524:4:40:3122:38:8:46:274476:48:245786:::::|h[Masterwork Sin'dorei Band |A:Professions-ChatIcon-Quality-Tier5:17:15::1|a]|h|r|cnIQ4:|Hitem:244576::::::::70:62::13:1:3524:6:40:4006:38:8:47:274476:48:240167:49:245786:50:-2147480202:::::|h[Silvermoon Agent's Deflectors |A:Professions-ChatIcon-Quality-Tier5:17:15::1|a]|h|r/w Me 4info]=]

local function toastFrame()
  return rawget(_G, "CraftAlertToast")
end

-- The toast font strings using this font object, in creation order (name, then headline, share
-- GameFontNormal).
local function part(font)
  local found = {}
  for _, region in ipairs(toastFrame().regions) do
    if region.font == font then
      found[#found + 1] = region
    end
  end
  return found
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
  Assert.equal(frame.template, "TooltipBackdropTemplate")
  Assert.equal(frame:GetWidth(), 320)
  -- Customer, the headline and the trimmed message; the crafter and the why stay off the face.
  local shown = texts()
  for _, part in ipairs({ "Customer1-Draenor", "LF plate belt", "Wants Blacksmithing — you have it" }) do
    Assert.truthy(string.find(shown, part, 1, true), part .. " missing from: " .. shown)
  end
  Assert.falsy(string.find(shown, "lf + blacksmith", 1, true), "why left the face")
  Assert.falsy(string.find(shown, "Me-Realm", 1, true))
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
  local link = "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r"
  ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      local record = accountDb.leads[1]
      record.kind, record.itemLink, record.cannotOrder = "item", link, true
    end,
  })
  ns.AlertToast.Show(ns.Leads.Latest())
  shown = texts()
  Assert.truthy(string.find(shown, "Wants " .. link .. " — you can craft it", 1, true), shown)
  Assert.truthy(string.find(shown, "can't order (realm)", 1, true), shown)
  Assert.falsy(string.find(shown, "R2", 1, true), "no rank, no R part: " .. shown)

  -- §4.5: the rank sits on the detail line; the crafter is not drawn.
  ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.leads[1].rank, accountDb.leads[1].rankConc = 2, true
    end,
  })
  ns.AlertToast.Show(ns.Leads.Latest())
  Assert.truthy(string.find(texts(), "R2 (conc)", 1, true), texts())
  Assert.falsy(string.find(texts(), "by Me-Realm", 1, true), texts())
end

local function testDetailLine()
  local ns = UiFixture.load({ leads = 1 })
  ns.AlertToast.Show(ns.Leads.Latest())
  local detail = part("GameFontDisableSmall")[1]
  Assert.equal(detail:IsShown(), false, "no rank, no realm tag: the line is hidden")
  Assert.falsy(string.find(texts(), "·", 1, true))
  ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.leads[1].rank, accountDb.leads[1].rankConc, accountDb.leads[1].cannotOrder = 2, true, true
    end,
  })
  ns.AlertToast.Show(ns.Leads.Latest())
  Assert.equal(part("GameFontDisableSmall")[1].text, "R2 (conc) · can't order (realm)")
end

local function testHeight()
  local ns = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.leads[1].message = CORPUS
    end,
  })
  local short = UiFixture.load({ leads = 1 })
  short.AlertToast.Show(short.Leads.Latest())
  local shortHeight = toastFrame():GetHeight()
  ns.AlertToast.Show(ns.Leads.Latest())
  local frame = toastFrame()
  local message -- the badge shares GameFontHighlightSmall, so pick the string holding the message
  for _, candidate in ipairs(part("GameFontHighlightSmall")) do
    if candidate.text == CORPUS then
      message = candidate
    end
  end
  Assert.equal(message.text, CORPUS)
  Assert.truthy(message:GetStringHeight() >= 5 * Widgets.LINE_HEIGHT, "254 visible characters wrap past one line")
  Assert.truthy(frame:GetHeight() > shortHeight, "the toast grows")
  -- Spec §4.3: PADDING + name + gap + headline + gap + message + PADDING (no detail line).
  local name, headline = part("GameFontNormal")[1], part("GameFontNormal")[2]
  Assert.equal(frame:GetHeight(), 8 + name:GetStringHeight() + 3 + headline:GetStringHeight() + 3 + message:GetStringHeight() + 8)
  Assert.equal(message:GetWidth(), 320 - 2 * 8)
end

local function testTooltip()
  local ns = UiFixture.load({ leads = 1 })
  ns.AlertToast.Show(ns.Leads.Latest())
  local frame, tip = toastFrame(), rawget(_G, "GameTooltip")
  frame.scripts.OnEnter(frame)
  Assert.same({ tip.owner, tip.anchor, tip.shown }, { frame, "ANCHOR_TOP", true })
  Assert.same(tip.lines, { "Craft Alert", "Matched: lf + blacksmith", "Click: greet · Shift: edit first · Ctrl: empty whisper · Right: dismiss" })
  frame.scripts.OnLeave(frame)
  Assert.equal(tip.shown, false)
  ns.Leads.Latest().why = ""
  ns.AlertToast.Show(ns.Leads.Latest())
  frame.scripts.OnEnter(frame)
  Assert.same(tip.lines, { "Craft Alert", "Click: greet · Shift: edit first · Ctrl: empty whisper · Right: dismiss" })
end

local function testLinks()
  local ns, _, calls = UiFixture.load({ leads = 2 })
  local tip = rawget(_G, "GameTooltip")
  local leads = ns.Leads.List() -- newest first
  leads[2].message = CORPUS
  ns.AlertToast.Show(leads[2])
  local frame = toastFrame()
  local links = {}
  for link in string.gmatch(CORPUS, "|H(item:[^|]*)|h") do
    links[#links + 1] = link
  end
  Assert.equal(#links, 3)
  -- Every item link in the real line is hoverable, in order.
  for _, link in ipairs(links) do
    frame.scripts.OnHyperlinkEnter(frame, link, "[x]")
    Assert.equal(tip.hyperlinks[#tip.hyperlinks], link)
    frame.scripts.OnHyperlinkLeave(frame)
  end
  -- Review Focus 2: a click on a hovered link does nothing; after the link leave it greets.
  Wow.clock.gettime = 51
  local before = #calls -- the sound and flash of Show
  frame.scripts.OnHyperlinkEnter(frame, links[1], "[x]")
  Widgets.click(frame, "LeftButton")
  Assert.equal(#calls, before, "no greet, prefill or dismissal while over a link")
  Assert.equal(frame:IsShown(), true)
  frame.scripts.OnHyperlinkLeave(frame)
  -- A new lead replaces the toast while the cursor is on a link: tooltip and hover state are gone.
  frame.scripts.OnHyperlinkEnter(frame, links[2], "[x]")
  Assert.equal(tip.shown, true)
  ns.AlertToast.Show(leads[1])
  Assert.same({ ns.LinkHover.IsOverLink(frame), tip.shown }, { false, false })
  Wow.clock.gettime = 52
  Widgets.click(frame, "LeftButton")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1, "the next plain click greets the new lead")
  Assert.equal(leads[1].greeted, true)
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

local ROWS = { -- launcher centre, toast point → launcher point, x
  { 100, 900, "TOPLEFT", "TOPRIGHT", 8 },
  { 100, 100, "BOTTOMLEFT", "BOTTOMRIGHT", 8 },
  { 1800, 900, "TOPRIGHT", "TOPLEFT", -8 },
  { 1800, 100, "BOTTOMRIGHT", "BOTTOMLEFT", -8 },
}

local function dockedAt(frame, launcher, row)
  local point, relativeTo, relativePoint, x, y = frame:GetPoint()
  Assert.truthy(rawequal(relativeTo, launcher))
  Assert.same({ point, relativePoint, x, y }, { row[3], row[4], row[5], 0 })
end

local function testDock()
  for _, row in ipairs(ROWS) do
    local ns = UiFixture.load({ leads = 1 })
    ns.ScanGate.IsActive = function()
      return true
    end
    local launcher = ns.Launcher.Create()
    launcher.center = { row[1], row[2] }
    ns.AlertToast.Show(ns.Leads.Latest())
    dockedAt(toastFrame(), launcher, row)
  end

  -- Drag: the toast moves the launcher, the drop saves ui.launcher and re-docks; ui.toast is untouched.
  local ns, db = UiFixture.load({
    leads = 1,
    db = function(accountDb)
      accountDb.ui.toast = { point = "BOTTOM", relativePoint = "BOTTOM", x = 5, y = 5 }
    end,
  })
  ns.ScanGate.IsActive = function()
    return true
  end
  local launcher = ns.Launcher.Create()
  ns.Launcher.OnMoved(ns.AlertToast.Dock)
  ns.AlertToast.Show(ns.Leads.Latest())
  local frame = toastFrame()
  Assert.equal(frame:GetPoint(), "TOPLEFT", "nil centres: left/upper; the saved ui.toast is ignored")
  frame.scripts.OnDragStart(frame)
  Assert.equal(launcher.moving, true)
  launcher:ClearAllPoints()
  launcher:SetPoint("BOTTOMRIGHT", rawget(_G, "UIParent"), "BOTTOMRIGHT", -20, 80)
  launcher.center = { 1800, 100 }
  frame.scripts.OnDragStop(frame)
  Assert.equal(launcher.moving, false)
  Assert.same(db.ui.launcher, { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -20, y = 80 })
  dockedAt(frame, launcher, ROWS[4])
  Assert.same(db.ui.toast, { point = "BOTTOM", relativePoint = "BOTTOM", x = 5, y = 5 }, "ui.toast neither read nor written")
  -- The launcher's own drop re-docks too.
  launcher.center = { 100, 900 }
  launcher.scripts.OnDragStop(launcher)
  dockedAt(frame, launcher, ROWS[1])

  -- No launcher yet: the fixed spot on UIParent. Dock before the toast exists does nothing.
  ns = UiFixture.load({ leads = 1 })
  ns.AlertToast.Dock()
  Assert.equal(toastFrame(), nil)
  ns.AlertToast.Show(ns.Leads.Latest())
  local point, relativeTo, relativePoint, x, y = toastFrame():GetPoint()
  Assert.truthy(rawequal(relativeTo, rawget(_G, "UIParent")))
  Assert.same({ point, relativePoint, x, y }, { "TOP", "TOP", 0, -160 })
end

local function testHiddenLauncherAndPulse()
  -- Review Focus 3: "Hide when no leads", launcher hidden, first lead arrives.
  local ns, db = UiFixture.load({ leads = 1 })
  db.settings.hideLauncherWhenNoLeads = true
  local active = false
  ns.ScanGate.IsActive = function()
    return true
  end
  ns.Leads.HasActive = function()
    return active
  end
  local launcher = ns.Launcher.Create()
  -- Bootstrap subscribes Launcher.Refresh to "change" at login, before the toast subscribes on
  -- its first alert. Once shown, the launcher has a centre: the right half, like its default spot.
  ns.Leads.On("change", function()
    ns.Launcher.Refresh()
    launcher.center = { 1800, 900 }
  end)
  Assert.equal(launcher:IsShown(), false)
  ns.AlertToast.Show(ns.Leads.Latest()) -- GetCenter() is nil: no error, left/upper row
  dockedAt(toastFrame(), launcher, ROWS[1])
  active = true
  ns.Leads.MarkGreeted(ns.Leads.Latest().id) -- a "change", as the one fired after "new"
  Assert.equal(launcher:IsShown(), true)
  dockedAt(toastFrame(), launcher, ROWS[3])

  -- Pulse and glow: a new lead starts them, the hide (timer, click or dismissal) stops the glow.
  Assert.same({ launcher.pulseOnce:IsPlaying(), launcher.pulseLoop:IsPlaying() }, { true, true })
  Wow.clock.gettime = 50 + TOAST_SECONDS
  runTimersUpTo(TOAST_SECONDS)
  Assert.equal(toastFrame():IsShown(), false)
  Assert.equal(launcher.pulseLoop:IsPlaying(), false)
end

return function()
  testLazyFrameAndContent()
  testDetailLine()
  testHeight()
  testTooltip()
  testLinks()
  testNewerLeadAndAutoHide()
  testClicks()
  testNoTestToast()
  testRealPathTestLead()
  testClassColor()
  testDock()
  testHiddenLauncherAndPulse()
  Wow.reset()
end
