local Assert = require("tests.helpers.assert")
local Fresh = require("tests.helpers.fresh")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")

-- Fresh Theme, FrameKit and Controls on a plain parent frame. → Controls, column, parent
local function load()
  Wow.reset()
  Wow.flavor("retail")
  Fresh.require("Core.FlavorCompat")
  Fresh.require("UI.Theme")
  Fresh.require("UI.FrameKit")
  local Controls = Fresh.require("UI.Settings.Controls")
  local parent = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
  return Controls, Controls.Column(parent), parent
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
  toggle.Set(true)
  Assert.same(seen, {}, "Set only paints")
  Widgets.click(toggle.input)
  Widgets.click(toggle.input)
  Assert.same(seen, { false, true }, "each click flips the value and reports it")
  Assert.equal(toggle.input.knob.points[1][1], "RIGHT", "knob on the right while on")
end

local function testSlider()
  local Controls, column = load()
  local seen, onChange = recorder()
  local slider = Controls.Slider(column, { label = "Timeout", min = 1, max = 60, step = 1, onChange = onChange })
  slider.Set(10)
  Assert.same(seen, {}, "Set only moves the thumb")
  Assert.truthy(table.concat(Widgets.texts(slider.row, Wow.frames), " "):find("10", 1, true))
  -- Dragging only updates the value text; letting go commits the stepped value once.
  slider.input:SetValue(4.6)
  Assert.same(seen, {})
  Assert.truthy(table.concat(Widgets.texts(slider.row, Wow.frames), " "):find("5", 1, true))
  slider.input.scripts.OnMouseUp(slider.input, "LeftButton")
  Assert.same(seen, { 5 })
  Widgets.slide(slider.input, 5)
  Assert.same(seen, { 5 }, "letting go without a change commits nothing")
  local opacity = Controls.Slider(column, {
    label = "Opacity",
    min = 0.3,
    max = 1,
    step = 0.05,
    format = function(value)
      return string.format("%d%%", value * 100 + 0.5)
    end,
    onChange = onChange,
  })
  opacity.Set(1)
  Widgets.slide(opacity.input, 0.62)
  Assert.equal(seen[2], 0.6, "rounded to the step")
  Assert.truthy(table.concat(Widgets.texts(opacity.row, Wow.frames), " "):find("60%", 1, true))
end

local function testInput()
  local Controls, column = load()
  local seen, onCommit = recorder()
  local input = Controls.Input(column, "Item", onCommit)
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
  choice.Set(8959)
  Assert.same(seen, {})
  Assert.equal(choice.input.label:GetText(), "Sound 1")
  Widgets.click(choice.input, "LeftButton")
  Widgets.click(choice.input, "LeftButton")
  Widgets.click(choice.input, "RightButton")
  Assert.same(seen, { 3081, 0, 3081 }, "left: next (wrapping), right: previous")
  -- New options keep the shown value when it is still offered, else show the first.
  choice.SetOptions({ { value = 3081, text = "Only" } }, 9999)
  Assert.equal(choice.input.label:GetText(), "Only")
  Assert.equal(choice.Value(), 3081)
end

local function testListPages()
  local Controls, column = load()
  local list = Controls.List(column, 3, function(row)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  end)
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

return function()
  testColumnStacksRows()
  testToggle()
  testSlider()
  testInput()
  testChoice()
  testListPages()
end
