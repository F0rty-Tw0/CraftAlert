local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local CrafterRank = ns.CrafterRank or require("CraftAlert.Model.CrafterRank")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")

-- Spec §7.2: the leads (matched requests) the player can answer. Steps 5-7 of §6.3 run here
-- on matched lines only. Leads live in `db.leads`, oldest first (an updated lead moves to the
-- end); a lead is plain data (no table fields), because the Matcher's result it is copied
-- from is reused by the next line. One expiry timer (§4.3 rule 1) waits for the oldest lead.
local Leads = {}

local concat = table.concat
local remove = table.remove
local sort = table.sort
local max = math.max
local pcall = pcall
local tostring = tostring
local type = type

local MAX_LEADS = 100
-- A lead whose guid starts with this is a synthetic `/ca test` lead: flagged `test`, never saved.
Leads.TEST_GUID_PREFIX = FlavorCompat.TEST_GUID_PREFIX
local EVENTS = { new = true, change = true, greeted = true, replied = true, seen = true }
local ITEM_EVENT = "GET_ITEM_INFO_RECEIVED"

---@type table
local db = nil
local leads = {} -- db.leads once Restore binds it, edited in place; empty while unbound
local nextId = 1
local timerArmed = false
local timerGeneration = 0 -- only the timer started last acts when it fires
local timerDeadline = 0 -- time() when the pending timer fires
local awaited = {} -- itemID -> true while the client loads an item a lead lacks the link of

-- A lead's item link is nil until the client has cached the item: a miss asks the client to
-- load it, and GET_ITEM_INFO_RECEIVED is registered only while an item is awaited (as in
-- BindLookup, §5.2). No timer of its own: every "change" stops waiting for items no listed lead
-- lacks any more (pruneAwaited), so the lead expiry bounds the wait.
local onItemInfo

local function stopIfIdle()
  if next(awaited) == nil then
    EventRouter.Off(ITEM_EVENT, onItemInfo)
  end
end

local function pruneAwaited()
  if next(awaited) == nil then
    return
  end
  local needed = {}
  for i = 1, #leads do
    if leads[i].itemID ~= nil and leads[i].itemLink == nil then
      needed[leads[i].itemID] = true
    end
  end
  for itemID in pairs(awaited) do
    awaited[itemID] = needed[itemID]
  end
  stopIfIdle()
end

local listeners = { new = {}, change = { pruneAwaited }, greeted = {}, replied = {}, seen = {} }

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
-- "greeted", "replied" and "seen" (lead; none after Mark all read).
function Leads.On(name, fn)
  if not EVENTS[name] then
    error("Leads.On: unknown event " .. tostring(name), 2)
  end
  local list = listeners[name]
  list[#list + 1] = fn
end

local function linkOf(itemID)
  return (select(2, FlavorCompat.GetItemInfo(itemID)))
end

-- Sets lead.itemLink from the item cache; on a miss, asks the client to load the item.
local function fillLink(lead)
  local itemID = lead.itemID
  lead.itemLink = linkOf(itemID)
  local items = _G["C_Item"]
  if lead.itemLink ~= nil or awaited[itemID] or type(items) ~= "table" then
    return
  end
  if type(items.RequestLoadItemDataByID) ~= "function" then
    return
  end
  awaited[itemID] = true
  EventRouter.On(ITEM_EVENT, onItemInfo)
  items.RequestLoadItemDataByID(itemID)
end

-- The client loaded an item, or failed to (its second argument false; GetItemInfo then stays
-- nil): either way it is no longer awaited. Every listed lead of it that lacks the link gets
-- it, with one "change" so the cards and the toast repaint.
onItemInfo = function(itemID)
  if not awaited[itemID] then
    return
  end
  awaited[itemID] = nil
  stopIfIdle()
  local link = linkOf(itemID)
  if not link then
    return
  end
  local filled = false
  for i = 1, #leads do
    if leads[i].itemID == itemID and leads[i].itemLink == nil then
      leads[i].itemLink = link
      filled = true
    end
  end
  if filled then
    fire("change")
  end
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

-- Drops the leads of every customer on Blizzard's ignore list. → whether any went.
local function dropIgnored(list)
  local removed = false
  for i = #list, 1, -1 do
    if CrafterRank.IsIgnored(list[i].customer) then
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

-- Removes synthetic (`/ca test`) leads from the list, in place (the list is db.leads).
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

-- Spec §4.4 rule 8, small saved data: a lead's `crafters` list is live only, so it leaves every
-- lead just before the client writes CraftAlertDB (PLAYER_LOGOUT, also on /reload). Schema still
-- drops it from a save written before this.
local function dropLiveFields()
  for i = 1, #leads do
    leads[i].crafters = nil
  end
end

-- Binds db.leads (Bootstrap, at PLAYER_LOGIN): repairs a hand-edited list (ids, times, order,
-- size), drops test leads, expired leads and the leads of ignored customers (the ignore list may
-- have loaded before the addon, so no IGNORELIST_UPDATE comes for it), starts the timer and asks
-- again for the item links the last session never got. The db is bound before the ignore check,
-- which calls Blizzard's API: while a repair raises, Leads stays unbound and makes no lead.
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
  EventRouter.On("PLAYER_LOGOUT", dropLiveFields)
  removed = dropIgnored(list) or removed
  for i = 1, #list do
    if list[i].itemID ~= nil and list[i].itemLink == nil then
      fillLink(list[i])
    end
  end
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

-- For /ca test: the lead a matched line from `customerKey` would update, or nil.
Leads.FindDuplicate = findDuplicate

-- Joins the Matcher's why tokens (the intent word, then what matched; item IDs are numbers).
local function joinWhy(result)
  local parts = {}
  for i = 1, result.whyCount do
    parts[i] = tostring(result.why[i])
  end
  return concat(parts, " + ")
end

-- The recipe key of the crafter's first entry in the match.
local function firstKey(result, crafter)
  for i = 1, result.entryCount do
    local entry = result.entries[i]
    if entry.character == crafter then
      return entry.recipeKey
    end
  end
  return nil
end

-- What the chosen crafter's own record says about the match: its recipe (item results) and
-- the name of the profession. `recipeKey` is the entry Pick ranked; nil leaves the recipe
-- fields empty.
local function describeCrafter(lead, kind, prof, crafter, recipeKey)
  lead.recipeKey = recipeKey
  local character = db.characters[crafter]
  local profession = character and character.professions and character.professions[prof]
  lead.profName = profession and profession.name or (type(prof) == "string" and prof or nil)
  if kind ~= "item" or recipeKey == nil then
    return
  end
  local recipe = character and character.recipes and character.recipes[recipeKey]
  lead.recipeName = recipe and recipe.name or (type(recipeKey) == "string" and recipeKey or nil)
  lead.itemID = recipe and recipe.item or nil
  if lead.itemID then
    fillLink(lead)
  end
end

-- The lead for a matched line from `crafter`, copied out of the Matcher's reused result;
-- numbered and stored by the caller.
local function buildLead(result, customerKey, text, channelKey, pick)
  local lead = {
    customer = customerKey,
    message = text,
    channel = channelKey,
    kind = result.kind,
    prof = result.prof,
    group = result.group,
    why = joinWhy(result),
    crafter = pick.crafter,
    cannotOrder = pick.cannotOrder,
    rank = pick.rank,
    rankConc = pick.rankConc,
    crafters = pick.candidates, -- live only: dropped at logout (dropLiveFields)
    time = now(),
    greeted = false,
    replied = false,
    seen = false,
  }
  local recipeKey = pick.recipeKey
  if recipeKey == nil and result.kind == "item" then
    recipeKey = firstKey(result, pick.crafter)
  end
  describeCrafter(lead, result.kind, result.prof, pick.crafter, recipeKey)
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
  local crafter, cannotOrder, rank, rankConc, recipeKey, candidates = CrafterRank.Pick(result, customerKey, db)
  if crafter == nil then
    return nil
  end
  local pick = {
    crafter = crafter,
    cannotOrder = cannotOrder,
    rank = rank,
    rankConc = rankConc,
    recipeKey = recipeKey,
    candidates = candidates,
  }
  lead = buildLead(result, customerKey, text, channelKey, pick)
  lead.id = nextId
  lead.guid = type(guid) == "string" and not FlavorCompat.issecretvalue(guid) and guid or nil
  if FlavorCompat.IsTestGuid(lead.guid) then
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

-- The main crafter moved: pick the crafter of an unanswered lead again from the candidates it
-- kept. → whether the crafter changed. A greeted or replied lead keeps who was greeted; a
-- restored lead has no candidates.
function Leads.Repick(id)
  local lead = find(id)
  if lead == nil or lead.greeted ~= false or lead.replied ~= false then
    return false
  end
  local crafters = lead.crafters
  if type(crafters) ~= "table" or #crafters == 0 then
    return false
  end
  local crafter, cannotOrder, rank, rankConc, recipeKey = CrafterRank.Repick(lead, db)
  if crafter == nil or crafter == lead.crafter then
    return false
  end
  lead.crafter, lead.cannotOrder, lead.rank, lead.rankConc = crafter, cannotOrder, rank, rankConc
  lead.recipeName, lead.itemID, lead.itemLink = nil, nil, nil
  describeCrafter(lead, lead.kind, lead.prof, crafter, recipeKey)
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

-- The first time a lead is shown in the details. "seen", not "change": the details mark it while
-- UI/LeadsView.lua refreshes, which a "change" would re-enter; that refresh repaints the row's
-- dot itself. → whether this was the first.
function Leads.MarkSeen(id)
  local lead = find(id)
  if lead == nil or lead.seen then
    return false
  end
  lead.seen = true
  fire("seen", lead)
  return true
end

-- WhisperMessenger's Mark all read: every listed lead of `ids` is seen, with one "seen" (no lead)
-- when any was not, so the badge refreshes once.
function Leads.MarkAllSeen(ids)
  local changed = false
  for _, id in ipairs(ids) do
    local lead = find(id)
    if lead and not lead.seen then
      lead.seen, changed = true, true
    end
  end
  if changed then
    fire("seen")
  end
end

-- Neither greeted nor seen: the badge counts it and its row shows the unseen dot (spec B).
function Leads.IsUnseen(lead)
  return not lead.greeted and not lead.seen
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
  if dropIgnored(leads) then
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
