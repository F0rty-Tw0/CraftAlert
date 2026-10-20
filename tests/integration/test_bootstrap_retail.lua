-- Task 1.19: the whole addon loaded from the TOC on Retail and started only through the
-- ADDON_LOADED and PLAYER_LOGIN events, as the client does; Bootstrap does every install.
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
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
local UNREAD_LINE = "Open Blacksmithing once to start listening."
local FIRST_RUN_HINT = "After opening a profession, try /ca test LF <profession> crafter"
local INSTALLED_EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "PLAYER_UPDATE_RESTING" }
local WHISPER_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }
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
-- Blacksmithing, `db` as the saved CraftAlertDB (nil: a fresh install). → session, the
-- profession stub state.
local function startClient(db, slots)
  Wow.reset()
  Wow.flavor("retail")
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
  return session, state
end

-- Every TOC file into one ns, then the two events the client fires. The toast is counted
-- before login, so Bootstrap's Leads.On("new") subscribes the counting wrapper.
local function login(session)
  local ns = {}
  for _, path in ipairs(Toc.luaFiles()) do
    assert(loadfile(path))("CraftAlert", ns)
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
  Assert.equal(#session.categories, 1, "one Blizzard Settings category")
  Assert.same(session.addOnCategories, session.categories, "listed under AddOns once")
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
  local ns = login(session)
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
  runFrame()
  Assert.same(ns.Index.Current().professionOrder, { ENCH, BS })
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
  Wow.reset()
end
