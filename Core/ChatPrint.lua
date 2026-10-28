local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Localization = ns.Localization or require("CraftAlert.Core.Localization")

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

-- In an instance, prints the off line and returns true for the caller to stop; false elsewhere.
function ChatPrint.OffInInstance()
  if not FlavorCompat.InInstance() then
    return false
  end
  ChatPrint.Line(Localization.Text("Off in instances; it works again when you leave."))
  return true
end

ns.ChatPrint = ChatPrint
return ChatPrint
