local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")
local Toc = require("tests.helpers.toc")

local T0 = 1000
local INFORM, WHISPER = "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_WHISPER"

-- Names the stubbed issecretvalue reports as secret (a real secret string still has type
-- "string", so only a plain string stub proves the guard comes before any use of it).
local secretNames = {}

-- Real Matcher over the fixture's item index and real Leads; the player is Me-Realm.
-- Install is left to the test. → ns, db.
local function setup(restored)
  local ns = Fixture.load("retail")
  Wow.clock.time = T0
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  local db
  Fixture.itemIndex(ns, function(captured)
    db = captured
  end)
  ns.PlayerName.Init()
  Wow.stub("issecretvalue", function(value)
    return secretNames[value] == true
  end)
  Fresh.require("Core.FlavorCompat")
  for _, name in ipairs({ "Model.RealmTag", "Model.CrafterRank", "Model.Leads", "Model.WhisperTracker" }) do
    ns[string.match(name, "%.(%w+)$")] = Fresh.require(name)
  end
  for i, customer in ipairs(restored or {}) do
    db.leads[i] = { id = i, customer = customer, time = T0, greeted = false, replied = false }
  end
  ns.Leads.Restore(db)
  return ns, db
end

local function newLead(ns, customer)
  local result = ns.Matcher.Match("trade", "LF plate belt", "Someone-Else")
  return ns.Leads.OnMatch(result, customer, "LF plate belt", "trade", nil)
end

-- Whether the addon's frame listens for the whisper events.
local function registered()
  local frame = Wow.frames[1]
  return frame ~= nil and frame:IsEventRegistered(INFORM), frame ~= nil and frame:IsEventRegistered(WHISPER)
end

return function()
  -- Whisper events follow the leads: none without a lead, both while one is unexpired.
  local ns = setup()
  ns.WhisperTracker.Install()
  Assert.same({ registered() }, { false, false }, "no lead, no whisper events")
  local lead = newLead(ns, "Bob-Draenor")
  Assert.same({ registered() }, { true, true })
  ns.Leads.Dismiss(lead.id)
  Assert.same({ registered() }, { false, false }, "the last lead is gone")
  newLead(ns, "Bob-Draenor")
  Assert.same({ registered() }, { true, true })
  Wow.clock.time = T0 + 11 * 60
  table.remove(Wow.timers, 1).fn() -- the expiry timer
  Assert.equal(ns.Leads.HasActive(), false)
  Assert.same({ registered() }, { false, false }, "expiry drops them too")

  -- Leads restored before Install still get whisper events.
  ns = setup({ "Bob-Draenor" })
  ns.WhisperTracker.Install()
  Assert.same({ registered() }, { true, true })

  -- A whisper to an active lead's customer marks it greeted once, however it was sent;
  -- the realm is added to a bare name.
  ns = setup({ "Bob-Realm", "Cy-Draenor" })
  local greeted = {}
  ns.Leads.On("greeted", function(l)
    greeted[#greeted + 1] = l.customer
  end)
  ns.WhisperTracker.Install()
  Wow.fireEvent(INFORM, "hi", "Bob")
  Wow.fireEvent(INFORM, "hi again", "Bob")
  Assert.same(greeted, { "Bob-Realm" })
  Wow.fireEvent(INFORM, "hi", "Stranger-Draenor")
  Assert.equal(#greeted, 1, "a whisper to somebody without a lead")
  secretNames["Cy-Draenor"] = true
  Wow.fireEvent(INFORM, "hi", "Cy-Draenor")
  Assert.equal(#greeted, 1, "a secret target is skipped")
  secretNames["Cy-Draenor"] = nil
  Wow.fireEvent(INFORM, "hi", "Cy-Draenor")
  Assert.same(greeted, { "Bob-Realm", "Cy-Draenor" })

  -- A whisper from a greeted customer marks the lead replied once; before the greeting it does not.
  ns = setup({ "Bob-Realm", "Cy-Draenor" })
  local replied = {}
  ns.Leads.On("replied", function(l)
    replied[#replied + 1] = l.customer
  end)
  ns.WhisperTracker.Install()
  Wow.fireEvent(WHISPER, "hello", "Bob-Realm")
  Assert.equal(#replied, 0, "not greeted yet")
  ns.Leads.MarkGreeted(1)
  Wow.fireEvent(WHISPER, "hello", "Bob")
  Wow.fireEvent(WHISPER, "still there?", "Bob-Realm")
  Assert.same(replied, { "Bob-Realm" })
  ns.Leads.MarkGreeted(2)
  secretNames["Cy-Draenor"] = true
  Wow.fireEvent(WHISPER, "hello", "Cy-Draenor")
  Assert.same(replied, { "Bob-Realm" }, "a secret sender is skipped")
  secretNames["Cy-Draenor"] = nil
  Wow.fireEvent(WHISPER, "hello", "Nobody-Draenor")
  Assert.equal(#replied, 1)

  -- The addon never listens for addon messages: no shipped file mentions the event.
  for _, path in ipairs(Toc.luaFiles()) do
    local handle = assert(io.open(path, "r"))
    local source = handle:read("*a")
    handle:close()
    Assert.falsy(string.find(source, "CHAT_MSG_ADDON", 1, true), path .. " mentions CHAT_MSG_ADDON")
  end
end
