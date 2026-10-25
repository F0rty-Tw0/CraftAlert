-- Where the stub frames of tests/helpers/wow.lua would sit: they keep anchors without laying them
-- out, so these resolve them as the client does. y grows upwards, as in the client.
--   Layout.edges(region)   → left, right through the horizontal anchors (TOP/BOTTOM/CENTER: the
--                            middle; no anchor: from 0)
--   Layout.ys(region)      → top, bottom through the vertical anchors (no anchor: from 0)
--   Layout.height(region)  the region's height; a font string without one set measures its text
local Layout = {}

-- The x of `point` ("LEFT", "TOPRIGHT", ...) on a region from `left` to `right`.
local function xOf(point, left, right)
  if point:find("LEFT") then
    return left
  end
  if point:find("RIGHT") then
    return right
  end
  return (left + right) / 2
end

-- The y of `point` on a region from `top` to `bottom`.
local function yOf(point, top, bottom)
  if point:find("TOP") then
    return top
  end
  if point:find("BOTTOM") then
    return bottom
  end
  return (top + bottom) / 2
end

function Layout.height(region)
  if region:GetHeight() == 0 and region.GetStringHeight then
    return region:GetStringHeight()
  end
  return region:GetHeight()
end

-- The width fills in an edge no anchor gives; a TOP, BOTTOM or CENTER anchor places the middle.
function Layout.edges(region)
  local left, right, middle
  for _, anchor in ipairs(region.points) do
    local point, relativeTo, relativePoint, x = anchor[1], anchor[2], anchor[3], anchor[4]
    local relativeLeft, relativeRight = Layout.edges(relativeTo)
    local at = xOf(relativePoint or point, relativeLeft, relativeRight) + (x or 0)
    if point:find("LEFT") then
      left = at
    elseif point:find("RIGHT") then
      right = at
    elseif point == "TOP" or point == "BOTTOM" or point == "CENTER" then
      middle = at
    end
  end
  if left == nil and right == nil and middle ~= nil then
    left = middle - region:GetWidth() / 2
  end
  left = left or (right and right - region:GetWidth()) or 0
  right = right or left + region:GetWidth()
  return left, right
end

-- The height fills in an edge no anchor gives; a LEFT, RIGHT or CENTER anchor places the middle.
function Layout.ys(region)
  local top, bottom, middle
  for _, anchor in ipairs(region.points) do
    local point, relativeTo, relativePoint, y = anchor[1], anchor[2], anchor[3], anchor[5]
    local relativeTop, relativeBottom = Layout.ys(relativeTo)
    local at = yOf(relativePoint or point, relativeTop, relativeBottom) + (y or 0)
    if point:find("TOP") then
      top = at
    elseif point:find("BOTTOM") then
      bottom = at
    else
      middle = at
    end
  end
  local height = Layout.height(region)
  if top == nil and bottom == nil and middle ~= nil then
    top = middle + height / 2
  end
  top = top or (bottom and bottom + height) or 0
  bottom = bottom or top - height
  return top, bottom
end

return Layout
