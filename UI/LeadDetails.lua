local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Greeting = ns.Greeting or require("CraftAlert.Model.Greeting")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")
local LinkHover = ns.LinkHover or require("CraftAlert.UI.LinkHover")

-- Leads-details spec §4: the details pane right of the leads window's list column. It shows one
-- lead: the pinned one (a row's hover pins it) while it is listed, else the newest; nothing for an
-- empty list. Leaving the rows, scrolling and new leads keep the pin; the window clears it on
-- open, on the way back from the settings, and hides the pane while they show.
local LeadDetails = {}

local concat = table.concat
local sort = table.sort
local tostring = tostring
local type = type

local LINE_GAP = 6

-- A wrapped line under `above`, as wide as the pane.
local function addLine(pane, above, font, color)
  local line = FrameKit.Text(pane, font, color)
  line:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LINE_GAP)
  line:SetPoint("RIGHT", pane, "RIGHT", -Theme.LAYOUT.PADDING, 0)
  line:SetJustifyV("TOP")
  line:SetWordWrap(true)
  return line
end

-- The pane takes the left-drag over its half of the window: the window's own drag handlers (set
-- by FrameKit.Draggable, which saves the position) run for it, with the window as `self`.
local function forwardDrag(pane, window, script)
  pane:SetScript(script, function()
    window:GetScript(script)(window)
  end)
end

-- The hidden pane in `inset` (the window's inset), right of the list column.
function LeadDetails.New(inset)
  local layout, colors, fonts = Theme.LAYOUT, Theme.COLORS, Theme.FONTS
  local pane = _G["CreateFrame"]("Frame", nil, inset)
  pane:SetPoint("TOPLEFT", inset, "TOPLEFT", layout.LIST_COLUMN_WIDTH, 0)
  pane:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
  -- Mouse on, so the message's links get their hyperlink scripts.
  pane:EnableMouse(true)
  pane:RegisterForDrag("LeftButton")
  forwardDrag(pane, inset:GetParent(), "OnDragStart")
  forwardDrag(pane, inset:GetParent(), "OnDragStop")
  pane.name = FrameKit.Text(pane, fonts.name)
  pane.name:SetPoint("TOPLEFT", pane, "TOPLEFT", layout.PADDING, -layout.PADDING)
  pane.age = FrameKit.Text(pane, fonts.detail, colors.textTimestamp)
  pane.age:SetPoint("LEFT", pane.name, "RIGHT", 6, 0)
  pane.message = addLine(pane, pane.name, fonts.body, colors.textPrimary)
  pane.why = addLine(pane, pane.message, fonts.body, colors.textSecondary)
  pane.profession = addLine(pane, pane.why, fonts.body, colors.textSecondary)
  pane.crafters = addLine(pane, pane.profession, fonts.body, colors.textSecondary)
  LinkHover.Attach(pane, nil)
  pane:Hide()
  return pane
end

function LeadDetails.Pin(pane, leadId)
  pane.pinnedId = leadId
end

function LeadDetails.Unpin(pane)
  pane.pinnedId = nil
end

-- The pinned lead while `leads` lists it, else the newest. A pin whose lead is gone is dropped.
local function pick(pane, leads)
  for _, lead in ipairs(leads) do
    if lead.id == pane.pinnedId then
      return lead
    end
  end
  pane.pinnedId = nil
  return leads[1]
end

-- A { key = string, rank = number or nil } entry.
local function isCrafter(entry)
  return type(entry) == "table" and type(entry.key) == "string" and (entry.rank == nil or type(entry.rank) == "number")
end

-- lead.crafters' valid entries (a newer schema's data is kept as it is, by Schema); a restored lead
-- has none, or no usable one: its picked crafter alone.
local function craftersOf(lead)
  local valid = {}
  for _, entry in ipairs(type(lead.crafters) == "table" and lead.crafters or {}) do
    if isCrafter(entry) then
      valid[#valid + 1] = entry
    end
  end
  if #valid > 0 then
    return valid
  end
  if lead.crafter == nil then
    return {}
  end
  return { { key = lead.crafter, rank = lead.rank, byConc = lead.rankConc } }
end

local function crafterLine(line)
  if line.rank == nil then
    return line.name
  end
  return line.name .. " · " .. line.rank
end

local function pickedFirst(a, b)
  if a.picked ~= b.picked then
    return a.picked
  end
  return a.name < b.name
end

-- "Crafters:" and a line each, the picked crafter first, then the rest by the name shown.
local function craftersText(lead)
  local lines = {}
  for _, crafter in ipairs(craftersOf(lead)) do
    local ranked = { rank = crafter.rank, rankConc = crafter.byConc }
    lines[#lines + 1] = {
      picked = crafter.key == lead.crafter,
      name = Greeting.CrafterName(crafter.key),
      rank = LeadText.Rank(ranked),
    }
  end
  if #lines == 0 then
    return Localization.Text("Crafters: none known")
  end
  sort(lines, pickedFirst)
  local texts = { Localization.Text("Crafters:") }
  for _, line in ipairs(lines) do
    texts[#texts + 1] = crafterLine(line)
  end
  return concat(texts, "\n")
end

-- Sets `line` to `text`, hidden when the lead has no such field (nil).
local function setLine(line, text)
  if text == nil then
    line:Hide()
    return
  end
  line:SetText(text)
  line:Show()
end

local function paint(pane, lead)
  pane.name:SetText(tostring(lead.customer))
  FrameKit.PaintName(pane.name, lead.guid)
  pane.age:SetText(LeadText.Age(_G["time"]() - lead.time))
  setLine(pane.message, lead.message)
  setLine(pane.why, lead.why and Localization.Text("Matched: %s", lead.why))
  setLine(pane.profession, lead.profName)
  pane.crafters:SetText(craftersText(lead))
end

-- Shows the chosen lead of `leads` (newest first, as Leads.List()), or hides the pane when
-- there is none.
function LeadDetails.Refresh(pane, leads)
  local lead = pick(pane, leads)
  if pane.lead ~= lead then
    -- The link under the cursor belonged to the old lead.
    LinkHover.Clear(pane)
  end
  pane.lead = lead
  if lead == nil then
    pane:Hide()
    return
  end
  paint(pane, lead)
  pane:Show()
end

-- The lead the pane shows, or nil while it is hidden.
function LeadDetails.Shown(pane)
  if not pane:IsShown() then
    return nil
  end
  return pane.lead
end

ns.LeadDetails = LeadDetails
return LeadDetails
