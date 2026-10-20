local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local SHOWN = 100

-- Fresh SendGuard with the player present (not AFK) at GetTime() == SHOWN + 1.
local function load()
  Wow.reset()
  Wow.clock.gettime = SHOWN + 1
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  Fresh.require("Core.FlavorCompat")
  return Fresh.require("Model.SendGuard")
end

local function lead(greeted)
  return { id = 1, customer = "Bob-Draenor", greeted = greeted == true }
end

-- Records n sends, one second apart, ending at the current clock.
local function recordSends(SendGuard, n)
  local last = Wow.clock.gettime
  for i = n - 1, 0, -1 do
    Wow.clock.gettime = last - i
    SendGuard.RecordSend()
  end
  Wow.clock.gettime = last
end

return function()
  -- A present player, a fresh lead and a toast shown for a second pass every rule.
  local SendGuard = load()
  local ok, reason = SendGuard.Check(lead(), SHOWN)
  Assert.equal(ok, true)
  Assert.equal(reason, nil)

  -- Rule 1: AFK, a secret AFK flag and a missing API all count as AFK.
  Wow.stub("UnitIsAFK", function()
    return true
  end)
  ok, reason = SendGuard.Check(lead(), SHOWN)
  Assert.equal(ok, false)
  Assert.equal(reason, "afk")
  Wow.stub("UnitIsAFK", function()
    return Wow.secret(false)
  end)
  Assert.equal(select(2, SendGuard.Check(lead(), SHOWN)), "afk", "a secret flag is unknown: AFK")
  Wow.stub("UnitIsAFK", nil)
  Assert.equal(select(2, SendGuard.Check(lead(), SHOWN)), "afk", "no UnitIsAFK: unknown counts as AFK")

  -- Rule 2: six greetings fit in a rolling 60 s, the seventh does not.
  SendGuard = load()
  recordSends(SendGuard, 5)
  Assert.equal(SendGuard.Check(lead(), SHOWN), true, "5 sent: the 6th passes")
  recordSends(SendGuard, 1)
  ok, reason = SendGuard.Check(lead(), SHOWN)
  Assert.equal(ok, false)
  Assert.equal(reason, "rate", "6 sent in the window: the 7th is blocked")

  -- The window rolls: the oldest send leaves it 60 s after it was made.
  SendGuard = load()
  Wow.clock.gettime = 1000
  recordSends(SendGuard, 6) -- t = 995 .. 1000
  Wow.clock.gettime = 1054.9 -- the oldest (995) is 59.9 s old
  Assert.equal(select(2, SendGuard.Check(lead(), 1000)), "rate")
  Wow.clock.gettime = 1055 -- the oldest is 60 s old: out of the window
  Assert.equal(SendGuard.Check(lead(), 1000), true)

  -- Rule 2: a lead greeted by any route is prefilled, whatever the rate.
  SendGuard = load()
  ok, reason = SendGuard.Check(lead(true), SHOWN)
  Assert.equal(ok, false)
  Assert.equal(reason, "greeted")

  -- Rule 3: the lead must have been shown for 0.5 s.
  SendGuard = load()
  Wow.clock.gettime = 10.49
  ok, reason = SendGuard.Check(lead(), 10)
  Assert.equal(ok, false)
  Assert.equal(reason, "look")
  Wow.clock.gettime = 10.5
  Assert.equal(SendGuard.Check(lead(), 10), true, "exactly 0.5 s passes")
  Assert.equal(select(2, SendGuard.Check(lead(), nil)), "look", "never shown (toast hidden, window closed): prefill")

  -- Precedence follows the rule numbers: AFK, then rate, greeted, look.
  SendGuard = load()
  recordSends(SendGuard, 6)
  Assert.equal(select(2, SendGuard.Check(lead(true), nil)), "rate")
  Wow.stub("UnitIsAFK", function()
    return true
  end)
  Assert.equal(select(2, SendGuard.Check(lead(true), nil)), "afk")
end
