local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

-- "Clear all" on the ledger line (UI/ClearAllLink.lua), in the leads window: at the line's right in
-- the "Settings" link's gold, white on hover with its tooltip; a click dismisses every lead; grey
-- and disabled with no lead; it hides with the list in Settings.

local function load(customers)
  local ns = UiFixture.load({
    db = function(accountDb)
      for id, customer in ipairs(customers) do
        accountDb.leads[id] = UiFixture.lead(id, customer)
      end
    end,
  })
  ns.Leads.On("change", ns.LeadsWindow.Refresh)
  ns.LeadsWindow.Toggle()
  local frame = rawget(_G, "CraftAlertLeadsWindow")
  return ns, frame, frame.view
end

-- 9 characters * 6 px wide, the ledger line's height, in the band over the list at its right; the
-- counts start right of the list. A list too narrow for it (54 + 2 * 8) hides it.
local function testLayout()
  local ns, _, view = load({ "Ann-Draenor" })
  local link, strip = view.clearAll, view.strip
  Assert.equal(link.parent, strip)
  Assert.equal(link.label:GetText(), "Clear all")
  Assert.same(link.label.textColor, ns.Theme.COLORS.gold)
  Assert.same({ link:GetWidth(), link:GetHeight() }, { 54, 20 })
  Assert.same(link.points, { { "BOTTOMRIGHT", view.listPane, "TOPRIGHT", -8, 0 } })
  Assert.same(strip.text.points[1], { "BOTTOMLEFT", view.listPane, "TOPRIGHT", 8, 0 })
  Assert.equal(link:IsShown(), true)
  view.getListWidth = function()
    return 69
  end
  ns.LeadsView.Layout(view)
  Assert.equal(link:IsShown(), false, "69 < 70")
  view.getListWidth = function()
    return 70
  end
  ns.LeadsView.Layout(view)
  Assert.equal(link:IsShown(), true, "70 fits")
end

local function testHover()
  local ns, _, view = load({ "Ann-Draenor" })
  local link = view.clearAll
  Widgets.fire(link, "OnEnter")
  local tip = ns.Tooltip.Get()
  Assert.same(link.label.textColor, ns.Theme.COLORS.white)
  Assert.equal(tip.owner, link)
  Assert.same(tip.lines, { "Clear all leads", "Dismisses every lead in the list." })
  Widgets.fire(link, "OnLeave")
  Assert.same(link.label.textColor, ns.Theme.COLORS.gold)
  Assert.equal(tip:IsShown(), false)
end

-- A click dismisses every lead; the window empties and the link turns grey and disabled, so a
-- second click does nothing. A new lead enables it again.
local function testClickAndDisabled()
  local ns, frame, view = load({ "Ann-Draenor", "Bob-Draenor", "Cid-Draenor" })
  local link = view.clearAll
  local lead = ns.Leads.Latest()
  Assert.equal(link:IsEnabled(), true)
  Widgets.click(link)
  Assert.same({ ns.Leads.HasActive(), lead.dismissed, frame.status:GetText() }, { false, true, "" })
  Assert.equal(link:IsEnabled(), false)
  Assert.same(link.label.textColor, ns.Theme.COLORS.grey)
  Widgets.click(link)
  Assert.equal(ns.Leads.HasActive(), false)
end

-- The click happens under the mouse, so the tooltip is up; the link disables itself and a
-- disabled Button gets no OnLeave, so disabling hides the tooltip.
local function testClickHidesTooltip()
  local ns, _, view = load({ "Ann-Draenor" })
  local link = view.clearAll
  Widgets.fire(link, "OnEnter")
  Widgets.click(link)
  Assert.equal(ns.Tooltip.Get():IsShown(), false)
end

-- Settings hides the view, the ledger line and the link with it.
local function testHiddenInSettings()
  local _, frame, view = load({ "Ann-Draenor" })
  Assert.equal(view.clearAll:IsVisible(), true)
  Widgets.click(frame.gear)
  Assert.equal(view.clearAll:IsVisible(), false)
  Widgets.click(frame.gear)
  Assert.equal(view.clearAll:IsVisible(), true)
end

return function()
  testLayout()
  testHover()
  testClickAndDisabled()
  testClickHidesTooltip()
  testHiddenInSettings()
  Wow.reset()
end
