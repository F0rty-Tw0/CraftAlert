local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Leads = ns.Leads or require("CraftAlert.Model.Leads")

-- Spec §8: daily counters { seen, greeted, replied, filled } in `db.ledger`, keyed by the local
-- date ("%Y-%m-%d"). "seen" counts new leads only: an update of a lead fires "change", not "new",
-- and the leads' own "seen" event (a lead viewed) is never counted. `/ca test` leads never count.
-- SavedState.Load drops the days older than 30.
local Ledger = {}

local pcall = pcall

local SECONDS_PER_DAY = 24 * 60 * 60
local NOON = 12 * 60 * 60
local FIELDS = { seen = true, greeted = true, replied = true, filled = true }

---@type table
local db = nil
local listeners = {}

local function now()
  return _G["time"]()
end

local function dayKey(at)
  return _G["date"]("%Y-%m-%d", at)
end

local function zeros()
  local counters = { seen = 0, greeted = 0, replied = 0, filled = 0 }

  return counters
end

local function reportError(err)
  local getHandler = _G["geterrorhandler"]
  if type(getHandler) == "function" then
    getHandler()(err)
  end
end

-- Listeners get no argument: the strip re-reads Today and LastDays.
function Ledger.OnChange(fn)
  listeners[#listeners + 1] = fn
end

-- One more of `field` today. Before Install, or for an unknown field, nothing.
function Ledger.Add(field)
  if db == nil or not FIELDS[field] then
    return
  end
  local key = dayKey(now())
  local day = db.ledger[key] or zeros()
  db.ledger[key] = day
  day[field] = day[field] + 1
  for i = 1, #listeners do
    local ok, err = pcall(listeners[i])
    if not ok then
      reportError(err)
    end
  end
end

-- A copy of `key`'s counters, zeros for a day without a record.
local function read(key)
  local day = db and db.ledger[key]
  local counters = zeros()
  if day then
    counters.seen, counters.greeted, counters.replied, counters.filled = day.seen, day.greeted, day.replied, day.filled
  end
  return counters
end

function Ledger.Today()
  return read(dayKey(now()))
end

-- Today first, then the `count` - 1 days before it; each entry carries its `day` key. Days are
-- stepped from today's noon, so a 23 or 25 hour day (summer time) never skips or repeats a date.
function Ledger.LastDays(count)
  local current = now()
  local clock = _G["date"]("*t", current)
  local noon = current - (clock.hour * 3600 + clock.min * 60 + clock.sec) + NOON
  local days = {}
  for i = 1, count do
    local key = dayKey(noon - (i - 1) * SECONDS_PER_DAY)
    local counters = read(key)
    counters.day = key
    days[i] = counters
  end
  return days
end

local function counter(field)
  return function(lead)
    if not lead.test then
      Ledger.Add(field)
    end
  end
end

-- Bootstrap, at PLAYER_LOGIN before Leads.Restore (which fires none of these).
function Ledger.Install(accountDb)
  db = accountDb
  Leads.On("new", counter("seen"))
  Leads.On("greeted", counter("greeted"))
  Leads.On("replied", counter("replied"))
end

ns.Ledger = Ledger
return Ledger
