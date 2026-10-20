local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local function launcher()
  return rawget(_G, "CraftAlertLauncher")
end

-- Scan state as the launcher reads it: ScanGate.IsActive() and the State() its tooltip prints.
local function setScan(ns, active)
  ns.ScanGate.IsActive = function()
    return active
  end
  ns.ScanGate.State = function()
    if active then
      return { active = true, channels = { "Trade" }, recipeCount = 4, crafterCount = 2 }
    end
    return { active = false, reason = "notResting", channels = { "Trade" }, recipeCount = 4, crafterCount = 2 }
  end
end

local function testLitDimAndTooltip()
  local ns = UiFixture.load({ leads = 2 })
  setScan(ns, false)
  -- Loading creates nothing; Create makes the one login frame, and only once.
  Assert.equal(launcher(), nil)
  ns.Launcher.Refresh()
  Assert.equal(launcher(), nil, "Refresh before Create creates nothing")
  local frame = ns.Launcher.Create()
  Assert.equal(frame, launcher())
  Assert.equal(ns.Launcher.Create(), frame)
  Assert.equal(frame.movable, true)
  -- §7.6: dim while the scan is paused, lit while it listens.
  Assert.equal(frame.icon.desaturated, true)
  Assert.truthy(frame:GetAlpha() < 1)
  setScan(ns, true)
  ns.Launcher.Refresh("ignored", "arguments")
  Assert.equal(frame.icon.desaturated, false)
  Assert.equal(frame:GetAlpha(), 1)
  -- The badge counts the leads.
  Assert.equal(frame.badge:IsShown(), true)
  Assert.equal(frame.badgeText:GetText(), "2")

  -- The tooltip is the status line, on GameTooltip, and goes away on leave.
  local tooltip = rawget(_G, "GameTooltip")
  frame.scripts.OnEnter(frame)
  Assert.equal(tooltip.owner, frame)
  Assert.equal(tooltip.shown, true)
  Assert.truthy(string.find(table.concat(tooltip.lines, " / "), "Listening in Trade — 4 recipes, 2 crafters", 1, true))
  frame.scripts.OnLeave(frame)
  Assert.equal(tooltip.shown, false)
  setScan(ns, false)
  frame.scripts.OnEnter(frame)
  Assert.truthy(string.find(table.concat(tooltip.lines, " / "), "Paused — not in a city or inn", 1, true))

  -- A click toggles the leads window.
  Widgets.click(frame, "LeftButton")
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), true)
  Widgets.click(frame, "LeftButton")
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"):IsShown(), false)
end

local function testLeadExpiryWhilePaused()
  -- A lead expiring while the scan is paused refreshes the badge and leaves the icon dim.
  local ns = UiFixture.load({ leads = 1 })
  setScan(ns, false)
  local frame = ns.Launcher.Create()
  ns.Leads.On("change", ns.Launcher.Refresh)
  Assert.equal(frame.badgeText:GetText(), "1")
  Wow.clock.time = UiFixture.T0 + 601
  for _, timer in ipairs(Wow.timers) do
    timer.fn()
  end
  Assert.equal(ns.Leads.HasActive(), false)
  Assert.equal(frame.badge:IsShown(), false)
  Assert.equal(frame.icon.desaturated, true)
  Assert.equal(frame:IsShown(), true)
end

local function testHideWhenNoLeads()
  local ns, db = UiFixture.load()
  db.settings.hideLauncherWhenNoLeads = true
  setScan(ns, true)
  local frame = ns.Launcher.Create()
  Assert.equal(frame:IsShown(), false, "hidden: no leads")
  db.settings.hideLauncherWhenNoLeads = false
  ns.Launcher.Refresh()
  Assert.equal(frame:IsShown(), true)

  -- The setting on and a lead listed: shown.
  ns, db = UiFixture.load({ leads = 1 })
  db.settings.hideLauncherWhenNoLeads = true
  setScan(ns, true)
  Assert.equal(ns.Launcher.Create():IsShown(), true, "shown: a lead is listed")
end

local function testSavedPosition()
  local ns, db = UiFixture.load()
  setScan(ns, true)
  local frame = ns.Launcher.Create()
  frame.scripts.OnDragStart(frame)
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOMRIGHT", rawget(_G, "UIParent"), "BOTTOMRIGHT", -20, 80)
  frame.scripts.OnDragStop(frame)
  Assert.same(db.ui.launcher, { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -20, y = 80 })
  local saved = db.ui.launcher
  ns = UiFixture.load({
    db = function(accountDb)
      accountDb.ui.launcher = saved
    end,
  })
  setScan(ns, true)
  local point, _, relativePoint, x, y = ns.Launcher.Create():GetPoint()
  Assert.same({ point, relativePoint, x, y }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -20, 80 })
end

return function()
  testLitDimAndTooltip()
  testLeadExpiryWhilePaused()
  testHideWhenNoLeads()
  testSavedPosition()
  Wow.reset()
end
