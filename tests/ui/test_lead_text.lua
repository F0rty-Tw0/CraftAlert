local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

local LINK = "|cff1eff00|Hitem:190001|h[Sim Plate Belt]|h|r"

return function()
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
  local channels = { trade = "Trade", services = "Services", general = "General", lfg = "LFG", guild = "Guild", communities = "Community" }
  for key, name in pairs(channels) do
    Assert.equal(ns.LeadText.Channel({ channel = key }), name, key)
  end
  Assert.equal(ns.LeadText.Channel({ channel = "weird" }), "weird")
  Assert.equal(ns.LeadText.Channel({}), nil)
  Wow.reset()
end
