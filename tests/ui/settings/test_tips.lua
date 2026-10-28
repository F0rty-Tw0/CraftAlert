local Assert = require("tests.helpers.assert")
local Widgets = require("tests.helpers.widgets")
local SettingsFixture = require("tests.helpers.settings_fixture")
local CraftersFixture = require("tests.helpers.crafters_fixture")

-- { page title, row label, tip text }: the "Tip strings" table of the plan, row for row.
local TIPS = {
  { "General", "Enable Craft Alert", "Turns scanning on or off. Off, Craft Alert reads no chat and shows no alerts." },
  {
    "General",
    "Only where Trade chat exists",
    "Scans only while a Trade channel is available to you, as in a major city. Elsewhere scanning pauses and resumes on its own.",
  },
  {
    "General",
    "Profession-word alerts",
    'Also alerts when a line names only a profession, such as "LF blacksmith", with no item. Off, only requests for an item you can craft alert.',
  },
  {
    "General",
    "Bell markers on recipe rows",
    "Draws a mute switch on each recipe in the profession window. Click it to mute or unmute that recipe.",
  },
  { "Alerts", "Alert sound", "The sound played with each new lead. Play tries the chosen one; None is silent." },
  {
    "Alerts",
    "Flash the taskbar icon",
    "Flashes the game's taskbar icon on a new lead while the game is in the background.",
  },
  { "Alerts", "Toast duration", "How long the alert toast stays on screen before it hides on its own." },
  { "Alerts", "Lead timeout", "How long a lead stays in the list before it expires and is removed." },
  {
    "Alerts",
    "Hide the launcher when there are no leads",
    "Hides the launcher button while there are no leads. It returns with the next lead.",
  },
  { "Alerts", "Opacity", "How see-through the leads window and the toast are." },
  {
    "Keywords",
    "Intent words",
    "Words that mark a request, such as lf or wtb. A line needs one of them to count as a request. Emptied, the default list returns.",
  },
  {
    "Keywords",
    "Blocker words",
    "Words that cancel a match, such as wts. A line with one of them never alerts.",
  },
  {
    "Keywords",
    "Extra slang (word=slot)",
    "Teach Craft Alert a word it does not know. Each word=target pair makes your word mean that slot or armor type.",
  },
  {
    "Greetings",
    "Item",
    "Whispered when you click Greet on a request for an item you can craft yourself.",
  },
  {
    "Greetings",
    "Alt item",
    "Whispered for an item one of your alts crafts. {crafter} is that alt, so the buyer knows who to ask.",
  },
  { "Greetings", "Profession", "Whispered when a request names only a profession and you have it." },
  {
    "Greetings",
    "Alt profession",
    "Whispered when a request names only a profession and one of your alts has it.",
  },
  {
    "Greetings",
    "Note",
    "Added after the greeting for the profession chosen above. Leave it empty for no note.",
  },
}

-- The Crafters page's rows and buttons ({ page, label, text, button? }), found on a page with recipes.
local MUTE_TEXT = "%s every recipe the list shows. With a search typed, only the recipes it finds."
local CRAFTERS = {
  { "Crafters", "Character", "Pick whose professions and recipes this page shows." },
  { "Crafters", "Listen for this character", "Alerts for this character's recipes. Off, its recipes are left out of matching." },
  {
    "Crafters",
    "Remove character",
    "Deletes this character's saved professions and recipes. It asks for a second click. Your logged-in character comes back empty until you open a profession window.",
    true,
  },
  {
    "Crafters",
    "Main crafter for this profession",
    "When several of your characters can craft a request, this one is chosen first and gets the greeting. One main crafter per profession.",
  },
  { "Crafters", "Search recipes", "Type part of a recipe's name. The list narrows as you type." },
  { "Crafters", "Mute all", MUTE_TEXT:format("Mutes"), true },
  { "Crafters", "Unmute all", MUTE_TEXT:format("Unmutes"), true },
}

local function hover(frame)
  Widgets.fire(frame, "OnEnter")
  local tip = _G["CraftAlertTooltip"]
  local seen = { owner = tip.owner, lines = tip.lines, colors = tip.colors }
  Widgets.fire(frame, "OnLeave")
  return seen
end

local function check(ns, entry)
  local page, label, text, isButton = entry[1], entry[2], entry[3], entry[4]
  SettingsFixture.open(ns, page)
  local frame = isButton and SettingsFixture.button(SettingsFixture.window(), label) or SettingsFixture.row(label)
  local seen = hover(frame)
  Assert.same(seen.lines, { label, text }, page .. " / " .. label)
  Assert.same(seen.colors, { { 1, 0.82, 0 }, { 1, 1, 1 } }, label)
  Assert.truthy(#text <= 240, label .. " tip is too long for a short tooltip")
end

return function()
  local ns = SettingsFixture.load()
  for _, entry in ipairs(TIPS) do
    check(ns, entry)
  end

  ns = SettingsFixture.load({ db = CraftersFixture.crafters })
  for _, entry in ipairs(CRAFTERS) do
    check(ns, entry)
  end

  -- C8: the Only button shows only for a profession with recipe lines; its title is its current text.
  local only_ns, db = SettingsFixture.load({ db = CraftersFixture.crafters })
  db.characters["Me-Realm"].recipes[9001].line = 2822
  SettingsFixture.open(only_ns, "Crafters")
  local only = SettingsFixture.button(SettingsFixture.window(), "Only current expansion")
  local text = "Alerts only for this expansion's recipes: all older ones are muted and your own picks are replaced."
  Assert.same(hover(only).lines, { "Only current expansion", text })
  only.label:SetText("Only Dragonflight")
  Assert.same(hover(only).lines, { "Only Dragonflight", text }, "title follows the button text")
end
