local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local EventRouter = ns.EventRouter or require("CraftAlert.Core.EventRouter")
local Index = ns.Index or require("CraftAlert.Model.Index")

-- Spec §5.2: fills in the `bind` of stored recipes. The bind type is the 14th value of
-- GetItemInfo, which is nil until the item is cached, so uncached items are requested in
-- batches of 50 (§4.4 rule 7) and GET_ITEM_INFO_RECEIVED is registered only while requests
-- are in flight. One 1 s timer (§4.3 rule 1; at most one pending) is armed whenever a batch
-- goes out or data arrives. Each tick stores the arrived bind types, gives up on items that
-- stayed silent for GIVE_UP_TICKS, and sends the next batch; the index is rebuilt once, on
-- the tick where nothing is in flight, waiting or arrived any more. Each item is requested
-- once per session, so a given-up item is retried only in a later session (its bind is
-- still nil then).
local BindLookup = {}

local pairs = pairs
local select = select

local EVENT = "GET_ITEM_INFO_RECEIVED"
local BATCH = 50
local DEBOUNCE_SECONDS = 1
local GIVE_UP_TICKS = 10
local BIND_INDEX = 14

local db = nil
local seen = {} -- itemID -> true once queued
local inflight = {} -- itemID -> tick it was requested while the client loads it
local inflightCount = 0
local waiting = {} -- queued behind a full batch, oldest first: waiting[waitingFirst..waitingLast]
local waitingFirst = 1
local waitingLast = 0
local received = {} -- itemID -> bind, applied on the next tick
local timerArmed = false
local tickCount = 0
local drainStored = 0 -- recipes stored since the last rebuild
BindLookup.lastStored = nil -- recipes stored by the last drain (the sim prints it)

function BindLookup.Configure(accountDb)
  db = accountDb
end

local function bindOf(itemID)
  return (select(BIND_INDEX, FlavorCompat.GetItemInfo(itemID)))
end

local onItemInfo
local onTimer

local function armTimer()
  if not timerArmed then
    timerArmed = true
    _G["C_Timer"].After(DEBOUNCE_SECONDS, onTimer)
  end
end

local function request(itemID)
  local bind = bindOf(itemID)
  if bind ~= nil then
    received[itemID] = bind
    armTimer()
    return
  end
  local items = _G["C_Item"]
  if type(items) ~= "table" or type(items.RequestLoadItemDataByID) ~= "function" then
    return
  end
  inflight[itemID] = tickCount
  inflightCount = inflightCount + 1
  EventRouter.On(EVENT, onItemInfo)
  items.RequestLoadItemDataByID(itemID)
  armTimer()
end

local function applyReceived()
  local stored = 0
  for _, character in pairs(db and db.characters or {}) do
    for _, recipe in pairs(character.recipes) do
      local bind = recipe.item and received[recipe.item]
      if bind ~= nil and recipe.bind == nil then
        recipe.bind = bind
        stored = stored + 1
      end
    end
  end
  received = {}
  return stored
end

local function giveUpOnSilentItems()
  for itemID, requestedAt in pairs(inflight) do
    if tickCount - requestedAt >= GIVE_UP_TICKS then
      inflight[itemID] = nil
      inflightCount = inflightCount - 1
    end
  end
  if inflightCount == 0 then
    EventRouter.Off(EVENT, onItemInfo)
  end
end

onTimer = function()
  timerArmed = false
  tickCount = tickCount + 1
  drainStored = drainStored + applyReceived()
  giveUpOnSilentItems()
  while inflightCount < BATCH and waitingFirst <= waitingLast do
    request(waiting[waitingFirst])
    waiting[waitingFirst] = nil
    waitingFirst = waitingFirst + 1
  end
  if inflightCount > 0 or waitingFirst <= waitingLast or next(received) ~= nil then
    armTimer()
    return
  end
  BindLookup.lastStored = drainStored
  if drainStored > 0 then
    drainStored = 0
    Index.RequestRebuild("bind")
  end
end

onItemInfo = function(itemID, success)
  if not inflight[itemID] then
    return
  end
  inflight[itemID] = nil
  inflightCount = inflightCount - 1
  if success then
    local bind = bindOf(itemID)
    if bind ~= nil then
      received[itemID] = bind
    end
  end
  if inflightCount == 0 then
    EventRouter.Off(EVENT, onItemInfo)
  end
  armTimer()
end

function BindLookup.Queue(itemID)
  if seen[itemID] then
    return
  end
  seen[itemID] = true
  if inflightCount < BATCH then
    request(itemID)
  else
    waitingLast = waitingLast + 1
    waiting[waitingLast] = itemID
  end
end

ns.BindLookup = BindLookup
return BindLookup
