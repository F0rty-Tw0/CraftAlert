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
-- are in flight. Arrivals are applied, and the index rebuilt once, by a single 1 s timer
-- (§4.3 rule 1), which then sends the next batch. Each item is requested once per session.
local BindLookup = {}

local pairs = pairs
local select = select

local EVENT = "GET_ITEM_INFO_RECEIVED"
local BATCH = 50
local DEBOUNCE_SECONDS = 1
local BIND_INDEX = 14

local db = nil
local seen = {} -- itemID -> true once queued
local inflight = {} -- itemID -> true while the client loads it
local inflightCount = 0
local waiting = {} -- queued behind a full batch, oldest first: waiting[waitingFirst..waitingLast]
local waitingFirst = 1
local waitingLast = 0
local received = {} -- itemID -> bind, applied when the timer fires
local timerArmed = false

BindLookup.lastStored = 0

function BindLookup.Configure(accountDb)
  db = accountDb
end

local function bindOf(itemID)
  return (select(BIND_INDEX, FlavorCompat.GetItemInfo(itemID)))
end

local onItemInfo
local onTimer
local armTimer

local function request(itemID)
  local bind = bindOf(itemID)
  if bind ~= nil then
    received[itemID] = bind
    return
  end
  local items = _G["C_Item"]
  if type(items) ~= "table" or type(items.RequestLoadItemDataByID) ~= "function" then
    return
  end
  inflight[itemID] = true
  inflightCount = inflightCount + 1
  EventRouter.On(EVENT, onItemInfo)
  items.RequestLoadItemDataByID(itemID)
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

onTimer = function()
  timerArmed = false
  local stored = applyReceived()
  BindLookup.lastStored = stored
  if stored > 0 then
    Index.RequestRebuild("bind")
  end
  while inflightCount < BATCH and waitingFirst <= waitingLast do
    request(waiting[waitingFirst])
    waiting[waitingFirst] = nil
    waitingFirst = waitingFirst + 1
  end
  if next(received) ~= nil then
    armTimer()
  end
end

armTimer = function()
  if not timerArmed then
    timerArmed = true
    _G["C_Timer"].After(DEBOUNCE_SECONDS, onTimer)
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
    if received[itemID] ~= nil then
      armTimer()
    end
  else
    waitingLast = waitingLast + 1
    waiting[waitingLast] = itemID
  end
end

ns.BindLookup = BindLookup
return BindLookup
