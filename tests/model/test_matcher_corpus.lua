local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fixture = require("tests.helpers.matcher_fixture")

-- Spec §13 "Matcher corpus" and §6.2 item 6: every labeled line of the trade corpus against
-- the §6.2 item 6 fixture index. The corpus is the only file this test needs beyond the
-- fixture helper; the user approved its lines and labels 2026-10-19 (Task 1.8 corpus gate).
local SENDER = "Customer-Other"
local GUID_PREFIX = "Player-0-"

-- case.class: the sender's class token, served for the GUID GUID_PREFIX .. class.
local function stubClasses()
  Wow.stub("GetPlayerInfoByGUID", function(guid)
    return "Localized", string.sub(guid, #GUID_PREFIX + 1)
  end)
end

local function outcome(ns, text, class)
  local result = ns.Matcher.Match("trade", text, SENDER, class and GUID_PREFIX .. class)
  if result == nil then
    return "silent:" .. ns.Matcher.lastStop
  end
  if result.kind == "item" then
    return "item:" .. tostring(result.group)
  end
  return "profession:" .. tostring(result.prof)
end

local function expected(case)
  if case.expect == "silent" then
    return "silent:" .. tostring(case.stop)
  end
  if case.expect.kind == "item" then
    return "item:" .. string.lower(case.expect.recipe)
  end
  return "profession:" .. tostring(case.expect.prof)
end

return function()
  local corpus = dofile("tests/fixtures/trade_corpus.lua")
  Assert.truthy(#corpus >= 100, "at least 100 labeled lines")
  local ns = Fixture.load()
  ns.Matcher.SetIndex(Fixture.index(ns))
  stubClasses()
  local failures, hits = {}, 0
  for i, case in ipairs(corpus) do
    local want, got = expected(case), outcome(ns, case.text, case.class)
    if want ~= got then
      failures[#failures + 1] = string.format("#%d %q: want %s, got %s", i, case.text, want, got)
    end
    if case.expect ~= "silent" then
      hits = hits + 1
    end
  end
  Assert.truthy(hits > 0 and hits < #corpus, "the corpus holds both hits and misses")
  Assert.equal(#failures, 0, table.concat(failures, "\n"))
  Wow.reset()
end
