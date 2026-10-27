local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")
local ProfessionsRetail = require("tests.helpers.professions_retail")

-- Spec §10.2: the one-time CraftScan offer at login.
local FRAME = "CraftAlertCraftScanPrompt"
local OFFER = "CraftScan data found. Import characters, recipes, and greetings?"
local ADVICE = "Craft Alert has your CraftScan data now; you can disable CraftScan."

-- opts.flavor; opts.craftScan = false leaves CraftScan_DB unset.
local function load(opts)
  opts = opts or {}
  local ns, db, refreshes = SettingsFixture.load({ flavor = opts.flavor })
  ProfessionsRetail.install({ recipes = { { id = 9004, name = "Sim Plate Helm", item = 190004 } } })
  if opts.craftScan ~= false then
    Wow.stub("CraftScan_DB", dofile("tests/fixtures/craftscan_db.lua"))
  end
  SettingsFixture.take(refreshes)
  return ns, db, refreshes
end

local function chatSince(from)
  local lines = {}
  for i = from + 1, #Wow.chat do
    lines[#lines + 1] = (string.gsub(Wow.chat[i], "^|cffffd100Craft Alert:|r ", ""))
  end
  return lines
end

local function frame()
  return rawget(_G, FRAME)
end

-- Asked once: the chat line and the window; Import answers it and runs the sliced import.
local function testAccept()
  local ns, db, refreshes = load()
  local before = #Wow.chat
  ns.CraftScanPrompt.MaybeShow(db)
  Assert.same(chatSince(before), { OFFER })
  Assert.equal(frame():IsShown(), true)
  Assert.equal(frame():GetTitleText():GetText(), "Craft Alert — CraftScan")
  Assert.equal(rawget(_G, "UISpecialFrames")[1], nil, "Escape does not close it (no UISpecialFrames entry)")
  Widgets.click(frame().accept)
  Assert.equal(db.settings.craftScanPrompted, true)
  Assert.equal(frame():IsShown(), false)
  Assert.equal(db.settings.craftScanImported, nil, "set when the job ends")
  ns.Slicer.Drain()
  Assert.equal(db.settings.craftScanImported, 1000)
  Assert.same(SettingsFixture.take(refreshes), { "rebuild:craftscan" })
  Assert.truthy(db.characters["Scanalt-OwnRealm"].recipes[9004])
  local result = "CraftScan import: 3 characters, 1 recipe (0 muted) and 2 greetings (9 skipped)."
  Assert.same(chatSince(before), { OFFER, result, ADVICE })
  -- Answered: never again.
  ns.CraftScanPrompt.MaybeShow(db)
  Assert.same(chatSince(before), { OFFER, result, ADVICE })
end

-- Decline answers without importing; the close button leaves the question for the next login.
local function testDeclineAndClose()
  local ns, db = load()
  ns.CraftScanPrompt.MaybeShow(db)
  local window = frame()
  Widgets.click(window.CloseButton)
  Assert.equal(db.settings.craftScanPrompted, nil)
  ns.CraftScanPrompt.MaybeShow(db)
  Assert.equal(frame(), window, "made once")
  Assert.equal(window:IsShown(), true)
  Widgets.click(window.decline)
  Assert.equal(db.settings.craftScanPrompted, true)
  Assert.equal(window:IsShown(), false)
  Assert.equal(ns.Slicer.IsRunning("craftscan"), false)
  Assert.equal(db.characters["Scanalt-OwnRealm"], nil)
end

-- Nothing without CraftScan's data, after an import, off Retail, or in an instance (still open).
local function testSilent()
  local cases = {
    { craftScan = false },
    { flavor = "forever" },
    { imported = true },
    { instance = true },
  }
  for _, case in ipairs(cases) do
    local ns, db = load(case)
    db.settings.craftScanImported = case.imported and 5 or nil
    if case.instance then
      Wow.stub("IsInInstance", function()
        return true, "party"
      end)
    end
    local before = #Wow.chat
    ns.CraftScanPrompt.MaybeShow(db)
    Assert.same(chatSince(before), {})
    Assert.equal(frame(), nil, "no window")
    Assert.equal(db.settings.craftScanPrompted, nil)
  end
end

return function()
  testAccept()
  testDeclineAndClose()
  testSilent()
  Wow.reset()
end
