-- Task 3.2: the whole addon loaded from the TOC and started through ADDON_LOADED and PLAYER_LOGIN,
-- as test_bootstrap_retail.lua does, once with a fake WhisperMessenger API present at login and
-- once without: Bootstrap activates the bridge, swaps the "new" subscriber and wires OnGate.
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")
local ProfessionsRetail = require("tests.helpers.professions_retail")
local FakeWm = require("tests.helpers.fake_wm_api")

local BS = 164
local START_TIME = 100000
local BELT_LINK = "|cff0070dd|Hitem:190001::::::::70:::::|h[Sim Plate Belt]|h|r"
local SLOTS = { { name = "Blacksmithing", skillLine = BS } }
local RECIPES = { { id = 9001, name = "Sim Plate Belt", item = 190001, learned = true } }
local ITEMS = { [190001] = { "INVTYPE_WAIST", 4, 4 } }
local BIND = { [190001] = 2 }

-- The client before the addon loads: Crafter-OwnRealm resting in a city with Blacksmithing.
local function startClient()
  Wow.reset()
  Wow.flavor("retail")
  Wow.clock.time = START_TIME
  Wow.stub("C_ChatInfo", { SendAddonMessage = function() end, SendChatMessage = function() end })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = function() end, SendTell = function() end })
  Wow.stub("SlashCmdList", {})
  Wow.stub("UISpecialFrames", {})
  Wow.stub("IsResting", function()
    return true
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  Wow.stub("UnitName", function()
    return "Crafter"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "OwnRealm"
  end)
  Wow.stub("C_AutoComplete", {
    GetAutoCompleteRealms = function()
      return { "OwnRealm", "Other Realm" }
    end,
  })
  Wow.stub("Settings", {
    RegisterCanvasLayoutCategory = function() end,
    RegisterAddOnCategory = function() end,
  })
  Wow.stub("CraftAlertDB", nil)
  ProfessionsRetail.install({ slots = SLOTS, base = BS, recipes = RECIPES, items = ITEMS, bind = BIND, autoCache = true })
  rawset(_G["C_TradeSkillUI"], "GetCraftingOperationInfo", function() end)
  Wow.stub("Enum", { TradeskillSlotDataType = { ModifiedReagent = 1 }, CraftingReagentType = { Finishing = 3 } })
  Wow.stub("C_CurrencyInfo", { GetCurrencyInfo = function() end })
end

local function recordErrors()
  local errors = {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      errors[#errors + 1] = err
    end
  end)
  return errors
end

-- Every TOC file into one ns, then the two events the client fires.
local function login()
  local ns = {}
  for _, path in ipairs(Toc.luaFiles()) do
    assert(loadfile(path))("CraftAlert", ns)
  end
  Wow.fireEvent("ADDON_LOADED", "CraftAlert")
  Wow.fireEvent("PLAYER_LOGIN")
  return ns
end

-- Runs the timers of this frame (delay 0: the coalesced index rebuild) and nothing later.
local function runFrame()
  local found = true
  while found do
    found = false
    for i, timer in ipairs(Wow.timers) do
      if timer.delay == 0 then
        table.remove(Wow.timers, i)
        timer.fn()
        found = true
        break
      end
    end
  end
end

local function trade(text, sender)
  Wow.fireEvent("CHAT_MSG_CHANNEL", text, sender, "", "2. Trade - City", sender, "", 2, 2, "Trade - City", 0, 1, nil)
end

local function enterInstance()
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  Wow.fireEvent("PLAYER_ENTERING_WORLD")
end

-- → ns, the error list, the fake (nil without the API). Opening the profession reads the recipe
-- and starts the scan.
local function boot(withApi)
  startClient()
  local wm
  if withApi then
    wm = select(2, FakeWm.install())
  end
  local errors = recordErrors()
  local ns = login()
  Wow.fireEvent("TRADE_SKILL_SHOW")
  runFrame()
  Assert.equal(ns.ScanGate.IsActive(), true, "the scan listens")
  return ns, errors, wm
end

local function testBridged()
  local ns, errors, wm = boot(true)
  local launcher = rawget(_G, "CraftAlertLauncher")
  Assert.equal(launcher == nil or not launcher:IsShown(), true, "launcher hidden")
  Assert.equal(#wm.callsTo("RegisterPanel"), 1, "the panel registered at login")
  trade("LF " .. BELT_LINK .. " crafter", "Buyer-OtherRealm")
  Assert.equal(#ns.Leads.List(), 1)
  Assert.equal(#wm.callsTo("ShowPreview"), 1, "Bootstrap wired ShowLead to new leads")
  Assert.equal(rawget(_G, "CraftAlertToast"), nil, "no own toast")
  Assert.equal(wm.badgeRefreshes >= 1, true, "the change handler is wired")
  Assert.equal(wm.info.CraftAlert["Buyer-OtherRealm"] ~= nil, true, "the info strip is wired")
  rawget(_G, "SlashCmdList").CRAFTALERT("") -- /ca -> the router
  Assert.equal(#wm.callsTo("TogglePanel"), 1)
  Assert.equal(rawget(_G, "CraftAlertLeadsWindow"), nil, "no own window")
  enterInstance()
  Assert.equal(wm.preview.CraftAlert, nil, "Bootstrap wired WhisperBridge.OnGate")
  Wow.stub("IsInInstance", nil)
  Assert.same(errors, {})
end

-- /reload: the leads come back from the saved data without a "change", so the customers' info
-- lines are sent by the login itself, after Restore.
local function testReloadSendsInfoLines()
  local ns = boot(true)
  trade("LF " .. BELT_LINK .. " crafter", "Buyer-OtherRealm")
  Assert.equal(#ns.Leads.List(), 1)
  Wow.fireEvent("PLAYER_LOGOUT")
  local saved = rawget(_G, "CraftAlertDB")
  startClient()
  Wow.clock.time = START_TIME + 30
  local wm2 = select(2, FakeWm.install())
  Wow.stub("CraftAlertDB", saved)
  local ns2 = login()
  Assert.equal(#ns2.Leads.List(), 1, "the lead was restored")
  local line = wm2.info.CraftAlert["Buyer-OtherRealm"]
  Assert.truthy(line and line:find("Craft Alert:", 1, true) and line:find("Blacksmithing", 1, true), "info line sent at login")
end

local function testStandalone()
  local ns, errors = boot(false)
  Assert.equal(rawget(_G, "WhisperMessengerAPI"), nil)
  Assert.equal(rawget(_G, "CraftAlertLauncher"):IsShown(), true, "launcher shown")
  trade("LF " .. BELT_LINK .. " crafter", "Buyer-OtherRealm")
  Assert.equal(#ns.Leads.List(), 1)
  Assert.truthy(rawget(_G, "CraftAlertToast"), "own toast")
  Assert.equal(rawget(_G, "CraftAlertToast"):IsShown(), true)
  enterInstance()
  Assert.equal(rawget(_G, "CraftAlertToast"):IsShown(), false, "the toast's gate ran")
  Wow.stub("IsInInstance", nil)
  Assert.same(errors, {}, "OnGate standalone raised nothing")
end

return function()
  testBridged()
  testReloadSendsInfoLines()
  testStandalone()
  Wow.reset()
end
