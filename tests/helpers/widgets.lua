-- Widget methods for the stub frames of tests/helpers/wow.lua, so UI modules run in plain Lua.
-- Setters store what they were given and getters read it back; anything the client draws
-- (fonts, textures, layout) is only recorded.
--   Widgets.extend(frame)           adds region, frame and child-creation methods
--   Widgets.click(frame, button)    runs the OnClick script as a mouse click would
--   Widgets.texts(frame, frames)    the shown texts under frame (itself and its descendants
--                                   among `frames`, usually Wow.frames), in creation order
local Widgets = {}

local function addRegion(region)
  region.points = {}
  region.alpha = 1
  region.width, region.height = 0, 0

  function region:SetPoint(point, relativeTo, relativePoint, x, y)
    table.insert(self.points, { point, relativeTo, relativePoint, x, y })
  end

  function region:ClearAllPoints()
    self.points = {}
  end

  function region:SetAllPoints(target)
    self.points = { { "ALL", target } }
  end

  -- The first anchor, as the client reports it: point, relativeTo, relativePoint, x, y.
  function region:GetPoint()
    local first = self.points[1]
    if first == nil then
      return nil
    end
    return first[1], first[2], first[3], first[4], first[5]
  end

  function region:SetSize(width, height)
    self.width, self.height = width, height
  end

  function region:SetWidth(width)
    self.width = width
  end

  function region:SetHeight(height)
    self.height = height
  end

  function region:GetWidth()
    return self.width
  end

  function region:GetHeight()
    return self.height
  end

  function region:SetAlpha(alpha)
    self.alpha = alpha
  end

  function region:GetAlpha()
    return self.alpha
  end
end

local function newTexture(parent, layer)
  local texture = { shown = true, parent = parent, layer = layer }
  addRegion(texture)

  function texture:SetColorTexture(r, g, b, a)
    self.color = { r, g, b, a }
  end

  function texture:SetTexture(path)
    self.texture = path
  end

  function texture:SetTexCoord(...)
    self.texCoord = { ... }
  end

  function texture:SetVertexColor(r, g, b, a)
    self.vertexColor = { r, g, b, a }
  end

  function texture:SetDesaturated(desaturated)
    self.desaturated = desaturated
  end

  function texture:Show()
    self.shown = true
  end

  function texture:Hide()
    self.shown = false
  end

  function texture:IsShown()
    return self.shown
  end

  return texture
end

local function newFontString(parent, layer, template)
  local fontString = { shown = true, parent = parent, layer = layer, font = template, text = nil }
  addRegion(fontString)

  function fontString:SetText(text)
    self.text = text
  end

  function fontString:GetText()
    return self.text
  end

  function fontString:SetTextColor(r, g, b, a)
    self.textColor = { r, g, b, a }
  end

  function fontString:SetFontObject(font)
    self.font = font
  end

  function fontString:SetJustifyH(justify)
    self.justifyH = justify
  end

  function fontString:SetJustifyV(justify)
    self.justifyV = justify
  end

  function fontString:SetWordWrap(wrap)
    self.wordWrap = wrap
  end

  function fontString:Show()
    self.shown = true
  end

  function fontString:Hide()
    self.shown = false
  end

  function fontString:IsShown()
    return self.shown
  end

  return fontString
end

local function addFrameState(frame)
  function frame:SetFrameStrata(strata)
    self.strata = strata
  end

  function frame:SetFrameLevel(level)
    self.level = level
  end

  function frame:GetFrameLevel()
    return self.level or 0
  end

  function frame:EnableMouse(enabled)
    self.mouseEnabled = enabled
  end

  function frame:EnableMouseWheel(enabled)
    self.mouseWheelEnabled = enabled
  end

  function frame:SetMovable(movable)
    self.movable = movable
  end

  function frame:SetResizable(resizable)
    self.resizable = resizable
  end

  function frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    self.resizeBounds = { minWidth, minHeight, maxWidth, maxHeight }
  end

  function frame:SetClampedToScreen(clamped)
    self.clamped = clamped
  end

  function frame:RegisterForDrag(...)
    self.dragButtons = { ... }
  end

  function frame:RegisterForClicks(...)
    self.clickButtons = { ... }
  end

  function frame:StartMoving()
    self.moving = true
  end

  function frame:StartSizing(corner)
    self.sizing = corner
  end

  function frame:StopMovingOrSizing()
    self.moving, self.sizing = false, nil
  end

  function frame:GetName()
    return self.name
  end
end

function Widgets.extend(frame)
  addRegion(frame)
  addFrameState(frame)
  frame.regions = {}

  function frame:CreateTexture(_, layer)
    local texture = newTexture(self, layer)
    table.insert(self.regions, texture)
    return texture
  end

  function frame:CreateFontString(_, layer, template)
    local fontString = newFontString(self, layer, template)
    table.insert(self.regions, fontString)
    return fontString
  end

  return frame
end

function Widgets.click(frame, button)
  local onClick = frame.scripts.OnClick
  assert(onClick, "frame has no OnClick script")
  onClick(frame, button or "LeftButton")
end

-- Font strings of frame and of every stub frame whose parent chain reaches it.
function Widgets.texts(frame, frames)
  local texts = {}
  local function isUnder(candidate)
    while candidate do
      if candidate == frame then
        return true
      end
      candidate = candidate.parent
    end
    return false
  end
  for _, candidate in ipairs(frames) do
    if isUnder(candidate) then
      for _, region in ipairs(candidate.regions or {}) do
        if region.text ~= nil and region.shown then
          texts[#texts + 1] = region.text
        end
      end
    end
  end
  return texts
end

return Widgets
