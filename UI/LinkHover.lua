local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

-- Native-HUD spec §4.5: hover tooltips and clicks for hyperlinks inside a frame's own text. A frame
-- reads its hovered link through IsOverLink so a click on a link never greets the lead.
local LinkHover = {}

local pcall = pcall
local type = type

local function tooltip()
  return _G["GameTooltip"]
end

local function linkType(link)
  local head = link:match("^([^:]*)")

  return head:lower()
end

local function showTooltip(frame, link)
  local tip = tooltip()
  tip:SetOwner(frame, "ANCHOR_CURSOR")
  local ok = pcall(tip.SetHyperlink, tip, link)
  if not ok then
    tip:SetText(link)
  end
  tip:Show()
end

local function hideIfOwned(frame)
  local tip = tooltip()
  local owned = tip:IsOwned(frame)
  if owned then
    tip:Hide()
  end
end

-- A trade link shows no tooltip, so one the frame itself owns (a card's chat line) goes instead.
local function onEnter(frame, link)
  frame.hoveredLink = link
  local isTrade = linkType(link) == "trade"
  if isTrade then
    hideIfOwned(frame)
    return
  end
  showTooltip(frame, link)
end

-- Off a link: hides the link's tooltip, never one a child frame has shown since.
local function makeOnLeave(onBodyEnter)
  return function(frame)
    LinkHover.Clear(frame)
    local backOnBody = onBodyEnter ~= nil and frame:IsMouseOver()
    if backOnBody then
      onBodyEnter(frame)
    end
  end
end

local function onClick(frame, link, text, button)
  local setItemRef = _G["SetItemRef"]
  if type(setItemRef) == "function" then
    setItemRef(link, text, button, frame)
  end
end

-- → true while the cursor is on a link inside frame.
function LinkHover.IsOverLink(frame)
  return frame.hoveredLink ~= nil
end

-- Forgets the hovered link; hides the tooltip only when frame owns it.
function LinkHover.Clear(frame)
  frame.hoveredLink = nil
  hideIfOwned(frame)
end

-- onBodyEnter(frame): called when the cursor leaves a link while still over the frame.
function LinkHover.Attach(frame, onBodyEnter)
  frame:SetHyperlinksEnabled(true)
  frame:SetScript("OnHyperlinkEnter", onEnter)
  frame:SetScript("OnHyperlinkLeave", makeOnLeave(onBodyEnter))
  frame:SetScript("OnHyperlinkClick", onClick)
  frame:HookScript("OnHide", LinkHover.Clear)
  frame:HookScript("OnLeave", LinkHover.Clear)
end

ns.LinkHover = LinkHover
return LinkHover
