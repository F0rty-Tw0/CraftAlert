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

return function()
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
  Leads.Dismiss(newer.id)
  Assert.equal(Leads.FindActiveByCustomer(CUSTOMER), lead)

  -- Dismiss, DismissCustomer: one change each, no event for unknown ids.
  changes = seen.change
  Leads.Dismiss(9999)
  Assert.equal(seen.change, changes)
  newLead(ns, "LF plate greaves")
  newLead(ns, "LF plate belt", "Carl-Draenor")
  changes = seen.change
  Leads.DismissCustomer(CUSTOMER)
  Assert.equal(seen.change, changes + 1)
  Assert.equal(#db.leads, 1)
  Assert.equal(db.leads[1].customer, "Carl-Draenor")
  Leads.DismissCustomer("Nobody-Draenor")
  Assert.equal(seen.change, changes + 1)
  Leads.Dismiss(db.leads[1].id)
  Assert.equal(Leads.HasActive(), false)
  Assert.equal(Leads.Latest(), nil)
  Assert.same(Leads.List(), {})

  -- Block: ignored, every lead of the customer dismissed, one rebuild asked for.
  ns, db = setup()
  Leads = ns.Leads
  newLead(ns, "LF plate belt")
  newLead(ns, "LF plate greaves")
  local keep = newLead(ns, "LF plate belt", "Carl-Draenor")
  Assert.equal(Wow.pendingTimers(0), 0)
  Leads.Block("Bob-Dra enor")
  Assert.equal(db.ignored["Bob-Draenor"], true)
  Assert.same(db.leads, { keep })
  Assert.equal(ns.Index.lastReason, "block")
  Assert.equal(Wow.pendingTimers(0), 1)
  Leads.Block("Dan")
  Assert.equal(db.ignored["Dan-Realm"], true, "keys are normalized")
  Leads.Block(nil)

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
