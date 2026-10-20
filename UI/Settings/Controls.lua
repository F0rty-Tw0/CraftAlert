local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- The settings pages' controls in WhisperMessenger's look (trimmed from its
-- UI/Shared/SettingsControls.lua and UI/Helpers/Controls.lua: section label, toggle switch,
-- slider, option button, input; no presets, no native-HUD variants). A Column stacks rows top
-- to bottom. Each control returns { row, input, Set(value) }: Set shows a value without
-- reporting it; only the player's action calls onChange. `row.settingsLabel` names the row.
local Controls = {}

local floor = math.floor
local max = math.max
local min = math.min
local tostring = tostring

local function create(frameType, parent)
  return _G["CreateFrame"](frameType, nil, parent)
end

function Controls.Column(parent)
  return { parent = parent, last = nil }
end

-- Anchors `region` below the column's last row (`gap` px; default CONTROL_GAP).
function Controls.Place(column, region, gap)
  if column.last then
    region:SetPoint("TOPLEFT", column.last, "BOTTOMLEFT", 0, -(gap or Theme.LAYOUT.CONTROL_GAP))
  else
    region:SetPoint("TOPLEFT", column.parent, "TOPLEFT", 0, 0)
  end
  column.last = region
end

function Controls.Section(column, text)
  local label = FrameKit.Text(column.parent, Theme.FONTS.name, Theme.COLORS.textSecondary)
  label:SetText(text)
  Controls.Place(column, label, column.last and Theme.LAYOUT.SECTION_GAP or 0)
  return label
end

-- A wrapping text block as wide as the controls (previews, results).
function Controls.Note(column, font)
  local text = FrameKit.Text(column.parent, font or Theme.FONTS.body, Theme.COLORS.textPrimary)
  text:SetWidth(Theme.LAYOUT.CONTROL_WIDTH)
  text:SetWordWrap(true)
  Controls.Place(column, text)
  return text
end

-- A flat option button; `button.label` holds its text. Hover lights it up.
function Controls.Button(parent, label, width, onClick)
  local button = create("Button", parent)
  button:SetSize(width, Theme.LAYOUT.BUTTON_HEIGHT)
  local background = FrameKit.Panel(button, Theme.COLORS.option)
  button.label = FrameKit.Text(button, Theme.FONTS.body, Theme.COLORS.textPrimary)
  button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
  button.label:SetJustifyH("CENTER")
  button.label:SetText(label)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function()
    FrameKit.Fill(background, Theme.COLORS.optionHover)
  end)
  button:SetScript("OnLeave", function()
    FrameKit.Fill(background, Theme.COLORS.option)
  end)
  return button
end

-- A labelled row; `height` defaults to CONTROL_HEIGHT.
local function newRow(column, label, height)
  local layout = Theme.LAYOUT
  local row = create("Frame", column.parent)
  row:SetSize(layout.CONTROL_WIDTH, height or layout.CONTROL_HEIGHT)
  row.settingsLabel = label
  local text = FrameKit.Text(row, Theme.FONTS.body, Theme.COLORS.textPrimary)
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
  text:SetText(label)
  Controls.Place(column, row)
  return row, text
end

local function paintSwitch(switch, on)
  local layout = Theme.LAYOUT
  FrameKit.Fill(switch.track, on and Theme.COLORS.toggleOn or Theme.COLORS.toggleOff)
  switch.knob:ClearAllPoints()
  if on then
    switch.knob:SetPoint("RIGHT", switch, "RIGHT", -layout.KNOB_INSET, 0)
  else
    switch.knob:SetPoint("LEFT", switch, "LEFT", layout.KNOB_INSET, 0)
  end
end

-- Label on the left, switch on the right; onChange(isOn).
function Controls.Toggle(column, label, onChange)
  local layout = Theme.LAYOUT
  local row = newRow(column, label)
  local switch = create("Button", row)
  switch:SetSize(layout.SWITCH_WIDTH, layout.SWITCH_HEIGHT)
  switch:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  switch.track = switch:CreateTexture(nil, "BACKGROUND")
  switch.track:SetAllPoints(switch)
  switch.knob = switch:CreateTexture(nil, "ARTWORK")
  switch.knob:SetSize(layout.KNOB_SIZE, layout.KNOB_SIZE)
  FrameKit.Fill(switch.knob, Theme.COLORS.knob)
  local value = false
  switch:SetScript("OnClick", function()
    value = not value
    paintSwitch(switch, value)
    onChange(value)
  end)
  paintSwitch(switch, value)
  local function set(newValue)
    value = newValue == true
    paintSwitch(switch, value)
  end
  return { row = row, input = switch, Set = set }
end

local function createTrack(slider)
  local layout = Theme.LAYOUT
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", slider, "LEFT", 0, 0)
  track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
  track:SetHeight(4)
  FrameKit.Fill(track, Theme.COLORS.toggleOff)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(layout.SLIDER_THUMB_WIDTH, layout.SLIDER_HEIGHT)
  FrameKit.Fill(thumb, Theme.COLORS.toggleOn)
  slider:SetThumbTexture(thumb)
end

-- spec = { label, min, max, step, format = fn(value) → text (optional), onChange(value) }.
-- Dragging updates the value text; letting go commits a changed value once, so one drag is
-- one write (WhisperMessenger's commitOnRelease).
function Controls.Slider(column, spec)
  local layout = Theme.LAYOUT
  local row = newRow(column, spec.label)
  local valueText = FrameKit.Text(row, Theme.FONTS.detail, Theme.COLORS.textSecondary)
  valueText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
  local slider = create("Slider", row)
  slider:SetSize(layout.CONTROL_WIDTH - layout.LABEL_WIDTH - 48, layout.SLIDER_HEIGHT)
  slider:SetPoint("LEFT", row, "LEFT", layout.LABEL_WIDTH, 0)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(spec.min, spec.max)
  slider:SetValueStep(spec.step)
  slider:SetObeyStepOnDrag(true)
  slider:EnableMouse(true)
  createTrack(slider)
  local format = spec.format or tostring
  local committed = nil
  local function stepped()
    local value = spec.min + floor((slider:GetValue() - spec.min) / spec.step + 0.5) * spec.step
    return floor(value * 1000 + 0.5) / 1000
  end
  slider:SetScript("OnValueChanged", function()
    valueText:SetText(format(stepped()))
  end)
  slider:SetScript("OnMouseUp", function()
    local value = stepped()
    if value ~= committed then
      committed = value
      spec.onChange(value)
    end
  end)
  local function set(value)
    committed = value
    slider:SetValue(value)
    valueText:SetText(format(value))
  end
  return { row = row, input = slider, Set = set }
end

-- Label above a full-width box. Enter or leaving the box commits a changed text
-- (onCommit(text)); Escape restores the last committed text.
function Controls.Input(column, label, onCommit)
  local layout = Theme.LAYOUT
  local row = newRow(column, label, layout.CONTROL_HEIGHT + layout.INPUT_HEIGHT)
  local box = create("EditBox", row)
  box:SetSize(layout.CONTROL_WIDTH, layout.INPUT_HEIGHT)
  box:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  box:SetAutoFocus(false)
  box:SetFontObject(Theme.FONTS.body)
  box:SetTextInsets(6, 6, 0, 0)
  box:SetMaxLetters(255)
  FrameKit.Panel(box, Theme.COLORS.input)
  local committed = ""
  local function commit()
    local text = box:GetText()
    if text ~= committed then
      committed = text
      onCommit(text)
    end
  end
  box:SetScript("OnEnterPressed", function()
    commit()
    box:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function()
    box:SetText(committed)
    box:ClearFocus()
  end)
  local function set(text)
    committed = text or ""
    box:SetText(committed)
  end
  return { row = row, input = box, Set = set }
end

local function indexOf(options, value)
  for i, option in ipairs(options) do
    if option.value == value then
      return i
    end
  end
  return nil
end

-- A button that steps through `options` ({ { value, text }, ... }): left-click the next,
-- right-click the previous, both wrapping; onChange(value).
function Controls.Choice(column, label, options, onChange)
  local layout = Theme.LAYOUT
  local row = newRow(column, label)
  local current = 1
  local button
  local function show()
    local option = options[current]
    button.label:SetText(option and option.text or "")
  end
  button = Controls.Button(row, "", layout.CONTROL_WIDTH - layout.LABEL_WIDTH, function(_, mouseButton)
    if #options == 0 then
      return
    end
    local step = mouseButton == "RightButton" and -1 or 1
    current = (current - 1 + step) % #options + 1
    show()
    onChange(options[current].value)
  end)
  button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  local control = { row = row, input = button }
  function control.Set(value)
    current = indexOf(options, value) or 1
    show()
  end
  function control.SetOptions(newOptions, value)
    options = newOptions
    control.Set(value)
  end
  function control.Value()
    local option = options[current]
    return option and option.value
  end
  return control
end

-- `count` rows of LIST_ROW_HEIGHT, made by createRow(row, index); the mouse wheel scrolls.
-- Render(items, show) fills them from the current offset with show(row, item).
function Controls.List(column, count, createRow)
  local layout = Theme.LAYOUT
  local frame = create("Frame", column.parent)
  frame:SetSize(layout.CONTROL_WIDTH, count * layout.LIST_ROW_HEIGHT)
  Controls.Place(column, frame)
  local list = { frame = frame, rows = {}, offset = 0, items = {}, show = nil }
  for index = 1, count do
    local row = create("Frame", frame)
    row:SetSize(layout.CONTROL_WIDTH, layout.LIST_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * layout.LIST_ROW_HEIGHT)
    createRow(row, index)
    list.rows[index] = row
  end
  local function paint()
    list.offset = max(0, min(list.offset, #list.items - count))
    for index, row in ipairs(list.rows) do
      local item = list.items[list.offset + index]
      if item ~= nil then
        list.show(row, item)
        row:Show()
      else
        row:Hide()
      end
    end
  end
  function list.Render(items, show)
    list.items, list.show = items, show
    paint()
  end
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    list.offset = list.offset - delta
    paint()
  end)
  return list
end

ns.SettingsControls = Controls
return Controls
