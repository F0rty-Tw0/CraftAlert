local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

-- Spec C.3: the info lines are built again only for a customer whose newest lead, or what of it
-- the line and its tooltip show, changed; every Leads event used to rebuild them all.
local function boot()
  local ns = UiFixture.load({ leads = 2 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.SyncInfo()
  return ns, wm
end

-- Counts CardTipText.InfoLines calls per customer: built[customer].
local function spyBuilds(ns)
  local built = {}
  local infoLines = ns.CardTipText.InfoLines
  ns.CardTipText.InfoLines = function(lead)
    built[lead.customer] = (built[lead.customer] or 0) + 1
    return infoLines(lead)
  end
  return built
end

local function leadOf(ns, id)
  for _, lead in ipairs(ns.Leads.List()) do
    if lead.id == id then
      return lead
    end
  end
  error("no lead " .. id)
end

-- A change to one customer's lead rebuilds their lines only.
local function testOnlyTheChangedCustomerIsRebuilt()
  local ns, wm = boot()
  local built = spyBuilds(ns)
  local changed, other = leadOf(ns, 1), leadOf(ns, 2)
  changed.message = "LF plate belt, thanks"
  ns.WhisperBridge.SyncInfo()
  Assert.same({ built[changed.customer], built[other.customer] }, { 1, nil })
  local tips = wm.tips.CraftAlert[changed.customer]
  Assert.truthy(string.find(tips[#tips], ": LF plate belt, thanks", 1, true), "the new chat line went out")
end

-- A Leads event that changes nothing the lines show (a greeting) rebuilds none.
local function testUnchangedLeadsAreNotRebuilt()
  local ns = boot()
  local built = spyBuilds(ns)
  ns.Leads.MarkGreeted(leadOf(ns, 2).id)
  Assert.same(built, {})
end

-- The item loading after the lead (Leads fills the link, then a "change") rebuilds its lines.
local function testLoadedItemLinkRebuilds()
  local ns, wm = boot()
  local built = spyBuilds(ns)
  local lead = leadOf(ns, 2)
  lead.itemLink = "|cff1eff00|Hitem:4305::::::::|h[Bolt of Silk Cloth]|h|r"
  ns.WhisperBridge.SyncInfo()
  Assert.equal(built[lead.customer], 1)
  Assert.equal(wm.info.CraftAlert[lead.customer], "|cffffd100Craft Alert:|r " .. lead.itemLink .. " · Blacksmithing · Me")
end

-- A new main crafter (Leads.Repick) on a profession lead changes only `crafter`; the line follows it.
local function testNewCrafterRebuilds()
  local ns, wm = boot()
  local built = spyBuilds(ns)
  local lead = leadOf(ns, 2)
  lead.crafter = "Alt-Realm"
  ns.WhisperBridge.SyncInfo()
  Assert.equal(built[lead.customer], 1)
  local info = wm.info.CraftAlert[lead.customer]
  Assert.equal(info:sub(-#" · Alt"), " · Alt", "the new crafter went out: " .. info)
end

-- One greeting syncs the info lines once: its "greeted" is always followed by a "change".
local function testGreetingSyncsOnce()
  local ns = boot()
  local syncs = 0
  local sync = ns.BridgeInfo.Sync
  ns.BridgeInfo.Sync = function(...)
    syncs = syncs + 1
    return sync(...)
  end
  ns.Leads.MarkGreeted(leadOf(ns, 2).id)
  Assert.equal(syncs, 1)
end

return function()
  testOnlyTheChangedCustomerIsRebuilt()
  testUnchangedLeadsAreNotRebuilt()
  testLoadedItemLinkRebuilds()
  testNewCrafterRebuilds()
  testGreetingSyncsOnce()
  Wow.reset()
end
