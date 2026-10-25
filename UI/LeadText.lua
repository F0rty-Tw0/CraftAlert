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

-- The words a lead shows as: the toast, the leads list rows, the details pane (header, Quality
-- row), the tooltips and WhisperMessenger's info lines.
local LeadText = {}

local floor = math.floor
local max = math.max
local tostring = tostring

-- A lead's channel key and its word, localized when shown. Only the keys come from
-- Core/ScanGate.lua:33; the words are the lead-cards spec's (§2.1), not the status line's.
local CHANNEL_NAMES = {
  trade = "Trade",
  services = "Services",
  general = "General",
  lfg = "LFG",
  guild = "Guild",
  communities = "Community",
}

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

-- §7.2: "can't order (realm)" when the customer cannot send the crafter an order, else nil.
function LeadText.RealmTag(lead)
  if lead.cannotOrder then
    return Localization.Text("can't order (realm)")
  end
  return nil
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

-- The lead's status word (unlocalized) and its dot colour, for the details header and the list
-- rows: grey new, green greeted, accent replied. A replied lead was greeted (Leads.MarkReplied).
function LeadText.State(lead)
  local colors = Theme.COLORS
  if lead.replied then
    return "Greeted, replied", colors.accent
  end
  if lead.greeted then
    return "Greeted", colors.greeted
  end
  return "New lead", colors.grey
end

ns.LeadText = LeadText
return LeadText
