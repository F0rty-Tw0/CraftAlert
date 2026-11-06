local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local T0 = 1000
local WHO_EVENT = "WHO_LIST_UPDATE"

-- Spec §9 B3-B7, modelled on WhisperMessenger's tests/helpers/who_lookup_env.lua: C_FriendList
-- records SendWho and SetWhoToUi and serves env.results; FriendsFrame, LFGWhoListFrame and WhoFrame
-- are stub frames (the two panels hidden); C_Timer gains a NewTimer that records each handle;
-- Leads is a fake whose SetWho writes the lead and records the call. → env, with WhoCity loaded and
-- Init run on `flavor` (default "forever").
local function setup(flavor, opts)
  opts = opts or {}
  Wow.reset()
  Wow.flavor(flavor or "forever")
  Wow.clock.gettime = T0
  local env = { sent = {}, whoToUi = {}, results = {}, newTimers = {}, setWho = {}, hooks = 0 }
  env.api = {
    SendWho = function(filter)
      if env.failSend then
        error("SendWho failed")
      end
      table.insert(env.sent, filter)
    end,
    GetWhoToUi = function()
      return opts.whoToUi or false
    end,
    SetWhoToUi = function(value)
      table.insert(env.whoToUi, value)
    end,
    GetNumWhoResults = function()
      return #env.results
    end,
    GetWhoInfo = function(i)
      return env.results[i]
    end,
  }
  Wow.stub("C_FriendList", env.api)
  local createFrame = _G["CreateFrame"]
  env.friends = createFrame("Frame", "FriendsFrame")
  env.lfg = createFrame("Frame", "LFGWhoListFrame")
  env.whoFrame = createFrame("Frame", "WhoFrame")
  env.friends:RegisterEvent(WHO_EVENT)
  env.lfg:RegisterEvent(WHO_EVENT)
  env.lfg:Hide()
  env.whoFrame:Hide()
  local after = _G["C_Timer"].After
  Wow.stub("C_Timer", {
    After = after,
    NewTimer = not opts.noNewTimer and function(seconds, fn)
      local handle = { seconds = seconds, fn = fn }
      function handle:Cancel()
        self.cancelled = true
      end
      table.insert(env.newTimers, handle)
      return handle
    end or nil,
  })
  Wow.stub("C_ChatInfo", {
    InChatMessagingLockdown = function()
      return env.chatLockdown == true
    end,
  })
  local hook = _G["hooksecurefunc"]
  Wow.stub("hooksecurefunc", function(...)
    env.hooks = env.hooks + 1
    hook(...)
  end)
  env.leads = {}
  package.loaded["Model.Leads"] = {
    SetWho = function(id, state, zone)
      table.insert(env.setWho, { id, state, zone })
      local lead = env.leads[id]
      lead.whoState, lead.whoZone = state, zone
      return true
    end,
  }
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.EventRouter")
  env.WhoCity = Fresh.require("Core.WhoCity")
  env.WhoCity.Init()
  return env
end

local function newLead(env, id, customer)
  local lead = { id = id, customer = customer }
  env.leads[id] = lead
  return lead
end

local function listening(env)
  return { env.friends:IsEventRegistered(WHO_EVENT), env.lfg:IsEventRegistered(WHO_EVENT) }
end

-- B4: a query for "Bob-Realm" asks for the short name, silences both Who listeners, routes the
-- answer to the API and arms the 4 s timer. Our own SendWho does not end our flight.
local function testSends()
  local env = setup()
  Assert.same({ env.WhoCity.WINDOW, env.WhoCity.MIN_GAP }, { 4, 6 })
  local lead = newLead(env, 7, "Bob-Realm")
  Assert.equal(env.WhoCity.TryFor(lead), true)
  Assert.same(env.sent, { 'n-"Bob"' })
  Assert.same(listening(env), { false, false }, "both listeners unregistered")
  Assert.same(env.whoToUi, { true })
  Assert.same(env.setWho, { { 7, "pending", nil } }, "pending, not ended by our own send")
  Assert.equal(#env.newTimers, 1)
  Assert.equal(env.newTimers[1].seconds, 4)
  Assert.equal(env.newTimers[1].cancelled, nil)
end

-- B5: the first entry whose name before "-" is the asker's (any case) gives the zone; cleanup
-- waits for the next frame, then restores both listeners and the previous WhoToUi. A later
-- WHO_LIST_UPDATE is not ours.
local function testResultFound()
  local env = setup("forever", { whoToUi = true })
  local lead = newLead(env, 7, "Bob-Realm")
  env.WhoCity.TryFor(lead)
  env.results = { { fullName = "Bobby-Realm", area = "Ironforge" }, { fullName = "bob-Other", area = "Orgrimmar" } }
  Wow.fireEvent(WHO_EVENT)
  Assert.same({ lead.whoState, lead.whoZone }, { "done", "Orgrimmar" })
  Assert.equal(env.newTimers[1].cancelled, true, "timer cancelled")
  Assert.same(listening(env), { false, false }, "not before the next frame")
  Assert.equal(Wow.pendingTimers(0), 1)
  Wow.runTimers()
  Assert.same(listening(env), { true, true })
  Assert.same(env.whoToUi, { true, true }, "previous WhoToUi was true")
  Wow.fireEvent(WHO_EVENT)
  Assert.equal(#env.setWho, 2, "no flight: ignored")
end

local function testResultMissing()
  local env = setup()
  local lead = newLead(env, 7, "Bob-Realm")
  env.WhoCity.TryFor(lead)
  env.results = { { fullName = "Bobby-Realm", area = "Ironforge" } }
  Wow.fireEvent(WHO_EVENT)
  Assert.same({ lead.whoState, lead.whoZone }, { "none", nil })
  Wow.runTimers()
  Assert.same(listening(env), { true, true })
  Assert.same(env.whoToUi, { true, false })
end

-- B7: the timer ends a flight with no answer, with cleanup at once.
local function testTimeout()
  local env = setup()
  local lead = newLead(env, 7, "Bob-Realm")
  env.WhoCity.TryFor(lead)
  env.newTimers[1].fn()
  Assert.equal(lead.whoState, "failed")
  Assert.same(listening(env), { true, true })
  Assert.same(env.whoToUi, { true, false })
  Wow.fireEvent(WHO_EVENT)
  Assert.equal(#env.setWho, 2, "a late answer is ignored")
end

-- B7: the player's own /who during our flight ends it at once, so their Who list opens; WhoToUi
-- stays on while a Who panel is on screen.
local function testForeignSend()
  local env = setup()
  local lead = newLead(env, 7, "Bob-Realm")
  env.WhoCity.TryFor(lead)
  env.whoFrame:Show()
  _G["C_FriendList"].SendWho("n-x")
  Assert.equal(lead.whoState, "failed")
  Assert.equal(env.newTimers[1].cancelled, true, "timer cancelled")
  Assert.same(listening(env), { true, true })
  Assert.same(env.whoToUi, { true, true }, "a Who panel is visible")
  Assert.equal(Wow.pendingTimers(0), 0, "cleanup ran at once")
end

-- B4: a SendWho that raises fails the lookup and cleans up at once.
local function testSendRaises()
  local env = setup()
  local lead = newLead(env, 7, "Bob-Realm")
  env.failSend = true
  Assert.equal(env.WhoCity.TryFor(lead), false)
  Assert.equal(lead.whoState, "failed")
  Assert.equal(env.newTimers[1].cancelled, true, "timer cancelled")
  Assert.same(listening(env), { true, true })
  Assert.same(env.whoToUi, { true, false })
end

-- B3: pending and done never resend; none and failed may.
local function testStates()
  for _, state in ipairs({ "pending", "done" }) do
    local env = setup()
    local lead = newLead(env, 7, "Bob-Realm")
    lead.whoState = state
    Assert.equal(env.WhoCity.TryFor(lead), false, state)
    Assert.same(env.sent, {}, state)
  end
  for _, state in ipairs({ "none", "failed" }) do
    local env = setup()
    local lead = newLead(env, 7, "Bob-Realm")
    lead.whoState = state
    Assert.equal(env.WhoCity.TryFor(lead), true, state)
    Assert.equal(lead.whoState, "pending", state)
  end
end

-- B3: each guard alone blocks a send, and a blocked click changes nothing.
local function testGuards()
  local env = setup()
  local lead = newLead(env, 7, "Bob-Realm")
  Wow.combat = true
  Assert.equal(env.WhoCity.TryFor(lead), false, "combat")
  Wow.combat = false
  env.chatLockdown = true
  Assert.equal(env.WhoCity.TryFor(lead), false, "chat lockdown")
  Assert.same({ env.sent, env.setWho, lead.whoState }, { {}, {}, nil })

  env = setup("forever", { noNewTimer = true })
  Assert.equal(env.WhoCity.TryFor(newLead(env, 7, "Bob-Realm")), false, "no C_Timer.NewTimer")
  Assert.same({ env.sent, env.setWho, env.whoToUi }, { {}, {}, {} }, "blocked before any change")

  -- In flight: a second lead waits.
  env = setup()
  env.WhoCity.TryFor(newLead(env, 7, "Bob-Realm"))
  Wow.clock.gettime = T0 + 10
  Assert.equal(env.WhoCity.TryFor(newLead(env, 8, "Ann-Realm")), false, "in flight")

  -- MIN_GAP after a foreign send: 5.9 s blocks, 6.0 s sends.
  env = setup()
  _G["C_FriendList"].SendWho("n-x")
  lead = newLead(env, 7, "Bob-Realm")
  Wow.clock.gettime = T0 + 5.9
  Assert.equal(env.WhoCity.TryFor(lead), false, "5.9 s after a foreign send")
  Wow.clock.gettime = T0 + 6
  Assert.equal(env.WhoCity.TryFor(lead), true, "6 s after a foreign send")
end

-- B1: Retail installs no hook (and so never sends); Init hooks once.
local function testInit()
  local env = setup("retail")
  Assert.equal(env.hooks, 0)
  Assert.equal(_G["C_FriendList"].SendWho, env.api.SendWho, "SendWho untouched")
  Assert.equal(env.WhoCity.TryFor(newLead(env, 7, "Bob-Realm")), false)
  Assert.same(env.sent, {})

  env = setup()
  env.WhoCity.Init()
  Assert.equal(env.hooks, 1, "hooked once")
end

return function()
  testSends()
  testResultFound()
  testResultMissing()
  testTimeout()
  testForeignSend()
  testSendRaises()
  testStates()
  testGuards()
  testInit()
end
