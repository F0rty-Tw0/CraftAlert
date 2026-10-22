-- Widget methods for the stub frames of tests/helpers/wow.lua, so UI modules run in plain Lua.
-- Setters store what they were given and getters read it back; anything the client draws
-- (fonts, textures, layout) is only recorded.
--   Widgets.extend(frame)           adds region, frame and child-creation methods
--   Widgets.click(frame, button)    runs the OnClick script as a mouse click would (a check button flips first)
--   Widgets.slide(control, value)   drags a Slider, or a template frame's inner Slider, to value and lets go
--   Widgets.step(control, forward)  clicks a slider template's Forward or Back stepper
--   Widgets.pick(dropdown, value)   picks the dropdown's radio whose data is value
--   Widgets.mouse                   buttons held right now (`LeftButton = true`), read by IsMouseButtonDown
--   Widgets.type(editBox, text)     types text into an EditBox and presses Enter
--   Widgets.texts(frame, frames)    the shown texts under frame (itself and its descendants
--                                   among `frames`, usually Wow.frames), in creation order
--   Widgets.fire(frame, name, ...)  runs the `name` script, then its HookScript hooks
--   Widgets.LINE_HEIGHT, Widgets.CHAR_WIDTH   the fake font metrics GetStringHeight wraps with
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

  function region:CreateAnimationGroup()
    return newAnimationGroup()
  end
end

local function newTexture(parent, layer)
  local texture = { shown = true, parent = parent, layer = layer }
  addRegion(texture)

  function texture:SetColorTexture(r, g, b, a)
    self.color = { r, g, b, a }
  end

  function texture:SetTexture(path, horizontalWrap, verticalWrap)
    self.texture = path
    self.wrap = { horizontalWrap, verticalWrap }
  end

  function texture:SetAtlas(atlas)
    self.atlas = atlas
  end

  function texture:SetBlendMode(mode)
    self.blendMode = mode
  end

  function texture:AddMaskTexture(mask)
    self.masks = self.masks or {}
    table.insert(self.masks, mask)
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

  -- 0 for no text; one line when wrapping is off or the width is unset; else LINE_HEIGHT per
  -- row of CHAR_WIDTH-wide characters the visible text fills.
  function fontString:GetStringHeight()
    local text = self.text
    if text == nil or text == "" then
      return 0
    end
    if not self.wordWrap or self.width == 0 then
      return Widgets.LINE_HEIGHT
    end
    local rows = ceil(visibleLength(text) * Widgets.CHAR_WIDTH / self.width)

    return Widgets.LINE_HEIGHT * math.max(rows, 1)
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

  function slider:SetThumbTexture(texture)
    self.thumb = texture
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

-- What the box keeps of `text`: the first maxLetters bytes, all when 0. The client counts
-- characters, so this matches it for ASCII text only.
local function capped(editBox, text)
  if editBox.maxLetters > 0 and type(text) == "string" then
    return string.sub(text, 1, editBox.maxLetters)
  end
  return text
end

-- As the client: SetText fires OnTextChanged(self, false); ClearFocus fires OnEditFocusLost
-- only when the box had the focus; SetMaxLetters cuts what is set or typed (0: no limit).
local function addEditBox(editBox)
  editBox.text, editBox.focused, editBox.maxLetters = "", false, 0

  function editBox:SetMaxLetters(count)
    self.maxLetters = count
  end

  function editBox:SetText(text)
    self.text = capped(self, text)
    local onTextChanged = self.scripts.OnTextChanged
    if onTextChanged then
      onTextChanged(self, false)
    end
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
    local onFocusLost = self.scripts.OnEditFocusLost
    if hadFocus and onFocusLost then
      onFocusLost(self)
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
  end

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
  if frame.toggleOnClick then
    frame:SetChecked(not frame:GetChecked())
  end
  onClick(frame, button or "LeftButton")
end

-- A drag that ends at `value`: the button goes down, the client moves the thumb (OnValueChanged),
-- then the button comes up (OnMouseUp, then its hooks). `control` is a Slider or a slider
-- template frame, whose inner Slider is dragged.
function Widgets.slide(control, value)
  local slider = control.Slider or control
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
