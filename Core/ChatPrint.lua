local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Addon notices in the default chat frame, with the gold addon prefix.
local ChatPrint = {}

local PREFIX = "|cffffd100Craft Alert:|r "

-- Prints one line; returns false when there is no chat frame to print to.
function ChatPrint.Line(text)
  local frame = _G["DEFAULT_CHAT_FRAME"]
  if frame == nil or type(frame.AddMessage) ~= "function" then
    return false
  end
  frame:AddMessage(PREFIX .. text)
  return true
end

ns.ChatPrint = ChatPrint
return ChatPrint
