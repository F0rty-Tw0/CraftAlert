local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Phone-style slide spec: how Craft Alert's frames stack in WhisperMessenger's host frame. Lifted,
-- a frame sits LIFT levels above the host: over WM's divider handle, which sits 50 above the
-- contacts pane, a sibling of the host (UI/MessengerWindow/LayoutBuilder/ContactsSection.lua:115-121
-- and UI/Theme/Layout.lua:17, WM), so its line never draws over the frame; it takes the mouse, so
-- nothing under it is clicked or dragged through it. Dropped, it sits at a child's own level, one
-- above the host, and lets the mouse through.
local HostLift = {}

HostLift.LIFT = 60

function HostLift.Apply(frame, host, lifted)
  frame:SetFrameLevel(host:GetFrameLevel() + (lifted and HostLift.LIFT or 1))
  frame:EnableMouse(lifted)
end

ns.HostLift = HostLift
return HostLift
