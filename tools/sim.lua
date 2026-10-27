-- CLI sim: feeds chat lines, events, slash commands and clicks through the real addon
-- modules with stubbed WoW APIs and returns what happened as text lines.
--   python scripts/sim.py [--flavor retail|forever|era|tbc|wrath|cata|mop] [--db FILE] [--class TOKEN] ...
--   lua5.1 tools/sim.lua ...   (from the repo root)
-- Output lines are `<area>: <fact>`; the first is always `sim: flavor=<key> modules=<n>`.
local ROOT = rawget(_G, "CRAFTALERT_ROOT") or "."
package.path = ROOT .. "/?.lua;" .. package.path

local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")
local ProfessionsRetail = require("tests.helpers.professions_retail")

local DEFAULT_SENDER = "Customer-OtherRealm"
local SIM_CLASS_GUID = "Player-0-SIMCLASS"
local OWN_NAME = "Crafter"
local OWN_REALM = "OwnRealm"
local DEFAULT_FLAVOR = "retail"
local CLICK_BUTTONS = { left = true, shift = true, ctrl = true, right = true }
-- Every sim chat line arrives on Trade: zone channel ID 2 (flavor-choices.md), as the
-- CHAT_MSG_CHANNEL payload carries it.
local TRADE_ZONE_CHANNEL_ID = 2
local TRADE_CHANNEL_NAME = "2. Trade - City"
local TRADE_BASE_NAME = "Trade - City"
-- Item data of the fixture items (tools/sim_fixture.lua) for GetItemInfoInstant:
-- itemID -> { equipLoc, classID, subclassID }.
local SIM_ITEMS = {
  [190001] = { "INVTYPE_WAIST", 4, 4 }, -- Sim Plate Belt: plate belt
  [190003] = { "", 7, 0 }, -- Sim Iron Reagent: trade goods
  [190004] = { "INVTYPE_HEAD", 4, 4 }, -- Sim Plate Helm: plate head
  [190005] = { "", 7, 0 }, -- Sim Iron Bar: trade goods
}
-- Bind types the client reports once an item is loaded (0 none, 2 bind on equip).
local SIM_BIND = { [190004] = 2, [190005] = 0 }
-- The open Blacksmithing window (retail and forever): the fixture's belt and reagent, a
-- recipe not learned yet (9004: NEW_RECIPE_LEARNED teaches it) and a new Iron Bar (9005).
local WINDOW_PROFESSION = 164
local SIM_RECIPES = {
  { id = 9001, name = "Sim Plate Belt", item = 190001, learned = true },
  { id = 9003, name = "Sim Iron Reagent", item = 190003, learned = true },
  { id = 9004, name = "Sim Plate Helm", item = 190004, profession = { professionID = 2872, parentProfessionID = 164 } },
  { id = 9005, name = "Sim Iron Bar", item = 190005, learned = true },
}
local BIND_DEBOUNCE_SECONDS = 1
local ON_OFF = { on = true, off = false }
-- Events with a known payload take exactly that many arguments, so a chat line may follow
-- them; any other event takes every following non-`--` token.
local EVENT_ARITY = {
  TRADE_SKILL_SHOW = 0,
  TRADE_SKILL_LIST_UPDATE = 0,
  NEW_RECIPE_LEARNED = 1,
  GET_ITEM_INFO_RECEIVED = 2,
  CHAT_MSG_WHISPER = 2, -- text, sender
  CHAT_MSG_WHISPER_INFORM = 2, -- text, target
  PLAYER_UPDATE_RESTING = 0,
  ZONE_CHANGED_NEW_AREA = 0,
  CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG = 5, -- orderType, itemName, playerName, tip, quantity
}
-- How long the toast counts as shown (seconds) when --click acts on the newest lead (§7.5 rule 3).
local SHOWN_FOR_SECONDS = 1

local Sim = {}

-- The shared ns of the most recent Run, for tests and ad-hoc inspection.
Sim.lastNs = nil

-- Flags taking exactly one value; the parser checks the value where it is not free text.
local ONE_VALUE = { "--flavor", "--db", "--sender", "--class", "--cmd", "--click", "--afk", "--resting" }

local function isOneValueFlag(flag)
  for _, name in ipairs(ONE_VALUE) do
    if name == flag then
      return true
    end
  end
  return false
end

-- Records a one-value option on the plan; returns an error line or nil.
local function acceptOption(plan, flag, value)
  if flag == "--flavor" then
    if not Wow.isFlavor(value) then
      return "error: unknown flavor " .. value
    end
    plan.flavor = value
  elseif flag == "--db" then
    plan.dbPath = value
  elseif flag == "--click" then
    if not CLICK_BUTTONS[value] then
      return "error: bad click button " .. value .. " (left|shift|ctrl|right)"
    end
    plan.steps[#plan.steps + 1] = { kind = "click", button = value }
  elseif flag == "--afk" or flag == "--resting" then
    if ON_OFF[value] == nil then
      return "error: " .. flag .. " takes on|off"
    end
    plan.steps[#plan.steps + 1] = { kind = string.sub(flag, 3), on = ON_OFF[value] }
  elseif flag == "--sender" then
    plan.steps[#plan.steps + 1] = { kind = "sender", name = value }
  elseif flag == "--class" then
    plan.steps[#plan.steps + 1] = { kind = "class", token = value }
  elseif flag == "--cmd" then
    plan.steps[#plan.steps + 1] = { kind = "cmd", text = value }
  end
  return nil
end

-- Turns argv into { flavor, dbPath, steps } or returns nil, "error: ...".
local function parse(argv)
  local plan = { flavor = DEFAULT_FLAVOR, dbPath = ROOT .. "/tools/sim_fixture.lua", steps = {} }
  local i = 1
  while i <= #argv do
    local token = argv[i]
    if token == "--event" then
      local name = argv[i + 1]
      if name == nil or string.sub(name, 1, 2) == "--" then
        return nil, "error: --event needs an event name"
      end
      i = i + 1
      local arity = EVENT_ARITY[name]
      local args = {}
      while argv[i + 1] and string.sub(argv[i + 1], 1, 2) ~= "--" and (arity == nil or #args < arity) do
        args[#args + 1] = argv[i + 1]
        i = i + 1
      end
      plan.steps[#plan.steps + 1] = { kind = "event", name = name, args = args }
    elseif isOneValueFlag(token) then
      local value = argv[i + 1]
      if value == nil then
        return nil, "error: " .. token .. " needs a value"
      end
      i = i + 1
      local err = acceptOption(plan, token, value)
      if err then
        return nil, err
      end
    elseif string.sub(token, 1, 2) == "--" then
      return nil, "error: unknown flag " .. token
    else
      plan.steps[#plan.steps + 1] = { kind = "line", text = token }
    end
    i = i + 1
  end
  return plan
end

local function loadDb(path)
  local chunk = loadfile(path)
  if not chunk then
    return nil, "error: cannot read db file " .. path
  end
  local db = chunk()
  if type(db) ~= "table" then
    return nil, "error: db file " .. path .. " must return a table"
  end
  return db
end

local function formatArgs(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  return table.concat(parts, " | ")
end

-- Every stub send and every chat print becomes an output line.
local function captureOutput(out)
  local function sender(name)
    return function(...)
      out[#out + 1] = "send: " .. name .. " " .. formatArgs(...)
    end
  end
  Wow.stub("SendChatMessage", sender("SendChatMessage"))
  Wow.stub("SendAddonMessage", sender("SendAddonMessage"))
  Wow.stub("C_ChatInfo", { SendChatMessage = sender("SendChatMessage"), SendAddonMessage = sender("SendAddonMessage") })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = sender("SendTellWithMessage"), SendTell = sender("SendTell") })
  Wow.stub("DEFAULT_CHAT_FRAME", {
    AddMessage = function(_, text)
      out[#out + 1] = "chat: " .. string.gsub(string.gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    end,
  })
end

-- Loads every TOC .lua file in order into one shared ns, with no require fallback.
local function loadModules(ns)
  local files = Toc.luaFiles(ROOT)
  local savedRequire = _G.require
  rawset(_G, "require", function(moduleName)
    error("require fallback reached in game: " .. tostring(moduleName))
  end)
  local ok, err = pcall(function()
    for _, path in ipairs(files) do
      local chunk = assert(loadfile(ROOT .. "/" .. path))
      chunk("CraftAlert", ns)
    end
  end)
  rawset(_G, "require", savedRequire)
  return ok and #files or nil, err
end

local function newContext(plan, out)
  local ctx = { out = out, flavor = plan.flavor, ns = {}, afk = false, resting = true, started = false, sender = DEFAULT_SENDER }
  ctx.keys = { shift = false, ctrl = false }
  Wow.stub("IsShiftKeyDown", function()
    return ctx.keys.shift
  end)
  Wow.stub("IsControlKeyDown", function()
    return ctx.keys.ctrl
  end)
  Wow.stub("UnitIsAFK", function()
    return ctx.afk
  end)
  Wow.stub("IsResting", function()
    return ctx.resting
  end)
  -- The --class sender (STEPS.class) of the line in flight; any other GUID has no class.
  Wow.stub("GetPlayerInfoByGUID", function(guid)
    if ctx.class and guid == SIM_CLASS_GUID then
      return "Class", ctx.class
    end
  end)
  -- What the client defines and the addon writes into (SlashCommands.Register).
  Wow.stub("SlashCmdList", {})
  Wow.stub("SLASH_CRAFTALERT1", nil)
  Wow.stub("SLASH_CRAFTALERT2", nil)
  -- The player is the fixture's Crafter-OwnRealm.
  Wow.stub("UnitName", function()
    return OWN_NAME
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return OWN_REALM
  end)
  Wow.stub("GetRealmName", function()
    return OWN_REALM
  end)
  ProfessionsRetail.install({
    slots = { { name = "Blacksmithing", skillLine = 164 }, { name = "Enchanting", skillLine = 333 } },
    base = WINDOW_PROFESSION,
    recipes = SIM_RECIPES,
    items = SIM_ITEMS,
    bind = SIM_BIND,
    autoCache = true,
  })
  return ctx
end

-- `read: prof=<key> stored=<n> pendingBind=<n>` after a profession window read.
local function reportRead(ctx)
  local read = ctx.ns.ModernReader.lastRead
  if read then
    ctx.ns.ModernReader.lastRead = nil
    ctx.out[#ctx.out + 1] = string.format("read: prof=%s stored=%d pendingBind=%d", tostring(read.prof), read.stored, read.pendingBind)
  end
end

-- `learn: stored=<bool>` after a NEW_RECIPE_LEARNED.
local function reportLearn(ctx)
  local stored = ctx.ns.LearnWatcher.lastStored
  if stored ~= nil then
    ctx.ns.LearnWatcher.lastStored = nil
    ctx.out[#ctx.out + 1] = "learn: stored=" .. tostring(stored)
  end
end

-- `bind: stored=<n>` once the 1 s timer has stored arrived bind types; printed just before
-- the rebuild it requested, or after the timers when no rebuild followed.
local function flushBind(ctx)
  local stored = ctx.ns.BindLookup.lastStored
  if stored ~= nil then
    ctx.ns.BindLookup.lastStored = nil
    ctx.out[#ctx.out + 1] = "bind: stored=" .. stored
  end
end

-- `match: <kind> group=<group> prof=<prof> why=<a+b+c>` for the Matcher's result.
local function matchLine(result)
  local why = {}
  for i = 1, result.whyCount do
    why[i] = tostring(result.why[i])
  end
  local group, prof = tostring(result.group), tostring(result.prof)
  return string.format("match: %s group=%s prof=%s why=%s", result.kind, group, prof, table.concat(why, "+"))
end

-- `lead: new|updated customer=<key> crafter=<key> cannotOrder=<bool>` (§6.3 steps 5-7), or
-- `lead: none` when no crafter qualifies.
local function leadLine(lead, isNew)
  if not lead then
    return "lead: none"
  end
  return string.format(
    "lead: %s customer=%s crafter=%s cannotOrder=%s",
    isNew and "new" or "updated",
    lead.customer,
    lead.crafter,
    tostring(lead.cannotOrder == true)
  )
end

-- Prints the match, lead and greeting lines of every line that reaches Leads.OnMatch: the
-- chat handler (ScanGate.HandleChat) calls it, so the sim wraps it to look.
local function reportMatches(ctx)
  local Leads = ctx.ns.Leads
  local onMatch = Leads.OnMatch
  Leads.OnMatch = function(result, customerKey, text, channelKey, guid)
    ctx.out[#ctx.out + 1] = matchLine(result)
    local lead, isNew = onMatch(result, customerKey, text, channelKey, guid)
    ctx.out[#ctx.out + 1] = leadLine(lead, isNew)
    if lead then
      ctx.out[#ctx.out + 1] = "greeting: " .. ctx.ns.Greeting.Build(lead, ctx.db.settings)
    end
    return lead, isNew
  end
end

-- `toast: shown lead=<id> more=<n>` whenever AlertToast.Show runs. Wrapped before login, so
-- the Leads.On("new", AlertToast.Show) Bootstrap makes subscribes the wrapper.
local function reportToasts(ctx)
  local AlertToast = ctx.ns.AlertToast
  local show = AlertToast.Show
  AlertToast.Show = function(lead)
    show(lead)
    ctx.out[#ctx.out + 1] = string.format("toast: shown lead=%s more=%d", tostring(lead.id), AlertToast.more)
  end
end

-- Notes that the chat handler ran, so a line the scan never delivered can say so.
local function watchHandler(ctx)
  local ScanGate = ctx.ns.ScanGate
  ScanGate.SetHandler(function(...)
    ctx.handled = true
    return ScanGate.HandleChat(...)
  end)
end

-- The sim's own listeners, made right after the modules load and before Bootstrap runs, so
-- each index build prints `index:` before the scan line its evaluation causes.
local function watch(ctx)
  local ns = ctx.ns
  ns.Leads.On("greeted", function(lead)
    ctx.out[#ctx.out + 1] = "lead: greeted customer=" .. lead.customer
  end)
  ns.Leads.On("replied", function(lead)
    ctx.out[#ctx.out + 1] = "lead: replied customer=" .. lead.customer
  end)
  ns.Index.OnRebuilt(function(index)
    -- The read or learn that requested this build is reported first: Slicer.Drain runs the
    -- index job right after it, before STEPS.event reports.
    reportRead(ctx)
    reportLearn(ctx)
    flushBind(ctx)
    ctx.out[#ctx.out + 1] = "index: size=" .. index.size
  end)
  ns.Ledger.OnChange(function()
    ctx.ledgerChanged = true
  end)
  ns.ScanGate.OnChange(function(active, state)
    ctx.out[#ctx.out + 1] = "scan: " .. (active and "active" or string.format("paused (%s)", state.reason))
  end)
  reportMatches(ctx)
  reportToasts(ctx)
  watchHandler(ctx)
end

-- PLAYER_LOGIN, once, before the first chat line, event, command or click: Bootstrap installs
-- everything and builds the index.
local function start(ctx)
  if not ctx.started then
    ctx.started = true
    ctx.ns.BindLookup.lastStored = nil
    Wow.fireEvent("PLAYER_LOGIN")
  end
end

local function count(map)
  local total = 0
  for _ in pairs(map) do
    total = total + 1
  end
  return total
end

-- ADDON_LOADED: Bootstrap loads the account DB through SavedState.Load; a newer-schema warning
-- arrives later, as a `chat:` line among the login lines.
local function bindDb(ctx)
  Wow.fireEvent("ADDON_LOADED", "CraftAlert")
  local db = rawget(_G, "CraftAlertDB")
  ctx.db = db
  local recipes = 0
  for _, character in pairs(db.characters) do
    recipes = recipes + count(character.recipes)
  end
  ctx.out[#ctx.out + 1] =
    string.format("db: schema=%s characters=%d recipes=%d leads=%d", tostring(db.schema), count(db.characters), recipes, #db.leads)
end

-- `ledger: seen=<n> greeted=<n> replied=<n> filled=<n>`, today's counters, as the last line of a
-- run that changed one (spec §8).
local function reportLedger(ctx)
  if ctx.ledgerChanged then
    local today = ctx.ns.Ledger.Today()
    ctx.out[#ctx.out + 1] = string.format("ledger: seen=%d greeted=%d replied=%d filled=%d", today.seen, today.greeted, today.replied, today.filled)
  end
end

local STEPS = {}

function STEPS.sender(ctx, step)
  ctx.sender = step.name
end

-- --class TOKEN: the next chat line's sender has that class (GUID SIM_CLASS_GUID).
function STEPS.class(ctx, step)
  ctx.class = step.token
end

-- The line as a CHAT_MSG_CHANNEL event from the current sender on Trade. A line the paused
-- scan never receives prints `stop: paused`; one the Matcher stopped prints `stop: <step>`.
function STEPS.line(ctx, step)
  start(ctx)
  local sender = ctx.sender
  ctx.out[#ctx.out + 1] = "sender: " .. tostring(ctx.ns.PlayerName.Normalize(sender))
  ctx.handled = false
  local guid = ctx.class and SIM_CLASS_GUID or nil
  Wow.fireEvent("CHAT_MSG_CHANNEL", step.text, sender, "", TRADE_CHANNEL_NAME, sender, "", TRADE_ZONE_CHANNEL_ID, 2, TRADE_BASE_NAME, 0, 1, guid)
  local lastStop = ctx.ns.Matcher.lastStop
  if not ctx.handled then
    ctx.out[#ctx.out + 1] = "stop: paused"
  elseif lastStop ~= "match" then
    ctx.out[#ctx.out + 1] = "stop: " .. lastStop
  end
  ctx.sender = DEFAULT_SENDER
  ctx.class = nil
end

-- Event arguments arrive as text: true/false and numbers become the values the client sends.
local function eventArg(text)
  if text == "true" or text == "false" then
    return text == "true"
  end
  return tonumber(text) or text
end

-- Runs the timers armed for `maxDelay` seconds or less (0: the same frame, such as the Slicer
-- tick that runs an index rebuild the bind timer requested); longer ones, such as the lead expiry, stay pending, as in the game where no
-- second passes between two sim steps.
local function runFrameTimers(maxDelay)
  local found = true
  while found do
    found = false
    for i, timer in ipairs(Wow.timers) do
      if timer.delay <= maxDelay then
        table.remove(Wow.timers, i)
        timer.fn()
        found = true
        break
      end
    end
  end
end

-- Fires the event, then runs the frame timers. Item data arriving is the one event that
-- lets the 1 s bind debounce elapse too, so its result (bind stored, index rebuilt) shows.
function STEPS.event(ctx, step)
  start(ctx)
  local args = {}
  for i, text in ipairs(step.args) do
    args[i] = eventArg(text)
  end
  ctx.ns.ModernReader.lastRead = nil
  ctx.ns.LearnWatcher.lastStored = nil
  ctx.ns.BindLookup.lastStored = nil
  Wow.fireEvent(step.name, unpack(args, 1, #step.args))
  ctx.ns.Slicer.Drain()
  reportRead(ctx)
  reportLearn(ctx)
  runFrameTimers(step.name == "GET_ITEM_INFO_RECEIVED" and BIND_DEBOUNCE_SECONDS or 0)
  flushBind(ctx)
end

function STEPS.afk(ctx, step)
  ctx.afk = step.on
  if ctx.started then
    Wow.fireEvent("PLAYER_FLAGS_CHANGED", "player")
  end
end

function STEPS.resting(ctx, step)
  ctx.resting = step.on
  if ctx.started then
    Wow.fireEvent("PLAYER_UPDATE_RESTING")
  end
end

function STEPS.cmd(ctx, step)
  start(ctx)
  local slashCommands = rawget(_G, "SlashCmdList")
  local handler = slashCommands and slashCommands.CRAFTALERT
  if not handler then
    ctx.out[#ctx.out + 1] = "error: no slash handler registered"
    return
  end
  local args = string.match(step.text, "^/%S+%s*(.*)$") or step.text
  handler(args)
end

-- The mouse button and modifier each --click value stands for (the §7.1 table).
local CLICKS = {
  left = { button = "LeftButton" },
  shift = { button = "LeftButton", shift = true },
  ctrl = { button = "LeftButton", ctrl = true },
  right = { button = "RightButton" },
}

-- The newest lead through ClickRouter, as if its toast had been shown for a second; the
-- `send:` lines come from the stubbed send APIs.
function STEPS.click(ctx, step)
  start(ctx)
  local lead = ctx.ns.Leads.Latest()
  if not lead then
    ctx.out[#ctx.out + 1] = "error: --click " .. step.button .. " has no lead to act on"
    return
  end
  local click = CLICKS[step.button]
  ctx.keys.shift, ctx.keys.ctrl = click.shift == true, click.ctrl == true
  local action = ctx.ns.ClickRouter.Handle(click.button, lead, rawget(_G, "GetTime")() - SHOWN_FOR_SECONDS)
  ctx.keys.shift, ctx.keys.ctrl = false, false
  if action == "dismiss" then
    ctx.out[#ctx.out + 1] = "lead: dismissed customer=" .. lead.customer
  end
end

function Sim.Run(argv)
  local plan, parseError = parse(argv)
  if not plan then
    return { parseError }
  end

  Wow.reset()
  Wow.flavor(plan.flavor)
  local out = { "" }
  captureOutput(out)
  local db, dbError = loadDb(plan.dbPath)
  if not db then
    return { dbError }
  end
  Wow.stub("CraftAlertDB", db)

  local ctx = newContext(plan, out)
  local moduleCount, loadError = loadModules(ctx.ns)
  if not moduleCount then
    return { "error: module load failed: " .. tostring(loadError) }
  end
  Sim.lastNs = ctx.ns
  out[1] = string.format("sim: flavor=%s modules=%d", ctx.ns.FlavorCompat.flavorKey, moduleCount)
  watch(ctx)
  bindDb(ctx)

  for _, step in ipairs(plan.steps) do
    STEPS[step.kind](ctx, step)
  end
  reportLedger(ctx)
  return out
end

if rawget(_G, "arg") and not rawget(_G, "CRAFTALERT_SIM_NO_MAIN") then
  local failed = false
  for _, line in ipairs(Sim.Run(rawget(_G, "arg"))) do
    print(line)
    failed = failed or string.find(line, "error: ", 1, true) == 1
  end
  -- A non-zero exit lets a Proof run notice a broken sim invocation.
  if failed then
    os.exit(1)
  end
end

return Sim
