-- The real chain for /ca tests: UiFixture's modules over the Matcher fixture's three crafters
-- (Ench-Realm, Smith-Realm, Tailor-Realm), an index built through Index.Rebuild and a scan gate
-- that is active, so the trade line "LF mongoose" makes a lead for Ench-Realm. The player is
-- Me-Realm, resting. The new-lead toast and TestLine are wired as Bootstrap wires them. Chat
-- lines printed while loading are dropped.
--   local ns, db, calls = SlashFixture.load({ db = function(accountDb) ... end })  -- opts.db: extra edits
--   SlashFixture.fireTrade("LF mongoose", "Bob-Draenor")   -- a CHAT_MSG_CHANNEL on Trade
--   SlashFixture.chat()                                    -- printed lines without the prefix
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")
local UiFixture = require("tests.helpers.ui_fixture")
local Fresh = require("tests.helpers.fresh")

local SlashFixture = {}

local CHANNEL = "CHAT_MSG_CHANNEL"
local TRADE_ZONE_CHANNEL_ID = 2
local PREFIX = "^|cffffd100Craft Alert:|r "

function SlashFixture.load(opts)
  local ns, db, calls = UiFixture.load({
    db = function(accountDb)
      local fixtureDb = Fixture.db({ Defaults = require("CraftAlert.Persistence.Defaults") })
      for key, character in pairs(fixtureDb.characters) do
        accountDb.characters[key] = character
      end
      if opts and opts.db then
        opts.db(accountDb)
      end
    end,
  })
  Wow.stub("IsResting", function()
    return true
  end)
  ns.Index.Configure(db, {
    professionOrder = function()
      return { Fixture.ENCH, Fixture.BS, Fixture.TAILOR, Fixture.LW }
    end,
  })
  ns.Index.OnRebuilt(ns.Matcher.SetIndex)
  ns.ScanGate.Install(db)
  ns.Index.OnRebuilt(ns.ScanGate.Evaluate)
  ns.Index.Rebuild()
  ns.Leads.On("new", ns.AlertToast.Show)
  ns.TestLine.Install()
  ns.WhisperTracker = Fresh.require("Model.WhisperTracker")
  ns.WhisperTracker.Install()
  Wow.chat = {}
  return ns, db, calls
end

function SlashFixture.fireTrade(text, sender)
  Wow.fireEvent(CHANNEL, text, sender, "", "2. Trade - City", sender, "", TRADE_ZONE_CHANNEL_ID, 2, "Trade - City", 0, 1, nil)
end

-- The lines printed so far, without the addon prefix.
function SlashFixture.chat()
  local lines = {}
  for i, line in ipairs(Wow.chat) do
    lines[i] = string.gsub(line, PREFIX, "")
  end
  return lines
end

return SlashFixture
