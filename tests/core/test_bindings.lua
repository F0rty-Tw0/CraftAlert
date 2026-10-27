local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local UiFixture = require("tests.helpers.ui_fixture")
local FakeWm = require("tests.helpers.fake_wm_api")

local function G(name)
  return rawget(_G, name)
end

-- Binding names and the function each <Binding> body calls, from Bindings.xml.
local function xmlBindings()
  local handle = assert(io.open("Bindings.xml", "r"))
  local xml = handle:read("*a")
  handle:close()
  local found = {}
  for name, body in string.gmatch(xml, '<Binding name="([%w_]+)"[^>]*>%s*(.-)%s*</Binding>') do
    found[#found + 1] = { name = name, call = string.match(body, "^([%w_]+)%(%)$") }
  end
  return found
end

local function testGlobalsMatchBindingsXml()
  UiFixture.load()
  local bindings = xmlBindings()
  Assert.equal(#bindings, 3)
  Assert.equal(type(G("BINDING_HEADER_CRAFTALERT")), "string")
  for _, binding in ipairs(bindings) do
    Assert.equal(type(G("BINDING_NAME_" .. binding.name)), "string", "label for " .. binding.name)
    Assert.equal(type(G(binding.call)), "function", binding.call .. " is defined")
  end
end

-- In an instance each key prints the off line once and does nothing else: nothing greeted,
-- dismissed or opened.
local function testOffInInstance()
  local ns, _, calls = UiFixture.load({ leads = 2 })
  Wow.stub("IsInInstance", function()
    return true, "party"
  end)
  for _, name in ipairs({ "CraftAlert_GreetLatest", "CraftAlert_DismissLatest", "CraftAlert_ToggleLeads" }) do
    Wow.chat = {}
    G(name)()
    Assert.same(Wow.chat, { "|cffffd100Craft Alert:|r Off in instances; it works again when you leave." }, name)
  end
  Assert.same(calls, {}, "nothing sent or prefilled")
  Assert.equal(#ns.Leads.List(), 2, "not dismissed")
  local window = G("CraftAlertLeadsWindow")
  Assert.equal(window ~= nil and window:IsShown(), false, "no window")
  Wow.stub("IsInInstance", nil)
end

local function testGreetLatest()
  -- Nothing on screen: the keybind prefills the latest lead (§7.5 rule 3), never sends.
  local calls = select(3, UiFixture.load({ leads = 2 }))
  G("CraftAlert_GreetLatest")()
  Assert.same(calls, { { "prefill", "Customer2-Draenor", "Hi! I have Blacksmithing, what do you need?" } })

  -- The toast has shown the latest lead for 0.5 s or more: the keybind greets it.
  local ns, _
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.AlertToast.Show(ns.Leads.Latest())
  Wow.clock.gettime = 50.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)
  Assert.equal(ns.Leads.Latest().greeted, true)

  -- The same through the leads window's top row; under 0.5 s it still prefills.
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.LeadsWindow.Toggle()
  Wow.clock.gettime = 50.2
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0)
  Assert.equal(#UiFixture.callsTo(calls, "prefill"), 1)
  Wow.clock.gettime = 51
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)

  -- Shown in both, the lead counts as on screen since the earlier of the two: the window's top
  -- row from 50, the toast only from 50.3.
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.LeadsWindow.Toggle()
  Wow.clock.gettime = 50.3
  ns.AlertToast.Show(ns.Leads.Latest())
  Wow.clock.gettime = 50.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)

  -- The toast showing an older lead does not count for the latest one.
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.AlertToast.Show(ns.Leads.List()[2])
  Wow.clock.gettime = 60
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0)
  Assert.equal(UiFixture.callsTo(calls, "prefill")[1][2], "Customer2-Draenor")

  -- With the UI hidden (Alt+Z) the toast and window stay "shown" but nothing is on screen: the
  -- keybind only prefills.
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.AlertToast.Show(ns.Leads.Latest())
  ns.LeadsWindow.Toggle()
  Wow.clock.gettime = 60
  G("UIParent"):Hide()
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0)
  Assert.equal(UiFixture.callsTo(calls, "prefill")[1][2], "Customer2-Draenor")
  Assert.equal(ns.Leads.Latest().greeted, false)

  -- Shown again after Alt+Z, the toast's lead counts as on screen from then: the time under the
  -- hidden UI is no look (§7.5 rule 3). Within 0.5 s the keybind prefills, after it greets.
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.AlertToast.Show(ns.Leads.Latest())
  Wow.clock.gettime = 55
  G("UIParent"):Hide()
  Wow.clock.gettime = 58
  G("UIParent"):Show()
  Wow.clock.gettime = 58.01
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0, "the toast was back on screen for 10 ms")
  Assert.equal(#UiFixture.callsTo(calls, "prefill"), 1)
  Wow.clock.gettime = 58.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)

  -- The same for the leads window's top row.
  ns, _, calls = UiFixture.load({ leads = 2 })
  ns.LeadsWindow.Toggle()
  Wow.clock.gettime = 55
  G("UIParent"):Hide()
  Wow.clock.gettime = 58
  G("UIParent"):Show()
  Wow.clock.gettime = 58.01
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0, "the row was back on screen for 10 ms")
  Assert.equal(#UiFixture.callsTo(calls, "prefill"), 1)
  Wow.clock.gettime = 58.6
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1)

  -- No lead: nothing happens.
  calls = select(3, UiFixture.load())
  G("CraftAlert_GreetLatest")()
  Assert.same(calls, {})
end

local function testDismissAndToggle()
  local ns = UiFixture.load({ leads = 2 })
  G("CraftAlert_DismissLatest")()
  Assert.equal(ns.Leads.Latest().id, 1)
  G("CraftAlert_DismissLatest")()
  Assert.equal(ns.Leads.HasActive(), false)
  G("CraftAlert_DismissLatest")()
  G("CraftAlert_ToggleLeads")()
  Assert.equal(G("CraftAlertLeadsWindow"):IsShown(), true)
  G("CraftAlert_ToggleLeads")()
  Assert.equal(G("CraftAlertLeadsWindow"):IsShown(), false)

  -- A fresh install whose saved data failed to load: the key does nothing, no error.
  UiFixture.load()
  local saved = _G["CraftAlertDB"]
  _G["CraftAlertDB"] = nil
  local ok, err = pcall(G("CraftAlert_ToggleLeads"))
  _G["CraftAlertDB"] = saved
  Assert.equal(ok, true, tostring(err))
  Assert.equal(G("CraftAlertLeadsWindow"), nil, "no window is built without saved data")
end

-- §7.5 rule 3: the key keeps a latest lead the toast or the window top row has shown for under
-- 0.5 s, and dismisses it from 0.5 s on.
local function testDismissLooks()
  for _, show in ipairs({ "toast", "window" }) do
    local ns = UiFixture.load({ leads = 2 })
    if show == "toast" then
      ns.AlertToast.Show(ns.Leads.Latest())
    else
      ns.LeadsWindow.Toggle()
    end
    Wow.clock.gettime = 50.2
    G("CraftAlert_DismissLatest")()
    Assert.equal(ns.Leads.Latest().id, 2, show .. ": shown 0.2 s")
    Wow.clock.gettime = 50.6
    G("CraftAlert_DismissLatest")()
    Assert.equal(ns.Leads.Latest().id, 1, show .. ": shown 0.6 s")
  end
end

-- Bridged (spec C.2): WhisperMessenger's preview is the toast, so the keys count it as on screen;
-- the full state rows are in tests/ui/test_whisper_bridge_states.lua.
local function testBridgedKeybinds()
  local ns, _, calls = UiFixture.load({ leads = 2 })
  local _, wm = FakeWm.install()
  ns.WhisperBridge.Activate()
  ns.WhisperBridge.ShowLead(ns.Leads.Latest())
  Wow.clock.gettime = 50.2
  G("CraftAlert_DismissLatest")()
  Assert.equal(ns.Leads.Latest().id, 2, "preview up 0.2 s: the lead stays")
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 0)
  Assert.equal(#wm.callsTo("OpenConversation"), 1, "under 0.5 s: the greeting is a draft in WM")
  Wow.clock.gettime = 51
  G("CraftAlert_GreetLatest")()
  Assert.equal(#UiFixture.callsTo(calls, "chat"), 1, "the preview counts as shown")
end

return function()
  testGlobalsMatchBindingsXml()
  testOffInInstance()
  testGreetLatest()
  testDismissAndToggle()
  testDismissLooks()
  testBridgedKeybinds()
  Wow.reset()
  Assert.equal(G("CraftAlert_GreetLatest"), nil, "the stubs are removed again")
end
