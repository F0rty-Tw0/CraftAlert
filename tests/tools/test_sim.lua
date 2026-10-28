local Assert = require("tests.helpers.assert")
local Toc = require("tests.helpers.toc")
local Wow = require("tests.helpers.wow")

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

-- The lines a run printed after its `db:` line: what the steps themselves produced, without the
-- closing `ledger:` and `away:` lines (asserted on their own).
local function stepLines(lines)
  for index, line in ipairs(lines) do
    if string.find(line, "^db: ") then
      local steps = {}
      for i = index + 1, #lines do
        if not string.find(lines[i], "^ledger: ") and not string.find(lines[i], "^away: ") then
          steps[#steps + 1] = lines[i]
        end
      end
      return steps
    end
  end
  error("no db: line in " .. table.concat(lines, " / "))
end

local function isRegistered(event)
  for _, frame in ipairs(Wow.frames) do
    if frame.events[event] then
      return true
    end
  end
  return false
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
  -- Newest expansion default: the window read mutes the older line of the seeded profession
  -- (8001, 8002 on line 2540) and leaves the newest line (9010 on 2872) on; chat stays silent.
  local seeded = Sim.Run({ "--db", "tools/sim_fixture_newest.lua", "--event", "TRADE_SKILL_SHOW" })
  local recipes = rawget(_G, "CraftAlertDB").characters["Crafter-OwnRealm"].recipes
  Assert.same({ recipes[8001].muted, recipes[8002].muted, recipes[9010].muted }, { true, true, nil })
  Assert.equal(rawget(_G, "CraftAlertDB").characters["Crafter-OwnRealm"].professions[164].newestLine, 2872)
  for _, line in ipairs(seeded) do
    Assert.falsy(string.find(line, "now alerts only", 1, true), line)
  end
  -- Classic: the TradeSkill window (every Classic flavor) and Enchanting's Craft window (Era, TBC)
  -- are read into name keys; the new recipe matches by name, the greeting keeps the client's spelling.
  local classicWindow =
    booted({ "professions: blacksmithing,enchanting", "read: prof=blacksmithing stored=3 pendingBind=1", "index: size=5" }, "Trade")
  for _, key in ipairs({ "era", "tbc", "wrath", "cata", "mop" }) do
    Assert.same(stepLines(Sim.Run({ "--flavor", key, "--event", "TRADE_SKILL_SHOW" })), classicWindow, key)
  end
  local craftWindow = booted({ "professions: blacksmithing,enchanting", "read: prof=enchanting stored=2 pendingBind=0", "index: size=5" }, "Trade")
  Assert.same(stepLines(Sim.Run({ "--flavor", "tbc", "--event", "CRAFT_SHOW" })), craftWindow)
  Assert.same(stepLines(Sim.Run({ "--flavor", "era", "--event", "CRAFT_SHOW" })), craftWindow)
  Assert.same(stepLines(Sim.Run({ "--flavor", "wrath", "--event", "CRAFT_SHOW" })), booted({ "professions: blacksmithing,enchanting" }, "Trade"))
  Assert.same(
    stepLines(Sim.Run({ "--flavor", "tbc", "--event", "CRAFT_SHOW", "--event", "CRAFT_CLOSE", "LF enchant boots sim agility" })),
    booted({
      "professions: blacksmithing,enchanting",
      "read: prof=enchanting stored=2 pendingBind=0",
      "index: size=5",
      "sender: Customer-OtherRealm",
      "match: item group=enchant boots - sim agility prof=enchanting why=lf+enchant boots sim agility",
      "toast: shown lead=1 more=0",
      "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=false",
      "greeting: Hi! I can craft Enchant Boots - Sim Agility.",
    }, "Trade")
  )

  -- Classic flavors log in on the Classic fixture (name keys): Bootstrap reads the professions
  -- (skill lines on Era/TBC/Wrath, GetProfessions on Cata/MoP) and listens for skill-line changes.
  for _, key in ipairs({ "era", "tbc", "wrath", "cata", "mop" }) do
    Assert.same(
      stepLines(Sim.Run({ "--flavor", key, "--event", "PLAYER_UPDATE_RESTING" })),
      booted({ "professions: blacksmithing,enchanting" }, "Trade"),
      key
    )
    Assert.truthy(isRegistered("SKILL_LINES_CHANGED"), key)
  end

  -- Recipe markers: the row callback registers once Blizzard_Professions loads, on Retail and Forever.
  local markers = booted({ "markers: installed modern" })
  Assert.same(stepLines(Sim.Run({ "--event", "ADDON_LOADED", "Blizzard_Professions" })), markers)
  Assert.same(stepLines(Sim.Run({ "--flavor", "forever", "--event", "ADDON_LOADED", "Blizzard_Professions" })), markers)
  Assert.same(
    stepLines(Sim.Run({ "--flavor", "tbc", "--event", "ADDON_LOADED", "Blizzard_Professions" })),
    booted({ "professions: blacksmithing,enchanting" }, "Trade"),
    "no Retail markers on Classic"
  )
  -- On Classic, the window's update is hooked once its addon loads; the Craft window on Era and TBC only.
  local function classicMarkers(flavor, addon)
    return stepLines(Sim.Run({ "--flavor", flavor, "--event", "ADDON_LOADED", addon }))
  end
  local professions = "professions: blacksmithing,enchanting"
  Assert.same(classicMarkers("tbc", "Blizzard_TradeSkillUI"), booted({ professions, "markers: installed tradeskill" }, "Trade"))
  Assert.same(classicMarkers("tbc", "Blizzard_CraftUI"), booted({ professions, "markers: installed craft" }, "Trade"))
  Assert.same(classicMarkers("mop", "Blizzard_TradeSkillUI"), booted({ professions, "markers: installed tradeskill" }, "Trade"))
  Assert.same(classicMarkers("mop", "Blizzard_CraftUI"), booted({ professions }, "Trade"), "no Craft window on MoP")

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

  -- Classic: the learn message adds the name to the session's pending list; it matches by name at
  -- once, crafted by the current character, and the greeting keeps the client's spelling.
  local learnMessage = "You have learned how to create a new item: Enchant Boots - Sim Agility."
  Assert.same(
    stepLines(Sim.Run({ "--flavor", "tbc", "--event", "CHAT_MSG_SYSTEM", learnMessage, "LF enchant boots sim agility" })),
    booted({
      "professions: blacksmithing,enchanting",
      "learn: pending=Enchant Boots - Sim Agility",
      "index: size=5",
      "sender: Customer-OtherRealm",
      "match: item group=enchant boots - sim agility prof=nil why=lf+enchant boots sim agility",
      "toast: shown lead=1 more=0",
      "lead: new customer=Customer-OtherRealm crafter=Crafter-OwnRealm cannotOrder=false",
      "greeting: Hi! I can craft Enchant Boots - Sim Agility.",
    }, "Trade")
  )

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
  Assert.equal(stepLines(Sim.Run({ "--cmd", "/ca test hello there" }))[4], "chat: Craft Alert: No match: the line does not look like a request")
  Assert.equal(
    stepLines(Sim.Run({ "--cmd", "/ca nonsense" }))[4],
    "chat: Craft Alert: Commands: /ca (leads window), /ca config, /ca test <line>, /ca perf"
  )

  -- The account DB goes through SavedState.Load first: one `db:` line. A newer schema's warning
  -- prints with the login lines, before the build lands and the gate's status line.
  Assert.equal(Sim.Run({})[2], "db: schema=1 characters=2 recipes=6 leads=0")
  Assert.equal(#Sim.Run({ "--db", "tests/fixtures/db_schema2.lua" }), 2)
  local newer = Sim.Run({ "--db", "tests/fixtures/db_schema2.lua", "LF plate belt" })
  Assert.equal(newer[2], "db: schema=2 characters=1 recipes=2 leads=100")
  assert(string.find(newer[3], "^chat: Craft Alert: .*newer"), newer[3])
  local warnings = 0
  for _, line in ipairs(newer) do
    if string.find(line, "^chat: Craft Alert: .*newer") then
      warnings = warnings + 1
    end
  end
  Assert.equal(warnings, 1, "one newer-schema warning per load")

  -- Spec §8: a run that changed a ledger counter ends with today's counters. The repeated request
  -- updates the lead (no second "seen"), the click greets it once.
  local ledger = Sim.Run({ "LF plate belt", "LF plate belt", "--click", "left" })
  Assert.equal(ledger[#ledger], "ledger: seen=1 greeted=1 replied=0 filled=0")
  -- The greeted customer's order filled: the event names them without a realm (5 arguments, so a
  -- chat line may follow).
  local fill = { "--event", "CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG", "Public", "Belt", "Customer", "0", "1" }
  local filled = Sim.Run({ "LF plate belt", "--click", "left", unpack(fill) })
  Assert.equal(filled[#filled], "ledger: seen=1 greeted=1 replied=0 filled=1")
  local stranger = Sim.Run({ "LF plate belt", "--click", "left", fill[1], fill[2], "Public", "Belt", "Stranger", "0", "1", "WTS belt" })
  Assert.equal(stranger[#stranger], "ledger: seen=1 greeted=1 replied=0 filled=0")
  Assert.equal(#senderLines(stranger), 2, "the line after the event's 5 arguments is a chat line")
  local quiet = Sim.Run({ "WTS plate belt" })
  Assert.falsy(string.find(quiet[#quiet], "^ledger: "), "no counter changed: no ledger line")

  -- Spec §7.6: a request while AFK, then --afk off (PLAYER_FLAGS_CHANGED for the player): one away
  -- summary, before the closing ledger line.
  local away = Sim.Run({ "--afk", "on", "LF plate belt", "--afk", "off" })
  Assert.same({ away[#away - 1], away[#away] }, { "away: summary count=1 expired=0", "ledger: seen=1 greeted=0 replied=0 filled=0" })

  -- Spec §10.1: --export prints the fixture's export string; --import of it into a second account's
  -- db stores Alt-OwnRealm (the player's own character is skipped) and the index rebuild follows.
  local exported = Sim.Run({ "--export" })
  local text = string.match(exported[#exported], "^export: (CA1:retail:.+)$")
  assert(text, exported[#exported])
  local imported = table.concat(Sim.Run({ "--db", "tests/fixtures/db_export_target.lua", "--import", text, "LF plate belt" }), " / ")
  Assert.truthy(imported:find("import: characters=1 recipes=3 skipped=1 / index: size=4", 1, true), imported)
  Assert.truthy(imported:find("crafter=Alt-OwnRealm", 1, true), imported)
  local refused = Sim.Run({ "--import", (string.gsub(text, "Sim Plate Belt", "Sim Plate Bolt")) })
  Assert.equal(refused[#refused], "import: error The string is damaged (checksum).")
  Assert.equal(Sim.Run({ "--import" })[1], "error: --import needs a value")

  -- Spec §10.2: --craftscan imports the CraftScan fixture; its alt answers the request.
  local scanned = table.concat(Sim.Run({ "--craftscan", "tests/fixtures/craftscan_db.lua", "LF Sim Plate Helm" }), " / ")
  local counts = "craftscan: characters=3 recipes=5 muted=3 greetings=2 skipped=5"
  local muted = "craftscan: muted Nosource-Kel'Thuzad:9003,Old-Legacyrealm:9005,Scanalt-OwnRealm:9005"
  Assert.truthy(scanned:find(counts .. " / " .. muted .. " / index: size=6", 1, true), scanned)
  Assert.truthy(scanned:find("crafter=Scanalt-OwnRealm", 1, true), scanned)
  local missing = Sim.Run({ "--craftscan", "tests/fixtures/no_such_file.lua" })
  Assert.equal(missing[#missing], "error: --craftscan tests/fixtures/no_such_file.lua holds no CraftScan_DB table")

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
