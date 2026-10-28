local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- Native-HUD spec §4.3: the toast's lines and its measured height. The name and the badge share the top
-- row; the headline, the detail line (shown only with a rank or realm tag) and the message stack
-- under it, each wrapping across the toast's inner width.
local ToastLayout = {}

local LINE_GAP = 3

-- A wrapping line. Its explicit width lets GetStringHeight measure it before the first layout.
local function wrapped(frame, font)
  local layout = Theme.LAYOUT
  local text = FrameKit.Text(frame, font)
  text:SetWidth(layout.TOAST_WIDTH - 2 * layout.PADDING)
  text:SetWordWrap(true)

  return text
end

-- Puts `text` `top` pixels below the frame's top edge, spanning the frame inset by PADDING on
-- both sides. → the offset where the next line starts.
local function place(frame, text, top)
  local padding = Theme.LAYOUT.PADDING
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -top)
  text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padding, -top)

  return top + text:GetStringHeight() + LINE_GAP
end

-- → { name, badge, headline, detail, message }, the toast's font strings, made in that order.
function ToastLayout.Build(frame)
  local padding, fonts = Theme.LAYOUT.PADDING, Theme.FONTS
  local name = FrameKit.Text(frame, fonts.name)
  name:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
  local badge = FrameKit.Text(frame, fonts.badge, Theme.COLORS.gold)
  badge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padding, -padding)
  badge:SetJustifyH("RIGHT")
  name:SetPoint("RIGHT", badge, "LEFT", -padding, 0)
  local headline = wrapped(frame, fonts.name)
  local detail = wrapped(frame, fonts.detail)
  local message = wrapped(frame, fonts.body)
  message:SetNonSpaceWrap(true)
  local parts = { name = name, badge = badge, headline = headline, detail = detail, message = message }

  return parts
end

-- Stacks the lines under the top row (the message under the detail line when `hasDetail`, else
-- under the headline: a hidden line keeps its size; an empty message is skipped) and sizes the frame to the text.
function ToastLayout.Fit(frame, parts, hasDetail)
  local padding = Theme.LAYOUT.PADDING
  local top = place(frame, parts.headline, padding + parts.name:GetStringHeight() + LINE_GAP)
  if hasDetail then
    top = place(frame, parts.detail, top)
  end
  -- An empty message (the away summary) adds no line, so no gap trails the line above it.
  local bottom = top - LINE_GAP
  if (parts.message:GetText() or "") ~= "" then
    bottom = place(frame, parts.message, top) - LINE_GAP
  end
  frame:SetHeight(bottom + padding)
end

ns.ToastLayout = ToastLayout
return ToastLayout
