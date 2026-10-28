local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local WindowSize = ns.WindowSize or require("CraftAlert.UI.WindowSize")

-- Spec B.2: a size grip in a window's bottom-right corner. Dragging it sizes a translucent ghost
-- outline (the client's StartSizing does the dragging, no OnUpdate) while the window fades out of
-- the way; the release sizes the window once, its top-left corner kept, and runs onStopped. The
-- window never relayouts mid-drag.
local GhostResize = {}

local GRIP_SIZE = 16
local DRAG_ALPHA = 0.08
local FILL = { 0.10, 0.09, 0.08, 0.20 }
local EDGE = { 1, 1, 1, 0.85 }

---@type table|nil
local resizing = nil -- the window being resized, nil when none is

local function gripTexture(grip, path, layer)
  local texture = grip:CreateTexture(nil, layer)
  texture:SetTexture(path)
  return texture
end

-- Above the NineSlice border, whose corner covers the window's bottom-right.
local function createGrip(frame)
  local art = Theme.ART
  local grip = _G["CreateFrame"]("Button", nil, frame)
  grip:SetSize(GRIP_SIZE, GRIP_SIZE)
  -- off-scale: the grip's inset from the window's corner art, kept as is.
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
  grip:EnableMouse(true)
  grip:SetFrameLevel((frame.TitleContainer or frame):GetFrameLevel() + 20)
  grip:SetNormalTexture(gripTexture(grip, art.SIZE_GRABBER_UP, "ARTWORK"))
  grip:SetPushedTexture(gripTexture(grip, art.SIZE_GRABBER_DOWN, "ARTWORK"))
  grip:SetHighlightTexture(gripTexture(grip, art.SIZE_GRABBER_HIGHLIGHT, "HIGHLIGHT"), "ADD")
  -- The resize cursor on hover, as PanelResizeButtonTemplate showed it.
  grip:SetScript("OnEnter", function()
    if _G["SetCursor"] then
      _G["SetCursor"]("UI_RESIZE_CURSOR")
    end
  end)
  grip:SetScript("OnLeave", function()
    if _G["ResetCursor"] then
      _G["ResetCursor"]()
    end
  end)
  return grip
end

-- A 1 px line along one side of the ghost, from corner `from` to corner `to`.
local function addEdge(ghost, from, to, horizontal)
  local edge = ghost:CreateTexture(nil, "BORDER")
  edge:SetPoint(from, ghost, from, 0, 0)
  edge:SetPoint(to, ghost, to, 0, 0)
  if horizontal then
    edge:SetHeight(1)
  else
    edge:SetWidth(1)
  end
  edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
end

-- The outline the client sizes, bounded like the window: the minimum up to the screen.
local function createGhost(size)
  local screen = _G["UIParent"]
  local ghost = _G["CreateFrame"]("Frame", nil, screen)
  ghost:SetFrameStrata("DIALOG")
  ghost:SetResizable(true)
  ghost:SetClampedToScreen(true)
  ghost:SetResizeBounds(size.minWidth, size.minHeight, screen:GetWidth(), screen:GetHeight())
  local fill = ghost:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(ghost)
  fill:SetColorTexture(FILL[1], FILL[2], FILL[3], FILL[4])
  addEdge(ghost, "TOPLEFT", "TOPRIGHT", true)
  addEdge(ghost, "BOTTOMLEFT", "BOTTOMRIGHT", true)
  addEdge(ghost, "TOPLEFT", "BOTTOMLEFT", false)
  addEdge(ghost, "TOPRIGHT", "BOTTOMRIGHT", false)
  ghost:Hide()
  return ghost
end

-- Adds the grip to `frame` (size = { key, width, height, minWidth, minHeight }) and returns it,
-- also as frame.resizeGrip, its ghost as grip.ghost. onStopped(frame) runs after a release has
-- set the size; hiding the window mid-drag drops the drag and calls nothing.
function GhostResize.Attach(frame, size, onStopped)
  local grip, ghost = createGrip(frame), createGhost(size)
  local alpha, left, top = 1, 0, 0

  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or resizing ~= nil then
      return
    end
    alpha, left, top = frame:GetAlpha(), frame:GetLeft(), frame:GetTop()
    frame:SetAlpha(DRAG_ALPHA)
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", _G["UIParent"], "BOTTOMLEFT", left, top)
    ghost:SetSize(frame:GetWidth(), frame:GetHeight())
    ghost:Show()
    ghost:StartSizing("BOTTOMRIGHT", true)
    resizing = frame
  end)

  -- The client clamps to the ghost's bounds too, but does not guarantee it: clamped again here.
  grip:SetScript("OnMouseUp", function(_, button)
    if button ~= "LeftButton" or resizing ~= frame then
      return
    end
    resizing = nil
    ghost:StopMovingOrSizing()
    local screen = _G["UIParent"]
    local width = WindowSize.Clamp(ghost:GetWidth(), size.minWidth, screen:GetWidth())
    local height = WindowSize.Clamp(ghost:GetHeight(), size.minHeight, screen:GetHeight())
    ghost:Hide()
    frame:SetAlpha(alpha)
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", screen, "BOTTOMLEFT", left, top)
    onStopped(frame)
  end)

  frame:HookScript("OnHide", function()
    if resizing ~= frame then
      return
    end
    resizing = nil
    ghost:StopMovingOrSizing()
    ghost:Hide()
    frame:SetAlpha(alpha)
  end)

  grip.ghost = ghost
  frame.resizeGrip = grip
  return grip
end

-- True from a grip's left press until its release or its window hides.
function GhostResize.IsResizing()
  return resizing ~= nil
end

ns.GhostResize = GhostResize
return GhostResize
