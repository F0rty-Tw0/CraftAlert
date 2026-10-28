local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- Spec §7.6 "Away summary" and plan revision 5.3: the summary on the alert toast, with its own
-- clicks (left opens the leads window, right hides it, shift/ctrl nothing), its own tooltip and the
-- toast duration; no sound (each lead alerted when it came); a new lead replaces it.
local TOAST_SECONDS = 20 -- the default toast duration
local TEXT = "4 requests you could craft while you were away (1 expired)"

local function toastFrame()
  return rawget(_G, "CraftAlertToast")
end

local function window()
  return rawget(_G, "CraftAlertLeadsWindow")
end

local function shows(text)
  return string.find(table.concat(Widgets.texts(toastFrame(), Wow.frames), " / "), text, 1, true) ~= nil
end

-- Runs the timers pending now with a delay of `seconds` or less (the toast's), as if that much
-- time had passed; the lead expiry is left alone.
local function runTimersUpTo(seconds)
  local due, kept = {}, {}
  for _, timer in ipairs(Wow.timers) do
    table.insert(timer.delay <= seconds and due or kept, timer)
  end
  Wow.timers = kept
  for _, timer in ipairs(due) do
    timer.fn()
  end
end

local function testFaceAndTooltip()
  local ns, _, calls = UiFixture.load({ leads = 1 })
  ns.AlertToast.ShowSummary(4, 1)
  local frame = toastFrame()
  Assert.equal(frame:IsShown(), true)
  Assert.truthy(shows("Craft Alert") and shows(TEXT), "title and summary on the face")
  Assert.falsy(shows("Customer1-Draenor"), "no customer")
  Assert.same(calls, {}, "no sound or flash")
  Assert.equal(ns.AlertToast.VisibleLead(), nil, "no lead on the toast")
  local tip = ns.Tooltip.Get()
  frame.scripts.OnEnter(frame)
  local gold, green = { 1, 0.82, 0 }, { 0.1, 1, 0.1 }
  Assert.same(tip.lines, { "Craft Alert", "Left-click: open the leads", "Right-click: dismiss", "Drag: move" })
  Assert.same(tip.colors, { gold, green, green, green })
end

-- The toast font strings using this font object, in creation order (name, then headline, share
-- GameFontNormal).
local function part(font)
  local found = {}
  for _, region in ipairs(toastFrame().regions) do
    if region.font == font then
      found[#found + 1] = region
    end
  end

  return found
end

-- PADDING + name + gap + headline + PADDING: the empty message adds no line and no trailing gap.
local function testHeightWithoutMessage()
  local ns = UiFixture.load({ leads = 1 })
  ns.AlertToast.ShowSummary(4, 1)
  local name, headline = part("GameFontNormal")[1], part("GameFontNormal")[2]
  Assert.equal(toastFrame():GetHeight(), 8 + name:GetStringHeight() + 3 + headline:GetStringHeight() + 8)
end

-- Left opens the leads window (an open one stays open), right hides the toast and dismisses no
-- lead, shift- and ctrl-click do nothing.
local function testClicks()
  local ns = UiFixture.load({ leads = 1 })
  local keys = { shift = false, ctrl = false }
  Wow.stub("IsShiftKeyDown", function()
    return keys.shift
  end)
  Wow.stub("IsControlKeyDown", function()
    return keys.ctrl
  end)
  ns.AlertToast.ShowSummary(1, 0)
  keys.shift = true
  Widgets.click(toastFrame(), "LeftButton")
  keys.shift, keys.ctrl = false, true
  Widgets.click(toastFrame(), "LeftButton")
  keys.ctrl = false
  Assert.same({ toastFrame():IsShown(), window() }, { true, nil }, "modified clicks do nothing")
  Widgets.click(toastFrame(), "LeftButton")
  Assert.same({ toastFrame():IsShown(), window():IsShown() }, { false, true })
  ns.AlertToast.ShowSummary(1, 0)
  Widgets.click(toastFrame(), "LeftButton")
  Assert.equal(window():IsShown(), true, "open, never a toggle")
  ns.AlertToast.ShowSummary(1, 0)
  Widgets.click(toastFrame(), "RightButton")
  Assert.equal(toastFrame():IsShown(), false)
  Assert.equal(#ns.Leads.List(), 1, "no lead dismissed")
end

-- Hidden after the toast duration; a new lead replaces it (no "+1 more") and it replaces a lead's
-- toast; nothing in an instance, and entering one hides it.
local function testHideReplaceInstance()
  local ns = UiFixture.load({ leads = 1 })
  local lead = ns.Leads.Latest()
  ns.AlertToast.ShowSummary(2, 0)
  Wow.clock.gettime = 50 + TOAST_SECONDS
  runTimersUpTo(TOAST_SECONDS)
  Assert.equal(toastFrame():IsShown(), false, "hidden after the toast duration")
  ns.AlertToast.ShowSummary(2, 0)
  ns.AlertToast.Show(lead)
  Assert.truthy(shows("Customer1-Draenor") and not shows("while you were away"), "the lead replaced it")
  Assert.same({ ns.AlertToast.more, (ns.AlertToast.VisibleLead()) }, { 0, lead })
  ns.AlertToast.ShowSummary(2, 0)
  Assert.truthy(shows("while you were away") and not shows("Customer1-Draenor"), "it replaced the lead")
  Assert.equal(ns.AlertToast.VisibleLead(), nil)
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.AlertToast.OnGate()
  Assert.equal(toastFrame():IsShown(), false, "entering an instance hides it")
  ns.AlertToast.ShowSummary(2, 0)
  Assert.equal(toastFrame():IsShown(), false, "nothing in an instance")
  Wow.stub("IsInInstance", nil)
end

return function()
  testFaceAndTooltip()
  testHeightWithoutMessage()
  testClicks()
  testHideReplaceInstance()
  Wow.reset()
end
