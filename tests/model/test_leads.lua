local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")
local Fixture = require("tests.helpers.matcher_fixture")

local BS = Fixture.BS
local T0 = 1000
local CUSTOMER = "Bob-Draenor"
local TIMEOUT = 10 * 60 -- default leadTimeoutMin

-- Real Matcher over the fixture's item index: Smith and Alt know "Thick Plate Belt" (501), Smith
-- also "Plate Greaves" (502). `extra(db)` edits the db before the index is built. The player is
-- Me-Realm. → ns, db, with Leads restored on an empty lead list.
local function setup(flavor, extra)
  local ns = Fixture.load(flavor)
  Wow.clock.time = T0
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Wow.stub("UnitIsAFK", function()
    return false
  end)
  local db
  Fixture.itemIndex(ns, function(captured)
    db = captured
    if extra then
      extra(db)
    end
  end)
  -- Fixture.itemIndex stubs C_Item for item words only.
  Wow.stub("C_Item", {
    GetItemInfoInstant = _G["C_Item"].GetItemInfoInstant,
    GetItemInfo = function(itemID)
      return "Item " .. itemID, "|cff1eff00|Hitem:" .. itemID .. "::::::::60:::::|h[Item " .. itemID .. "]|h|r"
    end,
  })
  ns.PlayerName.Init()
  ns.RealmTag = Fresh.require("Model.RealmTag")
  ns.CrafterRank = Fresh.require("Model.CrafterRank")
  ns.Leads = Fresh.require("Model.Leads")
  ns.Leads.Restore(db)
  return ns, db
end

-- The Matcher's reused result for `text`.
local function match(ns, text)
  local result = ns.Matcher.Match("trade", text, "Someone-Else")
  Assert.truthy(result, text)
  return result
end

local function newLead(ns, text, customer, guid)
  return ns.Leads.OnMatch(match(ns, text), customer or CUSTOMER, text, "trade", guid)
end

-- Counts every event the module can fire.
local function listen(Leads)
  local seen = { new = {}, change = 0, greeted = {}, replied = {}, order = {} }
  Leads.On("new", function(lead)
    seen.new[#seen.new + 1] = lead
    seen.order[#seen.order + 1] = "new"
  end)
  Leads.On("change", function(...)
    Assert.equal(select("#", ...), 0, "change takes no arguments")
    seen.change = seen.change + 1
    seen.order[#seen.order + 1] = "change"
  end)
  Leads.On("greeted", function(lead)
    seen.greeted[#seen.greeted + 1] = lead
  end)
  Leads.On("replied", function(lead)
    seen.replied[#seen.replied + 1] = lead
  end)
  return seen
end

-- Runs the one pending timer (Wow.runTimers would loop while leads keep re-arming it).
local function fireTimer()
  Assert.equal(#Wow.timers, 1, "exactly one pending timer")
  table.remove(Wow.timers, 1).fn()
end

-- Blizzard's ignore list: an ignored customer makes and refreshes no lead, and IGNORELIST_UPDATE
-- (Leads.DismissIgnored) drops the open leads of everyone ignored, with one "change".
local function testIgnoreList()
  local ns = setup()
  local Leads = ns.Leads
  local text = "LF plate belt"
  local first = newLead(ns, text)
  local time, message = first.time, first.message
  -- A second open lead of the same customer, next to the first: the pass must drop both.
  Assert.truthy(newLead(ns, "LF plate greaves"), "a second lead for the customer")
  Wow.clock.time = Wow.clock.time + 30
  Wow.stub("C_FriendList", {
    IsIgnored = function(name)
      return name == CUSTOMER
    end,
  })
  Assert.equal(newLead(ns, "LF plate belt now"), nil, "an ignored customer's repeat line refreshes nothing")
  Assert.same({ first.time, first.message }, { time, message }, "the open lead is untouched")

  Assert.truthy(newLead(ns, text, "Other-Draenor"), "Other is not ignored")
  local seen = listen(Leads)
  Leads.DismissIgnored()
  Assert.equal(seen.change, 1, "one change for the whole pass")
  Assert.equal(#Leads.List(), 1, "both of the customer's leads went")
  Assert.equal(Leads.List()[1].customer, "Other-Draenor")

  Wow.stub("C_FriendList", nil)
  Leads.DismissIgnored()
  Assert.equal(seen.change, 1, "nobody ignored: no change")
end

-- A guid under Leads.TEST_GUID_PREFIX marks a synthetic lead; nothing else does, whatever the name.
local function testTestFlag()
  local ns = setup()
  local Leads = ns.Leads
  local prefix = Leads.TEST_GUID_PREFIX
  Assert.equal(prefix, "Player-0-CRAFTALERTTEST")
  Assert.equal(prefix, ns.FlavorCompat.TEST_GUID_PREFIX, "one source for the prefix")
  local flagSeen
  Leads.On("new", function(lead)
    flagSeen = lead.test
  end)
  local text = "LF plate belt"
  local lead = newLead(ns, text, "Test0-Realm", prefix .. "1")
  Assert.equal(flagSeen, true, "the flag is set before the new event")
  Assert.equal(lead.test, true)

  local again, isNew = newLead(ns, text, "Test0-Realm", prefix .. "2")
  Assert.same({ again, isNew }, { lead, false }, "the repeat updates the same lead")
  Assert.equal(lead.guid, prefix .. "1", "the first guid stays")
  Assert.equal(Leads.FindDuplicate("Test0-Realm", match(ns, text)), lead, "the lead a repeat would update")
  Assert.equal(Leads.FindDuplicate("Other-Realm", match(ns, text)), nil, "another customer has none")

  local real = newLead(ns, text, "Test-Realm", "Player-1-ABC")
  Assert.equal(real.test, nil, "a real player named Test is a normal lead")
  Assert.equal(newLead(ns, "LF plate greaves", "Other-Realm").test, nil, "no guid, no flag")
end

-- Nothing a test lead triggers reaches saved state.
local function testTestGuards()
  local ns, db = setup()
  local Leads = ns.Leads
  local text = "LF plate belt"
  local testLead = newLead(ns, text, "Test0-Realm", Leads.TEST_GUID_PREFIX .. "1")
  local realLead = newLead(ns, text, CUSTOMER, "Player-1-ABC")
  Assert.equal(Leads.MarkGreeted(testLead.id), true)
  Assert.equal(db.recentGreeted["Test0-Realm"], nil, "a test greeting is not remembered")
  Assert.equal(Leads.MarkGreeted(realLead.id), true)
  Assert.equal(db.recentGreeted[CUSTOMER], T0, "a real one is")

  -- Restore drops test leads left in the list.
  db.leads = { testLead, realLead }
  Leads.Restore(db)
  Assert.same(db.leads, { realLead }, "only the real lead is left")
  Assert.same(Leads.List(), { realLead })
end

return function()
  testIgnoreList()
  testTestFlag()
  testTestGuards()
  -- A new lead copies what it keeps out of the Matcher's result (§6.3 step 7).
  local ns, db = setup()
  local Leads = ns.Leads
  local seen = listen(Leads)
  local lead, isNew = newLead(ns, "LF plate belt", CUSTOMER, "Player-1-0A")
  Assert.equal(isNew, true)
  Assert.same({
    customer = lead.customer,
    guid = lead.guid,
    message = lead.message,
    channel = lead.channel,
    kind = lead.kind,
    itemID = lead.itemID,
    itemLink = lead.itemLink,
    recipeName = lead.recipeName,
    prof = lead.prof,
    profName = lead.profName,
    group = lead.group,
    why = lead.why,
    crafter = lead.crafter,
    cannotOrder = lead.cannotOrder,
    time = lead.time,
    greeted = lead.greeted,
    replied = lead.replied,
    arrivedWhileAfk = lead.arrivedWhileAfk,
  }, {
    customer = CUSTOMER,
    guid = "Player-1-0A",
    message = "LF plate belt",
    channel = "trade",
    kind = "item",
    itemID = 501,
    itemLink = "|cff1eff00|Hitem:501::::::::60:::::|h[Item 501]|h|r",
    recipeName = "Thick Plate Belt",
    prof = BS,
    profName = tostring(BS),
    group = 501,
    why = "lf + plate + belt",
    crafter = "Alt-Realm",
    cannotOrder = nil,
    time = T0,
    greeted = false,
    replied = false,
    arrivedWhileAfk = false,
  })
  Assert.equal(type(lead.id), "number")
  Assert.same(db.leads, { lead })
  Assert.equal(Leads.Latest(), lead)
  Assert.same(Leads.List(), { lead })
  Assert.equal(Leads.HasActive(), true)
  Assert.equal(#seen.new, 1)
  Assert.equal(seen.new[1], lead)
  Assert.equal(seen.change, 1)
  Assert.same(seen.order, { "new", "change" }, "the alert comes first")

  -- The lead keeps no reference to the result, whose buffers the next Match overwrites.
  local before = { group = lead.group, prof = lead.prof, why = lead.why, kind = lead.kind, itemID = lead.itemID }
  match(ns, "LF plate greaves")
  Assert.same({ group = lead.group, prof = lead.prof, why = lead.why, kind = lead.kind, itemID = lead.itemID }, before)
  for key, value in pairs(lead) do
    Assert.falsy(type(value) == "table", key .. " holds a table")
  end

  -- Same sender + same match inside the timeout updates the lead: no new alert, one lead.
  Wow.clock.time = T0 + 30
  local again, againNew = newLead(ns, "WTB plate belt pls", CUSTOMER, "Player-1-0A")
  Assert.equal(againNew, false)
  Assert.equal(again, lead)
  Assert.equal(lead.message, "WTB plate belt pls")
  Assert.equal(lead.why, "wtb + plate + belt")
  Assert.equal(lead.time, T0 + 30)
  Assert.equal(#db.leads, 1)
  Assert.equal(#seen.new, 1, "no second alert")
  Assert.equal(seen.change, 2, "an update is a change")

  -- A different item, a different customer: new leads.
  local second, secondNew = newLead(ns, "LF plate greaves", CUSTOMER)
  Assert.equal(secondNew, true)
  Assert.equal(second.itemID, 502)
  Assert.truthy(second.id ~= lead.id)
  local other, otherNew = newLead(ns, "LF plate belt", "Carl-Draenor")
  Assert.equal(otherNew, true)
  Assert.equal(#db.leads, 3)
  Assert.equal(Leads.Latest(), other)
  Assert.same(Leads.List(), { other, second, lead }, "newest first")
  Assert.truthy(Leads.List() ~= Leads.List(), "List returns a copy")

  -- An updated lead becomes the newest.
  Wow.clock.time = T0 + 40
  Assert.equal(newLead(ns, "LF plate belt", CUSTOMER), lead)
  Assert.same(Leads.List(), { lead, other, second })
  Assert.equal(Leads.Latest(), lead)
  Assert.equal(Leads.FindActiveByCustomer(CUSTOMER), lead)

  -- Past the timeout the same line is a new lead, even before the sweep ran.
  Wow.clock.time = T0 + 40 + TIMEOUT + 1
  local fresh, freshNew = newLead(ns, "LF plate belt", CUSTOMER)
  Assert.equal(freshNew, true)
  Assert.truthy(fresh ~= lead)

  -- Greeted and replied fire once; replied only after greeted.
  ns, db = setup()
  Leads = ns.Leads
  seen = listen(Leads)
  lead = newLead(ns, "LF plate belt")
  Assert.equal(Leads.MarkReplied(lead.id), false, "not before greeted")
  Assert.equal(lead.replied, false)
  Assert.equal(#seen.replied, 0)
  Wow.clock.time = T0 + 5
  local changes = seen.change
  Assert.equal(Leads.MarkGreeted(lead.id), true)
  Assert.equal(Leads.MarkGreeted(lead.id), false)
  Assert.equal(lead.greeted, true)
  Assert.equal(db.recentGreeted[CUSTOMER], T0 + 5)
  Assert.equal(#seen.greeted, 1)
  Assert.equal(seen.greeted[1], lead)
  Assert.equal(seen.change, changes + 1)
  Wow.clock.time = T0 + 9
  Assert.equal(Leads.MarkGreeted(lead.id), false)
  Assert.equal(db.recentGreeted[CUSTOMER], T0 + 5, "only the first greeting is recorded")
  Assert.equal(Leads.MarkReplied(lead.id), true)
  Assert.equal(Leads.MarkReplied(lead.id), false)
  Assert.equal(lead.replied, true)
  Assert.equal(#seen.replied, 1)
  Assert.equal(Leads.MarkGreeted(9999), false, "unknown id")
  Assert.equal(Leads.MarkReplied(9999), false, "unknown id")

  -- FindActiveByCustomer: the customer's newest lead.
  local newer = newLead(ns, "LF plate greaves")
  Assert.equal(Leads.FindActiveByCustomer(CUSTOMER), newer)
  Assert.equal(Leads.FindActiveByCustomer("Nobody-Draenor"), nil)

  -- IsActive: whether the id is still in the list (not dismissed, expired or evicted).
  Assert.equal(Leads.IsActive(newer.id), true)
  Assert.equal(Leads.IsActive(nil), false)
  Leads.Dismiss(newer.id)
  Assert.equal(Leads.IsActive(newer.id), false)
  Assert.equal(Leads.FindActiveByCustomer(CUSTOMER), lead)

  -- Dismiss: one change, no event for unknown ids.
  changes = seen.change
  Leads.Dismiss(9999)
  Assert.equal(seen.change, changes)
  local carl = newLead(ns, "LF plate belt", "Carl-Draenor")
  changes = seen.change
  Leads.Dismiss(carl.id)
  Assert.equal(seen.change, changes + 1)
  Assert.equal(Leads.IsActive(carl.id), false)
  Assert.equal(#db.leads, 1)
  Assert.equal(db.leads[1], lead)
  Leads.Dismiss(lead.id)
  Assert.equal(Leads.HasActive(), false)
  Assert.equal(Leads.Latest(), nil)
  Assert.same(Leads.List(), {})

  -- Review Focus 3: eight alts know the recipe → one lead, the best crafter.
  ns, db = setup(nil, function(data)
    for i = 3, 8 do
      local key = "Alt" .. i .. "-Realm"
      data.characters[key] = Fixture.character({ BS }, { [1] = { item = 501, name = "Thick Plate Belt", prof = BS } })
    end
    data.characters["Me-Realm"] = Fixture.character({ BS }, { [77] = { item = 501, name = "Thick Plate Belt (Me)", prof = BS } })
  end)
  seen = listen(ns.Leads)
  lead = newLead(ns, "LF plate belt")
  Assert.equal(lead.crafter, "Me-Realm", "the current character first")
  Assert.equal(lead.recipeName, "Thick Plate Belt (Me)", "the crafter's own recipe")
  Assert.equal(#db.leads, 1)
  Assert.equal(#seen.new, 1)

  -- Profession matches have no item; they dedupe by profession.
  ns = setup()
  lead, isNew = newLead(ns, "LF blacksmith")
  Assert.equal(isNew, true)
  Assert.equal(lead.kind, "profession")
  Assert.equal(lead.prof, BS)
  Assert.equal(lead.profName, tostring(BS))
  for _, field in ipairs({ "itemID", "itemLink", "recipeName", "group" }) do
    Assert.equal(lead[field], nil, field)
  end
  Assert.equal(lead.crafter, "Alt-Realm")
  Assert.equal(select(2, newLead(ns, "LF blacksmith please")), false)
  Assert.equal(select(2, newLead(ns, "LF bs")), false, "another word for the same profession is the same match")
  local jewel, jewelNew = newLead(ns, "LF jewelcrafter")
  Assert.equal(jewelNew, true, "another profession is another lead")
  Assert.equal(jewel.prof, 755)
  Assert.equal(jewel.crafter, "Smith-Realm")

  -- An item lead and a profession lead for the same profession are different matches.
  ns = setup()
  Assert.equal(select(2, newLead(ns, "LF plate belt")), true)
  Assert.equal(select(2, newLead(ns, "LF blacksmith")), true)

  -- Several recipes in one profession: a profession lead that names no item.
  ns = setup()
  lead = newLead(ns, "LF plate")
  Assert.equal(lead.kind, "profession")
  Assert.equal(lead.prof, BS)
  Assert.equal(lead.itemID, nil)
  Assert.equal(lead.recipeName, nil)
  Assert.equal(lead.profName, tostring(BS))

  -- Realm tag on the lead (Retail), and nothing on Forever.
  local function withRealms(data)
    data.characters["Alt-Realm"].realms = { "Realm" }
    data.characters["Smith-Realm"].realms = { "Realm" }
  end
  ns = setup("retail", withRealms)
  lead = newLead(ns, "LF plate belt")
  Assert.equal(lead.cannotOrder, true)
  ns = setup("retail", withRealms)
  Assert.equal(newLead(ns, "LF plate belt", "Bob-Realm").cannotOrder, false)
  ns = setup("forever", withRealms)
  Assert.equal(newLead(ns, "LF plate belt").cannotOrder, nil)

  -- Blizzard's ignore list drops the lead; a secret guid is not kept; AFK arrival is flagged.
  ns = setup()
  Wow.stub("C_FriendList", {
    IsIgnored = function(name)
      return name == CUSTOMER
    end,
  })
  Assert.equal(newLead(ns, "LF plate belt"), nil)
  Assert.equal(#ns.Leads.List(), 0)
  Wow.stub("C_FriendList", nil)
  Assert.equal(newLead(ns, "LF plate belt", CUSTOMER, Wow.secret("Player-1-0A")).guid, nil)
  Wow.stub("UnitIsAFK", function()
    return true
  end)
  Assert.equal(newLead(ns, "LF plate greaves").arrivedWhileAfk, true)
  Wow.stub("UnitIsAFK", function()
    return Wow.secret(true)
  end)
  Assert.equal(newLead(ns, "LF plate belt", "Carl-Draenor").arrivedWhileAfk, nil, "a secret AFK flag leaves it unset")

  -- The 101st lead drops the oldest; the db keeps its table.
  ns, db = setup()
  local stored = db.leads
  for i = 1, 101 do
    Wow.clock.time = T0 + i
    newLead(ns, "LF plate belt", "Cust" .. i .. "-Draenor")
  end
  Assert.equal(#db.leads, 100)
  Assert.equal(db.leads, stored)
  Assert.equal(db.leads[1].customer, "Cust2-Draenor")
  Assert.equal(ns.Leads.Latest().customer, "Cust101-Draenor")

  -- One expiry timer, always for the oldest lead; it fires once per lead.
  ns, db = setup()
  Leads = ns.Leads
  seen = listen(Leads)
  Assert.equal(#Wow.timers, 0, "no leads, no timer")
  local first = newLead(ns, "LF plate belt")
  Assert.equal(#Wow.timers, 1)
  Assert.equal(Wow.timers[1].delay, TIMEOUT + 1)
  Wow.clock.time = T0 + 100
  local last = newLead(ns, "LF plate belt", "Carl-Draenor")
  Assert.equal(#Wow.timers, 1, "still one timer")
  Wow.clock.time = T0 + TIMEOUT + 1
  changes = seen.change
  fireTimer()
  Assert.same(db.leads, { last }, "the oldest lead expired")
  Assert.equal(seen.change, changes + 1)
  Assert.equal(#Wow.timers, 1, "re-armed for the next-oldest lead")
  Assert.equal(Wow.timers[1].delay, 100, "the second lead is 100 s younger")
  Wow.clock.time = T0 + 100 + TIMEOUT + 1
  fireTimer()
  Assert.same(db.leads, {})
  Assert.equal(#Wow.timers, 0, "nothing left to wait for")
  Assert.equal(Leads.HasActive(), false)
  Assert.truthy(first ~= last)

  -- A lead updated meanwhile outlives the timer that was armed for it, which just re-arms.
  ns, db = setup()
  lead = newLead(ns, "LF plate belt")
  Wow.clock.time = T0 + 300
  newLead(ns, "LF plate belt")
  Wow.clock.time = T0 + TIMEOUT + 1
  fireTimer()
  Assert.same(db.leads, { lead })
  Assert.equal(#Wow.timers, 1)
  Assert.equal(Wow.timers[1].delay, 300)

  -- The lead timeout setting applies at once.
  db.settings.leadTimeoutMin = 1
  Wow.clock.time = T0 + 400
  fireTimer()
  Assert.same(db.leads, {})

  -- Rearm after a lower timeout (settings page): the lead expires on the new timeout, not when
  -- the timer armed for the old one fires; that stale timer then does nothing.
  ns, db = setup()
  Leads = ns.Leads
  seen = listen(Leads)
  newLead(ns, "LF plate belt")
  Assert.equal(Wow.timers[1].delay, TIMEOUT + 1)
  Wow.clock.time = T0 + 30
  db.settings.leadTimeoutMin = 1
  Leads.Rearm()
  Assert.equal(#Wow.timers, 2, "a timer for the new deadline beside the stale one")
  Assert.equal(Wow.timers[2].delay, 31, "60 s timeout, 30 s already gone, + 1")
  Wow.clock.time = T0 + 61
  changes = seen.change
  table.remove(Wow.timers, 2).fn()
  Assert.same(db.leads, {}, "expired on the new timeout")
  Assert.equal(seen.change, changes + 1)
  table.remove(Wow.timers, 1).fn()
  Assert.equal(#Wow.timers, 0, "the stale timer neither sweeps nor re-arms")
  Assert.equal(seen.change, changes + 1)

  -- The stale timer firing while its lead is still listed does nothing either: the timer Rearm
  -- started stays the only live one.
  ns, db = setup()
  Leads = ns.Leads
  seen = listen(Leads)
  lead = newLead(ns, "LF plate belt")
  Wow.clock.time = T0 + 30
  db.settings.leadTimeoutMin = 1
  Leads.Rearm()
  Assert.equal(#Wow.timers, 2)
  Wow.clock.time = T0 + 40
  changes = seen.change
  table.remove(Wow.timers, 1).fn()
  Assert.same(db.leads, { lead })
  Assert.equal(seen.change, changes)
  Assert.equal(#Wow.timers, 1, "no second live timer")
  Assert.equal(Wow.timers[1].delay, 31, "the Rearm timer")

  -- Rearm sweeps at once what the new timeout already expired; a raised timeout or no leads
  -- arms nothing new (the pending timer fires early and re-arms itself).
  ns, db = setup()
  Leads = ns.Leads
  newLead(ns, "LF plate belt")
  Wow.clock.time = T0 + 120
  db.settings.leadTimeoutMin = 1
  Leads.Rearm()
  Assert.same(db.leads, {}, "120 s old with a 60 s timeout")
  Assert.equal(#Wow.timers, 1, "nothing left to arm for")
  ns, db = setup()
  Leads = ns.Leads
  lead = newLead(ns, "LF plate belt")
  db.settings.leadTimeoutMin = 30
  Leads.Rearm()
  Assert.equal(#Wow.timers, 1, "a later deadline keeps the pending timer")
  Wow.clock.time = T0 + TIMEOUT + 1
  fireTimer()
  Assert.same(db.leads, { lead }, "the early timer sweeps nothing")
  Assert.equal(Wow.timers[1].delay, 20 * 60, "re-armed for the 30 min deadline")

  -- Restore: sweeps what expired since the db was loaded, arms the timer, continues the ids.
  ns, db = setup()
  Leads = ns.Leads
  local old = { id = 7, customer = "Old-Draenor", time = T0 - TIMEOUT - 1, kind = "item", greeted = false, replied = false }
  local live = { id = 12, customer = "Live-Draenor", time = T0 - 10, kind = "item", greeted = false, replied = false }
  local edge = { id = 3, customer = "Edge-Draenor", time = T0 - TIMEOUT, kind = "item", greeted = false, replied = false }
  db.leads = { live, edge, old }
  Leads.Restore(db)
  Assert.same(db.leads, { edge, live }, "a lead exactly at the timeout stays; the list is oldest first")
  Assert.equal(Leads.Latest(), live)
  Assert.equal(Leads.FindActiveByCustomer("Live-Draenor"), live)
  Assert.equal(#Wow.timers, 1)
  Assert.equal(newLead(ns, "LF plate belt").id, 13)

  -- A lead dated in the future (hand-edited, or the clock went back) counts as arrived now, so it
  -- still expires after the timeout instead of never.
  ns, db = setup()
  Leads = ns.Leads
  local future = { id = 1, customer = "Future-Draenor", time = T0 + 1e9, kind = "item", greeted = false, replied = false }
  db.leads = { future }
  Leads.Restore(db)
  Assert.equal(future.time, T0)
  Assert.equal(Wow.timers[1].delay, TIMEOUT + 1)
  Wow.clock.time = T0 + TIMEOUT + 1
  fireTimer()
  Assert.same(db.leads, {}, "expired on the timeout")

  -- Restore keeps at most 100 leads, the newest, however many a hand-edited db holds.
  ns, db = setup()
  Leads = ns.Leads
  local flood = {}
  for i = 1, 5000 do
    flood[i] = { id = i, customer = "Cust" .. i .. "-Draenor", time = T0 - 590 + math.floor(i / 10), kind = "item", greeted = false, replied = false }
  end
  db.leads = flood
  Leads.Restore(db)
  Assert.equal(#db.leads, 100)
  Assert.equal(db.leads[1].id, 4901)
  Assert.equal(db.leads[100].id, 5000)
  Assert.equal(Leads.Latest().id, 5000)
  Assert.equal(db.leads, flood, "the db keeps its table")
  Assert.equal(newLead(ns, "LF plate belt").id, 5001)

  -- The oldest are the ones dropped, also when the list is out of order or part of it expired.
  ns, db = setup()
  Leads = ns.Leads
  db.leads = {}
  for i = 1, 150 do
    db.leads[i] = { id = i, customer = "Cust" .. i .. "-Draenor", time = T0 - 200 + (i * 37) % 150, kind = "item", greeted = false, replied = false }
  end
  Leads.Restore(db)
  Assert.equal(#db.leads, 100)
  for i = 2, 100 do
    Assert.truthy(db.leads[i - 1].time <= db.leads[i].time, "oldest first at " .. i)
  end

  -- Leads of the same second keep a stable order, by id.
  ns, db = setup()
  Leads = ns.Leads
  db.leads = {}
  for _, id in ipairs({ 3, 1, 4, 2 }) do
    db.leads[#db.leads + 1] = { id = id, customer = "Cust" .. id .. "-Draenor", time = T0 - 5, kind = "item", greeted = false, replied = false }
  end
  Leads.Restore(db)
  local order = {}
  for i, restored in ipairs(db.leads) do
    order[i] = restored.id
  end
  Assert.same(order, { 1, 2, 3, 4 })

  -- A missing or repeated id would make find(nil) or the second twin act on the wrong lead:
  -- each gets a fresh one, the first twin keeps its own.
  ns, db = setup()
  Leads = ns.Leads
  db.leads = {
    { id = 5, customer = "A-Draenor", time = T0 - 40, kind = "item", greeted = false, replied = false },
    { customer = "B-Draenor", time = T0 - 30, kind = "item", greeted = false, replied = false },
    { id = 5, customer = "C-Draenor", time = T0 - 20, kind = "item", greeted = false, replied = false },
    { id = "7", customer = "D-Draenor", time = T0 - 10, kind = "item", greeted = false, replied = false },
  }
  Leads.Restore(db)
  local ids = {}
  for _, restored in ipairs(db.leads) do
    Assert.equal(type(restored.id), "number")
    ids[restored.id] = true
  end
  local distinct = 0
  for _ in pairs(ids) do
    distinct = distinct + 1
  end
  Assert.equal(distinct, 4, "every lead has its own id")
  Assert.equal(db.leads[1].id, 5, "the first twin keeps its id")
  Assert.equal(Leads.MarkGreeted(nil), false)
  Assert.equal(db.leads[2].greeted, false)
  Assert.equal(Leads.MarkGreeted(db.leads[3].id), true)
  Assert.same({ db.leads[1].greeted, db.leads[2].greeted, db.leads[3].greeted, db.leads[4].greeted }, { false, false, true, false })
  Assert.equal(newLead(ns, "LF plate belt").id > 7, true, "new ids continue above every restored one")

  -- NaN and infinite ids are not ids: a NaN table key raises, inf + 1 repeats inf, and -inf
  -- would hand out ids below every real one.
  ns, db = setup()
  Leads = ns.Leads
  db.leads = {
    { id = 0 / 0, customer = "A-Draenor", time = T0 - 30, kind = "item", greeted = false, replied = false },
    { id = 2, customer = "B-Draenor", time = T0 - 20, kind = "item", greeted = false, replied = false },
    { id = 1 / 0, customer = "C-Draenor", time = T0 - 10, kind = "item", greeted = false, replied = false },
    { id = 1 / 0, customer = "D-Draenor", time = T0 - 5, kind = "item", greeted = false, replied = false },
    { id = -1 / 0, customer = "E-Draenor", time = T0 - 4, kind = "item", greeted = false, replied = false },
  }
  Leads.Restore(db)
  local finite = {}
  for _, restored in ipairs(db.leads) do
    Assert.truthy(restored.id == restored.id and restored.id > -math.huge and restored.id < math.huge, "finite id")
    Assert.falsy(finite[restored.id], "distinct id")
    finite[restored.id] = true
  end
  Assert.equal(#db.leads, 5)
  Assert.equal(db.leads[5].id > 2, true, "the -inf lead gets a fresh id above the real ones")

  -- A C_Timer.After that raises leaves no timer behind: the next lead arms one instead of
  -- trusting a timer that never started.
  ns = setup()
  local after = _G["C_Timer"].After
  local function failingAfter()
    error("timer failed", 0)
  end
  _G["C_Timer"].After = failingAfter
  Assert.raises(function()
    newLead(ns, "LF plate belt")
  end, "timer failed")
  _G["C_Timer"].After = after
  newLead(ns, "LF plate greaves")
  Assert.equal(#Wow.timers, 1, "the next lead arms the expiry timer")

  -- A Rearm whose timer raises keeps the pending timer live: it still sweeps when it fires.
  ns, db = setup()
  newLead(ns, "LF plate belt")
  Wow.clock.time = T0 + 30
  db.settings.leadTimeoutMin = 1
  _G["C_Timer"].After = failingAfter
  Assert.raises(ns.Leads.Rearm, "timer failed")
  _G["C_Timer"].After = after
  Wow.clock.time = T0 + TIMEOUT + 1
  fireTimer()
  Assert.same(db.leads, {}, "the pending timer swept the lead")

  -- A subscriber that raises does not stop the others or the lead.
  ns, db = setup()
  Leads = ns.Leads
  local reported = {}
  Wow.stub("geterrorhandler", function()
    return function(err)
      reported[#reported + 1] = err
    end
  end)
  Leads.On("new", function()
    error("boom")
  end)
  seen = listen(Leads)
  lead = newLead(ns, "LF plate belt")
  Assert.equal(#reported, 1)
  Assert.equal(#seen.new, 1)
  Assert.same(db.leads, { lead })
  Assert.raises(function()
    Leads.On("nope", function() end)
  end, "unknown")
end
