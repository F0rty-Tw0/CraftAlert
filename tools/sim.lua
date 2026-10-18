-- CLI sim: feeds chat lines, events, slash commands and clicks through the real addon
-- modules with stubbed WoW APIs and returns what happened as text lines.
--   python scripts/sim.py [--flavor retail|forever|era|tbc|wrath|cata|mop] [--db FILE] ...
--   lua5.1 tools/sim.lua ...   (from the repo root)
-- Output lines are `<area>: <fact>`; the first is always `sim: flavor=<key> modules=<n>`.
local ROOT = rawget(_G, "CRAFTALERT_ROOT") or "."
package.path = ROOT .. "/?.lua;" .. package.path

local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")

local DEFAULT_SENDER = "Customer-OtherRealm"
local OWN_NAME = "Crafter"
local OWN_REALM = "OwnRealm"
local DEFAULT_FLAVOR = "retail"
local CLICK_BUTTONS = { left = true, shift = true, ctrl = true, right = true }
local ON_OFF = { on = true, off = false }

local Sim = {}

-- The shared ns of the most recent Run, for tests and ad-hoc inspection.
Sim.lastNs = nil

-- Flags taking exactly one value; the parser checks the value where it is not free text.
local ONE_VALUE = { "--flavor", "--db", "--sender", "--cmd", "--click", "--afk", "--resting" }

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
      local args = {}
      while argv[i + 1] and string.sub(argv[i + 1], 1, 2) ~= "--" do
        args[#args + 1] = argv[i + 1]
        i = i + 1
      end
      if #args == 0 then
        return nil, "error: --event needs an event name"
      end
      plan.steps[#plan.steps + 1] = { kind = "event", name = table.remove(args, 1), args = args }
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
  Wow.stub("UnitIsAFK", function()
    return ctx.afk
  end)
  Wow.stub("IsResting", function()
    return ctx.resting
  end)
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
  return ctx
end

-- Runs once before the first chat line, event, command or click: the place where the
-- initial index build and scan evaluation go once those modules exist.
local function start(ctx)
  if not ctx.started then
    ctx.started = true
    ctx.ns.PlayerName.Init()
  end
end

local STEPS = {}

function STEPS.sender(ctx, step)
  ctx.sender = step.name
end

function STEPS.line(ctx, step)
  start(ctx)
  ctx.lastLine = { text = step.text, sender = ctx.sender }
  ctx.out[#ctx.out + 1] = "sender: " .. tostring(ctx.ns.PlayerName.Normalize(ctx.sender))
  ctx.sender = DEFAULT_SENDER
end

function STEPS.event(ctx, step)
  start(ctx)
  Wow.fireEvent(step.name, unpack(step.args))
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

function STEPS.click(ctx, step)
  start(ctx)
  ctx.out[#ctx.out + 1] = "error: --click " .. step.button .. " has no lead to act on yet"
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

  for _, step in ipairs(plan.steps) do
    STEPS[step.kind](ctx, step)
  end
  return out
end

if rawget(_G, "arg") and not rawget(_G, "CRAFTALERT_SIM_NO_MAIN") then
  for _, line in ipairs(Sim.Run(rawget(_G, "arg"))) do
    print(line)
  end
end

return Sim
