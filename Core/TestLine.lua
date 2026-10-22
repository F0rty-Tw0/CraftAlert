local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local ClassArmor = ns.ClassArmor or require("CraftAlert.Model.ClassArmor")
local Matcher = ns.Matcher or require("CraftAlert.Model.Matcher")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Status = ns.Status or require("CraftAlert.Core.Status")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")
local TestReport = ns.TestReport or require("CraftAlert.Core.TestReport")

-- Spec §7.3: `/ca test [as <class>] [x<N>] <line>` sends a synthetic Trade line through the real
-- path (scan gate, Matcher, Leads.OnMatch, toast), so it makes a real lead flagged `test`.
local TestLine = {}

local concat = table.concat
local ipairs = ipairs
local lower = string.lower
local match = string.match
local sub = string.sub
local tonumber = tonumber
local upper = string.upper

local MIN_BURST, MAX_BURST = 2, 6
local NO_MATCH = "nomatch"
local TRADE = "Trade"
local CHAT_EVENT = "CHAT_MSG_CHANNEL"
local TRADE_CHANNEL_NAME, TRADE_BASE_NAME, TRADE_ZONE_CHANNEL_ID = "2. Trade - City", "Trade - City", 2

local guidCount = 0 -- one per test line this session, so every line has its own guid
local say = TestReport.Say

local function usage()
  say("Usage: /ca test [as <class>] [x<N>] <a trade chat line> | /ca test reply")
end

local function nextWord(text)
  return match(text, "^(%S*)%s*(.-)$")
end

local function classToken(name)
  local wanted = upper(name)
  for _, token in ipairs(ClassArmor.Tokens()) do
    if token == wanted then
      return token
    end
  end
  return nil
end

-- → class token or nil, burst size, line; or nothing after printing the usage or the error.
-- Order is fixed: `as <class>`, then `x<N>`, then the line.
local function parse(args)
  local class
  local rest = args
  local word, after = nextWord(rest)
  if lower(word) == "as" then
    local name
    name, rest = nextWord(after)
    class = classToken(name)
    if class == nil then
      say("Unknown class %s. Classes: %s", name, concat(ClassArmor.Tokens(), ", "))
      return
    end
  end
  ---@type number
  local count = 1
  word, after = nextWord(rest)
  if match(word, "^[xX]%d+$") then
    count = tonumber(sub(word, 2)) or 0
    if count < MIN_BURST or count > MAX_BURST then
      return usage()
    end
    rest = after
  end
  if rest == "" then
    return usage()
  end
  return class, count, rest
end

-- Whether a real Trade line would be dropped before the Matcher; says why if so.
local function gateStops()
  local state = ScanGate.State()
  if state.reason then
    say("Test: %s, a real Trade line would be ignored too", Status.PausedText(state))
    return true
  end
  for _, name in ipairs(state.channels) do
    if name == TRADE then
      return false
    end
  end
  say("Test: Trade is off in channel settings, a real Trade line would be ignored too")
  return true
end

-- An update keeps its lead's first guid, but the Matcher reads the class of this line's guid.
-- The lead this line would update takes the line's class, so what is painted is what matched.
local function syncDuplicate(customer, sender, line, guid, class)
  if Leads.FindActiveByCustomer(customer) == nil then
    return
  end
  local result = Matcher.Match("trade", line, sender, guid)
  local duplicate = result and Leads.FindDuplicate(customer, result)
  if duplicate and duplicate.guid then
    FlavorCompat.SetTestClass(duplicate.guid, class)
  end
end

local function deliver(line, sender, class)
  guidCount = guidCount + 1
  local guid = FlavorCompat.TEST_GUID_PREFIX .. guidCount
  if class then
    FlavorCompat.SetTestClass(guid, class)
  end
  syncDuplicate(PlayerName.Normalize(sender), sender, line, guid, class)
  Matcher.lastStop = NO_MATCH
  TestReport.Begin()
  ScanGate.Deliver(CHAT_EVENT, line, sender, "", TRADE_CHANNEL_NAME, sender, "", TRADE_ZONE_CHANNEL_ID, 2, TRADE_BASE_NAME, 0, 1, guid)
  TestReport.End()
end

-- `/ca test` (§7.3), the command's arguments already trimmed.
function TestLine.Run(args)
  if args == "reply" then
    return TestReport.Reply()
  end
  local class, count, line = parse(args)
  if line == nil or gateStops() then
    return
  end
  local realm = PlayerName.RealmOf(PlayerName.Own() or "") or ""
  for i = 1, count do
    deliver(line, "Test" .. (count == 1 and 0 or i) .. "-" .. realm, class)
    TestReport.Print()
  end
end

-- Bootstrap, with the other lead listeners.
function TestLine.Install()
  TestReport.Install()
end

ns.TestLine = TestLine
return TestLine
