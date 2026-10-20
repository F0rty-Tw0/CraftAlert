local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

local T0 = 1000
local CUSTOMER = "Bob-Draenor"

-- Fresh modules; the player is Me-Realm, not AFK, GetTime() is 50. Every send lands in
-- `calls` as { api, args... } in call order. → ns, db, calls.
local function setup(extra)
  local ns = Fixture.load("retail")
  Wow.clock.time = T0
  Wow.clock.gettime = 50
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  local calls = {}
  local function record(api, result)
    return function(...)
      calls[#calls + 1] = { api, ... }
      return result
    end
  end
  Wow.stub("C_ChatInfo", { SendAddonMessage = record("addon", 3), SendChatMessage = record("chat") })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = record("prefill"), SendTell = record("empty") })
  ns.PlayerName.Init()
  local db = ns.Defaults.Db()
  Wow.stub("CraftAlertDB", db)
  for _, name in ipairs({ "Model.Greeting", "Model.SendGuard", "Model.RealmTag", "Model.CrafterRank", "Model.Leads" }) do
    ns[string.match(name, "%.(%w+)$")] = Fresh.require(name)
  end
  if extra then
    extra(db)
  end
  ns.Leads.Restore(db)
  ns.GreetAction = Fresh.require("Model.GreetAction")
  return ns, db, calls
end

local function leadRecord(id, customer)
  return {
    id = id,
    customer = customer or CUSTOMER,
    message = "LF plate belt",
    channel = "trade",
    kind = "profession",
    prof = 164,
    profName = "Blacksmithing",
    crafter = "Me-Realm",
    time = T0,
    greeted = false,
    replied = false,
  }
end

local function withLeads(count)
  return function(db)
    for id = 1, count do
      db.leads[id] = leadRecord(id, "Customer" .. id .. "-Draenor")
    end
  end
end

local GREETING = "Hi! I have Blacksmithing, what do you need?"

return function()
  -- Greet sends the disclosure notice, then the greeting whisper, records the send and
  -- marks the lead greeted.
  local ns, db, calls = setup(withLeads(1))
  local lead = ns.Leads.Latest()
  local greeted = {}
  ns.Leads.On("greeted", function(l)
    greeted[#greeted + 1] = l
  end)
  ns.GreetAction.Greet(lead, 49)
  Assert.same(calls, {
    { "addon", "robots.txt", "Q:CraftAlert", "WHISPER", "Customer1-Draenor" },
    { "chat", GREETING, "WHISPER", nil, "Customer1-Draenor" },
  })
  Assert.equal(lead.greeted, true)
  Assert.equal(#greeted, 1)
  Assert.equal(db.recentGreeted["Customer1-Draenor"], T0)

  -- A second greet on the same lead prefills (once per lead) and sends nothing else.
  ns.GreetAction.Greet(lead, 49)
  Assert.equal(#calls, 3)
  Assert.same(calls[3], { "prefill", "Customer1-Draenor", GREETING })

  -- The disclosure result is ignored: a throttle code does not stop the greeting (stub returns 3).
  ns, _, calls = setup(withLeads(1))
  ns.GreetAction.Greet(ns.Leads.Latest(), 49)
  Assert.equal(calls[2][1], "chat")

  -- A blocked greet (each rule) opens the edit box with the greeting and sends nothing, marks
  -- nothing greeted and does not count against the rate cap.
  local blocks = {
    afk = function()
      Wow.stub("UnitIsAFK", function()
        return true
      end)
    end,
    look = function()
      Wow.clock.gettime = 49.8
    end,
  }
  for name, block in pairs(blocks) do
    ns, db, calls = setup(withLeads(1))
    lead = ns.Leads.Latest()
    block()
    ns.GreetAction.Greet(lead, 49.7)
    Assert.same(calls, { { "prefill", "Customer1-Draenor", GREETING } }, name)
    Assert.equal(lead.greeted, false, name)
    Assert.equal(db.recentGreeted["Customer1-Draenor"], nil, name)
  end

  -- A lead that was dismissed or expired is gone from the list, so greeting it again could
  -- never mark it greeted: every click prefills and nothing is sent or counted.
  local gone = {
    dismissed = function(lead)
      ns.Leads.Dismiss(lead.id)
    end,
    expired = function()
      Wow.clock.time = T0 + 11 * 60
      table.remove(Wow.timers, 1).fn()
    end,
  }
  for name, remove in pairs(gone) do
    ns, db, calls = setup(withLeads(1))
    lead = ns.Leads.Latest()
    remove(lead)
    Assert.equal(ns.Leads.IsActive(lead.id), false, name)
    ns.GreetAction.Greet(lead, 49)
    ns.GreetAction.Greet(lead, 49)
    Assert.same(calls, {
      { "prefill", "Customer1-Draenor", GREETING },
      { "prefill", "Customer1-Draenor", GREETING },
    }, name)
    Assert.equal(lead.greeted, false, name)
    Assert.equal(db.recentGreeted["Customer1-Draenor"], nil, name)
  end

  -- The 7th greeting in 60 s prefills; a send made by Prefill or Empty never counted.
  ns, _, calls = setup(withLeads(8))
  for _ = 1, 3 do
    ns.GreetAction.Prefill(ns.Leads.List()[8])
    ns.GreetAction.Empty(ns.Leads.List()[8])
  end
  local all = ns.Leads.List() -- newest first
  for i = 1, 6 do
    ns.GreetAction.Greet(all[i], 49)
  end
  local sent = 0
  for _, call in ipairs(calls) do
    sent = sent + (call[1] == "chat" and 1 or 0)
  end
  Assert.equal(sent, 6, "prefills and empty whispers left the cap alone")
  calls[#calls + 1] = "marker"
  ns.GreetAction.Greet(all[7], 49)
  Assert.same(calls[#calls], { "prefill", all[7].customer, GREETING })
  Assert.equal(all[7].greeted, false)

  -- Prefill and Empty open the whisper box for the lead's customer and mark nothing.
  ns, _, calls = setup(withLeads(1))
  lead = ns.Leads.Latest()
  ns.GreetAction.Prefill(lead)
  ns.GreetAction.Empty(lead)
  Assert.same(calls, { { "prefill", "Customer1-Draenor", GREETING }, { "empty", "Customer1-Draenor" } })
  Assert.equal(lead.greeted, false)

  -- Settings (templates, notes) shape the whisper; the client may lack C_ChatInfo.SendAddonMessage.
  ns, _, calls = setup(function(db)
    withLeads(1)(db)
    db.settings.notes[164] = "Tips welcome."
  end)
  Wow.stub("C_ChatInfo", { SendChatMessage = _G["C_ChatInfo"].SendChatMessage })
  local globalNotices = {}
  Wow.stub("SendAddonMessage", function(...)
    globalNotices[#globalNotices + 1] = { ... }
  end)
  ns.GreetAction.Greet(ns.Leads.Latest(), 49)
  Assert.same(globalNotices, { { "robots.txt", "Q:CraftAlert", "WHISPER", "Customer1-Draenor" } })
  Assert.equal(calls[1][2], GREETING .. " Tips welcome.")
end
