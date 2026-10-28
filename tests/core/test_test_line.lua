local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Fixture = require("tests.helpers.matcher_fixture")
local UiFixture = require("tests.helpers.ui_fixture")
local SlashFixture = require("tests.helpers.slash_fixture")

local TOAST = "CraftAlertToast"
local USAGE = "Usage: /ca test [as <class>] [x<N>] <a trade chat line> | /ca test reply"
local PAUSED_RESTING = "Test: Paused — no Trade chat here, a real Trade line would be ignored too"
local MATCHED_NO_ONE = "Matched, but none of your enabled characters can answer it, or the customer is on your ignore list"
local UPDATED = "Updated the existing test lead (same customer asked again)"

-- The default SlashFixture recipes have no item IDs; this crafter owns the plate (501), leather
-- (701) and cloth (601) belts. → ns, db, calls, the /ca handler.
local function load()
  local ns, db, calls = SlashFixture.load({
    db = function(accountDb)
      Fixture.stubItems()
      accountDb.characters["Armor-Realm"] = Fixture.character({ Fixture.BS, Fixture.LW, Fixture.TAILOR }, {
        [501] = { item = 501, name = "Korvath Cinch", prof = Fixture.BS },
        [701] = { item = 701, name = "Hidemaw Strap", prof = Fixture.LW },
        [601] = { item = 601, name = "Silkveil Sash", prof = Fixture.TAILOR },
      })
    end,
  })
  Wow.stub("SlashCmdList", {})
  ns.SlashCommands.Register()
  return ns, db, calls, rawget(_G, "SlashCmdList").CRAFTALERT
end

local function run(handler, args)
  Wow.chat = {}
  handler("test " .. args)
  return SlashFixture.chat()
end

local function toastTexts()
  return table.concat(Widgets.texts(rawget(_G, TOAST), Wow.frames), " / ")
end

-- Whether the toast has a font string showing exactly `text` (the badge, not the customer name).
local function toastShows(text)
  for _, shown in ipairs(Widgets.texts(rawget(_G, TOAST), Wow.frames)) do
    if shown == text then
      return true
    end
  end
  return false
end

local function classOf(ns, lead)
  return ns.FlavorCompat.ClassOf(lead.guid)
end

-- A new test lead: flagged, "Test0-Realm", the four report lines, a toast badged "Test"; the
-- same line again updates that lead and shows no second toast.
local function testNewAndRepeat()
  local ns, _, calls, handler = load()
  local lines = run(handler, "LF plate belt")
  local lead = ns.Leads.Latest()
  Assert.same({ #ns.Leads.List(), lead.test, lead.customer, lead.itemID }, { 1, true, "Test0-Realm", 501 })
  Assert.same({ lead.guid, lead.crafter }, { "Player-0-CRAFTALERTTEST1", "Armor-Realm" })
  Assert.equal(#lines, 4, table.concat(lines, " | "))
  Assert.equal(string.sub(lines[1], 1, 6), "Item: ")
  Assert.same({ lines[2], lines[3] }, { "Why: lf + plate + belt", "Crafter: Armor-Realm" })
  Assert.equal(string.sub(lines[4], 1, 10), "Greeting: ")
  Assert.truthy(toastShows("Test"), toastTexts())
  Assert.equal(ns.AlertToast.VisibleLead(), lead)
  Assert.equal(#UiFixture.callsTo(calls, "sound"), 1)

  lines = run(handler, "LF plate belt")
  Assert.equal(#lines, 5, table.concat(lines, " | "))
  Assert.equal(lines[5], UPDATED)
  Assert.same({ #ns.Leads.List(), ns.Leads.Latest() }, { 1, lead })
  Assert.equal(#UiFixture.callsTo(calls, "sound"), 1, "no second toast")
  Assert.equal(lead.guid, "Player-0-CRAFTALERTTEST1", "the update keeps the first guid")
end

-- The real gate runs first: a paused scan or a switched-off Trade ignores a real line, so it
-- ignores the test line too.
local function testGate()
  local ns, db, _, handler = load()
  Wow.stub("IsResting", function()
    return false
  end)
  Assert.same(run(handler, "LF plate belt"), { PAUSED_RESTING })
  Assert.equal(#ns.Leads.List(), 0)

  Wow.stub("IsResting", function()
    return true
  end)
  db.settings.channels.trade = false
  Assert.same(run(handler, "LF plate belt"), { "Test: Trade is off in channel settings, a real Trade line would be ignored too" })
  Assert.equal(#ns.Leads.List(), 0)
end

local function testStops()
  local ns, _, _, handler = load()
  Assert.same(run(handler, "hello"), { "No match: the line does not look like a request" })
  Assert.same(run(handler, "xmog belt"), { "No match: the line does not look like a request" }, "an x word that is no burst is line text")
  Assert.equal(rawget(_G, TOAST), nil)

  -- Matched, but the customer is on Blizzard's ignore list: no lead.
  Wow.stub("C_FriendList", {
    IsIgnored = function()
      return true
    end,
  })
  Assert.same(run(handler, "LF plate belt"), { MATCHED_NO_ONE })
  Wow.stub("C_FriendList", nil)
  Assert.same({ #ns.Leads.List(), rawget(_G, TOAST) }, { 0, nil })
end

-- Test1..TestN for a burst; the toast counts the replaced ones.
local function testBurst()
  local ns, _, _, handler = load()
  local lines = run(handler, "x3 LF plate belt")
  local customers = {}
  for i, lead in ipairs(ns.Leads.List()) do
    customers[4 - i] = lead.customer
  end
  Assert.same(customers, { "Test1-Realm", "Test2-Realm", "Test3-Realm" })
  Assert.equal(#lines, 12, "three reports of four lines")
  Assert.equal(ns.AlertToast.more, 2)
  Assert.truthy(toastShows("Test · +2 more"), toastTexts())
  -- The burst letter is case-insensitive; Test1 and Test2 ask for another belt, so new leads, and
  -- the guid counter runs on across commands.
  run(handler, "as druid X2 LF belt")
  local latest = ns.Leads.Latest()
  Assert.same({ latest.customer, latest.guid, latest.itemID }, { "Test2-Realm", "Player-0-CRAFTALERTTEST5", 701 })
  Assert.equal(#ns.Leads.List(), 5)
end

-- A test toast already up, then a burst of new leads: the badge counts all three it replaced.
local function testBurstOverShownToast()
  local ns, _, _, handler = load()
  run(handler, "LF plate belt")
  Assert.truthy(toastShows("Test"), toastTexts())
  run(handler, "x3 LF plate belt")
  Assert.equal(#ns.Leads.List(), 4)
  Assert.equal(ns.AlertToast.more, 3)
  Assert.truthy(toastShows("Test · +3 more"), toastTexts())
end

local function testUsage()
  local ns, _, _, handler = load()
  for _, args in ipairs({ "", "   ", "as", "as   ", "x1 LF belt", "x0 LF belt", "x7 LF belt", "x3", "x3   ", "as warrior", "as warrior x3" }) do
    Assert.same(run(handler, args), { USAGE }, "args: " .. args)
  end
  Assert.equal(#ns.Leads.List(), 0, "usage makes no lead")
end

local function testClass()
  local ns, _, _, handler = load()
  run(handler, "as druid LF belt")
  Assert.same({ ns.Leads.Latest().itemID, classOf(ns, ns.Leads.Latest()) }, { 701, "DRUID" })

  -- Different classes asking for "a belt" from one customer: two leads, each painted as asked.
  ns, _, _, handler = load()
  run(handler, "as warrior LF belt")
  run(handler, "AS Priest LF belt")
  local priest, warrior = ns.Leads.List()[1], ns.Leads.List()[2]
  Assert.same({ warrior.itemID, classOf(ns, warrior) }, { 501, "WARRIOR" })
  Assert.same({ priest.itemID, classOf(ns, priest) }, { 601, "PRIEST" })
  Assert.same({ #ns.Leads.List(), warrior.customer, priest.customer }, { 2, "Test0-Realm", "Test0-Realm" })

  -- The error lists the classes in armor order and does nothing.
  local count = #ns.Leads.List()
  local lines = run(handler, "as wizard LF belt")
  Assert.same(lines, { "Unknown class wizard. Classes: " .. table.concat(ns.ClassArmor.Tokens(), ", ") })
  Assert.truthy(string.find(lines[1], "Classes: WARRIOR, PALADIN, DEATHKNIGHT, ", 1, true), lines[1])
  Assert.equal(#ns.Leads.List(), count)

  -- The order is fixed: the burst comes after `as`, so before it the words are line text.
  ns, _, _, handler = load()
  run(handler, "x3 as warrior LF belt")
  Assert.equal(ns.Leads.Latest().message, "as warrior LF belt")
  Assert.equal(#ns.Leads.List(), 3)
end

-- The update keeps the lead's first guid but the Matcher reads the new line's guid: the lead's
-- class follows the line, so what is painted is what was matched.
local function testRepeatKeepsClassInSync()
  local ns, _, _, handler = load()
  run(handler, "as warrior LF plate belt")
  local lead = ns.Leads.Latest()
  Assert.equal(classOf(ns, lead), "WARRIOR")
  local lines = run(handler, "as priest LF plate belt")
  Assert.equal(lines[#lines], UPDATED)
  Assert.same({ #ns.Leads.List(), ns.Leads.Latest() == lead, classOf(ns, lead) }, { 1, true, "PRIEST" })

  -- A repeat without `as` has no class to sync: the lead keeps the one it has.
  run(handler, "LF plate belt")
  Assert.same({ #ns.Leads.List(), classOf(ns, lead) }, { 1, "PRIEST" })
end

-- No `as`: the line takes the player's class, so a repeat re-colours the lead to it. With no class
-- API the lead keeps the one it has (testRepeatKeepsClassInSync).
local function testDefaultsToOwnClass()
  local ns, _, _, handler = load()
  Wow.stub("UnitClass", function()
    return "Priest", "PRIEST"
  end)
  run(handler, "LF plate belt")
  local lead = ns.Leads.Latest()
  Assert.equal(classOf(ns, lead), "PRIEST", "no `as`")
  run(handler, "as warrior LF plate belt")
  Assert.equal(classOf(ns, lead), "WARRIOR", "explicit class")
  run(handler, "LF plate belt")
  Assert.same({ #ns.Leads.List(), classOf(ns, lead) }, { 1, "PRIEST" })
end

-- /ca perf counts the test line like any chat line.
local function testPerf()
  local ns, _, _, handler = load()
  local times = { 0, 100, 100.010, 200, 200.5 }
  local next = 0
  Wow.stub("debugprofilestop", function()
    next = next + 1
    return assert(times[next], "debugprofilestop called more often than scripted")
  end)
  Wow.stub("GetAddOnMemoryUsage", function()
    return 100
  end)
  ns.Perf.Start()
  run(handler, "LF plate belt")
  Assert.equal(next, 3, "the clock was read around the test line")
  ns.Perf.Stop()
end

-- A click on a test toast, and the keybinds, only print what they would do.
local function testNothingIsSent()
  local ns, _, calls, handler = load()
  local keys = { shift = false, ctrl = false }
  Wow.stub("IsShiftKeyDown", function()
    return keys.shift
  end)
  Wow.stub("IsControlKeyDown", function()
    return keys.ctrl
  end)
  run(handler, "LF plate belt")
  Wow.clock.gettime = 51
  local lines = {}
  Wow.chat = {}
  Widgets.click(rawget(_G, TOAST), "LeftButton")
  for _, line in ipairs(SlashFixture.chat()) do
    lines[#lines + 1] = line
  end
  Assert.truthy(string.find(table.concat(lines, "\n"), "Test, would whisper Test0-Realm", 1, true), table.concat(lines, "\n"))

  local function bursts(label)
    for _, api in ipairs({ "addon", "chat", "prefill", "empty" }) do
      Assert.equal(#UiFixture.callsTo(calls, api), 0, label .. " reached " .. api)
    end
  end
  bursts("left")
  run(handler, "x2 LF plate belt")
  keys.shift = true
  Widgets.click(rawget(_G, TOAST), "LeftButton")
  bursts("shift")
  -- Ctrl needs a fresh toast on a NEW lead (another item, so no update), past the click guard.
  keys.shift, keys.ctrl = false, true
  run(handler, "LF leather belt")
  Assert.equal(ns.Leads.Latest().itemID, 701, "a new lead, so a fresh toast")
  Wow.clock.gettime = 70
  Wow.chat = {}
  Widgets.click(rawget(_G, TOAST), "LeftButton")
  local ctrlLines = table.concat(SlashFixture.chat(), "\n")
  Assert.truthy(string.find(ctrlLines, "Test, would open an empty whisper to ", 1, true), ctrlLines)
  bursts("ctrl")
  keys.ctrl = false
  Wow.clock.gettime = 90
  rawget(_G, "CraftAlert_GreetLatest")()
  bursts("greet keybind")
  Wow.clock.gettime = 95
  rawget(_G, "CraftAlert_GreetLatest")()
  bursts("greet keybind again")
  Assert.truthy(ns.Leads.Latest().test)
  rawget(_G, "CraftAlert_DismissLatest")()
  bursts("dismiss keybind")
end

-- `/ca test reply` fakes the customer's whisper through WhisperTracker's real handler, but only
-- once a greeting went out, and for the newest test lead even when a real lead is newer.
local function testReply()
  local ns, _, _, handler = load()
  Assert.same(run(handler, "reply"), { "No test lead to reply from" })
  run(handler, "LF plate belt")
  local lead = ns.Leads.Latest()
  local replies = 0
  ns.Leads.On("replied", function()
    replies = replies + 1
  end)
  Assert.same(run(handler, "reply"), { "Greet the test lead first (a reply counts only after a greeting)" })
  Assert.same({ lead.replied, replies }, { false, 0 })

  Wow.clock.gettime = 51
  Widgets.click(rawget(_G, TOAST), "LeftButton")
  Assert.truthy(lead.greeted)
  SlashFixture.fireTrade("LF mongoose", "Bob-Draenor")
  Assert.equal(ns.Leads.Latest().test, nil, "a real lead is newest")
  Assert.same(run(handler, "reply"), {})
  Assert.same({ lead.replied, replies }, { true, 1 })
  run(handler, "reply")
  Assert.equal(replies, 1, "replied fires once")
end

return function()
  testNewAndRepeat()
  testGate()
  testStops()
  testBurst()
  testBurstOverShownToast()
  testUsage()
  testClass()
  testRepeatKeepsClassInSync()
  testDefaultsToOwnClass()
  testPerf()
  testNothingIsSent()
  testReply()
  Wow.reset()
end
