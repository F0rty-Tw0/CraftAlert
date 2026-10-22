local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local CrafterRank = ns.CrafterRank or require("CraftAlert.Model.CrafterRank")

-- Spec §7.2: the leads (matched requests) the player can answer. Steps 5-7 of §6.3 run here
-- on matched lines only. Leads live in `db.leads`, oldest first (an updated lead moves to the
-- end); a lead is plain data (no table fields), because the Matcher's result it is copied
-- from is reused by the next line. One expiry timer (§4.3 rule 1) waits for the oldest lead.
local Leads = {}

local concat = table.concat
local remove = table.remove
local sort = table.sort
local sub = string.sub
local max = math.max
local pcall = pcall
local tostring = tostring
local type = type

local MAX_LEADS = 100
-- A lead whose guid starts with this is a synthetic `/ca test` lead: flagged `test`, never saved.
local TEST_GUID_PREFIX = "Player-0-CRAFTALERTTEST"
Leads.TEST_GUID_PREFIX = TEST_GUID_PREFIX
local EVENTS = { new = true, change = true, greeted = true, replied = true }

---@type table
local db = nil
local leads = {} -- db.leads once Restore binds it, edited in place; empty while unbound
local nextId = 1
local timerArmed = false
local timerGeneration = 0 -- only the timer started last acts when it fires
local timerDeadline = 0 -- time() when the pending timer fires
local listeners = { new = {}, change = {}, greeted = {}, replied = {} }

local function now()
  return _G["time"]()
end

local function timeoutSeconds(accountDb)
  return accountDb.settings.leadTimeoutMin * 60
end

local function reportError(err)
  local getHandler = _G["geterrorhandler"]
  if type(getHandler) == "function" then
    getHandler()(err)
  end
end

-- "change" listeners get no argument; the others get the lead.
local function fire(name, lead)
  local list = listeners[name]
  for i = 1, #list do
    local ok, err
    if lead then
      ok, err = pcall(list[i], lead)
    else
      ok, err = pcall(list[i])
    end
    if not ok then
      reportError(err)
    end
  end
end

-- "new" (lead: the first alert), "change" (no arguments: any add, update, dismiss, expiry),
-- "greeted" and "replied" (lead).
function Leads.On(name, fn)
  if not EVENTS[name] then
    error("Leads.On: unknown event " .. tostring(name), 2)
  end
  local list = listeners[name]
  list[#list + 1] = fn
end

local function sweep(list, limit)
  local current = now()
  local removed = false
  for i = #list, 1, -1 do
    if current - list[i].time > limit then
      remove(list, i)
      removed = true
    end
  end
  return removed
end

local armExpiry

local function onExpiry(generation)
  if generation ~= timerGeneration then
    return
  end
  timerArmed = false
  local limit = timeoutSeconds(db)
  if sweep(leads, limit) then
    fire("change")
  end
  armExpiry(leads, limit)
end

-- The state changes only once C_Timer.After returned: if it raises, the timer pending before
-- (if any) stays the live one, and the next lead tries again.
local function startTimer(delay)
  local generation = timerGeneration + 1
  _G["C_Timer"].After(delay, function()
    onExpiry(generation)
  end)
  timerArmed = true
  timerGeneration = generation
  timerDeadline = now() + delay
end

local function delayForOldest(list, limit)
  return max(1, list[1].time + limit - now() + 1)
end

-- Waits for the oldest lead to pass the timeout (strictly, as the sweep counts it). A timer
-- that is already pending is kept: if its lead was dismissed or refreshed, it fires early,
-- sweeps nothing and re-arms.
armExpiry = function(list, limit)
  if timerArmed or list[1] == nil then
    return
  end
  startTimer(delayForOldest(list, limit))
end

-- After a leadTimeoutMin change (settings page): sweeps what the new timeout already expired,
-- and when the oldest lead's new deadline comes before the pending timer, arms one for it. The
-- timer it replaces cannot be cancelled; it fires later and does nothing. A later deadline
-- keeps the pending timer, which fires early and re-arms.
function Leads.Rearm()
  if db == nil then
    return
  end
  local limit = timeoutSeconds(db)
  if sweep(leads, limit) then
    fire("change")
  end
  if leads[1] == nil then
    return
  end
  local delay = delayForOldest(leads, limit)
  if not timerArmed or now() + delay < timerDeadline then
    startTimer(delay)
  end
end

-- Oldest first; leads of the same second keep their id order (ids are unique by now).
local function isOlder(a, b)
  if a.time ~= b.time then
    return a.time < b.time
  end
  return a.id < b.id
end

-- A hand-edited db may repeat or lack ids; find(id) must see each lead once. The first holder
-- of an id keeps it, the rest get fresh ones above every id in the db.
local function fixIds(list)
  local seen, broken = {}, {}
  nextId = 1
  for i = 1, #list do
    local id = list[i].id
    -- NaN can't be a table key and inf + 1 == inf, so only finite numbers count as ids. NaN
    -- fails every comparison, so the bounds check drops it too.
    if type(id) == "number" and id > -math.huge and id < math.huge and not seen[id] then
      seen[id] = true
      nextId = max(nextId, id + 1)
    else
      broken[#broken + 1] = list[i]
    end
  end
  for i = 1, #broken do
    broken[i].id = nextId
    nextId = nextId + 1
  end
end

-- Keeps the newest MAX_LEADS of a list that is sorted oldest first.
local function trim(list)
  local count = #list
  local excess = count - MAX_LEADS
  if excess <= 0 then
    return
  end
  for i = 1, count do
    list[i] = list[i + excess]
  end
end

-- A lead dated after now (hand-edited, or the clock was set back) would never pass the timeout:
-- it counts as arrived now.
local function clampTimes(list)
  local current = now()
  for i = 1, #list do
    if list[i].time > current then
      list[i].time = current
    end
  end
end

-- The leads that are not synthetic, in place (the list is db.leads).
local function dropTest(list)
  local kept = 0
  for i = 1, #list do
    if not list[i].test then
      kept = kept + 1
      list[kept] = list[i]
    end
  end
  for i = #list, kept + 1, -1 do
    list[i] = nil
  end
end

-- Binds db.leads (Bootstrap, at PLAYER_LOGIN): repairs a hand-edited list (ids, times, order,
-- size), drops expired leads and starts the timer. The db is bound last: while a repair raises,
-- Leads stays unbound and makes no lead.
function Leads.Restore(accountDb)
  local list = accountDb.leads
  dropTest(list)
  local limit = timeoutSeconds(accountDb)
  fixIds(list)
  clampTimes(list)
  sort(list, isOlder)
  trim(list)
  local removed = sweep(list, limit)
  armExpiry(list, limit)
  db, leads = accountDb, list
  if removed then
    fire("change")
  end
end

-- Whether Restore bound the db; until then no match makes a lead (ScanGate does not scan).
function Leads.IsBound()
  return db ~= nil
end

local function find(id)
  for i = 1, #leads do
    if leads[i].id == id then
      return leads[i], i
    end
  end
  return nil
end

local function sameMatch(lead, result)
  if lead.kind ~= result.kind then
    return false
  end
  if result.kind == "profession" then
    return lead.prof == result.prof
  end
  return lead.group == result.group
end

-- The same sender asking for the same thing again inside the timeout. → lead, position.
local function findDuplicate(customerKey, result)
  local limit, current = timeoutSeconds(db), now()
  for i = #leads, 1, -1 do
    local lead = leads[i]
    if lead.customer == customerKey and current - lead.time <= limit and sameMatch(lead, result) then
      return lead, i
    end
  end
  return nil
end

-- Joins the Matcher's why tokens (the intent word, then what matched; item IDs are numbers).
local function joinWhy(result)
  local parts = {}
  for i = 1, result.whyCount do
    parts[i] = tostring(result.why[i])
  end
  return concat(parts, " + ")
end

-- What the chosen crafter's own record says about the match: its recipe (item results) and
-- the name of the profession.
local function describeCrafter(lead, result, crafter)
  local character = db.characters[crafter]
  local profession = character and character.professions and character.professions[result.prof]
  lead.profName = profession and profession.name or (type(result.prof) == "string" and result.prof or nil)
  if result.kind ~= "item" then
    return
  end
  for i = 1, result.entryCount do
    local entry = result.entries[i]
    if entry.character == crafter then
      local recipe = character and character.recipes and character.recipes[entry.recipeKey]
      lead.recipeName = recipe and recipe.name or (type(entry.recipeKey) == "string" and entry.recipeKey or nil)
      lead.itemID = recipe and recipe.item or nil
      if lead.itemID then
        lead.itemLink = select(2, FlavorCompat.GetItemInfo(lead.itemID))
      end
      return
    end
  end
end

-- The lead for a matched line from `crafter`, copied out of the Matcher's reused result;
-- numbered and stored by the caller.
local function buildLead(result, customerKey, text, channelKey, crafter, cannotOrder)
  local lead = {
    customer = customerKey,
    message = text,
    channel = channelKey,
    kind = result.kind,
    prof = result.prof,
    group = result.group,
    why = joinWhy(result),
    crafter = crafter,
    cannotOrder = cannotOrder,
    time = now(),
    greeted = false,
    replied = false,
  }
  describeCrafter(lead, result, crafter)
  return lead
end

-- nil when the player is not AFK-flagged or the flag is secret (§7.6).
local function afkNow()
  local isAfk = _G["UnitIsAFK"]
  if type(isAfk) ~= "function" then
    return nil
  end
  local afk = isAfk("player")
  if FlavorCompat.issecretvalue(afk) then
    return nil
  end
  return afk == true
end

-- Steps 5-7 on a matched line. result: the Matcher's (reused) result; customerKey: the
-- normalized sender. → lead, isNew; nil when no crafter qualifies (customer ignored, or none
-- of the matched crafters is left).
function Leads.OnMatch(result, customerKey, text, channelKey, guid)
  if db == nil or customerKey == nil then
    return nil
  end
  -- grug: ignore list asked twice on a new lead (here and in Pick); matched lines only
  if CrafterRank.IsIgnored(customerKey) then
    return nil
  end
  local lead, position = findDuplicate(customerKey, result)
  if lead then
    lead.message, lead.channel, lead.time = text, channelKey, now()
    lead.why = joinWhy(result)
    remove(leads, position)
    leads[#leads + 1] = lead
    fire("change")
    return lead, false
  end
  local crafter, cannotOrder = CrafterRank.Pick(result, customerKey, db)
  if crafter == nil then
    return nil
  end
  lead = buildLead(result, customerKey, text, channelKey, crafter, cannotOrder)
  lead.id = nextId
  lead.guid = type(guid) == "string" and not FlavorCompat.issecretvalue(guid) and guid or nil
  if lead.guid and sub(lead.guid, 1, #TEST_GUID_PREFIX) == TEST_GUID_PREFIX then
    lead.test = true
  end
  lead.arrivedWhileAfk = afkNow()
  nextId = nextId + 1
  leads[#leads + 1] = lead
  if #leads > MAX_LEADS then
    remove(leads, 1)
  end
  armExpiry(leads, timeoutSeconds(db))
  fire("new", lead)
  fire("change")
  return lead, true
end

-- `/ca test` (§7.3): the lead `text` would make if "Test" on the player's realm had sent it in
-- Trade, with the ignore list skipped. Not numbered, stored, counted or announced.
-- → lead or nil when no enabled crafter qualifies.
function Leads.Preview(result, text)
  if db == nil then
    return nil
  end
  local customerKey = PlayerName.TestCustomer()
  local crafter, cannotOrder = CrafterRank.Pick(result, customerKey, db, { skipIgnore = true })
  if crafter == nil then
    return nil
  end
  return buildLead(result, customerKey, text, "trade", crafter, cannotOrder)
end

-- The first time a lead is greeted, however it was sent (§7.1). → whether this was the first.
function Leads.MarkGreeted(id)
  local lead = find(id)
  if lead == nil or lead.greeted then
    return false
  end
  lead.greeted = true
  if not lead.test then
    db.recentGreeted[lead.customer] = now()
  end
  fire("greeted", lead)
  fire("change")
  return true
end

-- The first customer whisper after the greeting. → whether this was the first.
function Leads.MarkReplied(id)
  local lead = find(id)
  if lead == nil or not lead.greeted or lead.replied then
    return false
  end
  lead.replied = true
  fire("replied", lead)
  fire("change")
  return true
end

-- The customer's newest lead.
function Leads.FindActiveByCustomer(key)
  for i = #leads, 1, -1 do
    if leads[i].customer == key then
      return leads[i]
    end
  end
  return nil
end

-- Whether the lead is still listed; a dismissed, expired or evicted one is not.
function Leads.IsActive(id)
  return find(id) ~= nil
end

function Leads.Dismiss(id)
  local lead, position = find(id)
  if lead then
    remove(leads, position)
    fire("change")
  end
end

-- Blizzard's ignore list changed (IGNORELIST_UPDATE): drop the open leads of every ignored customer.
function Leads.DismissIgnored()
  local removed = false
  for i = #leads, 1, -1 do
    if CrafterRank.IsIgnored(leads[i].customer) then
      remove(leads, i)
      removed = true
    end
  end
  if removed then
    fire("change")
  end
end

function Leads.Latest()
  return leads[#leads]
end

-- Newest first, as a new array.
function Leads.List()
  local list = {}
  for i = #leads, 1, -1 do
    list[#list + 1] = leads[i]
  end
  return list
end

function Leads.HasActive()
  return #leads > 0
end

ns.Leads = Leads
return Leads
