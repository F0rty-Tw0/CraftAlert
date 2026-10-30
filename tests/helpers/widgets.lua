-- Widget methods for the stub frames of tests/helpers/wow.lua, so UI modules run in plain Lua.
-- Setters store what they were given and getters read it back; anything the client draws
-- (fonts, textures, layout) is only recorded.
--   Widgets.extend(frame)           adds region, frame and child-creation methods
--   Widgets.click(frame, button)    runs the OnClick script as a mouse click would (a check button flips first)
--   Widgets.slide(control, value)   drags a slider template frame's inner Slider to value and lets go
--   Widgets.step(control, forward)  clicks a slider template's Forward or Back stepper
--   Widgets.pick(dropdown, value)   picks the dropdown's radio whose data is value
--   Widgets.mouse                   buttons held right now (`LeftButton = true`), read by IsMouseButtonDown
--   Widgets.type(editBox, text)     types text into an EditBox and presses Enter
--   Widgets.texts(frame, frames)    the shown texts under frame (itself and its descendants
--                                   among `frames`, usually Wow.frames), in creation order
--   Widgets.fire(frame, name, ...)  runs the `name` script, then its HookScript hooks
--   Widgets.LINE_HEIGHT, Widgets.CHAR_WIDTH   the fake font metrics GetStringHeight and
--                                   GetStringWidth measure with
-- A frame made with a template name gets that template's fake (tests/helpers/templates.lua).
local Templates = require("tests.helpers.templates")

local Widgets = {}

Widgets.mouse = {}

Widgets.LINE_HEIGHT = 12
Widgets.CHAR_WIDTH = 6

local ceil = math.ceil
local unpack = unpack

-- As the client: an animation records every call made on it in `calls` as { method, args... }.
local function newAnimation(kind)
  local animation = { kind = kind, calls = {} }

  return setmetatable(animation, {
    __index = function(self, method)
      return function(_, ...)
        table.insert(self.calls, { method, ... })
      end
    end,
  })
end

local function runGroupScript(group, scriptName)
  local script = group.scripts[scriptName]
  if script then
    script(group)
  end
end

-- As the client: a group runs OnPlay when it starts, OnStop when stopped while playing, and
-- OnFinished when it finishes.
local function newAnimationGroup()
  local group = { playing = false, scripts = {}, animations = {} }

  function group:CreateAnimation(kind)
    local animation = newAnimation(kind)
    table.insert(self.animations, animation)

    return animation
  end

  function group:SetLooping(mode)
    self.looping = mode
  end

  function group:SetScript(scriptName, fn)
    self.scripts[scriptName] = fn
  end

  function group:SetToFinalAlpha() end

  function group:Play()
    self.playing = true
    runGroupScript(self, "OnPlay")
  end

  function group:Stop()
    if not self.playing then
      return
    end
    self.playing = false
    runGroupScript(self, "OnStop")
  end

  function group:Finish()
    self.playing = false
    runGroupScript(self, "OnFinished")
  end

  function group:IsPlaying()
    return self.playing
  end

  return group
end

local function addRegion(region)
  region.points = {}
  region.alpha = 1
  region.width, region.height = 0, 0

  -- As the client: setting a point the region already has moves that anchor.
  function region:SetPoint(point, relativeTo, relativePoint, x, y)
    for index, anchor in ipairs(self.points) do
      if anchor[1] == point then
        self.points[index] = { point, relativeTo, relativePoint, x, y }
        return
      end
    end
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

  function region:SetParent(parent)
    self.parent = parent
  end

  function region:GetParent()
    return self.parent
  end

  -- Through Show and Hide, so a frame still runs its OnShow and OnHide.
  function region:SetShown(shown)
    if shown then
      self:Show()
    else
      self:Hide()
    end
  end

  function region:CreateAnimationGroup()
    return newAnimationGroup()
  end
end

local function newTexture(parent, layer)
  local texture = { shown = true, parent = parent, layer = layer }
  addRegion(texture)

  -- Each fill replaces the others, as in the client.
  function texture:SetColorTexture(r, g, b, a)
    self.color = { r, g, b, a }
    self.texture = nil
    self.atlas = nil
  end

  function texture:SetTexture(path, horizontalWrap, verticalWrap)
    self.texture = path
    self.wrap = { horizontalWrap, verticalWrap }
    self.color = nil
    self.atlas = nil
  end

  function texture:SetAtlas(atlas)
    self.atlas = atlas
    self.color = nil
    self.texture = nil
  end

  function texture:SetBlendMode(mode)
    self.blendMode = mode
  end

  function texture:AddMaskTexture(mask)
    self.masks = self.masks or {}
    table.insert(self.masks, mask)
  end

  function texture:SetMask(path)
    self.mask = path
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

-- The text as drawn: colour, link, atlas and texture escapes removed, "||" shown as one "|".
-- ASCII only: the client counts characters, this counts bytes.
local function visibleLength(text)
  local shown = string.gsub(text, "||", "\1")
  shown = string.gsub(shown, "|c%x%x%x%x%x%x%x%x", "")
  shown = string.gsub(shown, "|cn[^:]*:", "")
  shown = string.gsub(shown, "|H[^|]*|h", "")
  shown = string.gsub(shown, "|A[^|]*|a", "")
  shown = string.gsub(shown, "|T[^|]*|t", "")
  shown = string.gsub(shown, "|[hr]", "")

  return #shown
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

  -- The fake has no font files: GetFont gives back only what SetFont was given (nil before).
  function fontString:SetFont(file, size, flags)
    self.fontFile, self.fontSize, self.fontFlags = file, size, flags
  end

  function fontString:GetFont()
    return self.fontFile, self.fontSize, self.fontFlags
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

  function fontString:SetNonSpaceWrap(wrap)
    self.nonSpaceWrap = wrap
  end

  function fontString:SetMaxLines(count)
    self.maxLines = count
  end

  -- CHAR_WIDTH per visible character on one line; a set width bounds it, as the client measures
  -- a truncated text (0: no width set).
  function fontString:GetStringWidth()
    local width = visibleLength(self.text or "") * Widgets.CHAR_WIDTH
    if self.width > 0 then
      return math.min(width, self.width)
    end

    return width
  end

  -- 0 for no text; one line when wrapping is off or the width is unset; else one row per width of
  -- CHAR_WIDTH-wide characters the visible text fills, at most maxLines rows (0: no cap).
  function fontString:GetNumLines()
    local text = self.text
    if text == nil or text == "" then
      return 0
    end
    if not self.wordWrap or self.width == 0 then
      return 1
    end
    local rows = math.max(ceil(visibleLength(text) * Widgets.CHAR_WIDTH / self.width), 1)
    if self.maxLines and self.maxLines > 0 then
      rows = math.min(rows, self.maxLines)
    end

    return rows
  end

  -- LINE_HEIGHT per line (GetNumLines).
  function fontString:GetStringHeight()
    return Widgets.LINE_HEIGHT * self:GetNumLines()
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

  -- A button's enabled state; Widgets.click on a disabled one does nothing, as in the client.
  function frame:SetEnabled(enabled)
    self.disabled = not enabled
  end

  function frame:Enable()
    self.disabled = false
  end

  function frame:Disable()
    self.disabled = true
  end

  function frame:IsEnabled()
    return not self.disabled
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

  function frame:SetClipsChildren(clips)
    self.clipsChildren = clips
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

  function frame:StartSizing(corner, useCursor)
    self.sizing, self.sizingUsesCursor = corner, useCursor
  end

  function frame:StopMovingOrSizing()
    self.moving, self.sizing, self.sizingUsesCursor = false, nil, nil
  end

  -- Screen coordinates the test sets (frame.left / frame.top); 0 when it never did.
  function frame:GetLeft()
    return self.left or 0
  end

  function frame:GetTop()
    return self.top or 0
  end

  function frame:GetName()
    return self.name
  end

  function frame:SetHyperlinksEnabled(enabled)
    self.hyperlinksEnabled = enabled
  end

  -- Tests set `mouseOver` to put the cursor on the frame.
  function frame:IsMouseOver()
    return self.mouseOver == true
  end

  -- Tests set `center = { x, y }`; without one the frame reports nothing, like an unlaid-out frame.
  function frame:GetCenter()
    if self.center == nil then
      return
    end

    return unpack(self.center)
  end

  -- Button textures are stored as given (a path or a texture); the highlight keeps its blend mode too.
  function frame:SetNormalTexture(texture)
    self.normalTexture = texture
  end

  function frame:GetNormalTexture()
    return self.normalTexture
  end

  function frame:SetPushedTexture(texture)
    self.pushedTexture = texture
  end

  function frame:GetPushedTexture()
    return self.pushedTexture
  end

  function frame:SetHighlightTexture(texture, mode)
    self.highlightTexture, self.highlightMode = texture, mode
  end

  function frame:GetHighlightTexture()
    return self.highlightTexture
  end

  function frame:LockHighlight()
    self.highlightLocked = true
  end

  function frame:UnlockHighlight()
    self.highlightLocked = false
  end
end

-- As the client: SetValue clamps and fires OnValueChanged(self, value, false) when it changes.
local function addSlider(slider)
  slider.value, slider.minValue, slider.maxValue = 0, 0, 0

  function slider:SetOrientation(orientation)
    self.orientation = orientation
  end

  function slider:SetMinMaxValues(minValue, maxValue)
    self.minValue, self.maxValue = minValue, maxValue
  end

  function slider:GetMinMaxValues()
    return self.minValue, self.maxValue
  end

  function slider:SetValueStep(step)
    self.valueStep = step
  end

  function slider:GetValueStep()
    return self.valueStep or 0
  end

  function slider:SetObeyStepOnDrag(obey)
    self.obeyStep = obey
  end

  -- As the client: the thumb is placed on the slider (at the top here; the value is not modelled).
  function slider:SetThumbTexture(texture)
    self.thumb = texture
    texture:ClearAllPoints()
    texture:SetPoint("TOP", self, "TOP", 0, 0)
  end

  function slider:SetValue(value)
    value = math.max(self.minValue, math.min(self.maxValue, value))
    local changed = value ~= self.value
    self.value = value
    local onValueChanged = self.scripts.OnValueChanged
    if changed and onValueChanged then
      onValueChanged(self, value, false)
    end
  end

  function slider:GetValue()
    return self.value
  end
end

-- A plain ScrollFrame's own methods. SetScrollChild records the child's anchors and size at that
-- moment in `childAtScrollChild`. Not modelled: the client's own range or clamping of the offset.
local function addScrollFrame(scroll)
  scroll.verticalScroll = 0

  function scroll:SetScrollChild(child)
    self.scrollChild = child
    local points = {}
    for index, anchor in ipairs(child.points) do
      points[index] = { unpack(anchor) }
    end
    self.childAtScrollChild = { points = points, width = child.width, height = child.height }
  end

  function scroll:GetScrollChild()
    return self.scrollChild
  end

  function scroll:SetVerticalScroll(offset)
    self.verticalScroll = offset
  end

  function scroll:GetVerticalScroll()
    return self.verticalScroll
  end

  function scroll:UpdateScrollChildRect()
    self.childRectUpdates = (self.childRectUpdates or 0) + 1
  end
end

-- What the box keeps of `text`: the first maxLetters bytes, all when 0. The client counts
-- characters, so this matches it for ASCII text only.
local function capped(editBox, text)
  if editBox.maxLetters > 0 and type(text) == "string" then
    return string.sub(text, 1, editBox.maxLetters)
  end
  return text
end

-- As the client: SetText fires OnTextChanged(self, false); ClearFocus fires OnEditFocusLost
-- only when the box had the focus; each script's HookScript hooks run after it; SetMaxLetters
-- cuts what is set or typed (0: no limit).
local function addEditBox(editBox)
  editBox.text, editBox.focused, editBox.maxLetters = "", false, 0

  function editBox:SetMaxLetters(count)
    self.maxLetters = count
  end

  function editBox:SetText(text)
    self.text = capped(self, text)
    Widgets.fire(self, "OnTextChanged", false)
  end

  function editBox:GetText()
    return self.text
  end

  function editBox:SetFocus()
    self.focused = true
  end

  function editBox:HasFocus()
    return self.focused
  end

  function editBox:ClearFocus()
    local hadFocus = self.focused
    self.focused = false
    if hadFocus then
      Widgets.fire(self, "OnEditFocusLost")
    end
  end

  for _, name in ipairs({ "SetAutoFocus", "SetFontObject", "SetTextInsets", "SetJustifyH", "HighlightText" }) do
    editBox[name] = function(self, ...)
      self[name .. "Args"] = { ... }
    end
  end
end

function Widgets.extend(frame)
  addRegion(frame)
  addFrameState(frame)
  frame.regions = {}
  if frame.frameType == "Slider" then
    addSlider(frame)
  elseif frame.frameType == "EditBox" then
    addEditBox(frame)
  elseif frame.frameType == "ScrollFrame" then
    addScrollFrame(frame)
  end

  function frame:CreateTexture(_, layer, _, sublevel)
    local texture = newTexture(self, layer)
    texture.sublevel = sublevel
    table.insert(self.regions, texture)
    return texture
  end

  function frame:CreateFontString(_, layer, template)
    local fontString = newFontString(self, layer, template)
    table.insert(self.regions, fontString)
    return fontString
  end

  function frame:CreateMaskTexture()
    local mask = newTexture(self, "ARTWORK")
    mask.isMask = true
    table.insert(self.regions, mask)

    return mask
  end

  if frame.template then
    Templates.Apply(frame, frame.template)
  end

  return frame
end

-- As the client: the frame's script runs, then every HookScript hook, each with the frame first.
function Widgets.fire(frame, scriptName, ...)
  local script = frame.scripts[scriptName]
  if script then
    script(frame, ...)
  end
  for _, hook in ipairs(frame.hooks[scriptName] or {}) do
    hook(frame, ...)
  end
end

function Widgets.click(frame, button)
  local onClick = frame.scripts.OnClick
  assert(onClick, "frame has no OnClick script")
  if frame.disabled then
    return
  end
  if frame.toggleOnClick then
    frame:SetChecked(not frame:GetChecked())
  end
  onClick(frame, button or "LeftButton")
end

-- A drag that ends at `value`: the button goes down, the client moves the thumb (OnValueChanged),
-- then the button comes up (OnMouseUp, then its hooks). `control` is a slider template frame,
-- whose inner Slider is dragged.
function Widgets.slide(control, value)
  local slider = control.Slider
  Widgets.mouse.LeftButton = true
  slider:SetValue(value)
  Widgets.mouse.LeftButton = false
  Widgets.fire(slider, "OnMouseUp", "LeftButton")
end

-- A click on the slider template's Forward (or Back) stepper.
function Widgets.step(control, forward)
  Widgets.click(forward and control.Forward or control.Back)
end

-- The player opens the dropdown and chooses the radio holding `value`.
function Widgets.pick(dropdown, value)
  for _, entry in ipairs(dropdown.menuEntries) do
    if entry.data == value then
      dropdown:Pick(entry)
      return
    end
  end
  error("no radio " .. tostring(value), 2)
end

-- The player clicks into the box, replaces its text and presses Enter.
function Widgets.type(editBox, text)
  editBox:SetFocus()
  editBox.text = capped(editBox, text)
  local onTextChanged = editBox.scripts.OnTextChanged
  if onTextChanged then
    onTextChanged(editBox, true)
  end
  local onEnter = editBox.scripts.OnEnterPressed
  if onEnter then
    onEnter(editBox)
  end
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
