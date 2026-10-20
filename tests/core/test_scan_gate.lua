local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

local BS = Fixture.BS
local CHANNEL, GUILD, COMMUNITIES = "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_COMMUNITIES_CHANNEL"
local PLAYER_RESTING = "PLAYER_UPDATE_RESTING"
local WHISPER = "CHAT_MSG_WHISPER"

-- Fresh modules for one flavor, the player Me-Realm resting in a city, Smith-Realm knowing a
-- plate belt. `edit(db)` changes the db before the index is built. Install and the first
-- Evaluate are left to the test. → ns, db, state ({ resting = bool } the IsResting stub reads).
local function setup(flavor, edit)
  local ns = Fixture.load(flavor)
  Wow.clock.time = 1000
  local state = { resting = true }
  Wow.stub("IsResting", function()
    return state.resting
  end)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  Fixture.stubItems()
  ns.PlayerName.Init()
  for _, name in ipairs({
    "Core.Localization",
    "Core.ChatPrint",
    "Model.RealmTag",
    "Model.CrafterRank",
    "Model.Leads",
    "Professions.ProfessionList",
    "Core.Status",
    "Core.ScanGate",
  }) do
    ns[string.match(name, "%.(%w+)$")] = Fresh.require(name)
  end
  local db = ns.Defaults.Db()
  db.characters["Smith-Realm"] = Fixture.character({ BS }, { [1] = { item = 501, name = "Thick Plate Belt", prof = BS } })
  if edit then
    edit(db)
  end
  ns.Leads.Restore(db)
  ns.Index.Configure(db, {
    professionOrder = function()
      return { BS }
    end,
  })
  ns.Index.OnRebuilt(ns.Matcher.SetIndex)
  return ns, db, state
end

-- Install, evaluate on each rebuild (as Bootstrap does) and build the index.
local function start(ns, db)
  ns.ScanGate.Install(db)
  ns.Index.OnRebuilt(ns.ScanGate.Evaluate)
  ns.Index.Rebuild()
end

-- The chat events the addon's frame listens for, sorted.
local function listening()
  local names = {}
  for event in pairs(Wow.frames[1] and Wow.frames[1].events or {}) do
    if string.find(event, "^CHAT_MSG_") then
      names[#names + 1] = event
    end
  end
  table.sort(names)
  return names
end

-- A CHAT_MSG_CHANNEL payload (spec §6.1; Blizzard's order: text, sender, language, channel
-- name, sender again, flags, zone channel ID, channel index, base name, language ID, line ID, guid).
local function fireChannel(text, sender, zoneChannelID, guid)
  Wow.fireEvent(CHANNEL, text, sender, "", "2. Trade - City", sender, "", zoneChannelID, 2, "Trade - City", 0, 1, guid)
end

return function()
  -- ChannelKey owns the event-to-channel mapping: zone channel IDs for CHAT_MSG_CHANNEL (never
  -- the base name), one event each for guild and communities, nil for anything else.
  local ns = setup("retail")
  local ChannelKey = ns.ScanGate.ChannelKey
  Assert.equal(ChannelKey(CHANNEL, "Trade - City", 2), "trade")
  Assert.equal(ChannelKey(CHANNEL, "Trade - English", 2), "trade", "the base name is never compared")
  Assert.equal(ChannelKey(CHANNEL, "Whatever", 42), "services")
  Assert.equal(ChannelKey(CHANNEL, "General - City", 1), "general")
  Assert.equal(ChannelKey(CHANNEL, "LookingForGroup", 26), "lfg")
  Assert.equal(ChannelKey(CHANNEL, "Custom", 0), nil, "a custom channel has zone ID 0")
  Assert.equal(ChannelKey(CHANNEL, "Trade - City", nil), nil)
  Assert.equal(ChannelKey(CHANNEL, "LocalDefense - City", 22), nil)
  Assert.equal(ChannelKey(GUILD, nil, 0), "guild")
  Assert.equal(ChannelKey(COMMUNITIES, nil, 0), "communities")
  Assert.equal(ChannelKey("CHAT_MSG_SAY", nil, 0), nil)
  -- A channel the flavor does not have is ignored.
  ns = setup("tbc")
  Assert.equal(ns.ScanGate.ChannelKey(CHANNEL, "Trade - City", 2), "trade")
  Assert.equal(ns.ScanGate.ChannelKey(CHANNEL, "Services", 42), nil)
  Assert.equal(ns.ScanGate.ChannelKey(COMMUNITIES, nil, 0), nil)
  ns = setup("forever")
  Assert.equal(ns.ScanGate.ChannelKey(CHANNEL, "Services", 42), "services")
  Assert.equal(ns.ScanGate.ChannelKey(CHANNEL, "LookingForGroup", 26), nil)
  Assert.equal(ns.ScanGate.ChannelKey(COMMUNITIES, nil, 0), "communities")

  -- Active while enabled, the index has entries and the player rests; then the enabled chat
  -- events are registered, and only those.
  local db, resting
  ns, db, resting = setup("retail")
  Assert.same(listening(), {}, "nothing listens before the first evaluation")
  start(ns, db)
  Assert.equal(ns.ScanGate.IsActive(), true)
  Assert.same(listening(), { CHANNEL })
  Assert.same(ns.ScanGate.State(), {
    active = true,
    reason = nil,
    channels = { "Trade", "Services" },
    recipeCount = 1,
    crafterCount = 1,
    unreadProfession = nil,
  })

  -- Guild and communities have events of their own; a channel switched off drops its event.
  db.settings.channels.guild = true
  db.settings.channels.communities = true
  ns.ScanGate.Evaluate()
  Assert.same(listening(), { CHANNEL, COMMUNITIES, GUILD })
  Assert.same(ns.ScanGate.State().channels, { "Trade", "Services", "Guild", "Communities" })
  db.settings.channels.guild = false
  db.settings.channels.communities = false
  db.settings.channels.trade = false
  db.settings.channels.services = false
  ns.ScanGate.Evaluate()
  Assert.same(listening(), {}, "no channel left: no event")
  db.settings.channels.general = true
  db.settings.channels.lfg = true
  ns.ScanGate.Evaluate()
  Assert.same(listening(), { CHANNEL })
  Assert.same(ns.ScanGate.State().channels, { "General", "LookingForGroup" })

  -- The resting gate: leaving the city pauses, the setting can lift it.
  db.settings.channels.trade = true
  ns.ScanGate.Evaluate()
  resting.resting = false
  ns.ScanGate.Evaluate()
  Assert.equal(ns.ScanGate.IsActive(), false)
  Assert.equal(ns.ScanGate.State().reason, "notResting")
  Assert.same(listening(), {}, "paused: no public chat event")
  db.settings.onlyResting = false
  ns.ScanGate.Evaluate()
  Assert.equal(ns.ScanGate.IsActive(), true)
  db.settings.onlyResting = true
  ns.ScanGate.Evaluate()
  Assert.equal(ns.ScanGate.IsActive(), false)

  -- The enable setting beats everything; an empty index names the first unread profession.
  resting.resting = true
  db.settings.enable = false
  ns.ScanGate.Evaluate()
  Assert.equal(ns.ScanGate.State().reason, "disabled")
  Assert.same(listening(), {})
  ns, db, resting = setup("retail", function(d)
    d.characters["Smith-Realm"] = nil
    d.characters["Me-Realm"] = Fixture.character({ BS, 333 }, {})
    d.characters["Me-Realm"].professions[BS] = { name = "Blacksmithing", primary = true, read = false }
    d.characters["Me-Realm"].professions[333] = { name = "Enchanting", primary = true, read = false }
  end)
  start(ns, db)
  resting.resting = false
  ns.ScanGate.Evaluate()
  local paused = ns.ScanGate.State()
  Assert.equal(paused.reason, "empty", "an empty index outranks the resting gate")
  Assert.equal(paused.unreadProfession, "Blacksmithing")
  Assert.equal(paused.recipeCount, 0)

  -- Settings pages and Bootstrap evaluate before Install ran: paused, no error.
  ns = setup("retail")
  ns.ScanGate.Evaluate()
  Assert.equal(ns.ScanGate.IsActive(), false)
  Assert.same(listening(), {})

  -- Install re-evaluates on PLAYER_UPDATE_RESTING and ZONE_CHANGED_NEW_AREA.
  ns, db, resting = setup("retail")
  start(ns, db)
  resting.resting = false
  Wow.fireEvent(PLAYER_RESTING)
  Assert.equal(ns.ScanGate.IsActive(), false)
  resting.resting = true
  Wow.fireEvent("ZONE_CHANGED_NEW_AREA")
  Assert.equal(ns.ScanGate.IsActive(), true)

  -- OnChange fires once per transition (the first evaluation counts), with (active, state).
  ns, db, resting = setup("retail")
  local changes = {}
  ns.ScanGate.OnChange(function(active, state)
    changes[#changes + 1] = { active, state.reason }
  end)
  start(ns, db)
  ns.ScanGate.Evaluate()
  ns.Index.Rebuild()
  Assert.same(changes, { { true, nil } }, "same state again: no event")
  resting.resting = false
  Wow.fireEvent(PLAYER_RESTING)
  Wow.fireEvent("ZONE_CHANGED_NEW_AREA")
  resting.resting = true
  Wow.fireEvent(PLAYER_RESTING)
  Assert.same(changes, { { true, nil }, { false, "notResting" }, { true, nil } })
  ns, db, resting = setup("retail")
  resting.resting = false
  changes = {}
  ns.ScanGate.OnChange(function(active, state)
    changes[#changes + 1] = { active, state.reason }
  end)
  start(ns, db)
  Assert.same(changes, { { false, "notResting" } }, "a first evaluation that pauses is reported too")

  -- The status line prints to chat once, the first time scanning activates in a session.
  ns, db, resting = setup("retail")
  resting.resting = false
  start(ns, db)
  Assert.equal(#Wow.chat, 0, "paused: nothing printed")
  resting.resting = true
  Wow.fireEvent(PLAYER_RESTING)
  Assert.equal(#Wow.chat, 1)
  Assert.equal(Wow.chat[1], "|cffffd100Craft Alert:|r Listening in Trade, Services — 1 recipe, 1 crafter")
  resting.resting = false
  Wow.fireEvent(PLAYER_RESTING)
  resting.resting = true
  Wow.fireEvent(PLAYER_RESTING)
  Assert.equal(#Wow.chat, 1, "later activations stay quiet")

  -- Chat lines reach the Matcher and Leads only while scanning; the channel key, the sender
  -- and the sender's GUID travel along.
  ns, db, resting = setup("retail")
  start(ns, db)
  fireChannel("LF plate belt", "Bob-Draenor", 2, "Player-1-0A")
  local lead = ns.Leads.Latest()
  Assert.equal(lead.customer, "Bob-Draenor")
  Assert.equal(lead.channel, "trade")
  Assert.equal(lead.guid, "Player-1-0A")
  Assert.equal(lead.itemID, 501)
  fireChannel("LF plate belt", "Cy-Draenor", 1, nil) -- General is off
  fireChannel("LF plate belt", "Di-Draenor", 22, nil) -- LocalDefense is no channel of ours
  fireChannel("LF plate belt", "Me-Realm", 2, nil) -- the player
  Assert.equal(#ns.Leads.List(), 1)
  resting.resting = false
  Wow.fireEvent(PLAYER_RESTING)
  fireChannel("LF plate belt", "Ed-Draenor", 2, nil)
  Assert.equal(#ns.Leads.List(), 1, "paused: the event never arrives")
  resting.resting = true
  Wow.fireEvent(PLAYER_RESTING)
  Wow.fireEvent(GUILD, "LF plate belt", "Fay-Draenor", "", "", "", "", 0, 0, "", 0, 1, nil)
  Assert.equal(#ns.Leads.List(), 1, "guild chat is off")
  db.settings.channels.guild = true
  ns.Index.Rebuild()
  Wow.fireEvent(GUILD, "LF plate belt", "Fay-Draenor", "", "", "", "", 0, 0, "", 0, 1, nil)
  Assert.equal(ns.Leads.Latest().channel, "guild")

  -- SetHandler swaps what the frame calls; nil restores HandleChat.
  local seen = {}
  ns.ScanGate.SetHandler(function(event, text, sender, ...)
    seen[#seen + 1] = { event, text, sender, select("#", ...) }
  end)
  fireChannel("LF plate belt", "Gus-Draenor", 2, nil)
  Assert.same(seen, { { CHANNEL, "LF plate belt", "Gus-Draenor", 10 } }, "the full payload arrives")
  Assert.equal(ns.Leads.Latest().channel, "guild", "HandleChat did not run")
  ns.ScanGate.SetHandler(nil)
  fireChannel("LF plate belt", "Gus-Draenor", 2, nil)
  Assert.equal(#seen, 1)
  Assert.equal(ns.Leads.Latest().customer, "Gus-Draenor")

  -- Blocking a customer end to end: the Block button drops their leads and asks for a rebuild;
  -- once it ran, their next Trade line stops at the block set and makes no lead.
  ns, db = setup("retail")
  start(ns, db)
  fireChannel("LF plate belt", "Bob-Draenor", 2, nil)
  fireChannel("LF plate belt", "Cy-Draenor", 2, nil)
  Assert.equal(#ns.Leads.List(), 2)
  ns.Leads.Block("Bob-Draenor")
  Assert.equal(#ns.Leads.List(), 1, "Bob's lead is dismissed")
  Assert.equal(Wow.pendingTimers(0), 1, "a rebuild is queued")
  for i, timer in ipairs(Wow.timers) do
    if timer.delay == 0 then
      table.remove(Wow.timers, i).fn()
      break
    end
  end
  fireChannel("LF plate belt", "Bob-Draenor", 2, nil)
  Assert.equal(ns.Matcher.lastStop, "blocked")
  Assert.equal(#ns.Leads.List(), 1, "no new lead for the blocked customer")
  Assert.equal(ns.Leads.FindActiveByCustomer("Bob-Draenor"), nil)
  fireChannel("LF plate belt", "Di-Draenor", 2, nil)
  Assert.equal(ns.Matcher.lastStop, "match", "other customers still match")
  Assert.equal(#ns.Leads.List(), 2)

  -- Whisper events are not the scan's business.
  Assert.falsy(Wow.frames[1]:IsEventRegistered(WHISPER))
end
