local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")
local SettingsFixture = require("tests.helpers.settings_fixture")

-- Phase 5 sweep: allocation, slide-lifetime and refresh-count meters for the WM panel.
local Meter = {}

local HEIGHT = 400
local FRAME_SETTERS = { "SetPoint", "ClearAllPoints", "SetAlpha", "SetWidth", "SetHeight", "SetSize" }
local ANIMATION_SETTERS = { "SetOffset", "SetDuration", "SetSmoothing" }

-- KB in use after two full collections.
function Meter.settled()
  collectgarbage("collect")
  collectgarbage("collect")
  return collectgarbage("count")
end

-- KB allocated by fn() with the collector stopped, garbage included.
function Meter.garbage(fn)
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  fn()
  local after = collectgarbage("count")
  collectgarbage("restart")
  return after - before
end

-- What the addon has made so far: frames, regions (textures, strings), ScreenSlide groups, hooks.
function Meter.objects(ns)
  local regions, groups, hooks = 0, 0, 0
  for _, frame in ipairs(Wow.frames) do
    regions = regions + #frame.regions
    if ns.ScreenSlide.Group(frame) then
      groups = groups + 1
    end
    for _, list in pairs(frame.hooks or {}) do
      hooks = hooks + #list
    end
  end
  return { frames = #Wow.frames, regions = regions, groups = groups, hooks = hooks }
end

-- The ScreenSlide groups that are playing right now.
function Meter.playing(ns)
  local found = {}
  for _, frame in ipairs(Wow.frames) do
    local group = ns.ScreenSlide.Group(frame)
    if group and group.playing then
      found[#found + 1] = group
    end
  end
  return found
end

-- The client ends the slides: each playing group finishes (OnFinished). `reverse` finishes them in
-- the opposite order. Repeats while an onDone starts another slide; returns the rounds used (10 = stuck).
function Meter.settle(ns, reverse)
  for round = 1, 10 do
    local groups = Meter.playing(ns)
    if #groups == 0 then
      return round - 1
    end
    local first, last, step = 1, #groups, 1
    if reverse then
      first, last, step = #groups, 1, -1
    end
    for index = first, last, step do
      groups[index]:Finish()
    end
  end
  return 10
end

-- A copy of the frame's anchors, to compare after a slide.
function Meter.anchors(frame)
  local copy = {}
  for index, anchor in ipairs(frame.points) do
    copy[index] = { unpack(anchor) }
  end
  return copy
end

-- Every frame's position and alpha setters, and every slide animation's setters, become no-ops.
-- Call after the first slide (the groups exist from then on).
function Meter.silence(ns)
  for _, frame in ipairs(Wow.frames) do
    for _, name in ipairs(FRAME_SETTERS) do
      frame[name] = function() end
    end
    frame.hooks.OnShow = frame.hooks.OnShow or {} -- Widgets.fire allocates {} when a script has no hooks
    frame.hooks.OnHide = frame.hooks.OnHide or {}
    local group = ns.ScreenSlide.Group(frame)
    if group then
      for _, animation in ipairs(group.animations) do
        for _, name in ipairs(ANIMATION_SETTERS) do
          rawset(animation, name, function() end) -- the fake's __index would log every call
        end
      end
    end
  end
end

-- Wraps tbl[name]; returns count() (calls so far).
function Meter.count(tbl, name)
  local original, calls = tbl[name], 0
  tbl[name] = function(...)
    calls = calls + 1
    return original(...)
  end
  return function()
    return calls
  end
end

-- The addon in a WM panel `width` wide and 400 high with `leads` leads, shown:
-- { ns, wm, host, view, width } (view = the LeadsView the panel built). The leads clip frame is
-- sized: the fake does not size an all-points frame, and 0 wide means an instant swap, no slide.
function Meter.panel(width, leads)
  local ns = UiFixture.load({ leads = leads })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  wm.calls = setmetatable({}, { __newindex = function() end }) -- the fake logs every WM API call (the unread count per row) and would count as growth
  local captured, new = {}, ns.LeadsView.New
  ns.LeadsView.New = function(...)
    captured.view = new(...)
    return captured.view
  end
  local host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  host:SetSize(width, HEIGHT)
  wm.showPanel("CraftAlert", host)
  captured.view.frame:SetSize(width, HEIGHT)
  return { ns = ns, wm = wm, host = host, view = captured.view, width = width }
end

-- Opens the settings on the panel and sizes their clip frame; returns it.
function Meter.openSettings(p)
  p.ns.BridgePanel.ShowSettings()
  local container = SettingsFixture.navButton("General").parent.parent
  container:SetSize(p.width, HEIGHT)
  return container
end

-- One leads slide pair, each slide run to its end: row click to Details, then Back.
function Meter.leadsCycle(p)
  Widgets.click(p.view.list.rows[1], "LeftButton")
  Meter.settle(p.ns)
  p.ns.LeadsView.Back(p.view)
  Meter.settle(p.ns)
end

-- One settings slide pair: a nav button to its page, then the header arrow back.
function Meter.settingsCycle(p)
  Widgets.click(SettingsFixture.navButton("Alerts"), "LeftButton")
  Meter.settle(p.ns)
  Widgets.click(SettingsFixture.pageHeader().back)
  Meter.settle(p.ns)
end

-- A 360 x 400 parent holding two full-size screens under a 20 px strip; `from` shown, `to` hidden.
-- Returns ns, parent, from, to (no panel around them: ScreenSlide alone).
function Meter.slideRig()
  local ns = UiFixture.load()
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  parent:SetSize(360, HEIGHT)
  local function screen()
    local frame = _G["CreateFrame"]("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -20)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    return frame
  end
  local from, to = screen(), screen()
  to:Hide()
  return ns, parent, from, to
end

-- LeadsView.Refresh calls per user action on a narrow panel, in order: { { name, refreshes }, ... }.
-- A click or Back includes running its slide to the end; one client frame passes after each action
-- (Widgets.nextFrame), so size events in one action are one frame's burst.
function Meter.actionCounts()
  local p = Meter.panel(360, 30)
  local refreshes, rows = Meter.count(p.ns.LeadsView, "Refresh"), {}
  local function measure(name, action)
    local before = refreshes()
    action()
    Widgets.nextFrame()
    rows[#rows + 1] = { name, refreshes() - before }
  end
  local function size(width)
    p.host:SetSize(width, HEIGHT)
    Widgets.fire(p.host, "OnSizeChanged", width, HEIGHT)
  end
  local function wheel(delta)
    Widgets.fire(p.view.frame, "OnMouseWheel", delta)
  end
  measure("wheel up at the top", function()
    wheel(1)
  end)
  measure("wheel down", function()
    wheel(-1)
  end)
  for _ = 1, 60 do
    wheel(-1)
  end
  measure("wheel down at the end", function()
    wheel(-1)
  end)
  measure("row click", function()
    Widgets.click(p.view.list.rows[1], "LeftButton")
    Meter.settle(p.ns)
  end)
  measure("wheel on the details", function()
    wheel(-1)
  end)
  measure("back", function()
    p.ns.LeadsView.Back(p.view)
    Meter.settle(p.ns)
  end)
  measure("lead change", function()
    p.ns.BridgePanel.Refresh()
  end)
  measure("ten size events", function()
    for width = 361, 370 do
      size(width)
    end
  end)
  measure("narrow to wide", function()
    size(600)
  end)
  measure("wide to narrow", function()
    size(360)
  end)
  p.wm.hidePanel("CraftAlert")
  measure("size event while hidden", function()
    size(380)
  end)
  return rows
end

return Meter
