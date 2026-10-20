local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- Builders the toast, leads window, rows and launcher share: the WhisperMessenger panel look
-- (dark surface, 1 px border), text, the customer's class colour, and dragging with the
-- position saved account-wide in `CraftAlertDB.ui[key]` (flat { point, relativePoint, x, y },
-- plus width/height for the window).
local FrameKit = {}

local type = type

local ANCHORS = {
  TOPLEFT = true,
  TOP = true,
  TOPRIGHT = true,
  LEFT = true,
  CENTER = true,
  RIGHT = true,
  BOTTOMLEFT = true,
  BOTTOM = true,
  BOTTOMRIGHT = true,
}

function FrameKit.Fill(texture, color)
  texture:SetColorTexture(color[1], color[2], color[3], color[4])
end

-- Surface fill plus a 1 px border on each edge, all inside the frame.
function FrameKit.Panel(frame, surface)
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(frame)
  FrameKit.Fill(background, surface or Theme.COLORS.surface)
  local size = Theme.LAYOUT.BORDER
  local edges = {
    { "TOPLEFT", "TOPRIGHT", nil, size },
    { "BOTTOMLEFT", "BOTTOMRIGHT", nil, size },
    { "TOPLEFT", "BOTTOMLEFT", size, nil },
    { "TOPRIGHT", "BOTTOMRIGHT", size, nil },
  }
  for _, edge in ipairs(edges) do
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetPoint(edge[1], frame, edge[1], 0, 0)
    line:SetPoint(edge[2], frame, edge[2], 0, 0)
    if edge[3] then
      line:SetWidth(edge[3])
    else
      line:SetHeight(edge[4])
    end
    FrameKit.Fill(line, Theme.COLORS.border)
  end
  return background
end

-- One-line, left-aligned text in a Blizzard font object.
function FrameKit.Text(parent, font, color)
  local text = parent:CreateFontString(nil, "OVERLAY", font)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)
  if color then
    text:SetTextColor(color[1], color[2], color[3], color[4])
  end
  return text
end

-- RAID_CLASS_COLORS entry of the player with this chat GUID, or nil. A secret GUID or class is
-- never passed on or compared: FlavorCompat.ClassOf owns that guard. The colour table is checked
-- first, so a client without it makes no API call.
local function classColor(guid)
  local colors = _G["RAID_CLASS_COLORS"]
  if type(colors) ~= "table" then
    return nil
  end
  local classFile = FlavorCompat.ClassOf(guid)
  return classFile ~= nil and colors[classFile] or nil
end

-- Colours a customer's name by class, or in the plain text colour when the class is unknown.
function FrameKit.PaintName(text, guid)
  local color = classColor(guid)
  if color then
    text:SetTextColor(color.r, color.g, color.b, 1)
    return
  end
  local plain = Theme.COLORS.textPrimary
  text:SetTextColor(plain[1], plain[2], plain[3], plain[4])
end

local function uiTable()
  local db = _G["CraftAlertDB"]
  if type(db) ~= "table" then
    return nil
  end
  if type(db.ui) ~= "table" then
    db.ui = {}
  end
  return db.ui
end

-- The saved record for `key`, created on first use; nil when there is no account DB.
function FrameKit.Saved(key)
  local ui = uiTable()
  if ui == nil then
    return nil
  end
  if type(ui[key]) ~= "table" then
    ui[key] = {}
  end
  return ui[key]
end

local function isPlacement(saved)
  local hasAnchors = ANCHORS[saved.point] and ANCHORS[saved.relativePoint]
  return hasAnchors and type(saved.x) == "number" and type(saved.y) == "number"
end

-- Anchors the frame where it was last dropped, else at `fallback` = { point, x, y } on UIParent.
function FrameKit.Place(frame, key, fallback)
  local saved = FrameKit.Saved(key)
  frame:ClearAllPoints()
  if saved and isPlacement(saved) then
    frame:SetPoint(saved.point, _G["UIParent"], saved.relativePoint, saved.x, saved.y)
    return
  end
  frame:SetPoint(fallback[1], _G["UIParent"], fallback[1], fallback[2], fallback[3])
end

function FrameKit.SavePosition(frame, key)
  local saved = FrameKit.Saved(key)
  local point, _, relativePoint, x, y = frame:GetPoint()
  if saved == nil or not ANCHORS[point] then
    return
  end
  saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint or point, x or 0, y or 0
end

-- Left-drag moves the frame, kept on screen; the drop position is saved under `key`.
function FrameKit.Draggable(frame, key)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    FrameKit.SavePosition(self, key)
  end)
end

-- The window chrome: a title bar with the title on the left and an "X" that hides the frame.
function FrameKit.TitleBar(frame, title)
  local layout = Theme.LAYOUT
  local bar = frame:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  bar:SetHeight(layout.TITLE_BAR_HEIGHT)
  FrameKit.Fill(bar, Theme.COLORS.chrome)
  local text = FrameKit.Text(frame, Theme.FONTS.title, Theme.COLORS.textPrimary)
  text:SetPoint("LEFT", bar, "LEFT", layout.PADDING, 0)
  text:SetText(title)
  local close = _G["CreateFrame"]("Button", nil, frame)
  close:SetSize(layout.TITLE_BUTTON_SIZE, layout.TITLE_BUTTON_SIZE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  local glyph = FrameKit.Text(close, Theme.FONTS.name, Theme.COLORS.textSecondary)
  glyph:SetPoint("CENTER", close, "CENTER", 0, 0)
  glyph:SetText("X")
  close:SetScript("OnClick", function()
    frame:Hide()
  end)
end

ns.FrameKit = FrameKit
return FrameKit
