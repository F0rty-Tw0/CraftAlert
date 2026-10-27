local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

-- Spec §7.6 "Away summary", §13 "Status and away summary" and plan revision R5c: the leads made
-- while AFK are counted per AFK period, and when the flag clears one summary shows the count and
-- how many of them timed out. A dismissed lead still counts but is not expired. Leads is a fake
-- that fires "new" and answers IsActive; the real one sets arrivedWhileAfk (tests/model/test_leads.lua).

-- → AwaySummary and the client state: `afk`, `active[id]`, `shown` ({ count, expired } per
-- summary), `arrive(lead)` (a "new" lead, listed), `flags(unit)` (PLAYER_FLAGS_CHANGED).
local function setup()
  Wow.reset()
  Wow.flavor("retail")
  local state = { afk = true, active = {}, shown = {} }
  Wow.stub("UnitIsAFK", function()
    return state.afk
  end)
  local listeners = {}
  local ns = {
    Localization = Fresh.require("Core.Localization"),
    FlavorCompat = Fresh.require("Core.FlavorCompat"),
    EventRouter = Fresh.require("Core.EventRouter"),
    Leads = {
      On = function(name, fn)
        listeners[name] = fn
      end,
      IsActive = function(id)
        return state.active[id] == true
      end,
    },
  }
  local AwaySummary = assert(loadfile("Model/AwaySummary.lua"))("CraftAlert", ns)
  AwaySummary.Install(function(count, expired)
    state.shown[#state.shown + 1] = { count, expired }
  end)
  function state.arrive(lead)
    state.active[lead.id] = true
    listeners.new(lead)
    return lead
  end
  function state.flags(unit)
    Wow.fireEvent("PLAYER_FLAGS_CHANGED", unit or "player")
  end
  return AwaySummary, state
end

local function inInstance(inside)
  Wow.stub("IsInInstance", inside and function()
    return true, "party"
  end or nil)
end

-- Four AFK leads count: one still listed, one timed out, one dismissed, one evicted (gone, never
-- dismissed: expired too). A lead made before the AFK flag, a test lead and one whose flag was
-- secret (arrivedWhileAfk nil) do not. One summary, then the period is over.
local function testCountsAndExpired()
  local _, state = setup()
  state.arrive({ id = 1, arrivedWhileAfk = true })
  local timedOut = state.arrive({ id = 2, arrivedWhileAfk = true })
  local dismissed = state.arrive({ id = 3, arrivedWhileAfk = true })
  local evicted = state.arrive({ id = 4, arrivedWhileAfk = true })
  state.arrive({ id = 5, arrivedWhileAfk = false })
  state.arrive({ id = 6, arrivedWhileAfk = true, test = true })
  state.arrive({ id = 7 })
  state.active[timedOut.id], state.active[evicted.id] = nil, nil
  state.active[dismissed.id], dismissed.dismissed = nil, true
  state.afk = false
  state.flags()
  Assert.same(state.shown, { { 4, 2 } })
  state.flags()
  Assert.equal(#state.shown, 1, "the period was reset")
end

-- Nothing yet: no AFK lead; another unit's flags; a secret unit; still AFK; a secret AFK flag
-- (kept counting). The player's flag clearing afterwards shows the whole count.
local function testNothingYet()
  local _, state = setup()
  state.afk = false
  state.flags()
  Assert.same(state.shown, {}, "count 0")
  state.afk = true
  state.arrive({ id = 1, arrivedWhileAfk = true })
  state.flags()
  Assert.same(state.shown, {}, "still AFK")
  state.afk = false
  state.flags("target")
  state.flags(Wow.secret("player"))
  Assert.same(state.shown, {}, "only the player's own flags, never a secret unit")
  state.afk = Wow.secret(false)
  state.flags()
  Assert.same(state.shown, {}, "a secret AFK flag shows nothing yet")
  state.afk = true
  state.arrive({ id = 2, arrivedWhileAfk = true })
  state.afk = false
  state.flags()
  Assert.same(state.shown, { { 2, 0 } }, "kept counting through the secret answer")
end

-- A client without UnitIsAFK: the event raises nothing and shows nothing, as Leads' afkNow.
local function testNoUnitIsAfk()
  local _, state = setup()
  state.arrive({ id = 1, arrivedWhileAfk = true })
  Wow.stub("UnitIsAFK", nil)
  state.flags()
  Assert.same(state.shown, {})
end

-- In an instance the flag clearing resets the count and shows nothing; the next period starts at 0.
local function testInstanceResets()
  local _, state = setup()
  state.arrive({ id = 1, arrivedWhileAfk = true })
  state.afk = false
  inInstance(true)
  state.flags()
  inInstance(false)
  Assert.same(state.shown, {}, "nothing shows in an instance")
  state.afk = true
  state.arrive({ id = 2, arrivedWhileAfk = true })
  state.afk = false
  state.flags()
  Assert.same(state.shown, { { 1, 0 } }, "only the new period's lead")
end

-- The toast's text: plural as the spec writes it, singular for one, the expired part only when
-- there is one.
local function testText()
  local AwaySummary = setup()
  Assert.equal(AwaySummary.Text(4, 1), "4 requests you could craft while you were away (1 expired)")
  Assert.equal(AwaySummary.Text(3, 0), "3 requests you could craft while you were away")
  Assert.equal(AwaySummary.Text(1, 0), "1 request you could craft while you were away")
  Assert.equal(AwaySummary.Text(1, 1), "1 request you could craft while you were away (1 expired)")
end

return function()
  testCountsAndExpired()
  testNothingYet()
  testNoUnitIsAfk()
  testInstanceResets()
  testText()
  Wow.reset()
end
