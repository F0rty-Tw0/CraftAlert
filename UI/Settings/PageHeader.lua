local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local FrameKit = ns.FrameKit or require("CraftAlert.UI.FrameKit")

-- The row above a settings page in a narrow host: the shared back arrow (texture only, no text,
-- no tooltip; a click runs onBack) and the page's title right of it.
local PageHeader = {}

function PageHeader.New(parent, onBack)
  local layout, art = Theme.LAYOUT, Theme.ART
  local header = _G["CreateFrame"]("Frame", nil, parent)
  header:SetHeight(layout.NAV_BUTTON_HEIGHT)
  header.pageHeader = true

  local back = _G["CreateFrame"]("Button", nil, header)
  back:SetSize(layout.GEAR_SIZE, layout.GEAR_SIZE)
  back:SetPoint("LEFT", header, "LEFT", layout.SPACE.S, 0)
  back:RegisterForClicks("LeftButtonUp")
  back.normal = back:CreateTexture(nil, "ARTWORK")
  FrameKit.Art(back.normal, art.BACK_ATLAS, art.BACK_FILE)
  back:SetNormalTexture(back.normal)
  back.highlight = back:CreateTexture(nil, "HIGHLIGHT")
  FrameKit.Art(back.highlight, art.BACK_ATLAS, art.BACK_FILE, "ADD")
  back:SetHighlightTexture(back.highlight)
  back:SetScript("OnClick", function()
    onBack()
  end)
  header.back = back

  local title = FrameKit.Text(header, Theme.FONTS.name)
  title:SetPoint("LEFT", back, "RIGHT", layout.SPACE.S, 0)
  title:SetPoint("RIGHT", header, "RIGHT", -layout.SPACE.S, 0)
  header.title = title

  return header
end

ns.PageHeader = PageHeader
return PageHeader
