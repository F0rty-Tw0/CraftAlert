local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local UiFixture = require("tests.helpers.ui_fixture")

local WINDOW_NAME = "CraftAlertLeadsWindow"

local function window()
  return rawget(_G, WINDOW_NAME)
end

-- The shown row frames of the window, top to bottom.
local function rows()
  local shown = {}
  for _, frame in ipairs(Wow.frames) do
    if frame.isLeadRow and frame:IsShown() then
      shown[#shown + 1] = frame
    end
  end
  table.sort(shown, function(a, b)
    return a.rowIndex < b.rowIndex
  end)
  return shown
end

local function rowText(row)
  return table.concat(Widgets.texts(row, Wow.frames), " / ")
end

-- The window's direct child button whose label is `label`.
local function buttonLabelled(parent, label)
  for _, frame in ipairs(Wow.frames) do
    if frame.parent == parent then
      for _, region in ipairs(frame.regions) do
        if region.text == label then
          return frame
        end
      end
    end
  end
  error("no button " .. label)
end

-- A fixture whose leads come from `customers` (oldest first), the window subscribed to
-- lead changes as Bootstrap will do it.
local function load(customers, edit)
  local ns, db, calls = UiFixture.load({
    db = function(accountDb)
      for id, customer in ipairs(customers) do
        accountDb.leads[id] = UiFixture.lead(id, customer)
      end
      if edit then
        edit(accountDb)
      end
    end,
  })
  ns.Leads.On("change", ns.LeadsWindow.Refresh)
  return ns, db, calls
end

local function testLazyAndEscape()
  local ns = load({ "Ann-Draenor" })
  -- §4.4 rule 5: nothing exists before the first open; a refresh before it creates nothing.
  ns.LeadsWindow.Refresh()
  Assert.equal(window(), nil)
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  ns.LeadsWindow.Toggle()
  Assert.truthy(window(), "window created on first open")
  Assert.equal(window():IsShown(), true)
  -- ESC closes it: our own frame name in UISpecialFrames, once, however often it opens.
  ns.LeadsWindow.Toggle()
  Assert.equal(window():IsShown(), false)
  ns.LeadsWindow.Toggle()
  Assert.same(rawget(_G, "UISpecialFrames"), { WINDOW_NAME })
  Assert.equal(window().movable, true)
  Assert.equal(window().resizable, true)
  Assert.equal(window().clamped, true)
  -- The close button hides it.
  Widgets.click(buttonLabelled(window(), "X"), "LeftButton")
  Assert.equal(window():IsShown(), false)
end

local function testRowFields()
  local ns, db = load({ "Ann-Draenor", "Bob-Draenor" }, function(accountDb)
    accountDb.leads[1].time = UiFixture.T0 - 125
    accountDb.leads[1].greeted = true
    accountDb.leads[1].replied = true
    accountDb.leads[2].time = UiFixture.T0 - 30
    accountDb.leads[2].kind, accountDb.leads[2].itemLink = "item", "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r"
    accountDb.leads[2].cannotOrder = true
  end)
  ns.LeadsWindow.Toggle()
  local shown = rows()
  Assert.equal(#shown, 2)
  -- §7.3: newest first, with age, customer, item/profession, crafter, greeted and replied.
  local first, second = rowText(shown[1]), rowText(shown[2])
  for _, part in ipairs({ "Bob-Draenor", "30s", "[Sim Plate Belt]", "Me-Realm", "can't order (realm)" }) do
    Assert.truthy(string.find(first, part, 1, true), part .. " missing from: " .. first)
  end
  for _, part in ipairs({ "Ann-Draenor", "2m", "Blacksmithing", "Me-Realm" }) do
    Assert.truthy(string.find(second, part, 1, true), part .. " missing from: " .. second)
  end
  Assert.equal(shown[1].greetedIcon:IsShown(), false)
  Assert.equal(shown[1].repliedTag:IsShown(), false)
  Assert.equal(shown[2].greetedIcon:IsShown(), true)
  Assert.equal(shown[2].repliedTag:IsShown(), true)
  -- Ages are refreshed on each refresh (window open or lead event), never by a ticker.
  Wow.clock.time = UiFixture.T0 + 60
  ns.LeadsWindow.Refresh()
  Assert.truthy(string.find(rowText(rows()[1]), "1m", 1, true), rowText(rows()[1]))
  Assert.equal(#db.leads, 2)

  -- No leads: an empty-state line, no rows.
  ns = load({})
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 0)
  Assert.truthy(string.find(table.concat(Widgets.texts(window(), Wow.frames), " / "), "No leads", 1, true))
end

local function testBlockAndClicks()
  -- The row "Block" button blocks the customer: every row of theirs goes, others stay.
  local ns, db, calls = load({ "Ann-Draenor", "Bob-Draenor", "Ann-Draenor" })
  ns.LeadsWindow.Toggle()
  Assert.equal(#rows(), 3)
  local blockButton = rows()[1].blockButton
  Widgets.click(blockButton, "LeftButton")
  Assert.equal(db.ignored["Ann-Draenor"], true)
  local left = rows()
  Assert.equal(#left, 1)
  Assert.truthy(string.find(rowText(left[1]), "Bob-Draenor", 1, true))
  Assert.equal(ns.Index.lastReason, "block", "the hot-path block set is rebuilt")

  -- Rows take the toast's clicks: left greets once the row has been up 0.5 s, right dismisses.
  Wow.clock.gettime = 51
  Widgets.click(left[1], "LeftButton")
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)
  Assert.equal(ns.Leads.Latest().greeted, true)
  Widgets.click(rows()[1], "RightButton")
  Assert.equal(ns.Leads.HasActive(), false)
  Assert.equal(#rows(), 0)
end

local function testVisibleLatestAndScroll()
  local customers = {}
  for i = 1, 12 do
    customers[i] = "Customer" .. i .. "-Draenor"
  end
  local ns = load(customers)
  ns.LeadsWindow.Toggle()
  -- The newest lead is in the top row, shown since the window opened (GetTime() 50).
  local lead, shownAt = ns.LeadsWindow.VisibleLatest()
  Assert.equal(lead, ns.Leads.Latest())
  Assert.equal(shownAt, 50)
  -- A refresh keeps that time; a lead new to the top row is shown from the refresh.
  Wow.clock.gettime = 55
  ns.LeadsWindow.Refresh()
  Assert.equal(select(2, ns.LeadsWindow.VisibleLatest()), 50)
  ns.Leads.Dismiss(ns.Leads.Latest().id)
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 55 })
  Assert.truthy(string.find(rowText(rows()[1]), "Customer11-Draenor", 1, true), rowText(rows()[1]))
  local visibleRows = #rows()
  Assert.truthy(visibleRows > 0 and visibleRows < 11, "only the rows that fit are shown")
  -- The mouse wheel scrolls; the latest lead is then off screen.
  window().scripts.OnMouseWheel(window(), -1)
  Assert.truthy(string.find(rowText(rows()[1]), "Customer10-Draenor", 1, true), rowText(rows()[1]))
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  for _ = 1, 20 do
    window().scripts.OnMouseWheel(window(), -1)
  end
  Assert.truthy(string.find(rowText(rows()[#rows()]), "Customer1-Draenor", 1, true), "stops at the oldest lead")
  -- Closing and reopening starts at the top again, shown from the new open time.
  ns.LeadsWindow.Toggle()
  Assert.equal(ns.LeadsWindow.VisibleLatest(), nil)
  Wow.clock.gettime = 70
  ns.LeadsWindow.Toggle()
  Assert.same({ ns.LeadsWindow.VisibleLatest() }, { ns.Leads.Latest(), 70 })
end

local function testSavedFrameAndOpacity()
  local ns, db = load({ "Ann-Draenor" })
  db.settings.opacity = 0.7
  ns.LeadsWindow.Toggle()
  local frame = window()
  Assert.equal(frame:GetAlpha(), 0.7)
  -- Dragging saves the position; the resize grip saves the size.
  frame.scripts.OnDragStart(frame)
  frame:ClearAllPoints()
  frame:SetPoint("LEFT", rawget(_G, "UIParent"), "LEFT", 30, 40)
  frame.scripts.OnDragStop(frame)
  local grip = frame.resizeGrip
  grip.scripts.OnMouseDown(grip, "LeftButton")
  Assert.equal(frame.sizing, "BOTTOMRIGHT")
  frame:SetSize(500, 400)
  grip.scripts.OnMouseUp(grip, "LeftButton")
  Assert.same(db.ui.window, { point = "LEFT", relativePoint = "LEFT", x = 30, y = 40, width = 500, height = 400 })

  -- The saved shapes are flat scalars, which the load-time Schema check keeps as they are.
  local Schema = Fresh.require("Persistence.Schema")
  local copy = { ui = { window = {}, toast = { point = "TOP", relativePoint = "TOP", x = 0, y = -160 } } }
  for key, value in pairs(db.ui.window) do
    copy.ui.window[key] = value
  end
  local repaired = Schema.Validate(copy)
  Assert.same(repaired.ui.window, db.ui.window)
  Assert.same(repaired.ui.toast, { point = "TOP", relativePoint = "TOP", x = 0, y = -160 })

  -- After a /reload it opens there, at that size.
  local saved = db.ui.window
  ns = load({ "Ann-Draenor" }, function(accountDb)
    accountDb.ui.window = saved
  end)
  ns.LeadsWindow.Toggle()
  local point, _, relativePoint, x, y = window():GetPoint()
  Assert.same({ point, relativePoint, x, y, window():GetWidth(), window():GetHeight() }, { "LEFT", "LEFT", 30, 40, 500, 400 })
end

return function()
  testLazyAndEscape()
  testRowFields()
  testBlockAndClicks()
  testVisibleLatestAndScroll()
  testSavedFrameAndOpacity()
  Wow.reset()
end
