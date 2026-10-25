local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local SlashFixture = require("tests.helpers.slash_fixture")

local LEADS_WINDOW, TOAST = "CraftAlertLeadsWindow", "CraftAlertToast"
local GREETING = "Hi! My alt Ench can craft Enchant Weapon - Mongoose, send the order there."

-- The loaded chain with /ca registered on a fresh SlashCmdList. → ns, db, calls, handler.
local function setup()
  local ns, db, calls = SlashFixture.load()
  Wow.stub("SlashCmdList", {})
  Wow.stub("SLASH_CRAFTALERT1", nil)
  Wow.stub("SLASH_CRAFTALERT2", nil)
  ns.SlashCommands.Register()
  return ns, db, calls, rawget(_G, "SlashCmdList").CRAFTALERT
end

local function shown(name)
  local frame = rawget(_G, name)
  return frame ~= nil and frame:IsShown()
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

local function testRegister()
  local _, _, _, handler = setup()
  Assert.equal(rawget(_G, "SLASH_CRAFTALERT1"), "/craftalert")
  Assert.equal(rawget(_G, "SLASH_CRAFTALERT2"), "/ca")
  Assert.equal(type(handler), "function")
  Assert.same(Wow.timers, {}, "registering arms no timer")
end

-- `/ca` toggles the leads window on its list, `/ca config` on its settings pane; lazily created.
local function testWindows()
  local _, _, _, handler = setup()
  local function title()
    return rawget(_G, LEADS_WINDOW):GetTitleText():GetText()
  end
  Assert.equal(rawget(_G, LEADS_WINDOW), nil, "no window before the first command")
  handler("")
  Assert.equal(shown(LEADS_WINDOW), true)
  handler("   ")
  Assert.equal(shown(LEADS_WINDOW), false)
  handler("config")
  Assert.equal(shown(LEADS_WINDOW), true)
  Assert.equal(title(), "Craft Alert — Settings")
  handler("  CONFIG ")
  Assert.equal(shown(LEADS_WINDOW), false, "case and spaces do not matter")
  handler("")
  Assert.equal(shown(LEADS_WINDOW), true)
  Assert.equal(title(), "Craft Alert — Leads")
end

-- §7.3: the text goes through the real path as customer Test0 on the own realm. It makes a test
-- lead (toast badged "Test"), prints what matched, why, the crafter and the greeting, and
-- sends nothing.
local function testTestCommand()
  local ns, db, calls, handler = setup()
  local ledger = {}
  for key, value in pairs(db.ledger) do
    ledger[key] = value
  end
  Wow.chat = {}
  handler("test LF mongoose")
  Assert.same(SlashFixture.chat(), {
    "Item: Enchant Weapon - Mongoose",
    "Why: lf + mongoose",
    "Crafter: Ench-Realm",
    "Greeting: " .. GREETING,
  })
  local lead = ns.Leads.Latest()
  Assert.same({ lead.test, lead.customer, #ns.Leads.List() }, { true, "Test0-Realm", 1 })
  Assert.equal(ns.AlertToast.VisibleLead(), lead)
  Assert.truthy(toastShows("Test"), toastTexts())
  Assert.truthy(string.find(toastTexts(), "LF mongoose", 1, true), toastTexts())
  Assert.same(db.ledger, ledger, "no ledger count")
  for _, api in ipairs({ "addon", "chat", "prefill", "empty" }) do
    Assert.equal(#UiFixture.callsTo(calls, api), 0, api)
  end

  -- A profession word names the profession; text keeps its spaces and case.
  Wow.chat = {}
  handler("test   Any Enchanters in ORG?  ")
  Assert.same(SlashFixture.chat(), {
    "Profession: 333",
    "Why: any + enchanters",
    "Crafter: Ench-Realm",
    "Greeting: Hi! My alt Ench has 333, what do you need?",
  })
end

-- The ignore list is the real one: an ignored Test0 makes no lead and says so.
local function testTestCommandIgnored()
  local ns, _, _, handler = setup()
  Wow.stub("C_FriendList", {
    IsIgnored = function()
      return true
    end,
  })
  Wow.chat = {}
  handler("test LF mongoose")
  Wow.stub("C_FriendList", nil)
  Assert.same(SlashFixture.chat(), {
    "Matched, but none of your enabled characters can answer it, or the customer is on your ignore list",
  })
  Assert.same({ #ns.Leads.List(), rawget(_G, TOAST) }, { 0, nil })
end

local function testTestCommandStops()
  local _, db, _, handler = setup()
  handler("test hello there")
  Assert.same(SlashFixture.chat(), { "No match (stopped at: prefilter)" })
  Assert.equal(rawget(_G, TOAST), nil, "no toast for a line that stopped")
  Wow.chat = {}
  handler("test")
  Assert.same(SlashFixture.chat(), { "Usage: /ca test [as <class>] [x<N>] <a trade chat line> | /ca test reply" })

  -- Matched, but every crafter is switched off since the index was built.
  for _, character in pairs(db.characters) do
    character.enabled = false
  end
  Wow.chat = {}
  handler("test any enchanters")
  Assert.same(SlashFixture.chat(), {
    "Matched, but none of your enabled characters can answer it, or the customer is on your ignore list",
  })
  Assert.equal(rawget(_G, TOAST), nil)
end

-- `/ca perf` starts and stops the timed handler; anything unknown lists the commands.
local function testPerfAndHelp()
  local ns, _, _, handler = setup()
  Wow.stub("debugprofilestop", function()
    return 0
  end)
  handler("perf")
  Assert.equal(ns.Perf.IsRunning(), true)
  handler("perf")
  Assert.equal(ns.Perf.IsRunning(), false)
  Wow.chat = {}
  handler("nonsense")
  Assert.same(SlashFixture.chat(), { "Commands: /ca (leads window), /ca config, /ca test <line>, /ca perf" })
  Assert.equal(ns.Perf.IsRunning(), false)
end

-- In an instance every form of /ca does nothing but print the off line once.
local function testOffInInstance()
  local ns, _, _, handler = setup()
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  Wow.stub("debugprofilestop", function()
    return 0
  end)
  for _, message in ipairs({ "", "config", "test LF plate belt", "perf", "nonsense" }) do
    Wow.chat = {}
    handler(message)
    Assert.same(SlashFixture.chat(), { "Off in instances; it works again when you leave." }, "/ca " .. message)
  end
  Assert.equal(shown(LEADS_WINDOW), false)
  Assert.equal(#ns.Leads.List(), 0, "/ca test made no lead")
  Assert.equal(ns.Perf.IsRunning(), false)
  Wow.stub("IsInInstance", nil)
end

return function()
  testRegister()
  testOffInInstance()
  testWindows()
  testTestCommand()
  testTestCommandIgnored()
  testTestCommandStops()
  testPerfAndHelp()
  Wow.reset()
end
