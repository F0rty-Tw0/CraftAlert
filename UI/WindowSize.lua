local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Native-HUD spec §7.1: the leads window keeps one size per mode, each under its own key of
-- CraftAlertDB.ui, and one position under the caller's key. A size is
-- { key, width, height, minWidth, minHeight }: the saved key, the defaults and the bounds.
local WindowSize = {}

local max = math.max
local min = math.min
local type = type

-- The saved number, else the default; at least the minimum and at most the screen's (the Schema
-- keeps any finite number).
local function clamped(saved, default, minimum, screen)
  local value = type(saved) == "number" and saved or default
  return max(min(value, screen), minimum)
end

-- Sets the resize bounds of `size.key`'s mode, then sizes the frame to its saved size: bounds
-- first, so a client that clamps SetSize to them lets the window shrink to a smaller mode.
function WindowSize.Apply(frame, size)
  frame:SetResizable(true)
  frame:SetResizeBounds(size.minWidth, size.minHeight)
  local resizeButton = frame.resizeButton
  if resizeButton then
    resizeButton:SetMinWidth(size.minWidth)
    resizeButton:SetMinHeight(size.minHeight)
  end
  local saved, screen = FrameKit.Saved(size.key) or {}, _G["UIParent"]
  local width = clamped(saved.width, size.width, size.minWidth, screen:GetWidth())
  local height = clamped(saved.height, size.height, size.minHeight, screen:GetHeight())
  frame:SetSize(width, height)
end

-- Saves the shared position under `positionKey` and the frame's size under `size.key`.
function WindowSize.Save(frame, size, positionKey)
  FrameKit.SavePosition(frame, positionKey)
  local saved = FrameKit.Saved(size.key)
  if saved then
    saved.width, saved.height = frame:GetWidth(), frame:GetHeight()
  end
end

ns.WindowSize = WindowSize
return WindowSize
