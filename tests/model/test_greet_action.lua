local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

local T0 = 1000
local CUSTOMER = "Bob-Draenor"

-- Fresh modules for `flavor` (default Retail); the player is Me-Realm, not AFK, GetTime() is
-- 50. Every send lands in `calls` as { api, args... } in call order. → ns, db, calls.
local function setup(extra, flavor)
  local ns = Fixture.load(flavor or "retail")
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

-- Test-lead helpers: a lead flagged `test` (as Leads.OnMatch does) never reaches a send API.
local PREFIX = "|cffffd100Craft Alert:|r "
local TARGET = "Test0-Realm"
local function setupTestLead(flavor, edit)
  local tns, tdb, tcalls = setup(edit, flavor)
  -- Restore drops test leads, so the record joins the live list after it.
  local record = leadRecord(1, TARGET)
  record.test = true
  tdb.leads[1] = record
  return tns, tdb, tcalls, record
end

local function chatLines(...)
  local lines = {}
  for i, text in ipairs({ ... }) do
    lines[i] = PREFIX .. text
  end
  return lines
end

-- true when five more sends put the rate cap in force (Check says "rate", not "greeted").
local function capped(tns, tlead)
  for _ = 1, 5 do
    tns.SendGuard.RecordSend()
  end
  local ok, why = tns.SendGuard.Check(tlead, 49)
  return ok == false and why == "rate"
end

-- SetOpener swaps what opens a whisper box (WhisperMessenger's conversation); nil restores the default.
local function testOpener()
  local ns, _, calls = setup()
  local opened = {}
  ns.GreetAction.SetOpener(function(target, text)
    opened[#opened + 1] = { target, text }
  end)
  local lead = leadRecord(1)
  ns.GreetAction.Empty(lead) -- empty whisper
  ns.GreetAction.Prefill(lead) -- greeting as draft
  Assert.same(opened[1], { CUSTOMER })
  Assert.equal(opened[2][1], CUSTOMER)
  Assert.truthy(opened[2][2] and string.find(opened[2][2], "%S"))
  -- refused greet (not active) goes through the opener, never the Blizzard box
  ns.GreetAction.Greet({ id = 99, customer = CUSTOMER, prof = 164, profName = "Blacksmithing", crafter = "Me-Realm", time = T0 }, 50)
  Assert.equal(#opened, 3)
  Assert.same(calls, {}, "no Blizzard call while an opener is set")
  -- nil restores the default
  ns.GreetAction.SetOpener(nil)
  ns.GreetAction.Empty(lead)
  Assert.same(calls, { { "empty", CUSTOMER } })
  Assert.equal(ns.GreetAction.Target(lead), CUSTOMER)
  -- Forever drops the realm
  local forever = setup(nil, "forever")
  Assert.equal(forever.GreetAction.Target(leadRecord(2, "Bob-Draenor")), "Bob")
end

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

  -- A notice call that raises (a lockdown error, a client change) does not stop the greeting either.
  ns, _, calls = setup(withLeads(1))
  Wow.stub("C_ChatInfo", {
    SendAddonMessage = function()
      error("addon messages are locked down")
    end,
    SendChatMessage = _G["C_ChatInfo"].SendChatMessage,
  })
  lead = ns.Leads.Latest()
  ns.GreetAction.Greet(lead, 49)
  Assert.same(calls, { { "chat", GREETING, "WHISPER", nil, "Customer1-Draenor" } })
  Assert.equal(lead.greeted, true)

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

  -- A greeting with nothing to say (a hand-edited empty template, or tags that all expand to
  -- nothing) is never sent: an empty whisper opens, with no notice, no count, nothing greeted.
  local blank = {
    empty = function(db)
      db.settings.templates.profession = ""
    end,
    spaces = function(db)
      db.settings.templates.profession = " {profession}\n "
      db.leads[1].profName = nil
    end,
  }
  for name, edit in pairs(blank) do
    ns, db, calls = setup(function(data)
      withLeads(1)(data)
      edit(data)
    end)
    lead = ns.Leads.Latest()
    ns.GreetAction.Greet(lead, 49)
    Assert.same(calls, { { "empty", "Customer1-Draenor" } }, name)
    Assert.equal(lead.greeted, false, name)
    Assert.equal(db.recentGreeted["Customer1-Draenor"], nil, name)
    for _ = 1, 5 do
      ns.SendGuard.RecordSend()
    end
    Assert.equal(ns.SendGuard.Check(lead, 49), true, name .. ": five sends, so the blank one was not counted")
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

  -- Forever names are region-unique: the stored key carries the own realm, but every whisper
  -- goes to the full name without a realm (spec §10); the lead and the greeting keep the key.
  ns, _, calls = setup(function(db)
    db.leads[1] = leadRecord(1, "Bob Smith-Realm")
  end, "forever")
  lead = ns.Leads.Latest()
  ns.GreetAction.Greet(lead, 49)
  ns.GreetAction.Greet(lead, 49)
  ns.GreetAction.Prefill(lead)
  ns.GreetAction.Empty(lead)
  Assert.same(calls, {
    { "addon", "robots.txt", "Q:CraftAlert", "WHISPER", "Bob Smith" },
    { "chat", "Hi! I have Blacksmithing, what do you need?", "WHISPER", nil, "Bob Smith" },
    { "prefill", "Bob Smith", "Hi! I have Blacksmithing, what do you need?" },
    { "prefill", "Bob Smith", "Hi! I have Blacksmithing, what do you need?" },
    { "empty", "Bob Smith" },
  })
  Assert.equal(lead.customer, "Bob Smith-Realm")
  Assert.equal(lead.greeted, true)

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

  -- A test lead (flag set by Leads.OnMatch for the reserved guid) never reaches a send API: each
  -- would-be send prints one chat line. Only the would-whisper line counts against the cap and
  -- marks the lead greeted.
  ns, db, calls, lead = setupTestLead()
  ns.GreetAction.Greet(lead, 49)
  Assert.same(
    Wow.chat,
    chatLines('Test, would send addon message robots.txt "Q:CraftAlert" to ' .. TARGET, "Test, would whisper " .. TARGET .. ": " .. GREETING)
  )
  Assert.same(calls, {})
  Assert.equal(lead.greeted, true)
  Assert.equal(db.recentGreeted[TARGET], nil)
  Assert.equal(capped(ns, lead), true, "the would-whisper line counted one send")

  -- A guard that blocks (shown just now) opens-a-whisper line only: not greeted, not counted.
  ns, _, calls, lead = setupTestLead()
  ns.GreetAction.Greet(lead, 50)
  Assert.same(Wow.chat, chatLines("Test, would open a whisper to " .. TARGET .. " with: " .. GREETING))
  Assert.same(calls, {})
  Assert.equal(lead.greeted, false)
  Assert.equal(capped(ns, lead), false, "a blocked dry run was not counted")

  -- Prefill and Empty print their lines, mark nothing, count nothing.
  ns, _, calls, lead = setupTestLead()
  ns.GreetAction.Prefill(lead)
  ns.GreetAction.Empty(lead)
  Assert.same(
    Wow.chat,
    chatLines("Test, would open a whisper to " .. TARGET .. " with: " .. GREETING, "Test, would open an empty whisper to " .. TARGET)
  )
  Assert.same(calls, {})
  Assert.equal(lead.greeted, false)
  Assert.equal(capped(ns, lead), false, "Prefill and Empty were not counted")

  -- An empty greeting through Greet prints the empty-whisper line, nothing greeted.
  ns, _, calls, lead = setupTestLead(nil, function(data)
    data.settings.templates.profession = ""
  end)
  ns.GreetAction.Greet(lead, 49)
  Assert.same(Wow.chat, chatLines("Test, would open an empty whisper to " .. TARGET))
  Assert.same(calls, {})
  Assert.equal(lead.greeted, false)

  -- Forever: the printed target drops the realm, as the real whisper does.
  ns, _, calls, lead = setupTestLead("forever")
  ns.GreetAction.Greet(lead, 49)
  ns.GreetAction.Prefill(lead)
  ns.GreetAction.Empty(lead)
  Assert.same(
    Wow.chat,
    chatLines(
      'Test, would send addon message robots.txt "Q:CraftAlert" to Test0',
      "Test, would whisper Test0: " .. GREETING,
      "Test, would open a whisper to Test0 with: " .. GREETING,
      "Test, would open an empty whisper to Test0"
    )
  )
  Assert.same(calls, {})
  Assert.equal(lead.customer, TARGET)

  testOpener()
end
