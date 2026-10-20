local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local function load(flavorKey)
  Wow.reset()
  Wow.flavor(flavorKey)
  return Fresh.require("Core.FlavorCompat")
end

local function testFlavorKeys()
  local expected = {
    retail = { isRetail = true, isForever = false, isClassic = false },
    forever = { isRetail = false, isForever = true, isClassic = false },
    era = { isRetail = false, isForever = false, isClassic = true },
    tbc = { isRetail = false, isForever = false, isClassic = true },
    wrath = { isRetail = false, isForever = false, isClassic = true },
    cata = { isRetail = false, isForever = false, isClassic = true },
    mop = { isRetail = false, isForever = false, isClassic = true },
  }
  for key, flags in pairs(expected) do
    local FlavorCompat = load(key)
    Assert.equal(FlavorCompat.flavorKey, key)
    Assert.equal(FlavorCompat.isRetail, flags.isRetail, key .. ".isRetail")
    Assert.equal(FlavorCompat.isForever, flags.isForever, key .. ".isForever")
    Assert.equal(FlavorCompat.isClassic, flags.isClassic, key .. ".isClassic")
  end
end

local function testForeverSignals()
  -- WOW_PROJECT_CAMELOT == WOW_PROJECT_ID alone is enough.
  Wow.reset()
  Wow.stub("WOW_PROJECT_MAINLINE", 1)
  Wow.stub("WOW_PROJECT_CAMELOT", 18)
  Wow.stub("WOW_PROJECT_ID", 18)
  Wow.stub("GetBuildInfo", nil)
  local byProject = Fresh.require("Core.FlavorCompat")
  Assert.truthy(byProject.isForever)
  Assert.equal(byProject.flavorKey, "forever")

  -- TOC 16001 on the retail engine id, no CAMELOT constant: the fallback.
  Wow.reset()
  Wow.flavor("retail")
  Wow.stub("GetBuildInfo", function()
    return "1.60.1", "70450", "Oct 1 2026", 16001
  end)
  local byToc = Fresh.require("Core.FlavorCompat")
  Assert.truthy(byToc.isForever)
  Assert.falsy(byToc.isRetail)
  Assert.equal(byToc.flavorKey, "forever")

  -- A CAMELOT constant that differs from the running project is not Forever.
  Wow.reset()
  Wow.flavor("era")
  Wow.stub("WOW_PROJECT_CAMELOT", 18)
  Assert.falsy(Fresh.require("Core.FlavorCompat").isForever)
end

local function testNoBuildInfoDefaultsToRetail()
  Wow.reset()
  Wow.stub("WOW_PROJECT_ID", nil)
  Wow.stub("GetBuildInfo", nil)
  local FlavorCompat = Fresh.require("Core.FlavorCompat")
  Assert.truthy(FlavorCompat.isRetail)
  Assert.equal(FlavorCompat.flavorKey, "retail")
end

local function testHasCraftFrame()
  local function craftFrame(key, apiPresent)
    Wow.reset()
    Wow.flavor(key)
    Wow.stub("GetCraftDisplaySkillLine", apiPresent and function() end or nil)
    return Fresh.require("Core.FlavorCompat").hasCraftFrame
  end
  Assert.equal(craftFrame("tbc", true), true)
  Assert.equal(craftFrame("era", true), true)
  Assert.equal(craftFrame("tbc", false), false)
  Assert.equal(craftFrame("wrath", true), false)
  Assert.equal(craftFrame("retail", true), false)
end

local function testWrappersPreferNamespacedApis()
  local FlavorCompat = load("retail")
  local calls = {}
  Wow.stub("SendChatMessage", function()
    calls[#calls + 1] = "global"
  end)
  Wow.stub("C_ChatInfo", {
    SendChatMessage = function(msg, chatType, lang, target)
      calls[#calls + 1] = table.concat({ msg, chatType, lang, target }, "|")
    end,
  })
  FlavorCompat.SendChatMessage("hi", "WHISPER", "Common", "Bob")
  Assert.same(calls, { "hi|WHISPER|Common|Bob" })

  Wow.stub("C_ChatInfo", nil)
  FlavorCompat.SendChatMessage("hi", "WHISPER", "Common", "Bob")
  Assert.equal(calls[2], "global")

  Wow.stub("C_Item", {
    GetItemInfoInstant = function(id)
      return id, "namespaced"
    end,
  })
  Wow.stub("GetItemInfoInstant", function(id)
    return id, "global"
  end)
  Assert.equal(select(2, FlavorCompat.GetItemInfoInstant(7)), "namespaced")
  Wow.stub("C_Item", nil)
  Assert.equal(select(2, FlavorCompat.GetItemInfoInstant(7)), "global")
  Assert.equal(FlavorCompat.GetItemInfo(7), nil)

  Wow.stub("C_AutoComplete", {
    GetAutoCompleteRealms = function()
      return { "OwnRealm" }
    end,
  })
  Assert.same(FlavorCompat.GetAutoCompleteRealms(), { "OwnRealm" })
  Wow.stub("C_AutoComplete", nil)
  Assert.equal(FlavorCompat.GetAutoCompleteRealms(), nil)
end

-- /ca perf reads the addon's memory in KB: the usage is refreshed first (the client caches it),
-- through C_AddOns when it has the functions, else the globals; nil when neither exists.
local function testAddOnMemoryUsage()
  local FlavorCompat = load("retail")
  local calls = {}
  local function api(source, usage)
    return {
      UpdateAddOnMemoryUsage = function()
        calls[#calls + 1] = source .. ":update"
      end,
      GetAddOnMemoryUsage = function(name)
        calls[#calls + 1] = source .. ":get:" .. name
        return usage
      end,
    }
  end
  local globals = api("global", 12.5)
  Wow.stub("UpdateAddOnMemoryUsage", globals.UpdateAddOnMemoryUsage)
  Wow.stub("GetAddOnMemoryUsage", globals.GetAddOnMemoryUsage)
  Assert.equal(FlavorCompat.GetAddOnMemoryUsage("CraftAlert"), 12.5)
  Assert.same(calls, { "global:update", "global:get:CraftAlert" })

  calls = {}
  Wow.stub("C_AddOns", api("namespace", 34))
  Assert.equal(FlavorCompat.GetAddOnMemoryUsage("CraftAlert"), 34)
  Assert.same(calls, { "namespace:update", "namespace:get:CraftAlert" })

  Wow.stub("C_AddOns", nil)
  Wow.stub("UpdateAddOnMemoryUsage", nil)
  Wow.stub("GetAddOnMemoryUsage", nil)
  Assert.equal(FlavorCompat.GetAddOnMemoryUsage("CraftAlert"), nil)
end

local function testTellWrappers()
  local FlavorCompat = load("retail")
  local sent = {}
  Wow.stub("ChatFrameUtil", {
    SendTellWithMessage = function(name, msg)
      sent[#sent + 1] = name .. ":" .. msg
    end,
    SendTell = function(name)
      sent[#sent + 1] = name
    end,
  })
  Assert.truthy(FlavorCompat.SendTellWithMessage("Bob-Realm", "hello"))
  Assert.truthy(FlavorCompat.SendTell("Bob-Realm"))
  Assert.same(sent, { "Bob-Realm:hello", "Bob-Realm" })

  Wow.stub("ChatFrameUtil", nil)
  Assert.falsy(FlavorCompat.SendTellWithMessage("Bob-Realm", "hello"))
  Assert.falsy(FlavorCompat.SendTell("Bob-Realm"))
end

local function testIsSecretValue()
  Wow.reset()
  Wow.stub("issecretvalue", nil)
  local without = Fresh.require("Core.FlavorCompat")
  Assert.equal(without.issecretvalue("anything"), false)

  Wow.reset()
  local FlavorCompat = Fresh.require("Core.FlavorCompat")
  Assert.equal(FlavorCompat.issecretvalue(Wow.secret("hidden")), true)
  Assert.equal(FlavorCompat.issecretvalue("plain"), false)
end

return function()
  testFlavorKeys()
  testForeverSignals()
  testNoBuildInfoDefaultsToRetail()
  testHasCraftFrame()
  testWrappersPreferNamespacedApis()
  testAddOnMemoryUsage()
  testTellWrappers()
  testIsSecretValue()
  Wow.reset()
end
