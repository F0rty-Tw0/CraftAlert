local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

local LINK = "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r"

local function testText()
  local ns = UiFixture.load()
  local H = ns.LeadText.Headline
  Assert.equal(H({ crafter = "Me-Realm", itemLink = LINK, profName = "Blacksmithing" }), "Wants " .. LINK .. " — you can craft it")
  Assert.equal(H({ crafter = "Me-Realm", recipeName = "Plate Belt", profName = "Blacksmithing" }), "Wants Plate Belt — you can craft it")
  Assert.equal(H({ crafter = "Alt-Realm", itemLink = LINK }), "Wants " .. LINK .. " — your alt Alt can craft it")
  Assert.equal(H({ crafter = "Me-Realm", profName = "Blacksmithing" }), "Wants Blacksmithing — you have it")
  Assert.equal(H({ crafter = "Alt-Realm", profName = "Blacksmithing" }), "Wants Blacksmithing — your alt Alt has it")
  -- An alt on another realm keeps its realm.
  Assert.equal(H({ crafter = "Alt-Other", recipeName = "Plate Belt" }), "Wants Plate Belt — your alt Alt-Other can craft it")
  Assert.equal(H({ crafter = "Alt-Other", profName = "Blacksmithing" }), "Wants Blacksmithing — your alt Alt-Other has it")
  -- A lead's channel key as its word; an unknown key as itself; no key, nil.
  local channels = { trade = "Trade", services = "Services", general = "General", lfg = "LookingForGroup", guild = "Guild", communities = "Communities" }
  for key, name in pairs(channels) do
    Assert.equal(ns.LeadText.Channel({ channel = key }), name, key)
  end
  -- One table feeds the lead words and the settings toggles, in the toggles' order.
  local keys, labels = {}, {}
  for i, channel in ipairs(ns.LeadText.CHANNELS) do
    keys[i], labels[i] = channel.key, channel.label
  end
  Assert.same(keys, { "trade", "services", "general", "lfg", "guild", "communities" })
  Assert.same(labels, { "Trade", "Services", "General", "LookingForGroup", "Guild", "Communities" })
  Assert.equal(ns.LeadText.Channel({ channel = "weird" }), "weird")
  Assert.equal(ns.LeadText.Channel({}), nil)
  Assert.equal(ns.LeadText.RealmTag({ cannotOrder = true }), "Can't send an order (other realm)")
  Assert.equal(ns.LeadText.RealmTag({}), nil)
  Wow.reset()
end

-- Details spec A.4: the lines under Quality, from the crafter's recipe record.
local CONC = 3168

local function qualityDb(recipe, concentration)
  local character = { recipes = { [9001] = recipe }, concentration = concentration }
  return { characters = { ["Alt-Realm"] = character } }
end

local function qualityLead(fields)
  local lead = { kind = "item", crafter = "Alt-Realm", recipeKey = 9001 }
  for k, v in pairs(fields or {}) do
    lead[k] = v
  end
  return lead
end

local function plain(lines)
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  end
  return out
end

local function testQuality()
  local ns = UiFixture.load()
  local Q = ns.LeadText.Quality
  local ranks = { 1, 2, 3 }
  local function record(fields)
    fields.name, fields.prof = "Belt", 164
    return fields
  end
  local snapshot = { [CONC] = { amount = 960, at = 0, cycleMs = 345600, perCycle = 1, max = 1000 } }

  -- Nothing to say: no record, no reach data, no or empty ranks, a profession lead, a lead without a key.
  local reached = qualityDb(record({ ranks = ranks, reachRank = 1, reachCost = 0, reachConc = CONC }))
  Assert.equal(Q(qualityLead({ recipeKey = 5 }), reached), nil, "no record")
  Assert.equal(Q(qualityLead(), qualityDb(record({ ranks = ranks }))), nil, "no reach data")
  Assert.equal(Q(qualityLead(), qualityDb(record({ reachRank = 1, reachCost = 0, reachConc = CONC }))), nil, "no ranks")
  Assert.equal(Q(qualityLead(), qualityDb(record({ ranks = {}, reachRank = 1, reachCost = 0, reachConc = CONC }))), nil, "empty ranks")
  local full = qualityDb(record({ ranks = ranks, reachRank = 2, reachCost = 120, reachConc = CONC }), snapshot)
  Assert.equal(Q(qualityLead({ kind = "profession" }), full), nil, "profession lead")
  Assert.equal(Q(qualityLead({ recipeKey = false }), full), nil, "no key")
  Assert.equal(Q(qualityLead({ crafter = "Gone-Realm" }), full), nil, "crafter removed")

  -- R == top, or cost 0: one line.
  local top = qualityDb(record({ ranks = ranks, reachRank = 3, reachCost = 120, reachConc = CONC }), snapshot)
  Assert.same(plain(Q(qualityLead(), top)), { "R3 with the best reagents" }, "top rank")
  local free = qualityDb(record({ ranks = ranks, reachRank = 2, reachCost = 0, reachConc = CONC }), snapshot)
  Assert.same(plain(Q(qualityLead(), free)), { "R2 with the best reagents" }, "cost 0")

  -- Concentration covers the next rank: the second line counts what is left after spending.
  Wow.clock.time = 0
  Assert.same(plain(Q(qualityLead(), full)), { "R2 with the best reagents", "R3 with 120 concentration (840 left)" })

  -- It does not: the second line says what is short.
  local short = qualityDb(record({ ranks = ranks, reachRank = 2, reachCost = 120, reachConc = CONC }), {
    [CONC] = { amount = 40, at = 0, cycleMs = 345600, perCycle = 1, max = 1000 },
  })
  Assert.same(plain(Q(qualityLead(), short)), { "R2 with the best reagents", "R3 needs 120 concentration (you have 40)" })

  -- Exactly enough still covers it, with none left.
  local exact = qualityDb(record({ ranks = ranks, reachRank = 2, reachCost = 120, reachConc = CONC }), {
    [CONC] = { amount = 120, at = 0, cycleMs = 345600, perCycle = 1, max = 1000 },
  })
  Assert.same(plain(Q(qualityLead(), exact)), { "R2 with the best reagents", "R3 with 120 concentration (0 left)" })

  -- Colours: the rank white, the explanation 55 % white, the count grey.
  Assert.equal(Q(qualityLead(), full)[2], "|cffffffffR3|r |cff8c8c8cwith 120 concentration|r |cff7f7f7f(840 left)|r")
  Wow.reset()
end

return function()
  testText()
  testQuality()
end
