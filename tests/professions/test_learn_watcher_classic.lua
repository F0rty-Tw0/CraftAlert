local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local ProfessionsClassic = require("tests.helpers.professions_classic")

-- Spec §5.3 and §13 "LearnWatcher" on Classic: CHAT_MSG_SYSTEM matched against ERR_LEARN_RECIPE_S
-- adds the learned name to the session-only pending list (a name match, crafted by the current
-- character), never to `recipes`.
local EVENT = "CHAT_MSG_SYSTEM"
-- ERR_LEARN_RECIPE_S as the TBC Anniversary client spells it (Phase 0, tools/captures/tbc_report.md).
local LEARN_FORMAT = "You have learned how to create a new item: %s."
local CHAR = "Me-Realm"
local FLAVORS = { "era", "tbc", "wrath", "cata", "mop" }

local function learnText(name)
  return string.format(LEARN_FORMAT, name)
end

local function isRegistered(event)
  for _, frame in ipairs(Wow.frames) do
    if frame.events[event] then
      return true
    end
  end
  return false
end

-- Logged in with the Classic readers, then the watcher installed with `signal` (default 1).
local function setup(flavor, state, signal)
  state = state or {}
  local ns, db = ProfessionsClassic.login(flavor, state)
  Wow.stub("ERR_LEARN_RECIPE_S", LEARN_FORMAT)
  ns.LearnWatcher = Fresh.require("Professions.LearnWatcher")
  ns.LearnWatcher.InstallClassic(signal == nil and 1 or signal)
  return ns, db
end

local function learn(ns, name)
  Wow.fireEvent(EVENT, learnText(name))
  ns.Slicer.Drain()
end

-- The own character's entry under the full-name record of `phrase`, or nil.
local function pendingEntry(ns, firstWord, phrase)
  for _, record in ipairs(ns.Index.Current().nameIndex[firstWord] or {}) do
    if record.phrase == phrase then
      return record.entries[1]
    end
  end
  return nil
end

-- A learn adds the client's name to the pending list on every Classic flavor: matched by name
-- at once, crafted by the current character, and `recipes` stays empty.
local function testLearnAddsPending(flavor)
  local ns, db = setup(flavor)
  Assert.truthy(isRegistered(EVENT), flavor)
  learn(ns, "Enchant Bracer - Minor Health")
  Assert.equal(ns.LearnWatcher.lastPending, "Enchant Bracer - Minor Health", flavor)
  Assert.equal(ns.Index.lastReason, "learn", flavor)
  local entry = pendingEntry(ns, "enchant", "enchant bracer minor health")
  Assert.same(entry, { character = CHAR, recipeKey = "enchant bracer - minor health", group = "enchant bracer - minor health" }, flavor)
  Assert.same(db.characters[CHAR].recipes, {}, flavor)
end

-- Other system messages, and a message that only looks like the format (the period is literal),
-- add nothing.
local function testOtherMessages()
  local ns = setup("tbc")
  for _, text in ipairs({
    "You have learned a new spell: Fireball.",
    "You have learned how to create a new item: Enchant Bracer - Minor Health!",
    "Bob says: You have learned how to create a new item: Fake.",
  }) do
    Wow.fireEvent(EVENT, text)
    ns.Slicer.Drain()
    Assert.equal(ns.LearnWatcher.lastPending, nil, text)
    Assert.equal(ns.Index.Current(), nil, text)
  end
end

-- Nothing runs in an instance.
local function testInstance()
  local ns = setup("tbc")
  Wow.stub("IsInInstance", function()
    return true
  end)
  learn(ns, "Enchant Bracer - Minor Health")
  Assert.equal(ns.LearnWatcher.lastPending, nil)
  Assert.equal(ns.Index.Current(), nil)
end

-- Only the system-message signal (option 1) installs a listener, and only when the client's
-- ERR_LEARN_RECIPE_S exists and has a %s for the name.
local function testOtherSignals()
  for _, signal in ipairs({ 2, 3, false }) do
    setup("tbc", {}, signal)
    Assert.falsy(isRegistered(EVENT), tostring(signal))
  end
  for _, format in ipairs({ false, "You have learned a new recipe." }) do
    ProfessionsClassic.login("tbc", {})
    Wow.stub("ERR_LEARN_RECIPE_S", format or nil)
    Fresh.require("Professions.LearnWatcher").InstallClassic(1)
    Assert.falsy(isRegistered(EVENT), tostring(format))
  end
end

-- A Cooking learn matches by name for the session, but the Cooking window never stores it.
local function testCookingNeverStored()
  local state = { tradeSkill = { line = "Cooking", rows = { { name = "Spiced Wolf Meat", item = 2680 } } } }
  local ns, db = setup("era", state)
  learn(ns, "Spiced Wolf Meat")
  Assert.truthy(pendingEntry(ns, "spiced", "spiced wolf meat"))
  Wow.fireEvent("TRADE_SKILL_SHOW")
  ns.Slicer.Drain()
  Assert.same(db.characters[CHAR].recipes, {})
end

-- The lead of a pending match names the recipe as the client spells it (PR #8 ruling), whichever
-- spelling learned it first; a second learn of the same name adds nothing.
local function testLeadKeepsClientSpelling()
  local ns, db = setup("tbc")
  Wow.clock.time = 1000
  learn(ns, "Enchant Bracer - Minor Health")
  learn(ns, "enchant bracer - minor health")
  Assert.equal(#ns.Index.Current().nameIndex.enchant, 1, "added once")
  ns.Matcher.SetIndex(ns.Index.Current())
  ns.RealmTag = Fresh.require("Model.RealmTag")
  ns.CrafterRank = Fresh.require("Model.CrafterRank")
  ns.Leads = Fresh.require("Model.Leads")
  ns.Leads.Restore(db)
  local text = "LF enchant bracer minor health"
  local result = ns.Matcher.Match("trade", text, "Bob-Realm")
  Assert.truthy(result, text)
  local lead = ns.Leads.OnMatch(result, "Bob-Realm", text, "trade")
  Assert.equal(lead.crafter, CHAR)
  Assert.equal(lead.recipeKey, "enchant bracer - minor health")
  Assert.equal(lead.recipeName, "Enchant Bracer - Minor Health")
end

return function()
  for _, flavor in ipairs(FLAVORS) do
    testLearnAddsPending(flavor)
  end
  testOtherMessages()
  testInstance()
  testOtherSignals()
  testCookingNeverStored()
  testLeadKeepsClientSpelling()
  Wow.reset()
end
