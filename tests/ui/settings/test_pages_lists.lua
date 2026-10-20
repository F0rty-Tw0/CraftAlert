local Assert = require("tests.helpers.assert")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")

local open, row, take, texts = SettingsFixture.open, SettingsFixture.row, SettingsFixture.take, SettingsFixture.texts

-- §6.2: keyword and block-list changes rebuild the index (the hot path reads copies).
local function testKeywordsPage()
  local ns, db, refreshes = SettingsFixture.load({ leads = 2 })
  local settings = db.settings
  open(ns, "Keywords")
  take(refreshes)
  Assert.equal(row("Intent words").input:GetText(), "lf lfc wtb need needs looking any any1 anyone who recraft")
  Widgets.type(row("Intent words").input, "LF  need, wtb lf")
  Assert.same(settings.intentWords, { "lf", "need", "wtb" }, "lowercase, once each")
  Assert.same(take(refreshes), { "rebuild:keywords" })
  Widgets.type(row("Intent words").input, "  ")
  Assert.same(settings.intentWords, { "lf", "lfc", "wtb", "need", "needs", "looking", "any", "any1", "anyone", "who", "recraft" })
  Assert.equal(row("Intent words").input:GetText(), "lf lfc wtb need needs looking any any1 anyone who recraft", "empty → defaults")
  take(refreshes)
  Widgets.type(row("Blocker words").input, "")
  Assert.same(settings.blockerWords, {}, "no blocker words is allowed")
  Assert.same(take(refreshes), { "rebuild:keywords" })

  -- Extra slang: word=target pairs; anything else is dropped.
  Widgets.type(row("Extra slang (word=slot)").input, "Pauldron=shoulders, hat=helm junk =x y=")
  Assert.same(settings.extraSlang, { pauldron = "shoulders", hat = "helm" })
  Assert.same(take(refreshes), { "rebuild:keywords" })
  Assert.equal(row("Extra slang (word=slot)").input:GetText(), "hat=helm pauldron=shoulders")

  -- Blocking from here works as the leads-window button: ignored, leads gone, block set rebuilt.
  Widgets.type(row("Block a player").input, "Customer1-Draenor")
  Assert.same(db.ignored, { ["Customer1-Draenor"] = true })
  Assert.equal(#db.leads, 1)
  Assert.same(take(refreshes), { "rebuild:block" })
  Assert.equal(row("Block a player").input:GetText(), "", "the box empties")
  Widgets.type(row("Block a player").input, "Other")
  Assert.truthy(db.ignored["Other-Realm"], "normalized with the player's realm")
  take(refreshes)
  Assert.truthy(texts():find("Customer1-Draenor", 1, true))
  Assert.truthy(texts():find("Other-Realm", 1, true))
  Widgets.click(SettingsFixture.button(SettingsFixture.window(), "Unblock"))
  Assert.same(db.ignored, { ["Other-Realm"] = true }, "the first row (by name) unblocked")
  Assert.same(take(refreshes), { "rebuild:block" })
  Assert.falsy(texts():find("Customer1-Draenor", 1, true))
end

return function()
  testKeywordsPage()
end
