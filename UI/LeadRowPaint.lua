local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local LeadText = ns.LeadText or require("CraftAlert.UI.LeadText")

-- What a leads list row (UI/LeadRow.lua) paints for a lead, worked out without touching the row:
-- the icon, the status dot's colour, the customer and their class colour, the age, the request
-- and the marks. The row compares it with what it painted last and repaints only on a difference,
-- so a list refresh that changes nothing sets no text (the age changes with the clock, the dot
-- with WhisperMessenger's unread count, the class colour once the client knows the customer).
local LeadRowPaint = {}

local select = select
local type = type
local ipairs = ipairs

-- Whisper pink for a lead whose customer has an unread whisper, when ChatTypeInfo has no WHISPER.
local FALLBACK_PINK = { 1, 0.5, 1, 1 }

-- Every value Read fills in; two paints with these equal look the same.
local FIELDS = { "icon", "dotR", "dotG", "dotB", "dotA", "name", "nameR", "nameG", "nameB", "age", "what", "greeted", "replied" }

---@type fun(lead: table): number|nil
local unreadOf = nil -- WhisperMessenger's unread count of a lead's customer; nil: none known

-- `fn(lead) -> integer` says how many whispers of the lead's customer the player has not read in
-- WhisperMessenger (WhisperBridge.Activate sets it, through LeadRow); nil clears it.
function LeadRowPaint.SetUnreadSource(fn)
  unreadOf = fn
end

-- Whisper pink, read at paint time (the player can recolour the whisper chat type).
local function whisperPink()
  local info = _G["ChatTypeInfo"]
  local whisper = type(info) == "table" and info.WHISPER
  if type(whisper) ~= "table" then
    return FALLBACK_PINK
  end
  return { whisper.r, whisper.g, whisper.b, 1 }
end

-- The dot's colour, first match wins: pink while the customer has an unread whisper, gold while
-- the lead is unseen and ungreeted, else the details header's state colour.
local function dotColor(lead)
  local unread = unreadOf and unreadOf(lead)
  if type(unread) == "number" and unread >= 1 then
    return whisperPink()
  end
  return Leads.IsUnseen(lead) and Theme.COLORS.gold or select(2, LeadText.State(lead))
end

-- The item's icon, else the profession's, else the addon's.
local function iconOf(lead)
  local itemIcon = type(lead.itemID) == "number" and select(5, FlavorCompat.GetItemInfoInstant(lead.itemID))
  return itemIcon or FrameKit.ProfessionIcon(lead.prof) or Theme.ICON
end

-- Fills `out` with what a row shows for `lead` now; `out.dot` is the dot's colour table.
function LeadRowPaint.Read(lead, out)
  out.icon = iconOf(lead)
  local dot = dotColor(lead)
  out.dot, out.dotR, out.dotG, out.dotB, out.dotA = dot, dot[1], dot[2], dot[3], dot[4]
  out.name = LeadText.Customer(lead)
  -- A customer of unknown class: white on the row (spec D6).
  out.nameR, out.nameG, out.nameB = FrameKit.ClassRGB(FrameKit.GuidClassColor(lead.guid), Theme.COLORS.white)
  out.age = LeadText.Age(_G["time"]() - lead.time)
  out.what = LeadText.What(lead)
  out.greeted, out.replied = lead.greeted, lead.replied
end

-- Whether paints `a` and `b` (Read's tables; `a` may be nil: nothing painted yet) look the same.
function LeadRowPaint.Same(a, b)
  if a == nil then
    return false
  end
  for _, field in ipairs(FIELDS) do
    if a[field] ~= b[field] then
      return false
    end
  end
  return true
end

ns.LeadRowPaint = LeadRowPaint
return LeadRowPaint
