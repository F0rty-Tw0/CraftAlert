local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")

-- ClickRouter over recording GreetAction and Leads fakes; the modifier keys come from `keys`.
-- → ClickRouter, calls ({ name, args... } in call order), keys ({ shift, ctrl }).
local function setup()
  Wow.reset()
  local calls, keys = {}, { shift = false, ctrl = false }
  local function record(name)
    return function(...)
      calls[#calls + 1] = { name, ... }
    end
  end
  Wow.stub("IsShiftKeyDown", function()
    return keys.shift
  end)
  Wow.stub("IsControlKeyDown", function()
    return keys.ctrl
  end)
  local ns = {
    GreetAction = { Greet = record("greet"), Prefill = record("prefill"), Empty = record("empty") },
    Leads = { Dismiss = record("dismiss") },
  }
  local ClickRouter = assert(loadfile("UI/ClickRouter.lua"))("CraftAlert", ns)
  return ClickRouter, calls, keys
end

local LEAD = { id = 7, customer = "Bob-Draenor" }

return function()
  -- Spec §7.1: left greets with the time the lead was shown (the §7.5 look rule needs it).
  local ClickRouter, calls = setup()
  Assert.equal(ClickRouter.Handle("LeftButton", LEAD, 12.5), "greet")
  Assert.same(calls, { { "greet", LEAD, 12.5 } })

  -- Shift-left prefills, ctrl-left opens an empty whisper; shift wins when both are held.
  local keys
  ClickRouter, calls, keys = setup()
  keys.shift = true
  Assert.equal(ClickRouter.Handle("LeftButton", LEAD, 1), "prefill")
  keys.shift, keys.ctrl = false, true
  Assert.equal(ClickRouter.Handle("LeftButton", LEAD, 1), "empty")
  keys.shift = true
  Assert.equal(ClickRouter.Handle("LeftButton", LEAD, 1), "prefill")
  Assert.same(calls, { { "prefill", LEAD }, { "empty", LEAD }, { "prefill", LEAD } })

  -- Right dismisses the lead, whatever modifier is held, once it has been up 0.5 s (§7.5 look
  -- rule); before that, or with no shown time, the click does nothing.
  ClickRouter, calls, keys = setup()
  Wow.clock.gettime = 1.4
  Assert.equal(ClickRouter.Handle("RightButton", LEAD, 1), nil, "shown 0.4 s ago")
  Assert.equal(ClickRouter.Handle("RightButton", LEAD, nil), nil, "not shown")
  Assert.same(calls, {})
  Wow.clock.gettime = 1.5
  Assert.equal(ClickRouter.Handle("RightButton", LEAD, 1), "dismiss")
  keys.shift, keys.ctrl = true, true
  Assert.equal(ClickRouter.Handle("RightButton", LEAD, 1), "dismiss")
  Assert.same(calls, { { "dismiss", 7 }, { "dismiss", 7 } })

  -- Other buttons and a missing lead do nothing.
  ClickRouter, calls, keys = setup()
  Assert.equal(ClickRouter.Handle("MiddleButton", LEAD, 1), nil)
  keys.shift = true
  Assert.equal(ClickRouter.Handle("MiddleButton", LEAD, 1), nil, "shift only acts on the left button")
  Assert.equal(ClickRouter.Handle("LeftButton", nil, 1), nil)
  Assert.same(calls, {})

  -- Missing modifier APIs count as not held.
  ClickRouter = setup()
  Wow.stub("IsShiftKeyDown", nil)
  Wow.stub("IsControlKeyDown", nil)
  Assert.equal(ClickRouter.Handle("LeftButton", LEAD, 3), "greet")

  -- Spec §7.6, the away summary's own table: left opens the leads, right dismisses (no look
  -- rule: no lead to send to), shift or ctrl on the left button and other buttons do nothing.
  ClickRouter, calls, keys = setup()
  Assert.same({ ClickRouter.Summary("LeftButton"), ClickRouter.Summary("RightButton") }, { "open", "dismiss" })
  Assert.equal(ClickRouter.Summary("MiddleButton"), nil)
  keys.shift = true
  Assert.equal(ClickRouter.Summary("LeftButton"), nil, "shift-click")
  keys.shift, keys.ctrl = false, true
  Assert.equal(ClickRouter.Summary("LeftButton"), nil, "ctrl-click")
  Assert.same(calls, {}, "no lead acted on")
  Wow.reset()
end
