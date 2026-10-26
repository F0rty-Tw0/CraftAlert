-- Spec §4.3 runtime rules and §13 "Runtime rules": loads the whole addon from the TOC under
-- trapping stubs (tests/helpers/runtime_traps.lua) and drives Bootstrap (ADDON_LOADED,
-- PLAYER_LOGIN), a matched line and a click, then the UI, the settings and the slash
-- commands, so a violation raises where it happens.
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")
local RuntimeTraps = require("tests.helpers.runtime_traps")
local ProfessionsRetail = require("tests.helpers.professions_retail")
local RecipeListStub = require("tests.helpers.recipe_list_stub")
local SettingsFixture = require("tests.helpers.settings_fixture")
local Widgets = require("tests.helpers.widgets")

local CHANNEL, PLAYER_RESTING = "CHAT_MSG_CHANNEL", "PLAYER_UPDATE_RESTING"
-- Timer delays the plan allows (§4.3 rule 1): index coalescing 0, bind tick 1, toast auto-hide
-- (20 s by default), lead expiry (timeout + 1 s, 601 with the default 10 min).
local ALLOWED_DELAYS = { [0] = true, [1] = true, [20] = true, [601] = true }
-- Own globals the tests below and Core/Bindings.lua create (Wow.stub restores only what it stubbed).
local OWN_GLOBALS_SET = {
  "CraftAlertDB",
  "SLASH_CRAFTALERT1",
  "SLASH_CRAFTALERT2",
  "CraftAlert_GreetLatest",
  "CraftAlert_DismissLatest",
  "CraftAlert_ToggleLeads",
  "BINDING_HEADER_CRAFTALERT",
  "BINDING_NAME_CRAFTALERT_GREET",
  "BINDING_NAME_CRAFTALERT_DISMISS",
  "BINDING_NAME_CRAFTALERT_TOGGLE",
}

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
    SetOwner = function() end,
    SetText = function() end,
    AddLine = function() end,
    ClearLines = function() end,
    Show = function(self)
      self.shown = true
    end,
    Hide = function(self)
      self.shown = false
    end,
    IsOwned = function()
      return false
    end,
  })
  Wow.stub("SlashCmdList", {})
  Wow.stub("UISpecialFrames", {})
  Wow.stub("Settings", {
    RegisterCanvasLayoutCategory = function(frame, name)
      return { frame = frame, name = name }
    end,
    RegisterAddOnCategory = function() end,
  })
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

-- The public chat events any frame the addon made listens for, sorted, once each.
local function publicChatEvents()
  local seen, events = {}, {}
  for _, frame in ipairs(Wow.frames) do
    for event in pairs(frame.events) do
      if string.find(event, "^CHAT_MSG_") and not seen[event] then
        seen[event] = true
        events[#events + 1] = event
      end
    end
  end
  table.sort(events)
  return events
end

-- Runs fn(state, sent, verify) with the traps installed, then verifies what the metatables could
-- not see; always removes the traps and resets the stubs. `learnSignal`: the flavor chose the
-- Classic learn signal (CHAT_MSG_SYSTEM allowed).
local function withTraps(fn, learnSignal)
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
    Wow.stub("ChatFrame_OpenChat", function() end)
    local sent = {}
    installBlizzard(sent)
    -- Blizzard's recipe list (ProfessionsFrame, ScrollUtil) behind the traps; its rows are made
    -- after RuntimeTraps.install, so they are proxies too.
    state.list = RecipeListStub.install({ recipes = { [9001] = { learned = true } } })
    ProfessionsRetail.install({
      slots = { { name = "Blacksmithing", skillLine = 164 } },
      base = 164,
      items = { [190001] = { "INVTYPE_WAIST", 4, 4 } },
      bind = { [190001] = 2 },
      autoCache = true,
    })
    local verify
    restore, verify = RuntimeTraps.install({
      isScanActive = function()
        return state.isActive()
      end,
      learnSignal = learnSignal,
    })
    fn(state, sent, verify)
    verify()
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
  withTraps(function(state, _, verify)
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

    -- Globals: only our own names. A new name raises at the write.
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
    verify()

    -- An existing global has no __newindex to hit, so verify() reports the overwrite by name
    -- (rule 3: never replace what Blizzard defined). Each case is undone before the next.
    local isResting, openChat, chatUtil = rawget(_G, "IsResting"), rawget(_G, "ChatFrame_OpenChat"), rawget(_G, "ChatFrameUtil")
    _G.IsResting = function() end
    Assert.raises(verify, "existing global IsResting was overwritten")
    rawset(_G, "IsResting", isResting)
    _G["ChatFrame_OpenChat"] = function() end
    Assert.raises(verify, "existing global ChatFrame_OpenChat was overwritten")
    rawset(_G, "ChatFrame_OpenChat", openChat)
    _G.ChatFrameUtil = {}
    Assert.raises(verify, "existing global ChatFrameUtil was overwritten")
    rawset(_G, "ChatFrameUtil", chatUtil)
    local slash = rawget(_G, "SlashCmdList")
    _G.SlashCmdList = {} -- only SlashCmdList.CRAFTALERT is ours, never the table itself
    Assert.raises(verify, "existing global SlashCmdList was overwritten")
    rawset(_G, "SlashCmdList", slash)
    _G.IsResting = nil
    Assert.raises(verify, "existing global IsResting was overwritten or removed")
    rawset(_G, "IsResting", isResting)
    rawset(_G, "Foo", 1) -- a new global that skips __newindex
    Assert.raises(verify, "new global Foo")
    rawset(_G, "Foo", nil)
    verify()

    -- Raw writes skip a proxy's __newindex; verify() finds what landed in it. The leads window's
    -- frame name in UISpecialFrames is the one sanctioned insert (rule 3): any other name traps,
    -- our own prefix and the old settings window's included.
    rawset(G("C_Timer"), "After", function() end)
    Assert.raises(verify, "raw write into Blizzard table C_Timer%[After%]")
    rawset(G("C_Timer"), "After", nil)
    rawset(G("ProfessionsFrame").CraftingPage, "Extra", 1)
    Assert.raises(verify, "ProfessionsFrame.CraftingPage%[Extra%]")
    rawset(G("ProfessionsFrame").CraftingPage, "Extra", nil)
    table.insert(G("UISpecialFrames"), "SomeoneElsesFrame")
    Assert.raises(verify, "UISpecialFrames%[1%]")
    rawset(G("UISpecialFrames"), 1, nil)
    table.insert(G("UISpecialFrames"), "CraftAlertWindow")
    Assert.raises(verify, "UISpecialFrames%[1%]")
    rawset(G("UISpecialFrames"), 1, nil)
    table.insert(G("UISpecialFrames"), "CraftAlertLeadsWindow")
    verify()
    table.insert(G("UISpecialFrames"), "CraftAlertSettingsWindow")
    Assert.raises(verify, "UISpecialFrames%[2%]")
    rawset(G("UISpecialFrames"), 2, nil)
    rawset(G("UISpecialFrames"), 1, nil)

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
    frame:RegisterEvent("PLAYER_LOGIN")

    -- Addon messages are never listened for, scanning or not (rule 5); CHAT_MSG_SYSTEM needs the
    -- Classic learn signal (rule 4), which this run does not have.
    local function forbidden(event)
      Assert.raises(function()
        frame:RegisterEvent(event)
      end, "rule [45]")
    end
    forbidden("CHAT_MSG_ADDON")
    forbidden("CHAT_MSG_ADDON_LOGGED")
    forbidden("CHAT_MSG_SYSTEM")
    state.scanActive = true
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
    forbidden("CHAT_MSG_ADDON")
    forbidden("CHAT_MSG_ADDON_LOGGED")
    forbidden("CHAT_MSG_SYSTEM")
    -- publicChatEvents looks at every frame, not only the first.
    G("CreateFrame")("Frame", "CraftAlertSecond"):RegisterEvent("CHAT_MSG_GUILD")
    Assert.same(publicChatEvents(), { "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" })
  end)
  Assert.equal(getmetatable(_G), nil, "the _G trap is removed")
end

-- A flavor that chose the Classic learn signal (§5.3) may listen to system messages, and only
-- that flavor; addon messages stay forbidden for it too.
local function testLearnSignalAllowsSystemEvents()
  withTraps(function()
    local frame = G("CreateFrame")("Frame", "CraftAlertLearn")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    Assert.raises(function()
      frame:RegisterEvent("CHAT_MSG_ADDON")
    end, "rule 5")
    Assert.same(publicChatEvents(), { "CHAT_MSG_SYSTEM" })
  end, true)
end

local function testAddonObeysTheRules()
  withTraps(function(state, sent, verify)
    local ns = loadAddon()
    -- The trap asks the gate itself, so a registration made before the gate flips raises.
    state.isActive = ns.ScanGate.IsActive
    -- Bootstrap does every install, from the two events the client fires: ADDON_LOADED binds
    -- the account DB (the fixture characters go in before login), PLAYER_LOGIN the rest.
    Wow.fireEvent("ADDON_LOADED", "CraftAlert")
    local db = rawget(_G, "CraftAlertDB")
    Assert.truthy(db, "ADDON_LOADED bound the account DB")
    db.characters = dofile("tools/sim_fixture.lua").characters
    Assert.same(publicChatEvents(), {}, "nothing listens before login")
    Wow.fireEvent("PLAYER_LOGIN")
    Assert.equal(ns.Leads.HasActive(), false)
    Assert.same({ rawget(_G, "SLASH_CRAFTALERT1"), rawget(_G, "SLASH_CRAFTALERT2") }, { "/craftalert", "/ca" })

    -- The login rebuild activated the scan: the channel event only (the trap saw the gate
    -- already active); whisper events wait for a lead.
    Assert.equal(ns.ScanGate.IsActive(), true)
    Assert.same(publicChatEvents(), { CHANNEL })

    -- Leaving the city drops it again; entering brings it back.
    state.resting = false
    Wow.fireEvent(PLAYER_RESTING)
    Assert.same(publicChatEvents(), {}, "paused: no public chat event")
    state.resting = true
    Wow.fireEvent(PLAYER_RESTING)
    Assert.same(publicChatEvents(), { CHANNEL })

    -- A request becomes a lead and its toast (whisper events on); a left-click on the toast
    -- greets: notice, then whisper.
    fireRequest("LF plate belt", "Customer-OtherRealm")
    local lead = ns.Leads.Latest()
    Assert.truthy(lead, "the request made a lead")
    Assert.same(publicChatEvents(), { CHANNEL, "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" })
    local toast = G("CraftAlertToast")
    Assert.equal(toast:IsShown(), true, "Bootstrap shows the toast for a new lead")
    Wow.clock.gettime = Wow.clock.gettime + 1
    toast:GetScript("OnClick")(toast, "LeftButton")
    Assert.equal(sent[1][1], "addon")
    Assert.equal(sent[2][1], "chat")
    Assert.equal(lead.greeted, true)
    ns.GreetAction.Prefill(lead)
    ns.GreetAction.Empty(lead)
    Assert.equal(sent[3][1], "prefill")
    Assert.equal(sent[4][1], "empty")

    -- The last lead gone: whisper events go too. Only the allowed timers are pending.
    -- The UI under the traps: the toast, the launcher Bootstrap made and its tooltip, the leads
    -- window (its UISpecialFrames insert) and the keybind functions.
    ns.AlertToast.Show(lead)
    local launcher = G("CraftAlertLauncher")
    launcher:GetScript("OnEnter")(launcher)
    launcher:GetScript("OnLeave")(launcher)
    ns.Launcher.Refresh()
    ns.LeadsWindow.Toggle()
    ns.LeadsWindow.Refresh()
    G("CraftAlert_GreetLatest")()
    G("CraftAlert_ToggleLeads")()
    G("CraftAlert_ToggleLeads")()
    Assert.same({ rawget(G("UISpecialFrames"), 1), rawget(G("UISpecialFrames"), 2) }, { "CraftAlertLeadsWindow", nil })

    -- The dismiss key waits for the 0.5 s look at a lead on screen (§7.5 rule 3).
    Wow.clock.gettime = Wow.clock.gettime + 1
    G("CraftAlert_DismissLatest")()
    Assert.equal(ns.Leads.HasActive(), false)
    Assert.same(publicChatEvents(), { CHANNEL })

    -- The settings pages under the traps: every page, and settings that rebuild, re-evaluate,
    -- re-arm and repaint (the pane in the leads window adds no UISpecialFrames entry).
    for _, title in ipairs({ "General", "Alerts", "Greetings", "Keywords", "Crafters", "Test" }) do
      SettingsFixture.open(ns, title)
    end
    SettingsFixture.open(ns, "General")
    local onlyResting = SettingsFixture.row("Only where Trade chat exists").input
    Widgets.click(onlyResting)
    Widgets.click(onlyResting)
    local guild = SettingsFixture.row("Guild").input
    Widgets.click(guild)
    Assert.same(publicChatEvents(), { CHANNEL, "CHAT_MSG_GUILD" }, "the gate registers a new channel at once")
    Widgets.click(guild)
    SettingsFixture.open(ns, "Alerts")
    Widgets.slide(SettingsFixture.row("Lead timeout").input, 5)
    local hide = SettingsFixture.row("Hide the launcher when there are no leads").input
    Widgets.click(hide)
    Widgets.click(hide)
    SettingsFixture.open(ns, "Test")
    local line = SettingsFixture.row("Test a line").input
    line:SetText("LF plate belt")
    line:GetScript("OnEnterPressed")(line)
    G("CraftAlert_ToggleLeads")()
    Assert.same(
      { rawget(G("UISpecialFrames"), 1), rawget(G("UISpecialFrames"), 2), rawget(G("UISpecialFrames"), 3) },
      { "CraftAlertLeadsWindow", nil, nil }
    )
    Assert.same(publicChatEvents(), { CHANNEL }, "and drops it at once")

    -- Slash commands under the traps: the windows, a test line (a toast and a test lead) and /ca perf
    -- around one chat line (swapping the handler registers no event and arms no timer).
    local slash = G("SlashCmdList").CRAFTALERT
    local leadsBefore = #ns.Leads.List()
    slash("")
    slash("config")
    slash("test LF plate belt")
    Assert.equal(#ns.Leads.List(), leadsBefore + 1, "/ca test makes a test lead")
    slash("perf")
    fireRequest("LF plate belt", "Dee-OtherRealm")
    slash("perf")
    slash("help")
    Assert.equal(#ns.Leads.List(), leadsBefore + 2, "the timed handler still makes the lead")
    Assert.same(publicChatEvents(), { CHANNEL, "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }, "only that lead's whisper events")
    for _, timer in ipairs(Wow.timers) do
      Assert.truthy(ALLOWED_DELAYS[timer.delay], "timer with delay " .. tostring(timer.delay))
    end
    for _, frame in ipairs(Wow.frames) do
      Assert.equal(frame.scripts.OnUpdate, nil, "no OnUpdate script")
    end

    -- Recipe markers (§6.2-6.5) under the traps: Blizzard_Professions loads after login, a stored
    -- row gets its switch, a click mutes and unmutes through the index rebuild. Nothing is
    -- written on the row, its node or the lists; verify() would report a raw write.
    local row = state.list:row(9001)
    Assert.raises(function()
      row.Extra = 1
    end, "write to Blizzard table row.Extra")
    Wow.fireEvent("ADDON_LOADED", "Blizzard_Professions")
    Assert.equal(#state.list.callbacks, 1, "the row callback registered through the ScrollUtil proxy")
    local switch
    for _, frame in ipairs(Wow.frames) do
      if frame.parent == row then
        switch = frame
      end
    end
    Assert.truthy(switch, "the stored row got its switch")
    Assert.equal(switch:IsShown(), true)
    Widgets.click(switch)
    ns.Index.Rebuild()
    Assert.equal(switch.icon.atlas, "voicechat-icon-speaker-mute", "the click muted the recipe and the rebuild kept it")
    Widgets.click(switch)
    ns.Index.Rebuild()
    Assert.equal(switch.icon.atlas, "voicechat-icon-speaker")
    Assert.equal(state.list.clicks.method + state.list.clicks.script, 0, "the row's own click never ran")
    verify()
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
  testLearnSignalAllowsSystemEvents()
  testAddonObeysTheRules()
  testSourceRules()
end
