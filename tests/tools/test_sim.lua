local Assert = require("tests.helpers.assert")
local Toc = require("tests.helpers.toc")

-- Runs tools/sim.lua as `python scripts/sim.py ...argv` would: its main block prints every line
-- and exits. print and os.exit are captured, then restored. → the printed lines, the exit code
-- (nil when the sim did not exit).
local function runMain(argv)
  local printed, code = {}, nil
  local savedPrint, savedExit, savedArg = print, os.exit, rawget(_G, "arg")
  _G.print = function(line)
    printed[#printed + 1] = line
  end
  rawset(os, "exit", function(status)
    code = status
  end)
  _G.arg = argv
  _G.CRAFTALERT_SIM_NO_MAIN = nil
  local ok, err = pcall(dofile, "tools/sim.lua")
  _G.CRAFTALERT_SIM_NO_MAIN = true
  rawset(os, "exit", savedExit)
  _G.print, _G.arg = savedPrint, savedArg
  assert(ok, err)
  return printed, code
end

-- Only the `sender:` lines of a run.
local function senderLines(lines)
  local senders = {}
  for _, line in ipairs(lines) do
    if string.find(line, "^sender: ") then
      senders[#senders + 1] = line
    end
  end
  return senders
end

-- The lines a run printed after its `db:` line: what the steps themselves produced.
local function stepLines(lines)
  for index, line in ipairs(lines) do
    if string.find(line, "^db: ") then
      return { unpack(lines, index + 1) }
    end
  end
  error("no db: line in " .. table.concat(lines, " / "))
end

-- The lines the first step prints before its own: the index build and scan activation
-- (Trade and Services listen on Retail; on TBC only Trade exists), then `lines`.
local function booted(lines, channels)
  local boot = {
    "index: size=4",
    "scan: active",
    "chat: Craft Alert: Listening in " .. (channels or "Trade, Services") .. " — 4 recipes, 2 crafters",
  }
  for _, line in ipairs(lines) do
    boot[#boot + 1] = line
  end
  return boot
end

return function()
  _G.CRAFTALERT_SIM_NO_MAIN = true
  local Sim = dofile("tools/sim.lua")

  local header = tostring(Sim.Run({})[1])
  assert(string.match(header, "^sim: flavor=retail modules=%d+$"), "bad header: " .. tostring(header))

  Assert.equal(Sim.Run({ "--flavor", "tbc" })[1], (string.gsub(header, "retail", "tbc")))

  -- The header's flavor comes from FlavorCompat, fed only by the build stubs.
  for _, key in ipairs({ "retail", "forever", "era", "tbc", "wrath", "cata", "mop" }) do
    Assert.equal(Sim.Run({ "--flavor", key })[1], string.format("sim: flavor=%s modules=%d", key, #Toc.luaFiles()))
    Assert.equal(Sim.lastNs.FlavorCompat.flavorKey, key)
  end
  Sim.Run({ "--flavor", "forever" })
  Assert.truthy(rawget(_G, "WOW_PROJECT_CAMELOT"))
  Assert.equal(rawget(_G, "WOW_PROJECT_CAMELOT"), rawget(_G, "WOW_PROJECT_ID"))

  -- Chat prints and sends land in the returned lines (the table stays live after Run).
  local lines = Sim.Run({})
  Sim.lastNs.ChatPrint.Line("hello")
  Assert.equal(lines[#lines], "chat: Craft Alert: hello")
  rawget(_G, "SendChatMessage")("hi", "WHISPER", nil, "Bob-Realm")
  Assert.equal(lines[#lines], "send: SendChatMessage hi | WHISPER | nil | Bob-Realm")

  -- Each chat line reports its normalized sender; --sender applies to the next line only.
  local senders = senderLines(Sim.Run({ "--sender", "Zoë-Kel'Thuzad", "LF belt", "LF boots", "--sender", "Bob-Area 52", "LF ring" }))
  Assert.same(senders, {
    "sender: Zoë-Kel'Thuzad",
    "sender: Customer-OtherRealm",
    "sender: Bob-Area52",
  })
  Assert.equal(senderLines(Sim.Run({ "--sender", "Bob", "hi" }))[1], "sender: Bob-OwnRealm")

  -- --class gives the next line's sender a class through the chat GUID; one line only.
  local function outcomeLines(output)
    local kept = {}
    for _, line in ipairs(output) do
      if string.find(line, "^match: ") or string.find(line, "^stop: ") then
        kept[#kept + 1] = line
      end
    end
    return kept
  end
  Assert.same(outcomeLines(Sim.Run({ "--class", "WARRIOR", "LF belt", "--class", "MAGE", "LF belt", "LF belt" })), {
    "match: item group=190001 prof=164 why=lf+belt+plate (warrior)",
    "stop: nomatch", -- the sim fixture has no cloth belt
    "match: item group=190001 prof=164 why=lf+belt", -- --class applies to one line only
  })
  Assert.equal(Sim.Run({ "--class" })[1], "error: --class needs a value")

  -- The first step builds the index from the fixture (bind 0 reagent left out: 2 chars x 2);
  -- each line then reports its Matcher result or the step that stopped it, and a match its lead:
  -- the same sender asking for the same thing again updates the lead.
  local link = "|cff1eff00|Hitem:2575::::::::60:::::|h[Red Linen Shirt]|h|r"
  Assert.same(
    stepLines(Sim.Run({
      "LF plate belt crafter",
      "WTS plate belt",
      "LF leather belt",
      "LF [Enchant Bracer - Sim Health]",
      "lf +8hp to wrist",
      "wtb " .. link .. " or |Hitem:190001|h[Sim Plate Belt]|h",
      "--sender",
      "Crafter-OwnRealm",
      "LF plate belt",
    })),
    booted({
      "sender: Customer-OtherRealm",
      "match: item group=190001 prof=164 why=lf+plate+belt",
      "toast: shown lead=1 more=0",
      "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
      "greeting: Hi! I can craft Sim Plate Belt.",
      "sender: Customer-OtherRealm",
      "stop: prefilter",
      "sender: Customer-OtherRealm",
      "stop: nomatch",
      "sender: Customer-OtherRealm",
      "match: item group=enchant bracer - sim health prof=333 why=lf+enchant bracer sim health",
      "toast: shown lead=2 more=1",
      "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
      "greeting: Hi! I can craft Enchant Bracer - Sim Health.",
      "sender: Customer-OtherRealm",
      "match: item group=enchant bracer - sim health prof=333 why=lf+wrist+8hp",
      "lead: updated customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
      "greeting: Hi! I can craft Enchant Bracer - Sim Health.",
      "sender: Customer-OtherRealm",
      "match: item group=190001 prof=164 why=wtb+190001",
      "lead: updated customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
      "greeting: Hi! I can craft Sim Plate Belt.",
      "sender: Crafter-OwnRealm",
      "stop: self",
    })
  )

  -- Leads (Task 1.11): one new, then one updated; another customer is a new lead, and on
  -- Forever, which has no crafting orders, nobody "cannot order".
  Assert.same(
    stepLines(Sim.Run({ "--flavor", "forever", "--sender", "Bob", "LF plate belt" })),
    booted({
      "sender: Bob-OwnRealm",
      "match: item group=190001 prof=164 why=lf+plate+belt",
      "toast: shown lead=1 more=0",
      "lead: new customer=Bob-OwnRealm crafter=Crafter-OwnRealm cannotOrder=false",
      "greeting: Hi! I can craft Sim Plate Belt.",
    })
  )
  local leadLines = {}
  for _, line in ipairs(Sim.Run({ "LF plate belt", "LF plate belt pls", "--sender", "Zoë-Kel'Thuzad", "LF plate belt" })) do
    if string.find(line, "^lead: ") then
      leadLines[#leadLines + 1] = line
    end
  end
  Assert.same(leadLines, {
    "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
    "lead: updated customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
    "lead: new customer=Zoë-Kel'Thuzad crafter=Crafter-OwnRealm cannotOrder=true",
  })

  -- The toast (Task 1.15): every AlertToast.Show prints the lead and its "+N more" badge;
  -- Bootstrap's Leads.On("new") shows it once per new lead (the sim adds no second
  -- subscription). An updated lead raises no second toast.
  local toastLines = {}
  for _, line in ipairs(Sim.Run({ "LF plate belt", "LF plate belt pls", "--sender", "Bob", "LF plate belt" })) do
    if string.find(line, "^toast: ") then
      toastLines[#toastLines + 1] = line
    end
  end
  Assert.same(toastLines, { "toast: shown lead=1 more=0", "toast: shown lead=2 more=1" })
  -- The first step fired PLAYER_LOGIN: Bootstrap made the launcher and timed the login.
  Assert.truthy(rawget(_G, "CraftAlertLauncher"))
  Assert.equal(type(Sim.lastNs.Perf.loginMs), "number")

  -- Clicks act on the newest lead as if its toast had been up for a second (Task 1.13): left
  -- sends the disclosure then the whisper, a second left prefills (once per lead), a reply
  -- from the customer is tracked, shift prefills, ctrl opens an empty whisper, right dismisses.
  local customer = "Customer-OtherRealm"
  local greeting = "Hi! I can craft Sim Plate Belt."
  local clicked = stepLines(Sim.Run({ "LF plate belt", "--click", "left", "--click", "left" }))
  Assert.same({ unpack(clicked, 9) }, {
    "send: SendAddonMessage robots.txt | Q:CraftAlert | WHISPER | " .. customer,
    "send: SendChatMessage " .. greeting .. " | WHISPER | nil | " .. customer,
    "lead: greeted customer=" .. customer,
    "send: SendTellWithMessage " .. customer .. " | " .. greeting,
  })
  Assert.same({ unpack(stepLines(Sim.Run({ "LF plate belt", "--click", "shift", "--click", "ctrl" })), 9) }, {
    "send: SendTellWithMessage " .. customer .. " | " .. greeting,
    "send: SendTell " .. customer,
  })
  Assert.same({ unpack(stepLines(Sim.Run({ "LF plate belt", "--click", "right", "--click", "left" })), 9) }, {
    "lead: dismissed customer=" .. customer,
    "error: --click left has no lead to act on",
  })
  Assert.same(stepLines(Sim.Run({ "--click", "left" })), booted({ "error: --click left has no lead to act on" }))

  -- A whisper from the customer after the greeting marks the lead replied; before it, nothing.
  local replied = stepLines(
    Sim.Run({ "LF plate belt", "--event", "CHAT_MSG_WHISPER", "hi", customer, "--click", "left", "--event", "CHAT_MSG_WHISPER", "hi", customer })
  )
  Assert.same({ unpack(replied, 9) }, {
    "send: SendAddonMessage robots.txt | Q:CraftAlert | WHISPER | " .. customer,
    "send: SendChatMessage " .. greeting .. " | WHISPER | nil | " .. customer,
    "lead: greeted customer=" .. customer,
    "lead: replied customer=" .. customer,
  })
  -- Whispering the customer by hand (a prefill sent) marks the lead greeted.
  Assert.same({ unpack(stepLines(Sim.Run({ "LF plate belt", "--event", "CHAT_MSG_WHISPER_INFORM", "hello", customer })), 9) }, {
    "lead: greeted customer=" .. customer,
  })

  -- Scan activation (Task 1.14): lines arrive as Trade channel events, so they only count while
  -- the scan is active: paused (no resting), no lead; resting again, active, a lead. Paused at
  -- login, Bootstrap prints the status line itself (§7.6), and the first activation again.
  Assert.same(stepLines(Sim.Run({ "--resting", "off", "LF plate belt", "--resting", "on", "--event", "PLAYER_UPDATE_RESTING", "LF plate belt" })), {
    "index: size=4",
    "scan: paused (noTrade)",
    "chat: Craft Alert: Paused — no Trade chat here",
    "sender: Customer-OtherRealm",
    "stop: paused",
    "scan: active",
    "chat: Craft Alert: Listening in Trade, Services — 4 recipes, 2 crafters",
    "sender: Customer-OtherRealm",
    "match: item group=190001 prof=164 why=lf+plate+belt",
    "toast: shown lead=1 more=0",
    "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
    "greeting: Hi! I can craft Sim Plate Belt.",
  })

  -- Opening the profession window reads it (a new Iron Bar, bind unknown) and rebuilds once;
  -- the item data arriving 1 s later stores bind 0, so the rebuild drops the bar again.
  local window = booted({ "read: prof=164 stored=3 pendingBind=1", "index: size=5" })
  Assert.same(stepLines(Sim.Run({ "--event", "TRADE_SKILL_SHOW" })), window)
  Assert.same(stepLines(Sim.Run({ "--flavor", "forever", "--event", "TRADE_SKILL_SHOW" })), window)
  Assert.same(
    stepLines(Sim.Run({ "--event", "TRADE_SKILL_SHOW", "--event", "GET_ITEM_INFO_RECEIVED", "190005", "true" })),
    booted({ "read: prof=164 stored=3 pendingBind=1", "index: size=5", "bind: stored=1", "index: size=4" })
  )
  Assert.same(stepLines(Sim.Run({ "--flavor", "tbc", "--event", "TRADE_SKILL_SHOW" })), booted({}, "Trade"))

  -- A recipe read from the window keeps Blizzard's spelling, so the greeting names it as the game does.
  local greeted = {}
  for _, line in ipairs(Sim.Run({ "--event", "TRADE_SKILL_SHOW", "LF plate belt crafter" })) do
    if string.find(line, "^greeting: ") then
      greeted[#greeted + 1] = line
    end
  end
  Assert.same(greeted, { "greeting: Hi! I can craft Sim Plate Belt." })

  -- The pending lead expiry timer (601 s) does not run when item data arrives.
  for _, line in ipairs(Sim.Run({ "LF plate belt", "--event", "TRADE_SKILL_SHOW", "--event", "GET_ITEM_INFO_RECEIVED", "190005", "true" })) do
    assert(not string.find(line, "^error: "), line)
  end

  -- A learned recipe is stored at once; the coalesced rebuild makes it matchable.
  Assert.same(
    stepLines(Sim.Run({ "--event", "NEW_RECIPE_LEARNED", "9004", "LF Sim Plate Helm" })),
    booted({
      "learn: stored=true",
      "index: size=5",
      "sender: Customer-OtherRealm",
      "match: item group=190004 prof=164 why=lf+sim plate helm",
      "toast: shown lead=1 more=0",
      "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=true",
      "greeting: Hi! I can craft |cffffffff|Hitem:190004|h[Item 190004]|h|r.",
    })
  )
  Assert.same(stepLines(Sim.Run({ "--event", "NEW_RECIPE_LEARNED", "123" })), booted({ "learn: stored=false" }))

  Assert.equal(Sim.Run({ "--event" })[1], "error: --event needs an event name")

  local unknownFlag = Sim.Run({ "--nope" })
  Assert.equal(#unknownFlag, 1)
  assert(string.find(tostring(unknownFlag[1]), "^error: unknown flag"), unknownFlag[1])

  assert(string.find(Sim.Run({ "--flavor", "cataclysm" })[1], "^error: unknown flavor"))
  assert(string.find(Sim.Run({ "--flavor" })[1], "^error: .* needs a value"))
  assert(string.find(Sim.Run({ "--db", "tools/does_not_exist.lua" })[1], "^error: cannot read db"))
  assert(string.find(Sim.Run({ "--click", "middle" })[1], "^error: "))

  -- The default fixture is the account DB before any module touches it.
  Sim.Run({})
  local db = rawget(_G, "CraftAlertDB")
  Assert.truthy(db.characters["Crafter-OwnRealm"])
  Assert.truthy(db.characters["Alt-OwnRealm"])

  -- --afk applies before the first chat line.
  Sim.Run({ "--afk", "on", "--resting", "off", "LF plate belt" })
  Assert.equal(rawget(_G, "UnitIsAFK")("player"), true)
  Assert.equal(rawget(_G, "IsResting")(), false)
  Sim.Run({ "--afk", "off" })
  Assert.equal(rawget(_G, "UnitIsAFK")("player"), false)
  Assert.equal(rawget(_G, "IsResting")(), true)

  -- --cmd routes through SlashCmdList.CRAFTALERT (registered by Bootstrap at PLAYER_LOGIN);
  -- what the command prints arrives as `chat:` lines, after the start-up build's three.
  -- A test line makes a test lead and a toast; the click prints what it would send and sends nothing.
  local test = stepLines(Sim.Run({ "--cmd", "/ca test LF plate belt crafter", "--click", "left" }))
  Assert.equal(test[4], "match: item group=190001 prof=164 why=lf+plate+belt")
  Assert.equal(test[5], "toast: shown lead=1 more=0")
  Assert.equal(test[6], "lead: new customer=Test0-OwnRealm crafter=Crafter-OwnRealm cannotOrder=false")
  Assert.equal(test[8], "chat: Craft Alert: Item: Sim Plate Belt")
  Assert.equal(test[11], "chat: Craft Alert: Greeting: Hi! I can craft Sim Plate Belt.")
  Assert.equal(test[13], "chat: Craft Alert: Test, would whisper Test0-OwnRealm: Hi! I can craft Sim Plate Belt.")
  Assert.equal(test[14], "lead: greeted customer=Test0-OwnRealm")
  for _, line in ipairs(test) do
    Assert.falsy(string.find(line, "^send: "), line)
  end
  Assert.equal(rawget(_G, "SLASH_CRAFTALERT2"), "/ca")
  Assert.equal(stepLines(Sim.Run({ "--cmd", "/ca test hello there" }))[4], "chat: Craft Alert: No match (stopped at: prefilter)")
  Assert.equal(
    stepLines(Sim.Run({ "--cmd", "/ca nonsense" }))[4],
    "chat: Craft Alert: Commands: /ca (leads window), /ca config, /ca test <line>, /ca perf"
  )

  -- The account DB goes through SavedState.Load first: one `db:` line, preceded by one
  -- `chat:` line per Schema warning.
  Assert.equal(Sim.Run({})[2], "db: schema=1 characters=2 recipes=6 leads=0")
  local newer = Sim.Run({ "--db", "tests/fixtures/db_schema2.lua" })
  Assert.equal(#newer, 3)
  assert(string.find(newer[2], "^chat: Craft Alert: .*newer"), newer[2])
  Assert.equal(newer[3], "db: schema=2 characters=1 recipes=2 leads=100")

  -- Run from the command line, any `error:` line makes the sim exit 1, so a Proof run notices a
  -- broken invocation: a bad flag (the only line) or a step that fails after others printed.
  local printed, code = runMain({ "--nope" })
  Assert.equal(code, 1)
  assert(string.find(printed[1], "^error: unknown flag"), printed[1])
  printed, code = runMain({ "--click", "left" })
  Assert.equal(code, 1)
  Assert.equal(printed[#printed], "error: --click left has no lead to act on")
  printed, code = runMain({ "LF plate belt" })
  Assert.equal(code, nil, "a clean run does not exit")
  Assert.truthy(#printed > 1)
end
