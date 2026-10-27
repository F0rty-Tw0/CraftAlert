-- Task 2.4: the Task 1.19 flow on Classic. The whole addon loaded from the TOC on TBC (TradeSkill
-- and Enchanting's Craft window) and MoP (TradeSkill only), started only through ADDON_LOADED
-- and PLAYER_LOGIN; Bootstrap installs the Classic readers and the learn message in place of the
-- Retail ones.
local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Toc = require("tests.helpers.toc")
local ProfessionsClassic = require("tests.helpers.professions_classic")
local ClassicRowsStub = require("tests.helpers.classic_rows_stub")
local RecipeListStub = require("tests.helpers.recipe_list_stub")

local OWN_KEY = "Crafter-OwnRealm"
local CUSTOMER = "Customer-OtherRealm"
local START_TIME = 100000
-- ERR_LEARN_RECIPE_S as the TBC Anniversary client spells it (Phase 0).
local LEARN_FORMAT = "You have learned how to create a new item: %s."
local BELT_LINK = "|cff1eff00|Hitem:190001::::::::60:::::|h[Sim Plate Belt]|h|r"
local SKILL_LINES = { { name = "Professions", header = true }, { name = "Blacksmithing" }, { name = "Enchanting" } }
local SLOTS = { { name = "Blacksmithing", skillLine = 164 }, { name = "Enchanting", skillLine = 333 } }
local ITEMS = {
  [190001] = { "INVTYPE_WAIST", 4, 4 },
  [190004] = { "INVTYPE_HEAD", 4, 4 },
  [190006] = { "INVTYPE_WRIST", 4, 4 },
}
-- Both flavors: the TradeSkill window and the learn message. The Retail reader and learn event
-- are never installed.
local CLASSIC_EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_CLOSE", "CHAT_MSG_SYSTEM", "SKILL_LINES_CHANGED" }
local RETAIL_EVENTS = { "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }
local CRAFT_EVENTS = { "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE" }

local function isRegistered(event)
  for _, frame in ipairs(Wow.frames) do
    if frame.events[event] then
      return true
    end
  end
  return false
end

-- The Blacksmithing list: the belt and the bracers; the helm is learned during the session.
local function blacksmithing()
  return {
    line = "Blacksmithing",
    rows = {
      { name = "Plate", kind = "header" },
      { name = "Sim Plate Belt", item = 190001 },
      { name = "Sim Plate Bracers", item = 190006 },
    },
  }
end

local function enchanting()
  return {
    line = "Enchanting",
    rows = {
      { name = "Bracer", kind = "header" },
      { name = "Enchant Bracer - Sim Health", link = "|cffffd000|Henchant:90002|h[Enchant Bracer - Sim Health]|h|r" },
    },
  }
end

-- The client before the addon loads: Crafter-OwnRealm resting in a city with Blacksmithing and
-- Enchanting, a fresh install. → session, the profession stub state.
local function startClient(flavor)
  Wow.reset()
  Wow.flavor(flavor)
  Wow.clock.time = START_TIME
  local session = { sent = {}, toasts = 0 }
  local function record(api)
    return function(...)
      session.sent[#session.sent + 1] = { api, ... }
    end
  end
  Wow.stub("C_ChatInfo", { SendAddonMessage = record("addon"), SendChatMessage = record("chat") })
  Wow.stub("ChatFrameUtil", { SendTellWithMessage = record("prefill"), SendTell = record("empty") })
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
  Wow.stub("CraftAlertDB", nil)
  Wow.stub("ERR_LEARN_RECIPE_S", LEARN_FORMAT)
  local state = ProfessionsClassic.install({
    skillLines = SKILL_LINES,
    slots = flavor == "mop" and SLOTS or nil,
    tradeSkill = blacksmithing(),
    craft = flavor == "tbc" and enchanting() or nil,
    items = ITEMS,
    autoCache = true,
  })
  return session, state
end

-- Every TOC file into one ns, then the two events the client fires. `prepare(ns)` runs between
-- loading and the events: the Retail reader's handlers become spies, so a Retail install would
-- register them on the shared TRADE_SKILL_SHOW/CLOSE events.
local function login(session, prepare)
  local ns = {}
  for _, path in ipairs(Toc.luaFiles()) do
    assert(loadfile(path))("CraftAlert", ns)
  end
  session.retailCalls = 0
  local function spy()
    session.retailCalls = session.retailCalls + 1
  end
  ns.ModernReader.OnShow, ns.ModernReader.OnClose, ns.ModernReader.OnListUpdate = spy, spy, spy
  if prepare then
    prepare(ns)
  end
  local show = ns.AlertToast.Show
  ns.AlertToast.Show = function(lead)
    session.toasts = session.toasts + 1
    show(lead)
  end
  Wow.fireEvent("ADDON_LOADED", "CraftAlert")
  Wow.fireEvent("PLAYER_LOGIN")
  return ns
end

-- Runs the timers of this frame (delay 0: the Slicer ticks and the coalesced index rebuild).
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

-- A window event, then its read and the rebuild it requests.
local function openWindow(event)
  Wow.fireEvent(event)
  runFrame()
end

-- Fresh install → window open → request → toast, lead, left-click greets; WTS → nothing; a
-- learn matches by name at once, and the next window open stores it with its profession.
local function testFlow(flavor)
  local session, state = startClient(flavor)
  local ns = login(session)
  local db = rawget(_G, "CraftAlertDB")
  Assert.truthy(db, flavor .. ": ADDON_LOADED created the account DB")
  Assert.same(ns.ProfessionList.Order(), { "blacksmithing", "enchanting" }, flavor)
  for _, event in ipairs(CLASSIC_EVENTS) do
    Assert.truthy(isRegistered(event), flavor .. ": " .. event .. " registered")
  end
  for _, event in ipairs(RETAIL_EVENTS) do
    Assert.falsy(isRegistered(event), flavor .. ": " .. event .. " not registered")
  end
  for _, event in ipairs(CRAFT_EVENTS) do
    Assert.equal(isRegistered(event), flavor == "tbc", flavor .. ": " .. event)
  end
  Assert.equal(ns.ScanGate.IsActive(), false, flavor .. ": paused, nothing read yet")

  -- Opening Blacksmithing reads it (the Slicer job and the rebuild run on frame timers); the
  -- Retail reader's handlers never run.
  openWindow("TRADE_SKILL_SHOW")
  local recipes = db.characters[OWN_KEY].recipes
  Assert.same(recipes["sim plate belt"], { item = 190001, name = "Sim Plate Belt", prof = "blacksmithing" }, flavor)
  Assert.equal(db.characters[OWN_KEY].professions.blacksmithing.read, true, flavor)
  Assert.equal(ns.ScanGate.IsActive(), true, flavor .. ": the scan is active")
  Wow.fireEvent("TRADE_SKILL_CLOSE")
  Assert.equal(session.retailCalls, 0, flavor .. ": no Retail reader handler ran")

  -- A request for the belt: one toast, one lead, then left-click sends the disclosure and the
  -- whisper.
  trade("LF " .. BELT_LINK .. " crafter", CUSTOMER)
  local lead = ns.Leads.Latest()
  Assert.truthy(lead, flavor .. ": the request made a lead")
  Assert.same({ lead.customer, lead.crafter, session.toasts }, { CUSTOMER, OWN_KEY, 1 }, flavor)
  local toast = rawget(_G, "CraftAlertToast")
  Wow.clock.gettime = Wow.clock.gettime + 1
  toast:GetScript("OnClick")(toast, "LeftButton")
  Assert.equal(#session.sent, 2, flavor)
  Assert.same({ session.sent[1][1], session.sent[1][5] }, { "addon", CUSTOMER }, flavor)
  Assert.same({ session.sent[2][1], session.sent[2][2], session.sent[2][3], session.sent[2][5] }, {
    "chat",
    "Hi! I can craft |cffffffff|Hitem:190001|h[Item 190001]|h|r.",
    "WHISPER",
    CUSTOMER,
  }, flavor)

  -- Selling is not asking.
  trade("WTS plate belt, cheap", "Seller-OtherRealm")
  Assert.same({ #ns.Leads.List(), session.toasts, #session.sent }, { 1, 1, 2 }, flavor .. ": WTS makes nothing")

  -- A learn: matched by name at once, crafted by the player, `recipes` unchanged.
  Wow.fireEvent("CHAT_MSG_SYSTEM", string.format(LEARN_FORMAT, "Sim Plate Helm"))
  runFrame()
  Assert.equal(recipes["sim plate helm"], nil, flavor .. ": a learn never writes recipes")
  trade("LF sim plate helm", "Buyer-OtherRealm")
  local learned = ns.Leads.Latest()
  Assert.same({ learned.customer, learned.crafter, learned.recipeName }, { "Buyer-OtherRealm", OWN_KEY, "Sim Plate Helm" }, flavor)

  -- The next window open stores it with its profession and item.
  table.insert(state.tradeSkill.rows, { name = "Sim Plate Helm", item = 190004 })
  openWindow("TRADE_SKILL_SHOW")
  Assert.same(recipes["sim plate helm"], { item = 190004, name = "Sim Plate Helm", prof = "blacksmithing" }, flavor)

  -- TBC: Enchanting's Craft window is read too.
  if flavor == "tbc" then
    openWindow("CRAFT_SHOW")
    Assert.same(recipes["enchant bracer - sim health"], { name = "Enchant Bracer - Sim Health", prof = "enchanting" })
    Assert.equal(db.characters[OWN_KEY].professions.enchanting.read, true)
  end
end

-- CHAT_MSG_SYSTEM is registered only where the flavor's learnSignal is the system message.
local function testLearnSignalGate()
  local session = startClient("tbc")
  login(session, function(ns)
    ns.Constants.flavors.tbc.learnSignal = 3
  end)
  Assert.falsy(isRegistered("CHAT_MSG_SYSTEM"), "learnSignal 3: no system-message listener")
  Assert.truthy(isRegistered("TRADE_SKILL_SHOW"), "the readers still install")
end

-- The player folds the Professions header (TBC skill lines): SKILL_LINES_CHANGED then lists
-- neither profession, yet both stay stored with their recipes, the order holds and nothing
-- rebuilds; unfolding changes nothing either.
local function testFoldedHeader()
  local session, state = startClient("tbc")
  local ns = login(session)
  openWindow("TRADE_SKILL_SHOW")
  local character = rawget(_G, "CraftAlertDB").characters[OWN_KEY]
  local recipes = character.recipes
  Assert.truthy(recipes["sim plate belt"], "the window read stored the belt")

  state.skillLines = {
    { name = "Professions", header = true, collapsed = true },
    { name = "Languages", header = true },
    { name = "Common" },
  }
  Wow.fireEvent("SKILL_LINES_CHANGED")
  Assert.truthy(character.professions.blacksmithing, "folded: Blacksmithing stays stored")
  Assert.truthy(character.professions.enchanting, "folded: Enchanting stays stored")
  Assert.equal(character.professions.blacksmithing.read, true, "folded: its read flag is kept")
  Assert.truthy(recipes["sim plate belt"], "folded: its recipes stay")
  Assert.same(ns.ProfessionList.Order(), { "blacksmithing", "enchanting" })
  Assert.equal(Wow.pendingTimers(0), 0, "folded: same order, no rebuild")
  Assert.truthy(ns.Index.Current().size > 0, "folded: the index still listens")

  state.skillLines = SKILL_LINES
  Wow.fireEvent("SKILL_LINES_CHANGED")
  Assert.same(ns.ProfessionList.Order(), { "blacksmithing", "enchanting" })
  Assert.equal(Wow.pendingTimers(0), 0, "unfolded: no rebuild")
  Assert.truthy(recipes["sim plate belt"], "unfolded: the recipes stay")
end

-- Recipe markers on Classic: nothing is hooked before the window's addon loads; then a stored
-- row gets its switch on Blizzard's update, a rebuild and entering an instance repaint it. The
-- Craft window gets them on TBC only.
local function testRecipeMarkers(flavor)
  local session = startClient(flavor)
  local stub = ClassicRowsStub.install({ craft = flavor == "tbc", loaded = false })
  local ns = login(session)
  local db = rawget(_G, "CraftAlertDB")
  stub.tradeSkill:define()
  local blizzardUpdate = rawget(_G, "TradeSkillFrame_Update")
  Wow.fireEvent("ADDON_LOADED", "Blizzard_TradeSkillUI")
  Assert.truthy(rawget(_G, "TradeSkillFrame_Update") ~= blizzardUpdate, flavor .. ": TradeSkillFrame_Update hooked")
  openWindow("TRADE_SKILL_SHOW")
  stub.tradeSkill:update(0)
  local switch = assert(RecipeListStub.switchOf(stub.tradeSkill.rows[2]), flavor .. ": the belt's row got its switch")
  Assert.same({ switch:IsShown(), switch.icon.atlas }, { true, RecipeListStub.SPEAKER }, flavor)

  db.characters[OWN_KEY].recipes["sim plate belt"].muted = true
  ns.Index.Rebuild()
  Assert.equal(switch.icon.atlas, RecipeListStub.MUTED, flavor .. ": an index rebuild repaints the rows")
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  ns.ScanGate.Evaluate()
  Assert.equal(switch:IsShown(), false, flavor .. ": entering an instance hides the switch")
  Wow.stub("IsInInstance", nil)
  ns.ScanGate.Evaluate()
  Assert.equal(switch:IsShown(), true, flavor .. ": back after leaving")

  if flavor == "tbc" then
    stub.craft:define()
    Wow.fireEvent("ADDON_LOADED", "Blizzard_CraftUI")
    openWindow("CRAFT_SHOW")
    stub.craft:update(0)
    Assert.truthy(RecipeListStub.switchOf(stub.craft.rows[2]), "the enchant's Craft row got its switch")
  end
end

return function()
  testRecipeMarkers("tbc")
  testRecipeMarkers("mop")
  testFlow("tbc")
  testFlow("mop")
  testLearnSignalGate()
  testFoldedHeader()
  Wow.reset()
end
