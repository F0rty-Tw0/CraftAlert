local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Fresh = require("tests.helpers.fresh")

local BS = 164
local LINK = "|cff1eff00|Hitem:501::::::::60:::::|h[Thick Plate Belt]|h|r"

-- Fresh modules for one flavor; the player is Me-Realm. → Greeting, default settings.
local function load(flavor)
  Wow.reset()
  Wow.flavor(flavor)
  Wow.stub("UnitName", function()
    return "Me"
  end)
  Wow.stub("GetNormalizedRealmName", function()
    return "Realm"
  end)
  Fresh.require("Core.FlavorCompat")
  Fresh.require("Core.Constants")
  Fresh.require("Core.PlayerName").Init()
  local Defaults = Fresh.require("Persistence.Defaults")
  return Fresh.require("Model.Greeting"), Defaults.Settings()
end

local function itemLead(crafter)
  return {
    kind = "item",
    customer = "Bob-Draenor",
    crafter = crafter,
    itemID = 501,
    itemLink = LINK,
    recipeName = "Thick Plate Belt",
    prof = BS,
    profName = "Blacksmithing",
  }
end

local function professionLead(crafter)
  return { kind = "profession", customer = "Bob-Draenor", crafter = crafter, prof = BS, profName = "Blacksmithing" }
end

return function()
  local Greeting, settings = load("retail")

  -- One template per case (§7.4): item / alt item / profession / alt profession, by whether the
  -- chosen crafter is the player's own character.
  Assert.equal(Greeting.Build(itemLead("Me-Realm"), settings), "Hi! I can craft " .. LINK .. ".")
  Assert.equal(Greeting.Build(itemLead("Alt-Realm"), settings), "Hi! My alt Alt can craft " .. LINK .. ", send the order there.")
  Assert.equal(Greeting.Build(professionLead("Me-Realm"), settings), "Hi! I have Blacksmithing, what do you need?")
  Assert.equal(Greeting.Build(professionLead("Alt-Realm"), settings), "Hi! My alt Alt has Blacksmithing, what do you need?")

  -- An alt on another realm keeps its realm; the player's own realm is dropped.
  Assert.equal(Greeting.Build(professionLead("Alt-Draenor"), settings), "Hi! My alt Alt-Draenor has Blacksmithing, what do you need?")

  -- Classic and Forever have no crafting orders: the alt item default says to whisper the alt.
  for _, flavor in ipairs({ "forever", "tbc", "era" }) do
    local greeting, flavorSettings = load(flavor)
    Assert.equal(greeting.Build(itemLead("Alt-Realm"), flavorSettings), "Hi! My alt Alt can craft " .. LINK .. ", whisper them.", flavor)
    Assert.equal(greeting.Build(itemLead("Me-Realm"), flavorSettings), "Hi! I can craft " .. LINK .. ".", flavor)
  end

  -- Every tag works in every template; the customer is greeted by name.
  local all = "{customer}/{crafter}/{item}/{profession}"
  settings.templates = { item = all, altItem = all, profession = all, altProfession = all }
  local expected = "Bob/%s/" .. LINK .. "/Blacksmithing"
  Assert.equal(Greeting.Build(itemLead("Me-Realm"), settings), string.format(expected, "Me"))
  Assert.equal(Greeting.Build(itemLead("Alt-Realm"), settings), string.format(expected, "Alt"))
  Assert.equal(Greeting.Build(professionLead("Me-Realm"), settings), "Bob/Me/Blacksmithing/Blacksmithing")
  Assert.equal(Greeting.Build(professionLead("Alt-Realm"), settings), "Bob/Alt/Blacksmithing/Blacksmithing")

  -- {item} is the recipe name without a link, and the profession for a profession lead.
  local lead = itemLead("Me-Realm")
  lead.itemLink = nil
  Assert.equal(Greeting.Build(lead, settings), "Bob/Me/Thick Plate Belt/Blacksmithing")

  -- Unknown tags, other casings and stray braces stay as written; replacement text is literal.
  settings.templates.item = "{Item} {nope} {} { item } {customer}%1 {item}"
  lead.recipeName = "100% %1 Belt"
  Assert.equal(Greeting.Build(lead, settings), "{Item} {nope} {} { item } Bob%1 100% %1 Belt")

  -- The profession's note is appended after the template; other professions' notes are not.
  settings.templates.item = "Hi {customer}."
  settings.notes = { [BS] = "Tips appreciated.", [333] = "Other." }
  Assert.equal(Greeting.Build(lead, settings), "Hi Bob. Tips appreciated.")
  settings.notes[BS] = ""
  Assert.equal(Greeting.Build(lead, settings), "Hi Bob.")
  settings.notes = {}
  Assert.equal(Greeting.Build(lead, settings), "Hi Bob.")

  -- Newlines are stripped (a line break becomes a space).
  settings.templates.item = "Hi\n{customer}.\r\n\r\nBye"
  settings.notes[BS] = "a\nb"
  Assert.equal(Greeting.Build(lead, settings), "Hi Bob. Bye a b")

  -- 255 cap: exactly 255 passes untouched, longer is cut.
  settings.notes = {}
  settings.templates.item = string.rep("x", 255)
  Assert.equal(#Greeting.Build(lead, settings), 255)
  settings.templates.item = string.rep("x", 300)
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 255))

  -- The cut never leaves half a UTF-8 character, half a hyperlink or half a colour code.
  settings.templates.item = string.rep("x", 254) .. "é"
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 254), "é takes two bytes")
  settings.templates.item = string.rep("é", 130)
  Assert.equal(Greeting.Build(lead, settings), string.rep("é", 127))
  for pad = 150, 205 do
    settings.templates.item = string.rep("x", pad) .. "{item}"
    local greeting = Greeting.Build(itemLead("Me-Realm"), settings)
    Assert.truthy(#greeting <= 255)
    local opened = select(2, string.gsub(greeting, "|H", ""))
    local closed = select(2, string.gsub(greeting, "|h", ""))
    Assert.equal(closed, opened * 2, "pad " .. pad .. " leaves a complete link or none")
    Assert.falsy(string.find(greeting, "|c%x?%x?%x?%x?%x?%x?%x?$"), "pad " .. pad)
    Assert.falsy(string.find(greeting, "|$"), "pad " .. pad)
  end
  settings.templates.item = string.rep("x", 250) .. "|cff1eff00plain|r"
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 250), "a colour code cut short is dropped")
  settings.templates.item = string.rep("x", 150) .. "{item}{item}"
  Assert.equal(Greeting.Build(itemLead("Me-Realm"), settings), string.rep("x", 150) .. LINK, "only the second link is cut")
  settings.templates.item = string.rep("x", 220) .. "{item}"
  Assert.equal(Greeting.Build(itemLead("Me-Realm"), settings), string.rep("x", 220), "a link that does not fit is dropped whole")
  settings.templates.item = string.rep("x", 190) .. "{item}"
  Assert.equal(Greeting.Build(itemLead("Me-Realm"), settings), string.rep("x", 190) .. LINK, "a link that fits stays whole")
  -- Retail's named colour form (|cnIQ4:...|r) is cut the same way, before a link and at the end.
  local namedLead = itemLead("Me-Realm")
  namedLead.itemLink = "|cnIQ4:|Hitem:190001::::::::60:::::|h[Thick Plate Belt]|h|r"
  settings.templates.item = string.rep("x", 190) .. "{item}"
  Assert.equal(Greeting.Build(namedLead, settings), string.rep("x", 190) .. namedLead.itemLink, "a named-colour link that fits stays whole")
  settings.templates.item = string.rep("x", 220) .. "{item}"
  Assert.equal(Greeting.Build(namedLead, settings), string.rep("x", 220), "the cut link takes its named colour with it")
  for pad = 150, 250 do
    settings.templates.item = string.rep("x", pad) .. "{item}"
    local greeting = Greeting.Build(namedLead, settings)
    Assert.truthy(#greeting <= 255)
    local opened = select(2, string.gsub(greeting, "|H", ""))
    local closed = select(2, string.gsub(greeting, "|h", ""))
    Assert.equal(closed, opened * 2, "pad " .. pad .. " leaves a complete link or none")
    Assert.falsy(string.find(greeting, "|cn[%w_]*:?$"), "pad " .. pad .. " ends in a named colour start")
  end
  for _, pad in ipairs({ 248, 249, 250, 252, 253 }) do -- the cut keeps "|cnIQ4:", "|cnIQ4", "|cnIQ", "|cn", "|c"
    settings.templates.item = string.rep("x", pad) .. "|cnIQ4:abc"
    Assert.equal(Greeting.Build(lead, settings), string.rep("x", pad), "pad " .. pad .. " drops the colour start")
  end
  settings.templates.item = string.rep("x", 254) .. "||"
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 254), "an escaped pipe is not cut in half")
  -- Dropping a colour start can expose a lone pipe, and the pipe trim can expose a colour start:
  -- either order alone leaves one of these broken, so no cut may end in an odd run of pipes.
  for _, tail in ipairs({ "||cafe", "||cnot", "||c", "|cnIQ4:|Hitem:1|h[a]|h|r" }) do
    for pad = 240, 254 do
      settings.templates.item = string.rep("x", pad) .. tail
      local greeting = Greeting.Build(lead, settings)
      Assert.equal(#string.match(greeting, "|*$") % 2, 0, "pad " .. pad .. " " .. tail .. " ends in a lone pipe")
      local pipes = string.match(greeting, "(|+)c[%xn]?[%w_]*:?$")
      Assert.falsy(pipes and #pipes % 2 == 1, "pad " .. pad .. " " .. tail .. " ends in a colour start")
    end
  end
  -- An escaped pipe ("||") is a literal "|", so the "c..." after it is text, not a colour code:
  -- a cut right after it keeps it.
  for _, tail in ipairs({ "||cafe", "||cnot", "||c", "||cnIQ4:" }) do
    local pad = 255 - #tail
    settings.templates.item = string.rep("x", pad) .. tail .. "zz"
    Assert.equal(Greeting.Build(lead, settings), string.rep("x", pad) .. tail, tail .. " is kept")
  end
  settings.templates.item = string.rep("x", 200) .. "||cffffffff|Hitem:1|h[" .. string.rep("a", 60) .. "]|h"
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 200) .. "||cffffffff", "the escaped text before a cut link stays")
  settings.templates.item = string.rep("x", 248) .. "|||cafe" .. "zz"
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 248) .. "||", "an escaped pipe, then a real colour start")
  -- An escaped "||H" is text, not a link start: the cut keeps everything up to the limit.
  local escapedH = string.rep("x", 200) .. "||Hello " .. string.rep("y", 60)
  settings.templates.item = escapedH
  Assert.equal(Greeting.Build(lead, settings), string.sub(escapedH, 1, 255), "an escaped ||H is not a half link")
  -- A real link after an escaped pipe ("|||H...") is still cut whole.
  settings.templates.item = string.rep("x", 200) .. "|||Hitem:1|h[" .. string.rep("a", 60) .. "]|h"
  Assert.equal(Greeting.Build(lead, settings), string.rep("x", 200) .. "||", "a real link after an escaped pipe")
end
