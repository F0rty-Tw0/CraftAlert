-- Fakes of the Blizzard frame templates the addon creates by name, so UI modules run in plain Lua.
--   Templates.Apply(frame, name)   gives `frame` what template `name` adds; an unknown name does nothing
--   Templates.fakes[name]          function(frame) that installs one template's children and methods
-- Widgets.extend calls Apply once the frame's own widget methods exist, before CreateFrame returns it.
-- That is earlier than newFrame (tests/helpers/wow.lua) defines SetScript/HookScript/Show/Hide, so a
-- fake that needs a script writes `frame.scripts.X` (and `frame.hooks.X`) directly.
-- portraitMethod: false models a client whose window template lacks `SetPortraitToAsset` (Classic).
local Templates = { fakes = {}, portraitMethod = true }

local unpack = unpack

-- Backdrop calls the frame forwards to its NineSlice child: frame method, NineSlice method.
local BACKDROP_FORWARDS = {
  { "SetBackdropColor", "SetCenterColor" },
  { "GetBackdropColor", "GetCenterColor" },
  { "SetBackdropBorderColor", "SetBorderColor" },
  { "GetBackdropBorderColor", "GetBorderColor" },
  { "SetBorderBlendMode", "SetBorderBlendMode" },
}

-- The child is a plain table, not a stub frame, so it stays out of Wow.frames.
local function newNineSlice()
  local nineSlice = {}

  function nineSlice:SetCenterColor(r, g, b, a)
    self.centerColor = { r, g, b, a }
  end

  function nineSlice:GetCenterColor()
    return unpack(self.centerColor or {})
  end

  function nineSlice:SetBorderColor(r, g, b, a)
    self.borderColor = { r, g, b, a }
  end

  function nineSlice:GetBorderColor()
    return unpack(self.borderColor or {})
  end

  function nineSlice:SetBorderBlendMode(mode)
    self.borderBlendMode = mode
  end

  return nineSlice
end

-- Blizzard_SharedXML/SharedTooltipTemplates.xml:111-121 (the NineSlice child, parentKey="NineSlice")
-- and SharedTooltipTemplates.lua:226-261 (TooltipBackdropTemplateMixin forwards each call to
-- self.NineSlice; the same mixin sits in ui_forever :232 and in ui_classic and ui_classic_era :226).
function Templates.fakes.TooltipBackdropTemplate(frame)
  frame.NineSlice = newNineSlice()
  for _, forward in ipairs(BACKDROP_FORWARDS) do
    local frameMethod, nineSliceMethod = forward[1], forward[2]
    frame[frameMethod] = function(self, ...)
      local nineSlice = self.NineSlice

      return nineSlice[nineSliceMethod](nineSlice, ...)
    end
  end
end

-- The client lays the inset out between its anchors: the frame's height, less the gap above its
-- last TOPLEFT anchor and the gap below its last BOTTOMRIGHT anchor.
local function insetHeight(inset)
  local topY, bottomY
  for _, point in ipairs(inset.points) do
    if point[1] == "TOPLEFT" then
      topY = point[5]
    elseif point[1] == "BOTTOMRIGHT" then
      bottomY = point[5]
    end
  end
  if topY == nil or bottomY == nil then
    return inset.height
  end

  return inset.parent:GetHeight() + topY - bottomY
end

-- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:680 (CloseButton), :684-693 (Inset at
-- TOPLEFT (4, -60) / BOTTOMRIGHT (-6, 26)) and :576-585 (TitleContainer.TitleText);
-- SharedUIPanelTemplates.lua:144-155 (UIPanelCloseButton_OnClick: the parent's onCloseCallback first,
-- then HideUIPanel(parent) only when there is none or it returns truthy) and
-- Blizzard_SharedXML/PortraitFrame.lua:4-14 (TitledPanelMixin GetTitleText and SetTitle).
-- Frame levels: the NineSlice border at 500 (:381, its metal top edge covers the title strip) and
-- the TitleContainer at 510 (:576; Classic/SharedUIPanelTemplates.xml:419 too). The CloseButton is
-- at 510 only in Mainline (:134); the Classic template (:172) sets no level, so it is modelled here
-- as a plain child of `frame`, under the border.
-- Children come from the stubbed CreateFrame: they are complete frames, unlike `frame` here.
function Templates.fakes.ButtonFrameTemplate(frame)
  local createFrame = _G["CreateFrame"]
  local nineSlice = createFrame("Frame", nil, frame)
  nineSlice:SetFrameLevel(500)
  frame.NineSlice = nineSlice

  local inset = createFrame("Frame", nil, frame)
  inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
  inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)
  inset.GetHeight = insetHeight
  frame.Inset = inset

  local close = createFrame("Button", nil, frame)
  close:SetScript("OnClick", function(self)
    local parent = self:GetParent()
    local continueHide = true
    if parent.onCloseCallback then
      continueHide = parent.onCloseCallback(self)
    end
    if continueHide then
      _G["HideUIPanel"](parent)
    end
  end)
  frame.CloseButton = close

  local titleContainer = createFrame("Frame", nil, frame)
  titleContainer:SetFrameLevel(510)
  titleContainer.TitleText = titleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.TitleContainer = titleContainer

  -- ButtonFrameTemplate.xml: PortraitContainer.portrait (parentKey) and PortraitFrameMixin:SetPortraitToAsset
  -- (Blizzard_SharedXML/PortraitFrame.lua), absent from the Classic templates.
  local portraitContainer = createFrame("Frame", nil, frame)
  portraitContainer.portrait = portraitContainer:CreateTexture(nil, "OVERLAY")
  frame.PortraitContainer = portraitContainer
  if Templates.portraitMethod ~= false then
    function frame:SetPortraitToAsset(asset)
      self.portraitAsset = asset
    end
  end

  function frame:GetTitleText()
    return self.TitleContainer.TitleText
  end

  function frame:SetTitle(title)
    self:GetTitleText():SetText(title)
  end
end

-- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:1561-1562 (16x16) and
-- SharedUIPanelTemplates.lua:1505-1543 (Init wraps the target's OnSizeChanged as it is then and
-- clamps only while the button is held), :1561 (OnMouseDown), :1584-1604 (OnMouseUp), :1640.
function Templates.fakes.PanelResizeButtonTemplate(button)
  button:SetSize(16, 16)

  function button:Init(target, minWidth, minHeight, maxWidth, maxHeight)
    self.target, self.minWidth, self.minHeight, self.maxWidth, self.maxHeight = target, minWidth, minHeight, maxWidth, maxHeight
    local original = target:GetScript("OnSizeChanged")
    target:SetScript("OnSizeChanged", function(sized, width, height)
      if original then
        original(sized, width, height)
      end
      if not self.isActive then
        return
      end
      if width < self.minWidth then
        sized:SetWidth(self.minWidth)
      elseif self.maxWidth and width > self.maxWidth then
        sized:SetWidth(self.maxWidth)
      end
      if height < self.minHeight then
        sized:SetHeight(self.minHeight)
      elseif self.maxHeight and height > self.maxHeight then
        sized:SetHeight(self.maxHeight)
      end
    end)
  end

  function button:SetOnResizeStoppedCallback(callback)
    self.resizeStoppedCallback = callback
  end

  -- :1610-1617: the mins are stored only; the wrapper Init installed reads them at each resize.
  function button:SetMinWidth(minWidth)
    self.minWidth = minWidth
  end

  function button:SetMinHeight(minHeight)
    self.minHeight = minHeight
  end

  button.scripts.OnMouseDown = function(self)
    self.isActive = true
    self.target:StartSizing("BOTTOMRIGHT", true)
  end

  button.scripts.OnMouseUp = function(self)
    self.isActive = false
    self.target:StopMovingOrSizing()
    if self.resizeStoppedCallback then
      self.resizeStoppedCallback(self.target)
    end
  end
end

-- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml:50-64 (32x32, the label FontString
-- `Text`, anchored LEFT of the box's RIGHT edge). The client flips a CheckButton before its OnClick
-- script runs; Widgets.click does that for a frame with `toggleOnClick`.
function Templates.fakes.UICheckButtonTemplate(button)
  button:SetSize(32, 32)
  button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  button.toggleOnClick = true
  button.checked = false

  function button:SetChecked(checked)
    self.checked = checked and true or false
  end

  function button:GetChecked()
    return self.checked
  end
end

local MINIMAL_SLIDER_EVENTS = { "OnValueChanged", "OnInteractStart", "OnInteractEnd" }

-- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml (InsetFrameTemplate: the marble `Bg`
-- texture, parentKey="Bg", in the BACKGROUND layer, plus a border).
function Templates.fakes.InsetFrameTemplate(frame)
  frame.Bg = frame:CreateTexture(nil, "BACKGROUND")
end

-- Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml:34-90 (250x40 Frame; inner Slider inset 19;
-- Back and Forward Buttons; five hidden Labels in Left, Right, Top, Min, Max order) and
-- MinimalSlider.lua: :35-43 the callback events and Label enum, :50-58 and :94-104 a stepper
-- click is Slider:SetValue(value +- step), :126-142 Init (range, step (max-min)/steps and value first,
-- then the formatters, then the OnValueChanged script), :160-171 FormatValue writes and shows Labels[labelID],
-- :202-204 SetValue, :70-75 the inner slider's own OnMouseUp (counted in `mouseUps`).
-- CallbackRegistry.lua:112-141 and :184-210: RegisterCallback(event, func, owner) calls func(owner, ...).
-- Not modelled: stepper enabling at the ends (UpdateStepperStates), interact events and narration.
function Templates.fakes.MinimalSliderWithSteppersTemplate(control)
  local createFrame = _G["CreateFrame"]
  control:SetSize(250, 40)
  control.mouseUps = 0
  control.Event = {}
  for _, event in ipairs(MINIMAL_SLIDER_EVENTS) do
    control.Event[event] = event
  end

  local slider = createFrame("Slider", nil, control)
  slider:SetScript("OnMouseUp", function()
    control.mouseUps = control.mouseUps + 1
  end)
  control.Slider = slider

  -- Back is the closure with forward = false, Forward the one with forward = true (:50-58).
  local function newStepper(direction)
    local stepper = createFrame("Button", nil, control)
    stepper:SetScript("OnClick", function()
      slider:SetValue(slider:GetValue() + direction * slider:GetValueStep())
    end)

    return stepper
  end
  control.Back, control.Forward = newStepper(-1), newStepper(1)

  control.Labels = {}
  for index = 1, 5 do
    local label = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:Hide()
    control.Labels[index] = label
  end

  local callbacks = {}

  function control:RegisterCallback(event, func, owner)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], { func = func, owner = owner })
  end

  function control:TriggerEvent(event, ...)
    for _, callback in ipairs(callbacks[event] or {}) do
      callback.func(callback.owner, ...)
    end
  end

  function control:FormatValue(value)
    for labelID, formatter in pairs(self.formatters or {}) do
      local label = self.Labels[labelID]
      if label then
        label:SetText(formatter(value))
        label:Show()
      end
    end
  end

  function control:Init(value, minValue, maxValue, steps, formatters)
    self.initArgs = { value, minValue, maxValue, steps }
    self.Slider:SetMinMaxValues(minValue, maxValue)
    self.Slider:SetValueStep((maxValue - minValue) / steps)
    self.Slider:SetValue(value)
    self.formatters = formatters
    self:FormatValue(value)
    self.Slider:SetScript("OnValueChanged", function(_, changed)
      self:FormatValue(changed)
      self:TriggerEvent(self.Event.OnValueChanged, changed)
    end)
  end

  function control:SetValue(value)
    self.Slider:SetValue(value)
  end

  function control:GetValue()
    return self.Slider:GetValue()
  end
end

-- Blizzard_Menu/Mainline/MenuTemplates.xml:3-33 (120x25 DropdownButton with the FontString `Text`);
-- Blizzard_Menu/DropdownButton.lua: :237-249 SetupMenu (generates at once only when the dropdown is
-- shown), :255-262 GenerateMenu (generator(dropdown, root)), :341-351 Pick (the radio's responder
-- runs, then the dropdown shows its selection); Blizzard_Menu/MenuTemplates.lua:345-354
-- CreateRadio(text, isSelected, onSelect, data) with isSelected(data) and onSelect(data).
-- The text shown is the first radio selected, "" when none is.
function Templates.fakes.WowStyle1DropdownTemplate(dropdown)
  dropdown:SetSize(120, 25)
  dropdown.Text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dropdown.menuEntries = {}

  local root = {}

  function root.CreateRadio(_, text, isSelected, onSelect, data)
    local entry = { text = text, isSelected = isSelected, onSelect = onSelect, data = data }
    table.insert(dropdown.menuEntries, entry)

    return entry
  end

  local function showSelection()
    dropdown.Text:SetText("")
    for _, entry in ipairs(dropdown.menuEntries) do
      if entry.isSelected(entry.data) then
        dropdown.Text:SetText(entry.text)
        return
      end
    end
  end

  function dropdown:GenerateMenu()
    if not self.menuGenerator then
      return
    end
    self.menuEntries = {}
    self.menuGenerator(self, root)
    showSelection()
  end

  function dropdown:SetupMenu(generator)
    self.menuGenerator = generator
    if self:IsShown() then
      self:GenerateMenu()
    end
  end

  function dropdown:Pick(entry)
    entry.onSelect(entry.data)
    showSelection()
  end
end

-- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:303 (ButtonText parentKey="Text") and
-- :315-320 (UIPanelButtonTemplate inherits UIPanelButtonNoTooltipTemplate). The button's one
-- FontString is what SetText and GetText act on.
function Templates.fakes.UIPanelButtonTemplate(button)
  local fontString = button:CreateFontString(nil, "ARTWORK", "GameFontNormalOutline")
  button.Text = fontString

  function button:SetText(text)
    fontString:SetText(text)
  end

  function button:GetText()
    return fontString:GetText()
  end

  function button:GetFontString()
    return fontString
  end
end

-- Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:177-254 (SearchBoxTemplate on
-- InputBoxInstructionsTemplate: the placeholder `Instructions`, the magnifier `searchIcon`, the
-- hidden `clearButton`) and InputBoxTemplates.lua:131-133, :175-211 (the placeholder shows while
-- the box is empty; the clear button shows while it has text or the focus, and its click empties
-- the box, then clears the focus; Enter and Escape clear the focus). Not modelled: the icon's
-- vertex colour, the clear button's hover art and OnEditFocusGained (the fake SetFocus fires none).
function Templates.fakes.SearchBoxTemplate(box)
  box.Instructions = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  box.Instructions:SetText("Search")
  box.searchIcon = box:CreateTexture(nil, "OVERLAY")
  box.searchIcon:SetAtlas("common-search-magnifyingglass")
  local clear = _G["CreateFrame"]("Button", nil, box)
  clear.shown = false -- hidden="true"; Hide would ask `box`, not yet complete, whether it shows
  clear:SetScript("OnClick", function()
    box:SetText("")
    box:ClearFocus()
  end)
  box.clearButton = clear
  box.scripts.OnTextChanged = function(self)
    self.clearButton:SetShown(self:HasFocus() or self:GetText() ~= "")
    self.Instructions:SetShown(self:GetText() == "")
  end
  box.scripts.OnEditFocusLost = function(self)
    if self:GetText() == "" then
      self.clearButton:Hide()
    end
  end
  box.scripts.OnEnterPressed = function(self)
    self:ClearFocus()
  end
  box.scripts.OnEscapePressed = box.scripts.OnEnterPressed
end

-- Blizzard_SharedXML/SharedTooltipTemplates.xml (SharedTooltipTemplate, hidden) under
-- GameTooltipTemplate: the addon's own tooltip (UI/Tooltip.lua). It records what it was given:
-- lines, their colours as { r, g, b } or {}, rights[line] = { text, r, g, b } of an
-- AddDoubleLine's right half, owner, anchor, hyperlinks; badLinks[link] makes SetHyperlink raise.
-- Show, Hide and IsShown are the stub frame's own.
function Templates.fakes.GameTooltipTemplate(tooltip)
  tooltip.shown, tooltip.lines, tooltip.colors, tooltip.rights, tooltip.hyperlinks = false, {}, {}, {}, {}
  function tooltip:SetOwner(owner, anchor)
    self.owner, self.anchor, self.lines, self.colors, self.rights, self.wraps = owner, anchor, {}, {}, {}, {}
  end
  function tooltip:ClearLines()
    self.lines, self.colors, self.rights, self.wraps = {}, {}, {}, {}
  end
  function tooltip:SetText(text, r, g, b)
    self.lines, self.colors, self.rights, self.wraps = { text }, { { r, g, b } }, {}, {}
  end
  -- `wraps[i]` is line i's wrap flag (nil when the caller passed none).
  function tooltip:AddLine(text, r, g, b, wrap)
    table.insert(self.lines, text)
    table.insert(self.colors, { r, g, b })
    self.wraps = self.wraps or {}
    self.wraps[#self.lines] = wrap
  end
  function tooltip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    table.insert(self.lines, left)
    table.insert(self.colors, { lr, lg, lb })
    self.rights[#self.lines] = { right, rr, rg, rb }
  end
  function tooltip:SetHyperlink(link)
    if self.badLinks and self.badLinks[link] then
      error("bad link: " .. link)
    end
    table.insert(self.hyperlinks, link)
  end
  function tooltip:IsOwned(frame)
    return self.owner == frame and self.shown
  end
  function tooltip:SetMinimumWidth(width)
    self.minWidth = width
  end
end

function Templates.Apply(frame, templateName)
  local fake = Templates.fakes[templateName]
  if fake == nil then
    return
  end
  fake(frame)
end

return Templates
