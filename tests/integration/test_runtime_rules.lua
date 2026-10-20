-- Spec §4.3 runtime rules and §13 "Runtime rules": loads the whole addon from the TOC under
-- trapping stubs (tests/helpers/runtime_traps.lua) and drives every Install/Restore plus a
-- greeting, so a violation raises where it happens. From Task 1.19 this drives Bootstrap.
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")
local RuntimeTraps = require("tests.helpers.runtime_traps")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local OWN_KEY = "Crafter-OwnRealm"
local CHANNEL, PLAYER_RESTING = "CHAT_MSG_CHANNEL", "PLAYER_UPDATE_RESTING"
-- Timer delays the plan allows (§4.3 rule 1): index coalescing 0, bind tick 1, lead expiry
-- (timeout + 1 s, 601 with the default 10 min).
local ALLOWED_DELAYS = { [0] = true, [1] = true, [601] = true }
-- Own globals the tests below create (Wow.stub restores only what it stubbed).
local OWN_GLOBALS_SET = { "CraftAlertDB", "CraftAlert_GreetLatest", "BINDING_NAME_CRAFTALERT_GREET", "SLASH_CRAFTALERT1" }

-- A global by name: the language server must not infer a stub's type from these writes.
local function G(name)
  return _G[name]
end

-- Installs the Blizzard stubs the addon touches, recording every send in `sent`.
local function installBlizzard(sent)
  local function record(api)
    return function(...)
      sent[#sent + 1] = { api, ... }
    end
  end
  Wow.stub("C_ChatInfo", { SendAddonMessage = record("addon"), SendChatMessage = record("chat") })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = record("prefill"), SendTell = record("empty") })
  Wow.stub("GameTooltip", {
    shown = false,
    Show = function(self)
      self.shown = true
    end,
  })
  Wow.stub("ProfessionsFrame", { CraftingPage = { RecipeList = { ScrollBox = {} } } })
  Wow.stub("SlashCmdList", {})
  Wow.stub("UISpecialFrames", {})
  Wow.stub("Settings", {})
end

-- Every .lua file of the TOC, in order, into one ns; the require fallback must stay unused.
local function loadAddon()
  local ns = {}
  local savedRequire = _G.require
  rawset(_G, "require", function(moduleName)
    error("require fallback reached: " .. tostring(moduleName))
  end)
  local ok, err = pcall(function()
    for _, path in ipairs(Toc.luaFiles()) do
      assert(loadfile(path))("CraftAlert", ns)
    end
  end)
  rawset(_G, "require", savedRequire)
  assert(ok, tostring(err))
  return ns
end

-- A request the fixture crafter can fill, as the chat event delivers it on Trade.
local function fireRequest(text, sender)
  Wow.fireEvent(CHANNEL, text, sender, "", "2. Trade - City", sender, "", 2, 2, "Trade - City", 0, 1, nil)
end

local function publicChatEvents()
  local events = {}
  for event in pairs(Wow.frames[1] and Wow.frames[1].events or {}) do
    if string.find(event, "^CHAT_MSG_") then
      events[#events + 1] = event
    end
  end
  table.sort(events)
  return events
end

-- Runs fn with the traps installed; always removes them and resets the stubs.
local function withTraps(fn)
  Wow.reset()
  Wow.flavor("retail")
  local state = { resting = true, scanActive = false }
  state.isActive = function()
    return state.scanActive
  end
  local restore = nil
  local ok, err = pcall(function()
    Wow.stub("IsResting", function()
      return state.resting
    end)
    Wow.stub("UnitName", function()
      return "Crafter"
    end)
    Wow.stub("GetNormalizedRealmName", function()
      return "OwnRealm"
    end)
    Wow.stub("UnitIsAFK", function()
      return false
    end)
    local sent = {}
    installBlizzard(sent)
    ProfessionsRetail.install({
      slots = { { name = "Blacksmithing", skillLine = 164 } },
      base = 164,
      items = { [190001] = { "INVTYPE_WAIST", 4, 4 } },
      bind = { [190001] = 2 },
      autoCache = true,
    })
    restore = RuntimeTraps.install({
      isScanActive = function()
        return state.isActive()
      end,
    })
    fn(state, sent)
  end)
  if restore then
    restore()
  end
  for _, name in ipairs(OWN_GLOBALS_SET) do
    rawset(_G, name, nil)
  end
  Wow.reset()
  assert(ok, tostring(err))
end

-- Source of a shipped file without its comments (a comment may name what the code avoids).
local function codeOf(path)
  local handle = assert(io.open(path, "r"))
  local lines = {}
  for line in handle:lines() do
    lines[#lines + 1] = (string.gsub(line, "%-%-.*$", ""))
  end
  handle:close()
  return table.concat(lines, "\n")
end

local function testTrapsCatchViolations()
  withTraps(function(state)
    -- Blizzard tables: reads and method calls work, any write raises (new field or overwrite).
    local before = rawget(_G, "GameTooltip").Show
    Assert.raises(function()
      G("GameTooltip").Show = function() end
    end, "write to Blizzard table GameTooltip.Show")
    Assert.raises(function()
      G("GameTooltip").Extra = 1
    end, "GameTooltip.Extra")
    Assert.raises(function()
      G("UIParent").Extra = 1
    end, "UIParent.Extra")
    Assert.raises(function()
      G("ProfessionsFrame").CraftingPage.RecipeList.ScrollBox.Extra = 1
    end, "ScrollBox.Extra")
    Assert.raises(function()
      G("C_Timer").After = function() end
    end, "C_Timer.After")
    Assert.raises(function()
      G("SlashCmdList").OTHER = function() end
    end, "SlashCmdList.OTHER")
    Assert.equal(rawget(_G, "GameTooltip").Show, before, "nothing was overwritten")
    G("GameTooltip"):Show()
    Assert.equal(rawget(_G, "GameTooltip").shown, true, "methods run on the real table")
    G("SlashCmdList").CRAFTALERT = function() end
    Assert.equal(type(G("SlashCmdList").CRAFTALERT), "function")

    -- Globals: only our own names.
    Assert.raises(function()
      _G.Foo = 1
    end, "write to global Foo")
    _G.CraftAlertDB = {}
    _G.CraftAlert_GreetLatest = function() end
    _G.BINDING_NAME_CRAFTALERT_GREET = "Greet"
    _G.SLASH_CRAFTALERT1 = "/ca"
    Assert.raises(function()
      _G.BINDING_NAME_OTHER = "x"
    end, "BINDING_NAME_OTHER")

    -- Frames: own names only, no OnUpdate, no public chat event while the scan is inactive.
    Assert.raises(function()
      G("CreateFrame")("Frame", "Foo")
    end, "frame name Foo")
    local frame = G("CreateFrame")("Frame", "CraftAlertToast")
    Assert.raises(function()
      frame:SetScript("OnUpdate", function() end)
    end, "OnUpdate")
    Assert.raises(function()
      frame:HookScript("OnUpdate", function() end)
    end, "OnUpdate")
    frame:SetScript("OnEvent", function() end)
    Assert.raises(function()
      frame:RegisterEvent("CHAT_MSG_CHANNEL")
    end, "scan is inactive")
    Assert.raises(function()
      frame:RegisterEvent("CHAT_MSG_GUILD")
    end, "scan is inactive")
    frame:RegisterEvent("CHAT_MSG_WHISPER")
    frame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    frame:RegisterEvent("PLAYER_LOGIN")
    state.scanActive = true
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
  end)
  Assert.equal(getmetatable(_G), nil, "the _G trap is removed")
end

local function testAddonObeysTheRules()
  withTraps(function(state, sent)
    local ns = loadAddon()
    -- The account DB goes through SavedState.Load exactly as at ADDON_LOADED.
    local db = ns.SavedState.Load()
    Assert.equal(rawget(_G, "CraftAlertDB"), db)
    db.characters = dofile("tools/sim_fixture.lua").characters
    ns.PlayerName.Init()
    ns.Leads.Restore(db)
    ns.ProfessionList.Refresh(db, OWN_KEY)
    ns.ModernReader.Install(db)
    ns.LearnWatcher.Install()
    ns.Index.Configure(db, { professionOrder = ns.ProfessionList.Order })
    ns.Index.OnRebuilt(ns.Matcher.SetIndex)
    ns.WhisperTracker.Install()
    ns.ScanGate.Install(db)
    -- The trap asks the gate itself, so a registration made before the gate flips raises.
    state.isActive = ns.ScanGate.IsActive
    ns.Index.OnRebuilt(ns.ScanGate.Evaluate)
    ns.Bootstrap.Install()

    -- Nothing listens to public chat before the first evaluation; whisper events wait for a lead.
    Assert.same(publicChatEvents(), {})
    -- Activating registers the channel event (the trap saw the gate already active).
    ns.Index.Rebuild()
    Assert.equal(ns.ScanGate.IsActive(), true)
    Assert.same(publicChatEvents(), { CHANNEL })

    -- Leaving the city drops it again; entering brings it back.
    state.resting = false
    Wow.fireEvent(PLAYER_RESTING)
    Assert.same(publicChatEvents(), {}, "paused: no public chat event")
    state.resting = true
    Wow.fireEvent(PLAYER_RESTING)
    Assert.same(publicChatEvents(), { CHANNEL })

    -- A request becomes a lead (whisper events on), a greeting goes out: notice, then whisper.
    fireRequest("LF plate belt", "Customer-OtherRealm")
    local lead = ns.Leads.Latest()
    Assert.truthy(lead, "the request made a lead")
    Assert.same(publicChatEvents(), { CHANNEL, "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" })
    ns.GreetAction.Greet(lead, rawget(_G, "GetTime")() - 1)
    Assert.equal(sent[1][1], "addon")
    Assert.equal(sent[2][1], "chat")
    Assert.equal(lead.greeted, true)
    ns.GreetAction.Prefill(lead)
    ns.GreetAction.Empty(lead)
    Assert.equal(sent[3][1], "prefill")
    Assert.equal(sent[4][1], "empty")

    -- The last lead gone: whisper events go too. Only the allowed timers are pending.
    ns.Leads.Dismiss(lead.id)
    Assert.same(publicChatEvents(), { CHANNEL })
    for _, timer in ipairs(Wow.timers) do
      Assert.truthy(ALLOWED_DELAYS[timer.delay], "timer with delay " .. tostring(timer.delay))
    end
    for _, frame in ipairs(Wow.frames) do
      Assert.equal(frame.scripts.OnUpdate, nil, "no OnUpdate script")
    end
  end)
end

-- Shipped folders only (the TOC lists exactly those): tools/ is not in it.
local function testSourceRules()
  local sendsAddonMessage = {}
  for _, path in ipairs(Toc.luaFiles()) do
    local code = codeOf(path)
    if string.find(path, "Tokenizer.lua", 1, true) or string.find(path, "Matcher.lua", 1, true) then
      Assert.falsy(string.find(code, "gmatch", 1, true), path .. " uses gmatch on the hot path")
    end
    if string.find(code, "SendAddonMessage", 1, true) then
      sendsAddonMessage[#sendsAddonMessage + 1] = path
    end
  end
  Assert.same(sendsAddonMessage, { "Model/GreetAction.lua" }, "only the greeting sends an addon message")
end

return function()
  testTrapsCatchViolations()
  testAddonObeysTheRules()
  testSourceRules()
end
