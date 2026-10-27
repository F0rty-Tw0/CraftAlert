-- Task 1.19: the whole addon loaded from the TOC on Retail and started only through the
-- ADDON_LOADED and PLAYER_LOGIN events, as the client does; Bootstrap does every install.
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")
local Toc = require("tests.helpers.toc")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local OWN_KEY = "Crafter-OwnRealm"
local CUSTOMER = "Customer-OtherRealm"
local BS, ENCH, COOKING = 164, 333, 185
local START_TIME = 100000
local LEAD_AGE = 60
-- The default lead timeout is 10 min; the expiry timer waits one second past it.
local EXPIRY_DELAY = 600 - LEAD_AGE + 1
local BELT_LINK = "|cff0070dd|Hitem:190001::::::::70:::::|h[Sim Plate Belt]|h|r"
local STATUS_ACTIVE = "Listening in Trade, Services — 3 recipes, 1 crafter"
local STATUS_UNREAD = "Paused — no profession read yet: open Blacksmithing once"
local STATUS_NOT_STARTED = "Paused — Craft Alert did not start; /reload to try again"
local NO_DB = "Craft Alert's saved data did not load; /reload to try again"
local UNREAD_LINE = "Open Blacksmithing once to start listening."
local FIRST_RUN_HINT = "After opening a profession, try /ca test LF <profession> crafter"
local INSTALLED_EVENTS = {
  "TRADE_SKILL_SHOW",
  "TRADE_SKILL_CLOSE",
  "TRADE_SKILL_LIST_UPDATE",
  "NEW_RECIPE_LEARNED",
  "PLAYER_UPDATE_RESTING",
  "IGNORELIST_UPDATE",
  "PLAYER_LOGOUT",
}
local WHISPER_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }
local ORDER_FILLED = "CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG"
-- The customer's realm is connected, so the lead carries no "can't order" tag.
local CONNECTED_REALMS = { "OwnRealm", "Other Realm" }
local DIM_ALPHA = 0.5

local SLOTS = { { name = "Blacksmithing", skillLine = BS } }
local RECIPES = {
  { id = 9001, name = "Sim Plate Belt", item = 190001, learned = true },
  { id = 9004, name = "Sim Plate Helm", item = 190004, learned = true },
  { id = 9006, name = "Sim Plate Bracers", item = 190006, learned = true },
}
local ITEMS = {
  [190001] = { "INVTYPE_WAIST", 4, 4 },
  [190004] = { "INVTYPE_HEAD", 4, 4 },
  [190006] = { "INVTYPE_WRIST", 4, 4 },
}
local BIND = { [190001] = 2, [190004] = 2, [190006] = 2 }

-- The client before the addon loads: the player Crafter-OwnRealm resting in a city with
-- Blacksmithing, `db` as the saved CraftAlertDB (nil: a fresh install), on `flavor` (default
-- Retail). → session, the profession stub state.
local function startClient(db, slots, flavor)
  Wow.reset()
  Wow.flavor(flavor or "retail")
  Wow.clock.time = START_TIME
  local session = { sent = {}, toasts = 0, db = db, categories = {}, addOnCategories = {} }
  local function record(api)
    return function(...)
      session.sent[#session.sent + 1] = { api, ... }
    end
  end
  Wow.stub("C_ChatInfo", { SendAddonMessage = record("addon"), SendChatMessage = record("chat") })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = record("prefill"), SendTell = record("empty") })
  Wow.stub("SlashCmdList", {})
  Wow.stub("UISpecialFrames", {})
  Wow.stub("IsResting", function()
    return true
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  Wow.stub("UnitName", function()
    return "Crafter"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "OwnRealm"
  end)
  Wow.stub("C_AutoComplete", {
    GetAutoCompleteRealms = function()
      return CONNECTED_REALMS
    end,
  })
  Wow.stub("Settings", {
    RegisterCanvasLayoutCategory = function(frame, name)
      local category = { frame = frame, name = name }
      session.categories[#session.categories + 1] = category
      return category
    end,
    RegisterAddOnCategory = function(category)
      session.addOnCategories[#session.addOnCategories + 1] = category
    end,
  })
  Wow.stub("CraftAlertDB", db)
  local state = ProfessionsRetail.install({ slots = slots or SLOTS, base = BS, recipes = RECIPES, items = ITEMS, bind = BIND, autoCache = true })
  -- The three APIs QualityReach needs; none answers for the stub recipes.
  rawset(_G["C_TradeSkillUI"], "GetCraftingOperationInfo", function() end)
  Wow.stub("Enum", { TradeskillSlotDataType = { ModifiedReagent = 1 }, CraftingReagentType = { Finishing = 3 } })
  Wow.stub("C_CurrencyInfo", { GetCurrencyInfo = function() end })
  return session, state
end

-- Every TOC file into one ns, then the two events the client fires. The toast is counted
-- before login, so Bootstrap's Leads.On("new") subscribes the counting wrapper. `prepare(ns)`,
-- when given, runs between loading and the events.
local function login(session, prepare)
  local ns = {}
  for _, path in ipairs(Toc.luaFiles()) do
    assert(loadfile(path))("CraftAlert", ns)
  end
  if prepare then
    prepare(ns)
  end
  local show = ns.AlertToast.Show
  ns.AlertToast.Show = function(lead)
    session.toasts = session.toasts + 1
    show(lead)
  end
  Wow.fireEvent("ADDON_LOADED", "SomeOtherAddon")
  Assert.equal(rawget(_G, "CraftAlertDB"), session.db, "another addon's ADDON_LOADED loads nothing")
  Wow.fireEvent("ADDON_LOADED", "CraftAlert")
  Wow.fireEvent("PLAYER_LOGIN")
  return ns
end

-- The chat lines printed since `from`, without the addon prefix.
local function chatSince(from)
  local lines = {}
  for i = from + 1, #Wow.chat do
    lines[#lines + 1] = (string.gsub(Wow.chat[i], "^|cffffd100Craft Alert:|r ", ""))
  end
  return lines
end

local function count(lines, text)
  local found = 0
  for _, line in ipairs(lines) do
    if line == text then
      found = found + 1
    end
  end
  return found
end

local function isRegistered(event)
  for _, frame in ipairs(Wow.frames) do
    if frame.events[event] then
      return true
    end
  end
  return false
end

-- The leads window's rows that show a lead.
local function shownRows()
  local rows = 0
  for _, frame in ipairs(Wow.frames) do
    if frame.isLeadRow and frame.lead and frame:IsShown() then
      rows = rows + 1
    end
  end
  return rows
end

-- Lit while scanning, dim while paused: the icon's colour and the button's alpha.
local function isLit(launcher)
  local lit = launcher:GetAlpha() == 1 and launcher.icon.desaturated == false
  local dim = launcher:GetAlpha() == DIM_ALPHA and launcher.icon.desaturated == true
  Assert.truthy(lit or dim, "the launcher is either lit or dim")
  return lit
end

-- Runs the timers of this frame (delay 0: the coalesced index rebuild) and nothing later.
local function runFrame()
  local found = true
  while found do
    found = false
    for i, timer in ipairs(Wow.timers) do
      if timer.delay == 0 then
        table.remove(Wow.timers, i)
        timer.fn()
        found = true
        break
      end
    end
  end
end

local function trade(text, sender)
  Wow.fireEvent("CHAT_MSG_CHANNEL", text, sender, "", "2. Trade - City", sender, "", 2, 2, "Trade - City", 0, 1, nil)
end

-- Fresh install: login lines, every install, then open the window, a request, a click.
local function testFreshInstall()
  local session = startClient(nil)
  local ns = login(session)
  local db = rawget(_G, "CraftAlertDB")
  Assert.truthy(db, "ADDON_LOADED created the account DB")
  Assert.equal(ns.SavedState.isFirstRun, true)
  Assert.same(chatSince(0), { STATUS_UNREAD, UNREAD_LINE, FIRST_RUN_HINT }, "login lines on a fresh DB")
  Assert.equal(type(ns.Perf.loginMs), "number")

  for _, event in ipairs(INSTALLED_EVENTS) do
    Assert.truthy(isRegistered(event), event .. " registered")
  end
  Assert.equal(isRegistered("ADDON_LOADED"), false, "ADDON_LOADED is dropped once handled")
  Assert.equal(isRegistered("PLAYER_LOGIN"), false)
  Assert.equal(type(rawget(_G, "SlashCmdList").CRAFTALERT), "function")
  local launcher = rawget(_G, "CraftAlertLauncher")
  Assert.truthy(launcher, "the launcher exists after login")
  Assert.equal(isLit(launcher), false, "dim while paused")
  Assert.equal(isRegistered("CHAT_MSG_CHANNEL"), false, "paused: nothing read yet")
  Assert.same(ns.ProfessionList.Order(), { BS })
  Assert.equal(#session.categories, 0, "no Blizzard Settings category (spec R10)")
  Assert.same(session.addOnCategories, {}, "nothing listed under AddOns")
  Assert.same(db.characters[OWN_KEY].realms, { "OwnRealm", "OtherRealm" }, "the connected realms are stored")

  -- Opening the window reads the 3 recipes; the coalesced rebuild activates the scan, and the
  -- first activation prints the status line.
  local before = #Wow.chat
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runFrame()
  Assert.equal(ns.Index.Current().size, 3)
  Assert.equal(ns.ScanGate.IsActive(), true)
  Assert.truthy(isRegistered("CHAT_MSG_CHANNEL"))
  Assert.same(chatSince(before), { STATUS_ACTIVE })
  Assert.equal(isLit(launcher), true, "lit once the scan is active, before any lead")

  -- /ca opens the empty leads window; the request below fills its first row.
  rawget(_G, "SlashCmdList").CRAFTALERT("")
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true)
  Assert.equal(shownRows(), 0)

  -- A request for the belt: one toast, one lead, then the whisper events.
  trade("LF " .. BELT_LINK .. " crafter", CUSTOMER)
  Assert.equal(shownRows(), 1, "the open window shows the new lead")
  rawget(_G, "SlashCmdList").CRAFTALERT("")
  local lead = ns.Leads.Latest()
  Assert.truthy(lead, "the request made a lead")
  Assert.equal(lead.customer, CUSTOMER)
  Assert.equal(lead.crafter, OWN_KEY)
  Assert.equal(session.toasts, 1, "one toast per new lead")
  local toast = rawget(_G, "CraftAlertToast")
  launcher.center = { 1800, 100 }
  launcher.scripts.OnDragStop(launcher) -- Bootstrap wired Launcher.OnMoved(AlertToast.Dock)
  Assert.equal(toast:GetPoint(), "BOTTOMRIGHT")
  Assert.equal(toast:IsShown(), true)
  for _, event in ipairs(WHISPER_EVENTS) do
    Assert.truthy(isRegistered(event), event .. " registered with a lead")
  end
  Assert.equal(rawget(_G, "CraftAlertLauncher").badgeText:GetText(), "1", "the launcher counts the lead")

  -- Left-click on the toast once it has been seen: the disclosure, then the whisper.
  Wow.clock.gettime = Wow.clock.gettime + 1
  toast:GetScript("OnClick")(toast, "LeftButton")
  Assert.equal(#session.sent, 2)
  Assert.equal(session.sent[1][1], "addon")
  Assert.equal(session.sent[1][5], CUSTOMER)
  Assert.same({ session.sent[2][1], session.sent[2][2], session.sent[2][3], session.sent[2][5] }, {
    "chat",
    "Hi! I can craft |cffffffff|Hitem:190001|h[Item 190001]|h|r.",
    "WHISPER",
    CUSTOMER,
  })
  Assert.equal(lead.greeted, true)
  -- Bootstrap installed the ledger: the new lead and its greeting are today's counters.
  Assert.same(ns.Ledger.Today(), { seen = 1, greeted = 1, replied = 0, filled = 0 }, "Ledger.Install subscribed")
  -- Retail: the greeted customer's order filled (the event names them without a realm) counts.
  Assert.truthy(isRegistered(ORDER_FILLED), ORDER_FILLED .. " registered on Retail")
  Wow.fireEvent(ORDER_FILLED, 0, "Sim Plate Belt", "Customer", 0, 1)
  Assert.equal(ns.Ledger.Today().filled, 1)

  -- Selling is not asking: nothing.
  trade("WTS plate belt, cheap", "Seller-OtherRealm")
  Assert.equal(#ns.Leads.List(), 1, "a WTS line makes no lead")
  Assert.equal(session.toasts, 1, "and no toast")
  Assert.equal(#session.sent, 2, "and sends nothing")
  return db
end

-- A /reload a minute later: the lead comes back with its expiry timer and whisper events, the
-- scan is active at login, and the status line prints once, not again on later evaluations.
local function testRestoredSession(db)
  local session = startClient(db)
  Wow.clock.time = START_TIME + LEAD_AGE
  local ns = login(session)
  Assert.equal(ns.SavedState.isFirstRun, false)
  Assert.equal(#ns.Leads.List(), 1)
  Assert.equal(Wow.pendingTimers(EXPIRY_DELAY), 1, "the restored lead's expiry timer is armed")
  for _, event in ipairs(WHISPER_EVENTS) do
    Assert.truthy(isRegistered(event), event .. " registered for the restored lead")
  end
  Assert.equal(ns.ScanGate.IsActive(), true)
  Assert.same(chatSince(0), { STATUS_ACTIVE }, "one status line, no first-run hint, nothing unread")
  ns.Index.Rebuild()
  Wow.fireEvent("PLAYER_UPDATE_RESTING")
  Assert.equal(count(chatSince(0), STATUS_ACTIVE), 1, "the first activation was the login line")
  Assert.equal(session.toasts, 0, "a restored lead raises no toast")
end

-- At login only the secondary slots have loaded: the stored profession and its recipes stay,
-- the order is seeded from storage, and SKILL_LINES_CHANGED refreshes once the data is there.
local function testPartialProfessionsAtLogin(db)
  local session, state = startClient(db, { false, false, { name = "Cooking", skillLine = COOKING } })
  rawset(_G["C_TradeSkillUI"], "GetTradeSkillTexture", function(key)
    return "tex" .. key
  end)
  local ns = login(session)
  local launcher = rawget(_G, "CraftAlertLauncher")
  Assert.equal(launcher.icon.texture, "tex164", "idle icon: the first profession")
  local character = rawget(_G, "CraftAlertDB").characters[OWN_KEY]
  Assert.truthy(character.professions[BS], "the stored profession is kept")
  Assert.equal(ns.Index.Current().size, 3, "its recipes are still listened for")
  Assert.same(ns.ProfessionList.Order(), { BS })
  Assert.truthy(isRegistered("SKILL_LINES_CHANGED"))

  -- The same professions arriving change nothing; a new one in front changes the order.
  state.slots = { { name = "Blacksmithing", skillLine = BS }, false, { name = "Cooking", skillLine = COOKING } }
  Wow.fireEvent("SKILL_LINES_CHANGED")
  Assert.equal(Wow.pendingTimers(0), 0, "same order: no rebuild")
  state.slots = { { name = "Enchanting", skillLine = ENCH }, { name = "Blacksmithing", skillLine = BS } }
  Wow.fireEvent("SKILL_LINES_CHANGED")
  Assert.same(ns.ProfessionList.Order(), { ENCH, BS })
  Assert.truthy(character.professions[ENCH])
  Assert.equal(Wow.pendingTimers(0), 1, "a new order requests one rebuild")
  Assert.equal(launcher.icon.texture, "tex333", "the launcher's idle icon follows the new order")
  runFrame()
  Assert.same(ns.Index.Current().professionOrder, { ENCH, BS })
end

-- The errors the client's error handler receives from now on.
local function recordErrors()
  local errors = {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      errors[#errors + 1] = err
    end
  end)
  return errors
end

-- A hand-edited db mixes number and string profession keys, and at login only the secondary
-- slots have loaded: the order is seeded without raising and every install runs.
local function testMixedKeysAtLogin(db)
  db.characters[OWN_KEY].professions[tostring(ENCH)] = { name = "Enchanting", primary = false, read = true }
  local session = startClient(db, { false, false, { name = "Cooking", skillLine = COOKING } })
  local errors = recordErrors()
  local ns = login(session)
  Assert.same(errors, {}, "no error at login")
  Assert.same(ns.ProfessionList.Order(), { BS })
  Assert.equal(type(rawget(_G, "SlashCmdList").CRAFTALERT), "function")
  Assert.truthy(rawget(_G, "CraftAlertLauncher"), "the launcher exists")
  Assert.equal(ns.ScanGate.IsActive(), true)
end

-- One install step raising at login is reported, and every later step still runs; the chat
-- events still come from the gate alone.
local function testRaisingLoginStep(db)
  local session = startClient(db)
  local errors = recordErrors()
  local ns = login(session, function(ns)
    ns.RealmTag.Store = function()
      error("realm list failed", 0)
    end
  end)
  Assert.same(errors, { "realm list failed" }, "the error reaches the error handler")
  Assert.equal(type(rawget(_G, "SlashCmdList").CRAFTALERT), "function", "/ca works")
  Assert.truthy(rawget(_G, "CraftAlertLauncher"), "the launcher exists")
  Assert.equal(#session.categories, 0, "no settings category")
  Assert.equal(ns.Index.Current().size, 3, "the index is built")
  Assert.equal(ns.ScanGate.IsActive(), true)
  Assert.truthy(isRegistered("CHAT_MSG_CHANNEL"), "the gate registered the chat events")
  Assert.same(chatSince(0), { STATUS_ACTIVE }, "the login lines print")
end

-- The resting events failing to register leave the gate without its db: no rebuild registers
-- the chat events, so scanning never runs outside a city. The status line says the addon did
-- not start, not that the player turned it off.
local function testRaisingRestingRegistration(db)
  local session = startClient(db)
  local errors = recordErrors()
  local ns = login(session, function(ns)
    local on = ns.EventRouter.On
    ns.EventRouter.On = function(event, fn)
      if event == "PLAYER_UPDATE_RESTING" then
        error("resting event failed", 0)
      end
      on(event, fn)
    end
  end)
  ns.Index.Rebuild()
  Assert.same(errors, { "resting event failed" }, "the error reaches the error handler")
  Assert.equal(ns.ScanGate.IsActive(), false)
  Assert.equal(isRegistered("CHAT_MSG_CHANNEL"), false, "no chat event without the resting gate")
  Assert.same(chatSince(0), { STATUS_NOT_STARTED })
end

-- The restored lead's expiry timer failing to start makes Leads.Restore raise: Leads stays
-- unbound, so the gate does not scan (a match would make no lead that a toast, the launcher or
-- the window could show) and a trade line makes no lead.
local function testRaisingLeadsRestore(db)
  local session = startClient(db)
  local errors = recordErrors()
  local freshExpiryDelay = EXPIRY_DELAY + LEAD_AGE -- no minute has passed since the lead
  local ns = login(session, function()
    local after = _G["C_Timer"].After
    _G["C_Timer"].After = function(delay, fn)
      if delay == freshExpiryDelay then
        error("timer failed", 0)
      end
      after(delay, fn)
    end
  end)
  Assert.same(errors, { "timer failed" }, "the error reaches the error handler")
  Assert.equal(ns.ScanGate.IsActive(), false)
  Assert.equal(isRegistered("CHAT_MSG_CHANNEL"), false, "no chat event without Leads")
  Assert.same(chatSince(0), { STATUS_NOT_STARTED })
  trade("LF " .. BELT_LINK .. " crafter", "Buyer-OtherRealm")
  Assert.equal(#rawget(_G, "CraftAlertDB").leads, 1, "a trade line makes no lead")
  Assert.equal(session.toasts, 0)
end

-- The saved variables failing to load leave no db: the load error is the only one reported,
-- /ca is still there, and nothing listens to chat.
local function testRaisingLoad(db)
  local session = startClient(db)
  local errors = recordErrors()
  login(session, function(ns)
    ns.SavedState.Load = function()
      error("load failed", 0)
    end
  end)
  Assert.same(errors, { "load failed" }, "only the load error is reported")
  Assert.equal(type(rawget(_G, "SlashCmdList").CRAFTALERT), "function", "/ca works")
  Assert.equal(isRegistered("CHAT_MSG_CHANNEL"), false, "no chat event without a db")
end

-- Saved data whose load raises partway stays the unchecked stored table: /ca and the toggle
-- key keep the windows closed instead of opening them on it.
local function testRaisingLoadKeepsWindowsClosed(db)
  local session = startClient(db)
  local errors = recordErrors()
  login(session, function(ns)
    ns.Schema.Validate = function()
      error("validate failed", 0)
    end
  end)
  Assert.same(errors, { "validate failed" }, "only the load error is reported")
  Assert.equal(rawget(_G, "CraftAlertDB"), db, "the stored table is left in place")
  local slash = rawget(_G, "SlashCmdList").CRAFTALERT
  slash("")
  slash("config")
  rawget(_G, "CraftAlert_ToggleLeads")()
  Assert.same(chatSince(0), { NO_DB, NO_DB })
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "no window from /ca or /ca config on unchecked data")
end

-- A fresh install whose saved variables fail to load has no CraftAlertDB at all: the windows
-- stay closed and say why instead of raising, and /ca test names the stage it stopped at.
local function testRaisingLoadOnFreshInstall()
  local session = startClient(nil)
  local errors = recordErrors()
  login(session, function(ns)
    ns.SavedState.Load = function()
      error("load failed", 0)
    end
  end)
  Assert.equal(rawget(_G, "CraftAlertDB"), nil)
  local slash = rawget(_G, "SlashCmdList").CRAFTALERT
  slash("")
  slash("config")
  slash("test LF plate belt")
  Assert.same(
    chatSince(0),
    { NO_DB, NO_DB, "Test: Paused — Craft Alert did not start; /reload to try again, a real Trade line would be ignored too" }
  )
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "no window from /ca or /ca config without a db")
  Assert.same(errors, { "load failed" }, "only the load error is reported")
end

-- The player's name failing to resolve at login (`name`: "Init" or "Own") is reported once;
-- /ca is still there, and nothing listens to chat without the player's key.
local function testRaisingPlayerName(db, name)
  local session = startClient(db)
  local errors = recordErrors()
  login(session, function(ns)
    ns.PlayerName[name] = function()
      error("name failed", 0)
    end
  end)
  Assert.same(errors, { "name failed" }, "only the " .. name .. " error is reported")
  Assert.equal(type(rawget(_G, "SlashCmdList").CRAFTALERT), "function", "/ca works")
  Assert.equal(isRegistered("CHAT_MSG_CHANNEL"), false, "no chat event without the player's key")
end

-- §4.4: the login time counts the saved-variable load and check at ADDON_LOADED and the
-- PLAYER_LOGIN work, not the time between the two events.
local function testLoginTime(db)
  local session = startClient(db)
  local function spend(fn, ms)
    return function(...)
      Wow.clock.profile = Wow.clock.profile + ms
      return fn(...)
    end
  end
  local ns = login(session, function(ns)
    ns.SavedState.Load = spend(ns.SavedState.Load, 7)
    ns.PlayerName.Init = spend(ns.PlayerName.Init, 1000)
    ns.Index.Rebuild = spend(ns.Index.Rebuild, 3)
  end)
  Assert.equal(ns.Perf.loginMs, 10)
end

-- /ignore through the real wiring: IGNORELIST_UPDATE drops the ignored customer's leads, and
-- the toast showing one goes with it.
local function testIgnoreDropsLead(db)
  local buyer = "Buyer-OtherRealm"
  local session = startClient(db)
  local ns = login(session)
  trade("LF " .. BELT_LINK .. " crafter", buyer)
  Assert.equal(rawget(_G, "CraftAlertToast"):IsShown(), true, "the toast shows Buyer's lead")
  local before = #ns.Leads.List()
  Wow.stub("C_FriendList", {
    IsIgnored = function(name)
      return name == buyer
    end,
  })
  Wow.fireEvent("IGNORELIST_UPDATE")
  Assert.equal(#ns.Leads.List(), before - 1, "only Buyer's lead went")
  for _, lead in ipairs(ns.Leads.List()) do
    Assert.equal(lead.customer ~= buyer, true, "no lead of the ignored customer is left")
  end
  Assert.equal(rawget(_G, "CraftAlertToast"):IsShown(), false, "the toast hides with its lead")
  -- Their next Trade line, through the whole chat path, makes no lead.
  trade("LF " .. BELT_LINK .. " crafter", buyer)
  Assert.equal(#ns.Leads.List(), before - 1, "an ignored customer's line makes no lead")
  Assert.equal(rawget(_G, "CraftAlertToast"):IsShown(), false, "and no toast")
  Wow.stub("C_FriendList", nil)
end

-- Spec §7.6: Bootstrap installs the away summary on the own toast. A request made while AFK, then
-- the player's AFK flag clearing (PLAYER_FLAGS_CHANGED), shows one summary.
local function testAwaySummary(db)
  local session = startClient(db)
  local errors = recordErrors()
  login(session)
  Assert.truthy(isRegistered("PLAYER_FLAGS_CHANGED"), "PLAYER_FLAGS_CHANGED registered")
  Wow.stub("UnitIsAFK", function()
    return true
  end)
  trade("LF " .. BELT_LINK .. " crafter", "Buyer-OtherRealm")
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  Wow.fireEvent("PLAYER_FLAGS_CHANGED", "player")
  local toast = rawget(_G, "CraftAlertToast")
  local face = table.concat(Widgets.texts(toast, Wow.frames), " / ")
  Assert.truthy(toast:IsShown() and string.find(face, "1 requests you could craft while you were away", 1, true), face)
  Assert.same(errors, {})
end

-- Entering an instance after login (PLAYER_ENTERING_WORLD) takes down the launcher, the toast and
-- the leads window through the gate's change listeners; leaving brings back only the launcher.
local function testInstanceHidesUi(db)
  local session = startClient(db)
  local ns = login(session)
  trade("LF " .. BELT_LINK .. " crafter", "Buyer-OtherRealm")
  ns.LeadsWindow.Toggle()
  local launcher, toast, window = rawget(_G, "CraftAlertLauncher"), rawget(_G, "CraftAlertToast"), rawget(_G, "CraftAlertLeadsWindow")
  Assert.equal(toast:IsShown() and window:IsShown() and launcher:IsShown(), true)
  local inside = true
  Wow.stub("IsInInstance", function()
    return inside, inside and "party" or "none"
  end)
  Wow.fireEvent("PLAYER_ENTERING_WORLD")
  Assert.equal(ns.ScanGate.State().reason, "instance")
  Assert.equal(launcher:IsShown(), false, "launcher hidden")
  Assert.equal(toast:IsShown(), false, "toast hidden")
  Assert.equal(window:IsShown(), false, "window hidden")
  for _, event in ipairs(WHISPER_EVENTS) do
    Assert.falsy(isRegistered(event), event .. " dropped in an instance")
  end
  inside = false
  Wow.fireEvent("PLAYER_ENTERING_WORLD")
  Assert.equal(launcher:IsShown(), true, "launcher back")
  for _, event in ipairs(WHISPER_EVENTS) do
    Assert.truthy(isRegistered(event), event .. " back outside")
  end
  Assert.equal(toast:IsShown() or window:IsShown(), false, "toast and window stay closed")
  Wow.stub("IsInInstance", nil)
end

-- A login or /reload inside an instance prints no chat line: an addon line taints the chat frame.
-- The db comes from a newer schema, so its load warning is held too.
local function testLoginInInstanceIsSilent(db)
  db.schema = 2
  local session = startClient(db)
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  local before = #Wow.chat
  local ns = login(session)
  Assert.equal(ns.ScanGate.State().reason, "instance")
  Assert.same(chatSince(before), {}, "no login lines in an instance")
  Wow.stub("IsInInstance", nil)
end

-- Bootstrap hands Launcher.Refresh and LeadsWindow.Refresh to the Alerts page: with no leads,
-- ticking "Hide the launcher when there are no leads" hides the launcher at once, and dragging
-- Opacity repaints the window.
local function testAlertsPageRepaints(db)
  db.leads = {}
  local session = startClient(db)
  local ns = login(session)
  SettingsFixture.open(ns, "Alerts")
  local launcher = rawget(_G, "CraftAlertLauncher")
  Assert.equal(launcher:IsShown(), true)
  Widgets.click(SettingsFixture.row("Hide the launcher when there are no leads").input)
  Assert.equal(launcher:IsShown(), false, "hidden at once")
  local window = rawget(_G, "CraftAlertLeadsWindow")
  Assert.equal(window:GetAlpha(), 1)
  Widgets.slide(SettingsFixture.row("Opacity").input, 0.5)
  Assert.equal(window:GetAlpha(), 0.5)
end

-- Forever has no crafting orders: no orders-filled listener there.
local function testNoOrdersOffRetail(db)
  local session = startClient(db, nil, "forever")
  local errors = recordErrors()
  login(session)
  Assert.same(errors, {})
  Assert.equal(isRegistered(ORDER_FILLED), false, ORDER_FILLED .. " not registered on Forever")
end

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, inner in pairs(value) do
    copy[key] = deepCopy(inner)
  end
  return copy
end

return function()
  local db = testFreshInstall()
  local saved = deepCopy(db)
  testRestoredSession(deepCopy(saved))
  testPartialProfessionsAtLogin(deepCopy(saved))
  testMixedKeysAtLogin(deepCopy(saved))
  testRaisingLoginStep(deepCopy(saved))
  testRaisingRestingRegistration(deepCopy(saved))
  testRaisingLeadsRestore(deepCopy(saved))
  testRaisingLoad(deepCopy(saved))
  testRaisingLoadKeepsWindowsClosed(deepCopy(saved))
  testRaisingLoadOnFreshInstall()
  testRaisingPlayerName(deepCopy(saved), "Init")
  testRaisingPlayerName(deepCopy(saved), "Own")
  testLoginTime(deepCopy(saved))
  testIgnoreDropsLead(deepCopy(saved))
  testInstanceHidesUi(deepCopy(saved))
  testLoginInInstanceIsSilent(deepCopy(saved))
  testAlertsPageRepaints(deepCopy(saved))
  testNoOrdersOffRetail(deepCopy(saved))
  testAwaySummary(deepCopy(saved))
  Wow.reset()
end
