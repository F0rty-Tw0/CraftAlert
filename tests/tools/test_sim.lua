local Assert = require("tests.helpers.assert")
local Toc = require("tests.helpers.toc")

return function()
  _G.CRAFTALERT_SIM_NO_MAIN = true
  local Sim = dofile("tools/sim.lua")

  local header = tostring(Sim.Run({})[1])
  assert(string.match(header, "^sim: flavor=retail modules=%d+$"), "bad header: " .. tostring(header))

  Assert.equal(Sim.Run({ "--flavor", "tbc" })[1], (string.gsub(header, "retail", "tbc")))

  -- The header's flavor comes from FlavorCompat, fed only by the build stubs.
  for _, key in ipairs({ "retail", "forever", "era", "tbc", "wrath", "cata", "mop" }) do
    Assert.equal(Sim.Run({ "--flavor", key })[1], string.format("sim: flavor=%s modules=%d", key, #Toc.luaFiles()))
    Assert.equal(Sim.lastNs.FlavorCompat.flavorKey, key)
  end
  Sim.Run({ "--flavor", "forever" })
  Assert.truthy(rawget(_G, "WOW_PROJECT_CAMELOT"))
  Assert.equal(rawget(_G, "WOW_PROJECT_CAMELOT"), rawget(_G, "WOW_PROJECT_ID"))

  -- Chat prints and sends land in the returned lines (the table stays live after Run).
  local lines = Sim.Run({})
  Sim.lastNs.ChatPrint.Line("hello")
  Assert.equal(lines[#lines], "chat: Craft Alert: hello")
  rawget(_G, "SendChatMessage")("hi", "WHISPER", nil, "Bob-Realm")
  Assert.equal(lines[#lines], "send: SendChatMessage hi | WHISPER | nil | Bob-Realm")

  -- Each chat line reports its normalized sender; --sender applies to the next line only.
  local senders = Sim.Run({ "--sender", "Zoë-Kel'Thuzad", "LF belt", "LF boots", "--sender", "Bob-Area 52", "LF ring" })
  Assert.same({ senders[2], senders[3], senders[4] }, {
    "sender: Zoë-Kel'Thuzad",
    "sender: Customer-OtherRealm",
    "sender: Bob-Area52",
  })
  Assert.equal(Sim.Run({ "--sender", "Bob", "hi" })[2], "sender: Bob-OwnRealm")

  local unknownFlag = Sim.Run({ "--nope" })
  Assert.equal(#unknownFlag, 1)
  assert(string.find(tostring(unknownFlag[1]), "^error: unknown flag"), unknownFlag[1])

  assert(string.find(Sim.Run({ "--flavor", "cataclysm" })[1], "^error: unknown flavor"))
  assert(string.find(Sim.Run({ "--flavor" })[1], "^error: .* needs a value"))
  assert(string.find(Sim.Run({ "--db", "tools/does_not_exist.lua" })[1], "^error: cannot read db"))
  assert(string.find(Sim.Run({ "--click", "middle" })[1], "^error: "))

  -- The default fixture is the account DB before any module touches it.
  Sim.Run({})
  local db = rawget(_G, "CraftAlertDB")
  Assert.truthy(db.characters["Crafter-OwnRealm"])
  Assert.truthy(db.characters["Alt-OwnRealm"])

  -- --afk applies before the first chat line.
  Sim.Run({ "--afk", "on", "--resting", "off", "LF plate belt" })
  Assert.equal(rawget(_G, "UnitIsAFK")("player"), true)
  Assert.equal(rawget(_G, "IsResting")(), false)
  Sim.Run({ "--afk", "off" })
  Assert.equal(rawget(_G, "UnitIsAFK")("player"), false)
  Assert.equal(rawget(_G, "IsResting")(), true)

  -- Commands without a registered handler report it instead of crashing.
  assert(string.find(tostring(Sim.Run({ "--cmd", "/ca" })[2]), "^error: no slash handler"))
end
