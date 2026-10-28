local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local PlayerName = ns.PlayerName or require("CraftAlert.Core.PlayerName")
local CrafterRank = ns.CrafterRank or require("CraftAlert.Model.CrafterRank")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local ScanGate = ns.ScanGate or require("CraftAlert.Core.ScanGate")

-- The words a lead shows as: the toast, the leads list rows, the details pane (header, Quality
-- row), the tooltips and WhisperMessenger's info lines; also the test-line result words (StopText).
local LeadText = {}

local floor = math.floor
local match = string.match
local max = math.max
local tostring = tostring

local WHY_SEPARATOR = " + "

-- A lead's channel key and its word, localized when shown; ScanGate.CHANNELS owns both.
local CHANNEL_NAMES = {}

for _, channel in ipairs(ScanGate.CHANNELS) do
  CHANNEL_NAMES[channel.key] = channel.label
end

-- The matched item link, else the recipe, else the profession.
function LeadText.What(lead)
  return lead.itemLink or lead.recipeName or lead.profName or ""
end

-- Native-HUD spec §4.2: "Wants <what> — you can craft it" / "— your alt <name> can craft it"; a lead without
-- an item or recipe says "you have it" / "your alt <name> has it".
function LeadText.Headline(lead)
  local what = LeadText.What(lead)
  local craftable = lead.itemLink or lead.recipeName
  local isOwn = lead.crafter == PlayerName.Own()
  if isOwn then
    return Localization.Text(craftable and "Wants %s — you can craft it" or "Wants %s — you have it", what)
  end
  local alt = Greeting.CrafterName(lead.crafter)

  return Localization.Text(craftable and "Wants %s — your alt %s can craft it" or "Wants %s — your alt %s has it", what, alt)
end

-- The customer's chat line, trimmed.
function LeadText.Message(lead)
  return match(lead.message or "", "^%s*(.-)%s*$")
end

-- WhisperMessenger's preview, third row: "You can craft it" / "Your alt <name> can craft it"; a
-- lead without an item or recipe "You have <profession>" / "Your alt <name> has <profession>". nil
-- without a crafter.
function LeadText.CrafterLine(lead)
  if lead.crafter == nil then
    return nil
  end
  local craftable = lead.itemLink or lead.recipeName
  if lead.crafter == PlayerName.Own() then
    return craftable and Localization.Text("You can craft it") or Localization.Text("You have %s", LeadText.What(lead))
  end
  local alt = Greeting.CrafterName(lead.crafter)
  if craftable then
    return Localization.Text("Your alt %s can craft it", alt)
  end
  return Localization.Text("Your alt %s has %s", alt, LeadText.What(lead))
end

-- §4.5: "R2 (conc)" when the rank counts on concentration, "R2" when it needs none, else nil.
function LeadText.Rank(lead)
  if not lead.rank then
    return nil
  end
  if lead.rankConc then
    return Localization.Text("R%d (conc)", lead.rank)
  end
  return Localization.Text("R%d", lead.rank)
end

-- §7.2: the one realm warning (toast, crafters tooltip, details pane) when the customer cannot
-- send the crafter an order, else nil.
function LeadText.RealmTag(lead)
  if lead.cannotOrder then
    return Localization.Text("Can't send an order (other realm)")
  end
  return nil
end

-- Matcher.lastStop codes the Test page and /ca test explain in plain words.
local STOP_WORDS = {
  prefilter = "No match: the line does not look like a request",
  intent = "No match: no request word such as LF",
  blocker = "No match: it reads like a crafter's ad, or has a blocked word",
  nomatch = "No match: nothing in it that you can craft",
  noIndex = "No match: the word list is not built yet, try /reload",
}

-- The result line for a Matcher stop reason; a code without words is shown as itself.
function LeadText.StopText(reason)
  local words = STOP_WORDS[reason]

  if words then
    return Localization.Text(words)
  end

  return Localization.Text("No match (%s)", tostring(reason))
end

-- What each click on a lead does (UI/ClickRouter.lua), one tooltip instruction line each.
function LeadText.ClickLines()
  return {
    Localization.Text("Click: greet"),
    Localization.Text("Shift-click: edit first"),
    Localization.Text("Ctrl-click: empty whisper"),
    Localization.Text("Right-click: dismiss"),
  }
end

-- Details spec A.4: the rank this lead's crafter reaches with the best reagents, and what the
-- next one costs in concentration. → nil, or 1-2 lines with colour codes: nil for a profession
-- lead, or when the crafter's recipe has no reach data or no `ranks`.
function LeadText.Quality(lead, db)
  local character = db.characters[lead.crafter]
  local recipes = lead.kind == "item" and lead.recipeKey ~= nil and character and character.recipes
  local recipe = recipes and recipes[lead.recipeKey]
  local top = recipe and recipe.ranks and #recipe.ranks
  if not (recipe and recipe.reachRank and top and top > 0) then
    return nil
  end
  local reached = recipe.reachRank
  local colors = Theme.COLORS
  local rank = FrameKit.ThemeCode(Localization.Text("R%d", reached), colors.white)
  local lines = { rank .. " " .. FrameKit.ThemeCode(Localization.Text("with the best reagents"), colors.textSecondary) }
  local cost = recipe.reachCost or 0
  if reached >= top or cost <= 0 then
    return lines
  end
  rank = FrameKit.ThemeCode(Localization.Text("R%d", reached + 1), colors.white)
  local have = CrafterRank.Available(db, lead.crafter, recipe.reachConc)
  if have >= cost then
    lines[2] = rank
      .. " "
      .. FrameKit.ThemeCode(Localization.Text("with %d concentration", cost), colors.textSecondary)
      .. " "
      .. FrameKit.ThemeCode(Localization.Text("(%d left)", have - cost), colors.grey)
  else
    lines[2] = rank
      .. " "
      .. FrameKit.ThemeCode(Localization.Text("needs %d concentration", cost), colors.textSecondary)
      .. " "
      .. FrameKit.ThemeCode(Localization.Text("(you have %d)", have), colors.grey)
  end

  return lines
end

-- "35s" under a minute, else whole minutes ("2m"); leads expire within the hour.
function LeadText.Age(seconds)
  if seconds < 60 then
    return Localization.Text("%ds", max(0, floor(seconds)))
  end
  return Localization.Text("%dm", floor(seconds / 60))
end

-- The word for the lead's channel, a key the table lacks as itself, nil for a lead without one.
function LeadText.Channel(lead)
  local key = lead.channel
  if key == nil then
    return nil
  end
  local name = CHANNEL_NAMES[key]
  return name and Localization.Text(name) or tostring(key)
end

-- The parts of a why text (the Matcher joins its tokens with " + "), one per tooltip line.
function LeadText.WhyParts(why)
  local parts, from = {}, 1
  while true do
    local at = string.find(why, WHY_SEPARATOR, from, true)
    if at == nil then
      parts[#parts + 1] = string.sub(why, from)
      return parts
    end
    parts[#parts + 1] = string.sub(why, from, at - 1)
    from = at + #WHY_SEPARATOR
  end
end

-- The lead's status word (unlocalized) and its dot colour: grey new, blue greeted, green replied.
-- A replied lead was greeted (Leads.MarkReplied). The list rows and the details header's dot take
-- the colour; the header writes its own coloured words (DetailsHeader stateText) and uses this
-- word only for a new lead.
function LeadText.State(lead)
  local colors = Theme.COLORS
  if lead.replied then
    return "Greeted, replied", colors.replied
  end
  if lead.greeted then
    return "Greeted", colors.greeted
  end
  return "New lead", colors.grey
end

ns.LeadText = LeadText
return LeadText
