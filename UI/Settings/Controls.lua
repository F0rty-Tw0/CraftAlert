local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- The settings pages' controls on Blizzard templates: check button, slider with steppers,
-- input box, dropdown and panel button. A Column stacks rows top to bottom. Each control returns
-- { row, input, Set(value) }: Set shows a value without reporting it; only the player's action
-- calls onChange. `row.settingsLabel` names the row and `row.input` is its control frame.
local Controls = {}

local floor = math.floor
local max = math.max
local min = math.min
local tostring = tostring

local function create(frameType, parent, template)
  return _G["CreateFrame"](frameType, nil, parent, template)
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
  local label = FrameKit.Text(column.parent, Theme.FONTS.name)
  label:SetText(text)
  Controls.Place(column, label, column.last and Theme.LAYOUT.SECTION_GAP or 0)
  return label
end

-- A wrapping text block as wide as the controls (previews, results).
function Controls.Note(column, font)
  local text = FrameKit.Text(column.parent, font or Theme.FONTS.body)
  text:SetWidth(Theme.LAYOUT.CONTROL_WIDTH)
  text:SetWordWrap(true)
  Controls.Place(column, text)
  return text
end

-- A panel button; `button.label` is its FontString.
function Controls.Button(parent, label, width, onClick)
  local button = create("Button", parent, "UIPanelButtonTemplate")
  button:SetSize(width, Theme.LAYOUT.BUTTON_HEIGHT)
  button:SetText(label)
  button.label = button:GetFontString()
  button:SetScript("OnClick", onClick)
  return button
end

local function newRow(column, label)
  local layout = Theme.LAYOUT
  local row = create("Frame", column.parent)
  row:SetSize(layout.CONTROL_WIDTH, layout.CONTROL_HEIGHT)
  row.settingsLabel = label
  local text = FrameKit.Text(row, Theme.FONTS.body)
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
  text:SetText(label)
  Controls.Place(column, row)
  return row, text
end

-- A page's refresh list: add(fn) collects, refresh() runs them all. → add, refresh
function Controls.Refresher()
  local list = {}
  local function add(fn)
    list[#list + 1] = fn
  end
  local function refresh()
    for _, fn in ipairs(list) do
      fn()
    end
  end
  return add, refresh
end

-- Label on the left, check button on the right; onChange(isOn). The client flips the box
-- before OnClick runs, so the box holds the value.
function Controls.Toggle(column, label, onChange)
  local size = Theme.LAYOUT.CONTROL_HEIGHT
  local row = newRow(column, label)
  local check = create("CheckButton", row, "UICheckButtonTemplate")
  check:SetSize(size, size)
  check:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  check:SetScript("OnClick", function()
    onChange(check:GetChecked() and true or false)
  end)
  local function set(value)
    check:SetChecked(value == true)
  end
  row.input = check
  return { row = row, input = check, Set = set }
end

-- A toggle that writes owner()[key] and then runs after(). → the fn that shows the db value
function Controls.BoundToggle(column, label, owner, key, after)
  local toggle = Controls.Toggle(column, label, function(value)
    owner()[key] = value
    after()
  end)
  return function()
    toggle.Set(owner()[key])
  end
end

-- spec = { label, min, max, step, format = fn(value) → text (optional), onChange(value) }.
-- The template draws the value text right of the bar. A change made with the left button up
-- (a stepper click) commits at once; a drag commits when the button comes up. A commit writes
-- the stepped value only when it differs from the last one, so one drag is one write.
function Controls.Slider(column, spec)
  local layout = Theme.LAYOUT
  local row = newRow(column, spec.label)
  local slider = create("Frame", row, "MinimalSliderWithSteppersTemplate")
  slider:SetSize(layout.CONTROL_WIDTH - layout.LABEL_WIDTH - layout.SLIDER_VALUE_WIDTH, layout.CONTROL_HEIGHT)
  slider:SetPoint("LEFT", row, "LEFT", layout.LABEL_WIDTH, 0)
  local format = spec.format or tostring
  local function stepped(value)
    local onStep = spec.min + floor((value - spec.min) / spec.step + 0.5) * spec.step
    return floor(onStep * 1000 + 0.5) / 1000
  end
  -- Rounded: (1 - 0.3) / 0.05 is 13.999999999999998 in floating point.
  local steps = floor((spec.max - spec.min) / spec.step + 0.5)
  slider:Init(spec.min, spec.min, spec.max, steps, {
    [_G["MinimalSliderWithSteppersMixin"].Label.Right] = function(value)
      return format(stepped(value))
    end,
  })
  local committed = nil
  local quiet = false
  local function commit()
    local value = stepped(slider.Slider:GetValue())
    if value ~= committed then
      committed = value
      spec.onChange(value)
    end
  end
  slider:RegisterCallback(slider.Event.OnValueChanged, function()
    if quiet then
      return
    end
    if not _G["IsMouseButtonDown"]("LeftButton") then
      commit()
    end
  end, row)
  slider.Slider:HookScript("OnMouseUp", commit)
  local function set(value)
    committed = value
    quiet = true
    slider:SetValue(value)
    quiet = false
  end
  row.input = slider
  return { row = row, input = slider, Set = set }
end

-- Label on the left, box on the right. Enter or leaving the box commits a changed text
-- (onCommit(text)); Escape restores the last committed text. maxLetters (optional) caps the
-- box; without it a long word list is kept whole (a cut text would be committed on focus loss).
-- The template's art reaches 5 px left of the box, so the box is 8 px short of the column.
function Controls.Input(column, label, onCommit, maxLetters)
  local layout = Theme.LAYOUT
  local row = newRow(column, label)
  local box = create("EditBox", row, "InputBoxTemplate")
  box:SetSize(layout.CONTROL_WIDTH - layout.LABEL_WIDTH - 8, layout.INPUT_HEIGHT)
  box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  box:SetAutoFocus(false)
  if maxLetters then
    box:SetMaxLetters(maxLetters)
  end
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
  -- These replace the template's own Escape and focus-lost scripts.
  box:SetScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function()
    box:SetText(committed)
    box:ClearFocus()
  end)
  local function set(text)
    committed = text or ""
    box:SetText(committed)
  end
  row.input = box
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

-- A dropdown of `options` ({ { value, text }, ... }), one radio each; picking one calls
-- onChange(value). The dropdown shows the selected option's text in `input.Text`.
function Controls.Choice(column, label, options, onChange)
  local layout = Theme.LAYOUT
  local row = newRow(column, label)
  local current = 1
  local dropdown = create("DropdownButton", row, "WowStyle1DropdownTemplate")
  dropdown:SetSize(layout.CONTROL_WIDTH - layout.LABEL_WIDTH, layout.CONTROL_HEIGHT)
  dropdown:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  local function isSelected(value)
    local option = options[current]
    return option ~= nil and option.value == value
  end
  local function onSelect(value)
    current = indexOf(options, value) or current
    onChange(value)
  end
  dropdown:SetupMenu(function(_, root)
    for _, option in ipairs(options) do
      root:CreateRadio(option.text, isSelected, onSelect, option.value)
    end
  end)
  row.input = dropdown
  local control = { row = row, input = dropdown }
  function control.Set(value)
    current = indexOf(options, value) or 1
    dropdown:GenerateMenu()
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
-- Rows are Buttons, as only a button draws its HIGHLIGHT layer on hover.
-- Render(items, show) fills them from the current offset with show(row, item).
function Controls.List(column, count, createRow)
  local layout = Theme.LAYOUT
  local frame = create("Frame", column.parent)
  frame:SetSize(layout.CONTROL_WIDTH, count * layout.LIST_ROW_HEIGHT)
  Controls.Place(column, frame)
  local list = { frame = frame, rows = {}, offset = 0, items = {}, show = nil }
  for index = 1, count do
    local row = create("Button", frame)
    row:SetSize(layout.CONTROL_WIDTH, layout.LIST_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * layout.LIST_ROW_HEIGHT)
    FrameKit.ListHighlight(row)
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
