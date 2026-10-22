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

local ART_RING, ART_GLOW = "Soulbinds_Tree_Ring", "Soulbinds_Tree_Ring_Glow"

local function stubAtlases(present) -- present: set of atlas names, or nil for "none"
  Wow.stub("C_Texture", {
    GetAtlasInfo = function(name)
      return present and present[name] and { width = 1 } or nil
    end,
  })
end

local function testArt()
  local ns = UiFixture.load()
  setScan(ns, true)
  stubAtlases({ Soulbinds_Tree_Ring_Disabled = true, [ART_RING] = true, [ART_GLOW] = true, ["GarrLanding-CircleGlow"] = true })
  local frame = ns.Launcher.Create()
  Assert.same({ frame:GetWidth(), frame:GetHeight() }, { 53, 53 })
  Assert.equal(frame:GetNormalTexture().atlas, "Soulbinds_Tree_Ring_Disabled")
  Assert.equal(frame:GetPushedTexture().atlas, ART_RING)
  Assert.same({ frame:GetHighlightTexture().atlas, frame:GetHighlightTexture().blendMode }, { ART_RING, "ADD" })
  Assert.equal(frame.icon.masks[1].texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
  Assert.same({ frame.icon:GetWidth(), frame.icon:GetHeight() }, { 44, 44 })
  -- Hover glow follows the cursor.
  Assert.equal(frame.glow:IsShown(), false)
  frame.scripts.OnEnter(frame)
  Assert.equal(frame.glow:IsShown(), true)
  frame.scripts.OnLeave(frame)
  Assert.equal(frame.glow:IsShown(), false)

  -- No CraftScan atlas (Classic): file fallbacks, no pushed art, no glow, no pulse.
  ns = UiFixture.load()
  setScan(ns, true)
  stubAtlases(nil)
  frame = ns.Launcher.Create()
  Assert.equal(frame:GetNormalTexture().texture, "Interface\\Minimap\\MiniMap-TrackingBorder")
  Assert.same({ frame:GetHighlightTexture().texture, frame:GetHighlightTexture().blendMode }, { "Interface\\Buttons\\UI-Common-MouseHilight", "ADD" })
  Assert.equal(frame:GetPushedTexture(), nil, "no pushed texture: a press keeps the normal ring")
  Assert.same({ frame.glow, frame.pulse, frame.pulseOnce, frame.pulseLoop }, {})
  ns.Launcher.ShowLead(UiFixture.lead(1)) -- plays nothing, raises nothing
  frame.scripts.OnEnter(frame)
end

local function testIconAndPulse()
  local ns = UiFixture.load()
  setScan(ns, true)
  ns.Launcher.ShowLead(UiFixture.lead(1)) -- before Create: a no-op
  Assert.equal(ns.Launcher.Frame(), nil)
  local asked = {}
  Wow.stub("C_TradeSkillUI", {
    GetTradeSkillTexture = function(key)
      asked[#asked + 1] = key
      return key ~= 999 and ("tex" .. key) or nil
    end,
  })
  ns.ProfessionList.Order = function()
    return { 164, 171 }
  end
  local frame = ns.Launcher.Create()
  Assert.equal(frame.icon.texture, "tex164", "idle: the first profession")
  local lead = UiFixture.lead(1)
  lead.prof = 171
  ns.Launcher.ShowLead(lead)
  Assert.equal(frame.icon.texture, "tex171")
  Assert.same({ frame.pulseOnce:IsPlaying(), frame.pulseLoop:IsPlaying() }, { true, true })
  ns.Launcher.Refresh()
  Assert.equal(frame.icon.texture, "tex171", "Refresh keeps the lead icon while one is shown")
  ns.Launcher.ShowLead(nil)
  Assert.equal(frame.pulseLoop:IsPlaying(), false)
  Assert.equal(frame.icon.texture, "tex164")
  -- Bell: key not a number, API returns nil, API missing.
  lead.prof = "Blacksmithing"
  ns.Launcher.ShowLead(lead)
  Assert.equal(frame.icon.texture, "Interface\\Icons\\INV_Misc_Bell_01")
  lead.prof = 999
  ns.Launcher.ShowLead(lead)
  Assert.equal(frame.icon.texture, "Interface\\Icons\\INV_Misc_Bell_01")
  Wow.stub("C_TradeSkillUI", nil)
  lead.prof = 171
  ns.Launcher.ShowLead(lead)
  Assert.equal(frame.icon.texture, "Interface\\Icons\\INV_Misc_Bell_01")
end

local function testDragApi()
  local ns, db = UiFixture.load()
  setScan(ns, true)
  ns.Launcher.StartDrag() -- before Create: no-ops
  ns.Launcher.StopDrag()
  local order = {}
  ns.Launcher.OnMoved(function()
    order[#order + 1] = "first"
  end)
  ns.Launcher.OnMoved(function()
    order[#order + 1] = "second"
  end)
  local frame = ns.Launcher.Create()
  Assert.equal(ns.Launcher.Frame(), frame)
  frame.scripts.OnDragStart(frame)
  Assert.equal(frame.moving, true)
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOMRIGHT", rawget(_G, "UIParent"), "BOTTOMRIGHT", -20, 80)
  frame.scripts.OnDragStop(frame)
  Assert.equal(frame.moving, false)
  Assert.same(db.ui.launcher, { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -20, y = 80 })
  Assert.same(order, { "first", "second" }, "saved first, then each OnMoved in registration order")
end

return function()
  testLitDimAndTooltip()
  testLeadExpiryWhilePaused()
  testHideWhenNoLeads()
  testSavedPosition()
  testArt()
  testIconAndPulse()
  testDragApi()
  Wow.reset()
end
