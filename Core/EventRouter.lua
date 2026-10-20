local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- One hidden frame for all game events. An event is registered on it only while at least
-- one handler wants it (spec §4.3 rule 4), and handlers receive the event's arguments
-- without the event name.
local EventRouter = {}

local pcall = pcall
local frame = nil
local handlers = {} -- event -> array of functions; replaced, never edited, so Dispatch can walk it safely

-- Hands a caught error to the client's error handler (BugSack and the like); raises it when
-- there is none, so bare tests see it. Dispatch and Bootstrap's login steps use it.
function EventRouter.ReportError(err)
  local getHandler = _G["geterrorhandler"]
  if type(getHandler) ~= "function" then
    error(err, 0)
  end
  getHandler()(err)
end

function EventRouter.Dispatch(event, ...)
  local list = handlers[event]
  if list == nil then
    return
  end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then
      EventRouter.ReportError(err)
    end
  end
end

local function getFrame()
  if frame == nil then
    frame = _G["CreateFrame"]("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
      EventRouter.Dispatch(event, ...)
    end)
  end
  return frame
end

function EventRouter.On(event, fn)
  local list = handlers[event]
  local copy = {}
  for i = 1, list and #list or 0 do
    if list[i] == fn then
      return
    end
    copy[i] = list[i]
  end
  copy[#copy + 1] = fn
  -- Register before storing: clients throw on unknown events, and a stored
  -- handler would make every later On skip registration for good.
  if #copy == 1 then
    getFrame():RegisterEvent(event)
  end
  handlers[event] = copy
end

function EventRouter.Off(event, fn)
  local list = handlers[event]
  if list == nil then
    return
  end
  local copy = {}
  for i = 1, #list do
    if list[i] ~= fn then
      copy[#copy + 1] = list[i]
    end
  end
  if #copy == #list then
    return
  end
  if #copy == 0 then
    handlers[event] = nil
    getFrame():UnregisterEvent(event)
  else
    handlers[event] = copy
  end
end

ns.EventRouter = EventRouter
return EventRouter
