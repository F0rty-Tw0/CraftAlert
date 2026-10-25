-- The details pane's tests (tests/ui/test_lead_details.lua, tests/ui/test_details_header.lua):
-- UiFixture with Me-Realm a smithing mage, every customer a warrior, and the Bolt of Silk item.
--   local ns, d, calls, lead = DetailsFixture.open({ DetailsFixture.itemLead() })
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")

local DetailsFixture = {}

DetailsFixture.LINK = "item:4305"
DetailsFixture.LINK_TEXT = "|cffffffff|Hitem:4305|h[Bolt of Silk]|h|r"
DetailsFixture.ITEM_ICON = 132891
DetailsFixture.MAGE = { r = 0.25, g = 0.78, b = 0.92 }
DetailsFixture.WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
-- MAGE as a colour code, format("|cff%02x%02x%02x", r * 255, g * 255, b * 255).
DetailsFixture.MAGE_CODE = "|cff3fc6ea"
-- The spec's 16 px padding.
DetailsFixture.PAD = 16

-- The fixture over `leads` (records, oldest first, given ids 1..n); Me-Realm smiths and is a
-- mage; every customer is a warrior. → ns, the sends (UiFixture's calls).
function DetailsFixture.load(leads)
  local ns, _, calls = UiFixture.load({
    db = function(accountDb)
      accountDb.characters["Me-Realm"] = { class = "MAGE", professions = { [164] = { name = "Blacksmithing" } } }
      for id, lead in ipairs(leads) do
        lead.id = id
        accountDb.leads[id] = lead
      end
    end,
  })
  Wow.stub("RAID_CLASS_COLORS", { MAGE = DetailsFixture.MAGE, WARRIOR = DetailsFixture.WARRIOR })
  Wow.stub("LOCALIZED_CLASS_NAMES_MALE", { MAGE = "Mage", WARRIOR = "Warrior" })
  Wow.stub("GetPlayerInfoByGUID", function()
    return "Warrior", "WARRIOR"
  end)
  Wow.stub("C_Item", {
    GetItemInfoInstant = function(itemID)
      if itemID == 4305 then
        return 4305, "Tradeskill", "Cloth", "", DetailsFixture.ITEM_ICON
      end
    end,
  })

  return ns, calls
end

function DetailsFixture.leadOf(ns, id)
  for _, lead in ipairs(ns.Leads.List()) do
    if lead.id == id then
      return lead
    end
  end
  error("no lead " .. tostring(id))
end

-- A details pane in a bare host, laid out at the default size (840 wide: 840 - 4 - 6 - 260 - 1
-- = 569; any width over 348 gives full buttons), showing lead `id` (default 1).
-- → ns, the details, the sends, the lead.
function DetailsFixture.open(leads, id)
  local ns, calls = DetailsFixture.load(leads)
  local d = ns.LeadDetails.New(_G["CreateFrame"]("Frame"))
  ns.LeadDetails.Layout(d, 449)
  local lead = DetailsFixture.leadOf(ns, id or 1)
  ns.LeadDetails.Show(d, lead)

  return ns, d, calls, lead
end

-- Buyer-Realm wants the Bolt of Silk, 30 s ago; three crafters, Me-Realm first.
function DetailsFixture.itemLead()
  local lead = UiFixture.lead(1, "Buyer-Realm")
  lead.kind, lead.itemID, lead.itemLink = "item", 4305, DetailsFixture.LINK_TEXT
  lead.why, lead.profName, lead.message = "lf + bolt", "Tailoring", "LF bolt of silk"
  lead.guid = "Player-1-0001"
  lead.crafters = {
    { key = "Me-Realm", rank = 3, byConc = true },
    { key = "Bob-Realm" },
    { key = "Alt-Other", rank = 2 },
  }
  lead.time = UiFixture.T0 - 30

  return lead
end

-- A recipe lead: no link in its what line.
function DetailsFixture.recipeLead()
  local lead = DetailsFixture.itemLead()
  lead.itemLink, lead.recipeName = nil, "Bolt of Silk"

  return lead
end

function DetailsFixture.gold(text)
  return "|cffffd100" .. text .. "|r"
end

return DetailsFixture
