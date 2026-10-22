local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SlashFixture = require("tests.helpers.slash_fixture")

local LEADS_WINDOW, SETTINGS_WINDOW, TOAST = "CraftAlertLeadsWindow", "CraftAlertSettingsWindow", "CraftAlertToast"
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

local function testRegister()
  local _, _, _, handler = setup()
  Assert.equal(rawget(_G, "SLASH_CRAFTALERT1"), "/craftalert")
  Assert.equal(rawget(_G, "SLASH_CRAFTALERT2"), "/ca")
  Assert.equal(type(handler), "function")
  Assert.same(Wow.timers, {}, "registering arms no timer")
end

-- `/ca` toggles the leads window, `/ca config` the settings window; both lazily created.
local function testWindows()
  local _, _, _, handler = setup()
  Assert.equal(rawget(_G, LEADS_WINDOW), nil, "no window before the first command")
  handler("")
  Assert.equal(shown(LEADS_WINDOW), true)
  handler("   ")
  Assert.equal(shown(LEADS_WINDOW), false)
  Assert.equal(shown(SETTINGS_WINDOW), false)
  handler("config")
  Assert.equal(shown(SETTINGS_WINDOW), true)
  handler("  CONFIG ")
  Assert.equal(shown(SETTINGS_WINDOW), false, "case and spaces do not matter")
end

-- §7.3: steps 2-5 on the text as "Test" on the own realm; it prints the result, why, crafter and
-- greeting, shows a test toast and creates no lead, no ledger count, no send, no sound.
local function testTestCommand()
  local ns, db, calls, handler = setup()
  Wow.stub("C_FriendList", {
    IsIgnored = function()
      return true
    end,
  })
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
  Assert.truthy(string.find(toastTexts(), "Test", 1, true), toastTexts())
  Assert.truthy(string.find(toastTexts(), GREETING, 1, true), toastTexts())
  Assert.same({ #db.leads, #ns.Leads.List(), ns.Leads.HasActive() }, { 0, 0, false })
  Assert.same(db.ledger, ledger, "no ledger count")
  Assert.same(calls, {}, "nothing sent, no sound or flash")
  Assert.equal(ns.AlertToast.VisibleLead(), nil, "the test toast is no lead")

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

local function testTestCommandStops()
  local _, db, _, handler = setup()
  handler("test hello there")
  Assert.same(SlashFixture.chat(), { "No match (stopped at: prefilter)" })
  Assert.equal(rawget(_G, TOAST), nil, "no toast for a line that stopped")
  Wow.chat = {}
  handler("test")
  Assert.same(SlashFixture.chat(), { "Usage: /ca test <a trade chat line>" })

  -- Matched, but every crafter is switched off since the index was built.
  for _, character in pairs(db.characters) do
    character.enabled = false
  end
  Wow.chat = {}
  handler("test any enchanters")
  Assert.same(SlashFixture.chat(), { "Matched, but none of your enabled characters can answer it" })
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

return function()
  testRegister()
  testWindows()
  testTestCommand()
  testTestCommandStops()
  testPerfAndHelp()
  Wow.reset()
end
