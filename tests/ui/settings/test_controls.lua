local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")

-- Fresh Theme, FrameKit and Controls on a plain parent frame. → Controls, column, parent, Theme
local function load()
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  local Theme = Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  local Controls = Fresh.require("UI.Settings.Controls")
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  return Controls, Controls.Column(parent), parent, Theme
end

local function recorder()
  local seen = {}
  return seen, function(value)
    seen[#seen + 1] = value
  end
end

local function testColumnStacksRows()
  local Controls, column, parent = load()
  local first = Controls.Section(column, "First")
  local toggle = Controls.Toggle(column, "Second", function() end)
  Assert.same(first.points[1], { "TOPLEFT", parent, "TOPLEFT", 0, 0 })
  local point, relativeTo, relativePoint = toggle.row:GetPoint()
  Assert.same({ point, relativeTo, relativePoint }, { "TOPLEFT", first, "BOTTOMLEFT" }, "each row hangs below the last")
  Assert.equal(toggle.row.settingsLabel, "Second")
end

local function testToggle()
  local Controls, column = load()
  local seen, onChange = recorder()
  local toggle = Controls.Toggle(column, "Enable", onChange)
  Assert.equal(toggle.input.template, "UICheckButtonTemplate")
  toggle.Set(true)
  Assert.same(seen, {}, "Set only shows the value")
  Assert.equal(toggle.input:GetChecked(), true)
  Widgets.click(toggle.input)
  Widgets.click(toggle.input)
  Assert.same(seen, { false, true }, "each click reports the box's new state")
end

local function testSlider()
  local Controls, column = load()
  local seen, onChange = recorder()
  local slider = Controls.Slider(column, { label = "Timeout", min = 1, max = 60, step = 1, onChange = onChange })
  local inner = slider.input.Slider
  Assert.equal(slider.input.template, "MinimalSliderWithSteppersTemplate")
  Assert.same(slider.input.initArgs, { 1, 1, 60, 59 })
  slider.Set(10)
  Assert.same(seen, {}, "Set only moves the thumb")
  Assert.equal(slider.input.Labels[2]:GetText(), "10")
  -- A drag under way: hovering in and out, and moving the thumb, commit nothing.
  Widgets.mouse.LeftButton = true
  inner:SetValue(30)
  Widgets.fire(inner, "OnEnter")
  Widgets.fire(inner, "OnLeave")
  Assert.same(seen, {}, "no commit on interact events")
  inner:SetValue(31)
  inner:SetValue(40)
  Assert.same(seen, {}, "no commit while the button is held")
  Assert.equal(slider.input.Labels[2]:GetText(), "40")
  -- Letting go commits the stepped value once.
  Widgets.mouse.LeftButton = false
  Widgets.fire(inner, "OnMouseUp", "LeftButton")
  Assert.same(seen, { 40 })
  Widgets.step(slider.input, true)
  Assert.same(seen, { 40, 41 }, "a stepper click commits at once")
  Widgets.slide(slider.input, 41)
  Assert.same(seen, { 40, 41 }, "letting go without a change commits nothing")
  slider.Set(12)
  Assert.same(seen, { 40, 41 })
  Widgets.slide(slider.input, 12)
  Assert.same(seen, { 40, 41 }, "Set records the value as committed")
  Widgets.slide(slider.input, 4.6)
  Assert.equal(seen[#seen], 5, "rounded to the step")
  Assert.equal(slider.input.mouseUps, 4, "the template's own OnMouseUp still runs")
  -- A value past the end: the slider clamps it, and Set still reports nothing.
  local before = #seen
  slider.Set(99)
  Assert.equal(#seen, before, "Set never commits")
  Assert.equal(slider.input.Labels[2]:GetText(), "60")
  local opacitySeen, onOpacity = recorder()
  local opacity = Controls.Slider(column, {
    label = "Opacity",
    min = 0.3,
    max = 1,
    step = 0.05,
    format = function(value)
      return string.format("%d%%", value * 100 + 0.5)
    end,
    onChange = onOpacity,
  })
  Assert.equal(opacity.input.initArgs[4], 14, "(1 - 0.3) / 0.05 counts 14 steps")
  opacity.Set(1)
  Assert.equal(opacity.input.Labels[2]:GetText(), "100%")
  Widgets.slide(opacity.input, 0.62)
  Assert.same(opacitySeen, { 0.6 }, "rounded to the step")
  Assert.equal(opacity.input.Labels[2]:GetText(), "60%")
end

local function testInput()
  local Controls, column = load()
  local seen, onCommit = recorder()
  local input = Controls.Input(column, "Item", onCommit)
  Assert.equal(input.input.template, "InputBoxTemplate")
  input.Set("Hi")
  Assert.same(seen, {}, "Set only shows the text")
  Widgets.type(input.input, "Hello")
  Assert.same(seen, { "Hello" }, "Enter commits")
  Assert.equal(input.input:HasFocus(), false, "and leaves the box")
  -- Focus lost commits a change; Escape puts the committed text back.
  input.input:SetFocus()
  input.input.text = "Hey"
  input.input:ClearFocus()
  Assert.same(seen, { "Hello", "Hey" })
  input.input:SetFocus()
  input.input.text = "typo"
  input.input.scripts.OnEscapePressed(input.input)
  Assert.equal(input.input:GetText(), "Hey")
  Assert.same(seen, { "Hello", "Hey" }, "Escape commits nothing")
end

local function testChoice()
  local Controls, column = load()
  local seen, onChange = recorder()
  local options = { { value = 0, text = "None" }, { value = 8959, text = "Sound 1" }, { value = 3081, text = "Sound 2" } }
  local choice = Controls.Choice(column, "Sound", options, onChange)
  Assert.equal(choice.input.template, "WowStyle1DropdownTemplate")
  choice.Set(8959)
  Assert.same(seen, {}, "Set only shows the value")
  Assert.equal(choice.input.Text:GetText(), "Sound 1")
  local entries = {}
  for _, entry in ipairs(choice.input.menuEntries) do
    entries[#entries + 1] = entry.text
  end
  Assert.same(entries, { "None", "Sound 1", "Sound 2" }, "one radio per option")
  Widgets.pick(choice.input, 3081)
  Assert.same(seen, { 3081 })
  Assert.equal(choice.input.Text:GetText(), "Sound 2")
  Assert.equal(choice.Value(), 3081)
  -- New options keep the shown value when it is still offered, else show the first.
  choice.SetOptions({ { value = 3081, text = "Only" } }, 9999)
  Assert.equal(choice.input.Text:GetText(), "Only")
  Assert.equal(choice.Value(), 3081)
  Assert.same(seen, { 3081 }, "SetOptions reports nothing")
  choice.SetOptions({}, nil)
  Assert.equal(choice.Value(), nil)
  Assert.equal(choice.input.Text:GetText(), "")
end

local function testButton()
  local Controls, _, parent = load()
  local clicks = 0
  local button = Controls.Button(parent, "Go", 48, function()
    clicks = clicks + 1
  end)
  Assert.equal(button.template, "UIPanelButtonTemplate")
  Assert.equal(button.label:GetText(), "Go")
  Widgets.click(button)
  Assert.equal(clicks, 1)
end

local function testSectionKeepsFontColour()
  local Controls, column = load()
  local section = Controls.Section(column, "Sounds")
  Assert.equal(section.textColor, nil, "the font object's colour stands")
end

local function testListPages()
  local Controls, column, _, Theme = load()
  local list = Controls.List(column, 3, function(row)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  end)
  for index, row in ipairs(list.rows) do
    local highlight
    for _, region in ipairs(row.regions) do
      if region.layer == "HIGHLIGHT" then
        highlight = region
      end
    end
    Assert.equal(highlight and highlight.texture, Theme.ART.LIST_HOVER, "row " .. index .. " lights up on hover")
  end
  local function shown()
    local texts = {}
    for _, row in ipairs(list.rows) do
      if row:IsShown() then
        texts[#texts + 1] = row.text:GetText()
      end
    end
    return table.concat(texts, ",")
  end
  local show = function(row, item)
    row.text:SetText(item)
  end
  list.Render({ "a", "b", "c", "d", "e" }, show)
  Assert.equal(shown(), "a,b,c")
  list.frame.scripts.OnMouseWheel(list.frame, -1)
  Assert.equal(shown(), "b,c,d")
  list.frame.scripts.OnMouseWheel(list.frame, -5)
  Assert.equal(shown(), "c,d,e", "never past the last page")
  list.Render({ "x" }, show)
  Assert.equal(shown(), "x", "a shorter list scrolls back")
end

local function frame(frameType, template)
  return _G["CreateFrame"](frameType, nil, _G["UIParent"], template)
end

local function testFakeCheckButton()
  Wow.reset()
  local c = frame("CheckButton", "UICheckButtonTemplate")
  c:SetChecked(true)
  Assert.equal(c:GetChecked(), true)
  Assert.truthy(c.Text, "the template's label")
  local seen = {}
  c:SetScript("OnClick", function(self)
    seen[#seen + 1] = self:GetChecked()
  end)
  Widgets.click(c)
  Assert.same(seen, { false }, "the client flips the box before the script runs")
  Assert.equal(c:GetChecked(), false)
end

local function testFakeSlider()
  Wow.reset()
  local s = frame("Frame", "MinimalSliderWithSteppersTemplate")
  Assert.equal(rawget(_G, "MinimalSliderWithSteppersMixin").Label.Right, 2)
  local seen = {}
  local mouseDown = {}
  s:RegisterCallback(s.Event.OnValueChanged, function(_, value)
    seen[#seen + 1] = value
    mouseDown[#mouseDown + 1] = _G["IsMouseButtonDown"]("LeftButton")
  end, s)
  s:Init(5, 1, 10, 9, {
    [2] = function(v)
      return v .. "!"
    end,
  })
  Assert.equal(s.Labels[2]:GetText(), "5!")
  Assert.truthy(s.Labels[2]:IsShown())
  Assert.falsy(s.Labels[1]:IsShown(), "labels without a formatter stay hidden")
  Assert.same(seen, {}, "Init sets the value before it installs the script")
  Assert.same(s.initArgs, { 5, 1, 10, 9 })
  Assert.equal(s.Slider:GetValueStep(), 1)
  s.Slider:SetValue(7)
  Assert.same(seen, { 7 })
  Assert.equal(s.Labels[2]:GetText(), "7!")
  Widgets.step(s, true)
  Assert.same(seen, { 7, 8 })
  Widgets.step(s, false)
  Assert.same(seen, { 7, 8, 7 })
  mouseDown = {}
  Widgets.slide(s, 3)
  Assert.equal(seen[#seen], 3)
  Assert.same(mouseDown, { true }, "the button is held while the thumb moves")
  Assert.equal(_G["IsMouseButtonDown"]("LeftButton"), false, "and up afterwards")
  Assert.equal(s.mouseUps, 1)
  local hooked = 0
  s.Slider:HookScript("OnMouseUp", function()
    hooked = hooked + 1
  end)
  Widgets.fire(s.Slider, "OnMouseUp")
  Assert.same({ s.mouseUps, hooked }, { 2, 1 }, "the mixin's script runs, then the hook")
end

local function testFakeDropdown()
  Wow.reset()
  local d = frame("DropdownButton", "WowStyle1DropdownTemplate")
  local current = 2
  local picked = {}
  local function isSel(value)
    return current == value
  end
  local function onSel(value)
    picked[#picked + 1] = value
  end
  d:SetupMenu(function(_, root)
    root:CreateRadio("A", isSel, onSel, 1)
    root:CreateRadio("B", isSel, onSel, 2)
  end)
  d:GenerateMenu()
  Assert.equal(d.Text:GetText(), "B")
  Assert.equal(#d.menuEntries, 2, "generating again replaces the entries")
  Widgets.pick(d, 1)
  Assert.same(picked, { 1 })
  current = 1
  d:GenerateMenu()
  Assert.equal(d.Text:GetText(), "A")
  Assert.raises(function()
    Widgets.pick(d, 9)
  end, "no radio")
end

local function testFakeButton()
  Wow.reset()
  local b = frame("Button", "UIPanelButtonTemplate")
  b:SetText("Go")
  Assert.equal(b:GetText(), "Go")
  Assert.equal(b:GetFontString():GetText(), "Go")
  b:LockHighlight()
  Assert.equal(b.highlightLocked, true)
  b:UnlockHighlight()
  Assert.equal(b.highlightLocked, false)
end

local function testFakeResizeMins()
  Wow.reset()
  local target = frame("Frame")
  local button = frame("Button", "PanelResizeButtonTemplate")
  button:Init(target, 360, 160, 1000, 800)
  button:SetMinWidth(600)
  button:SetMinHeight(480)
  button.isActive = true
  target:GetScript("OnSizeChanged")(target, 500, 400)
  Assert.same({ target:GetWidth(), target:GetHeight() }, { 600, 480 }, "the wrapper reads the new mins")
end

return function()
  testColumnStacksRows()
  testToggle()
  testSlider()
  testInput()
  testChoice()
  testButton()
  testSectionKeepsFontColour()
  testListPages()
  testFakeCheckButton()
  testFakeSlider()
  testFakeDropdown()
  testFakeButton()
  testFakeResizeMins()
end
