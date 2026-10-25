local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local Widgets = require("tests.helpers.widgets")
local Templates = require("tests.helpers.templates")

-- The stub layer the tests and tools/sim.lua share: a reset leaves nothing of the last run.
return function()
  Wow.reset()
  local frame = _G["CreateFrame"]("Frame", "CraftAlertResetProbe")
  Assert.equal(rawget(_G, "CraftAlertResetProbe"), frame, "a named frame is a global, as in the client")
  _G["CreateFrame"]("Frame", nil)
  Assert.equal(#Wow.frames, 2)
  Wow.reset()
  Assert.equal(rawget(_G, "CraftAlertResetProbe"), nil, "the named frame is gone")
  Assert.same(Wow.frames, {})
  -- TooltipBackdropTemplate: colour calls reach the NineSlice child, which is not a frame.
  local parent = rawget(_G, "UIParent")
  local box = rawget(_G, "CreateFrame")("Button", nil, parent, "TooltipBackdropTemplate")
  box:SetBackdropColor(0.1, 0.2, 0.3, 0.4)
  Assert.same({ box:GetBackdropColor() }, { 0.1, 0.2, 0.3, 0.4 })
  Assert.equal(#Wow.frames, 1)
  Assert.equal(rawget(_G, "CreateFrame")("Frame", nil, parent, "NoSuchTemplate").NineSlice, nil)
  -- Hide runs OnHide, then its hooks, once, and only for a shown frame.
  local order = {}
  box:SetScript("OnHide", function()
    order[#order + 1] = "script"
  end)
  box:HookScript("OnHide", function()
    order[#order + 1] = "hook"
  end)
  box:Hide()
  box:Hide()
  Assert.same(order, { "script", "hook" })
  Widgets.fire(box, "OnLeave") -- no script, no hooks: nothing happens
  -- GetStringHeight: LINE_HEIGHT per wrapped line of the visible text.
  local fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetWordWrap(true)
  fs:SetWidth(10 * Widgets.CHAR_WIDTH)
  fs:SetText("0123456789012345678901234")
  Assert.equal(fs:GetStringHeight(), 3 * Widgets.LINE_HEIGHT)
  fs:SetText("|cff1eff00|Hitem:1::|h[0123456789]|h|r")
  Assert.equal(fs:GetStringHeight(), 2 * Widgets.LINE_HEIGHT)
  fs:SetWordWrap(false)
  Assert.equal(fs:GetStringHeight(), Widgets.LINE_HEIGHT)
  fs:SetText("")
  Assert.equal(fs:GetStringHeight(), 0)
  -- GetCenter, masks, animation groups, SetItemRef and the atlas default.
  Assert.equal(parent:GetCenter(), 960)
  Assert.equal(box:GetCenter(), nil)
  local tex = box:CreateTexture()
  tex:AddMaskTexture(box:CreateMaskTexture())
  Assert.equal(tex.masks[1].isMask, true)
  local group, seen = tex:CreateAnimationGroup(), {}
  group:SetScript("OnStop", function()
    seen[#seen + 1] = "stop"
  end)
  group:Play()
  Assert.equal(group:IsPlaying(), true)
  group:Stop()
  group:Stop()
  Assert.same(seen, { "stop" })
  rawget(_G, "SetItemRef")("item:1", "[x]", "LeftButton", box)
  Assert.same(Wow.itemRefs, { { "item:1", "[x]", "LeftButton", box } })
  Assert.equal(type(rawget(_G, "C_Texture").GetAtlasInfo("Any")), "table")
  -- SetClipsChildren is stored; the portrait template fakes follow ButtonFrameTemplate.
  box:SetClipsChildren(true)
  Assert.equal(box.clipsChildren, true)
  local window = rawget(_G, "CreateFrame")("Frame", nil, parent, "ButtonFrameTemplate")
  window:SetPortraitToAsset("asset")
  Assert.equal(window.portraitAsset, "asset")
  window.PortraitContainer.portrait:SetTexture("file")
  Assert.equal(window.PortraitContainer.portrait.texture, "file")
  Templates.portraitMethod = false
  local classic = rawget(_G, "CreateFrame")("Frame", nil, parent, "ButtonFrameTemplate")
  Templates.portraitMethod = true
  Assert.equal(classic.SetPortraitToAsset, nil)
  Assert.equal(type(classic.PortraitContainer.portrait.SetTexture), "function")
  local inset = rawget(_G, "CreateFrame")("Frame", nil, parent, "InsetFrameTemplate")
  Assert.equal(inset.Bg.layer, "BACKGROUND")
end
