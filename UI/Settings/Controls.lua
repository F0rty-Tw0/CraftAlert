local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")
local Column = ns.SettingsColumn or require("CraftAlert.UI.Settings.Column")

-- The settings pages' controls on Blizzard templates: check button, slider with steppers,
-- input box, search box, dropdown and panel button, in a Column (UI/Settings/Column.lua). Each
-- control returns { row, input, Set(value) }: Set shows a value without reporting it; only the
-- player's action calls onChange. `row.settingsLabel` names the row and `row.input` is its control
-- frame. A row is as wide as the column and its controls are anchored to its edges. As
-- WhisperMessenger's settings, a slider, input or dropdown sits on the line under its label; a
-- toggle's label wraps beside the check.
local Controls = {}

local floor = math.floor
local max = math.max
local tostring = tostring

-- A toggle's label sits this far below the row's top, and as far above its bottom: one line is
-- centred on the check.
local LABEL_TOP = 6

local function create(frameType, parent, template)
  return _G["CreateFrame"](frameType, nil, parent, template)
end

-- The column's layout, as the pages call it.
Controls.Column = Column.New
Controls.Place = Column.Place
Controls.Section = Column.Section
Controls.Note = Column.Note
Controls.Bar = Column.Bar
Controls.List = Column.List

-- A panel button; `button.label` is its FontString.
function Controls.Button(parent, label, width, onClick)
  local button = create("Button", parent, "UIPanelButtonTemplate")
  button:SetSize(width, Theme.LAYOUT.BUTTON_HEIGHT)
  button:SetText(label)
  button.label = button:GetFontString()
  button:SetScript("OnClick", onClick)
  return button
end

-- A row and its label (`row.labelText`, WhisperMessenger's label font): beside the control, or
-- `stacked` on a line of its own above it, cut at the row's end.
local function newRow(column, label, stacked)
  local layout = Theme.LAYOUT
  local row = create("Frame", column.parent)
  Column.Span(column, row)
  row.settingsLabel = label
  local text = FrameKit.Text(row, Theme.FONTS.setting)
  text:SetText(label)
  row.labelText = text
  if stacked then
    row:SetHeight(layout.LABEL_HEIGHT + layout.CONTROL_HEIGHT)
    text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  else
    row:SetHeight(layout.CONTROL_HEIGHT)
    text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -LABEL_TOP)
  end
  Column.Place(column, row)
  return row, text
end

-- A stacked row's control LABEL_HEIGHT down, on the line under the label, `left` and `right` px
-- in from its edges.
local function underLabel(row, control, left, right)
  local top = -Theme.LAYOUT.LABEL_HEIGHT
  control:SetPoint("TOPLEFT", row, "TOPLEFT", left, top)
  control:SetPoint("TOPRIGHT", row, "TOPRIGHT", -right, top)
end

-- Enter or leaving the box commits a changed text (onCommit(text)); Escape restores the last
-- committed text. Enter and Escape replace the template's scripts (which only clear the focus);
-- the commit on focus loss is hooked, so the template's own focus-lost script still runs.
-- → set(text), which shows a text without committing it, and commit().
local function commitOn(box, onCommit)
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
  box:HookScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function()
    box:SetText(committed)
    box:ClearFocus()
  end)
  return function(text)
    committed = text or ""
    box:SetText(committed)
  end, commit
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

-- Label on the left, wrapped short of the check button on the right; the row grows with the
-- label's lines. onChange(isOn). The client flips the box before OnClick runs, so the box holds
-- the value.
function Controls.Toggle(column, label, onChange)
  local layout = Theme.LAYOUT
  local size = layout.CONTROL_HEIGHT
  local row, text = newRow(column, label)
  local check = create("CheckButton", row, "UICheckButtonTemplate")
  check:SetSize(size, size)
  check:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  text:SetWordWrap(true)
  Column.OnWidth(column, function(width)
    text:SetWidth(max(0, width - size - layout.PADDING))
    row:SetHeight(max(size, text:GetStringHeight() + 2 * LABEL_TOP))
  end)
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
-- The template draws the value text right of the bar, in the room the row keeps there. A change
-- made with the left button up (a stepper click) commits at once; a drag commits when the button
-- comes up. A commit writes the stepped value only when it differs from the last one, so one drag
-- is one write.
function Controls.Slider(column, spec)
  local layout = Theme.LAYOUT
  local row = newRow(column, spec.label, true)
  local slider = create("Frame", row, "MinimalSliderWithSteppersTemplate")
  slider:SetHeight(layout.CONTROL_HEIGHT)
  underLabel(row, slider, 0, layout.SLIDER_VALUE_WIDTH)
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

-- The box under its label, committed as commitOn says. maxLetters (optional) caps the box;
-- without it a long word list is kept whole (a cut text would be committed on focus loss).
-- The template's art reaches 5 px left of the box, so the box starts 5 px in: the art lines up
-- with the label. Its text is in the label font, inset clear of the art's end caps.
function Controls.Input(column, label, onCommit, maxLetters)
  local layout = Theme.LAYOUT
  local row = newRow(column, label, true)
  local box = create("EditBox", row, "InputBoxTemplate")
  box:SetHeight(layout.INPUT_HEIGHT)
  underLabel(row, box, 5, 0)
  box:SetAutoFocus(false)
  box:SetFontObject(Theme.FONTS.setting)
  box:SetTextInsets(layout.INPUT_INSET.left, layout.INPUT_INSET.right, 0, 0)
  if maxLetters then
    box:SetMaxLetters(maxLetters)
  end
  row.input = box
  return { row = row, input = box, Set = commitOn(box, onCommit) }
end

-- A search box (SearchBoxTemplate: magnifier, clear button) with `placeholder` as the template's
-- empty-box text in place of a label, committed as commitOn says. The clear button empties the
-- box and clears its focus; with no focus to lose, its click commits here. The template keeps its
-- own font and insets (room for the magnifier and the clear button). `row.settingsLabel` is the
-- placeholder.
function Controls.Search(column, placeholder, onCommit)
  local row = Column.Bar(column, Theme.LAYOUT.INPUT_HEIGHT)
  row.settingsLabel = placeholder
  local box = create("EditBox", row, "SearchBoxTemplate")
  box:SetPoint("TOPLEFT", row, "TOPLEFT", 5, 0)
  box:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  box.Instructions:SetText(placeholder)
  local set, commit = commitOn(box, onCommit)
  box.clearButton:HookScript("OnClick", commit)
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
-- onChange(value), under its label. The dropdown shows the selected option's text in `input.Text`.
function Controls.Choice(column, label, options, onChange)
  local layout = Theme.LAYOUT
  local row = newRow(column, label, true)
  local current = 1
  local dropdown = create("DropdownButton", row, "WowStyle1DropdownTemplate")
  dropdown:SetHeight(layout.CONTROL_HEIGHT)
  underLabel(row, dropdown, 0, 0)
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

ns.SettingsControls = Controls
return Controls
