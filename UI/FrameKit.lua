local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local FlavorCompat = ns.FlavorCompat or require("CraftAlert.Core.FlavorCompat")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")

-- Builders the toast, leads window, cards, launcher and settings share: text, colour codes, the
-- customer's class colour, atlas-or-file art, list highlight, and dragging with the position saved
-- account-wide in `CraftAlertDB.ui[key]`.
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

-- True when the client knows the atlas. C_Texture is read through _G (luacheck's read_globals
-- lacks it); a raising GetAtlasInfo counts as unknown.
local function atlasExists(atlas)
  local api = _G["C_Texture"]
  if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then
    return false
  end
  local ok, info = pcall(api.GetAtlasInfo, atlas)

  return ok and type(info) == "table"
end

-- Draws `atlas` on the texture; when the client lacks it, `fallbackFile`; with neither, hides the
-- texture. `blend` (when given) is set on a texture that stays visible. True only for the atlas.
function FrameKit.Art(texture, atlas, fallbackFile, blend)
  local hasAtlas = atlasExists(atlas)
  if hasAtlas then
    texture:SetAtlas(atlas)
  elseif fallbackFile then
    texture:SetTexture(fallbackFile)
  else
    texture:Hide()

    return false
  end
  if blend then
    texture:SetBlendMode(blend)
  end

  return hasAtlas
end

-- The quest-log hover highlight over the whole of `button`, shown by the client while hovered.
function FrameKit.ListHighlight(button)
  local texture = button:CreateTexture(nil, "HIGHLIGHT")
  texture:SetAllPoints(button)
  texture:SetTexture(Theme.ART.LIST_HOVER)
  texture:SetBlendMode("ADD")
  texture:SetAlpha(Theme.ART.LIST_HOVER_ALPHA)

  return texture
end

-- RAID_CLASS_COLORS entry of a class token, or nil. A client without the table makes no lookup.
function FrameKit.ClassColor(token)
  local colors = _G["RAID_CLASS_COLORS"]
  if type(colors) ~= "table" or type(token) ~= "string" then
    return nil
  end

  return colors[token]
end

-- The client's icon for a profession skill-line ID, or nil: Classic name keys and a client without
-- the API have none. C_TradeSkillUI is read through _G (luacheck's read_globals lacks it).
function FrameKit.ProfessionIcon(prof)
  local api = _G["C_TradeSkillUI"]
  local canAsk = type(prof) == "number" and type(api) == "table" and type(api.GetTradeSkillTexture) == "function"
  if not canAsk then
    return nil
  end

  return api.GetTradeSkillTexture(prof)
end

-- RAID_CLASS_COLORS entry of the player with this chat GUID, or nil. A secret GUID or class is
-- never passed on or compared: FlavorCompat.ClassOf owns that guard. The colour table is checked
-- first, so a client without it makes no API call.
function FrameKit.GuidClassColor(guid)
  if type(_G["RAID_CLASS_COLORS"]) ~= "table" then
    return nil
  end

  return FrameKit.ClassColor(FlavorCompat.ClassOf(guid))
end

-- `text` in r, g, b as a colour code. From r/g/b only: a RAID_CLASS_COLORS entry may lack colorStr.
function FrameKit.ColorCode(text, r, g, b)
  return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) .. text .. "|r"
end

-- Colours a customer's name by class, or in the plain text colour when the class is unknown.
function FrameKit.PaintName(text, guid)
  local color = FrameKit.GuidClassColor(guid)
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

ns.FrameKit = FrameKit
return FrameKit
