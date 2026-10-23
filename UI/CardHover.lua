local addonName, ns = ...
if type(ns) ~= "table" then
  ns = {}
end

local Localization = ns.Localization or require("CraftAlert.Core.Localization")
local Leads = ns.Leads or require("CraftAlert.Model.Leads")
local GreetAction = ns.GreetAction or require("CraftAlert.Model.GreetAction")
local Theme = ns.Theme or require("CraftAlert.UI.Theme")
local ClickRouter = ns.ClickRouter or require("CraftAlert.UI.ClickRouter")

-- Lead-cards spec §2, §3: the hover highlight and the Greet / Whisper / Dismiss buttons of a card.
-- They show while the cursor is anywhere inside the card, its child frames included: a child takes
-- the mouse focus from the card, so the card's HIGHLIGHT-layer texture would go dark under a button.
-- The card therefore locks its highlight by the same rule as the buttons show. One card at a time.
local CardHover = {}

local BUTTON_GAP = 4
local BUTTON_BOTTOM = 4

-- Left to right: each button's key in card.buttons, its label and what it does to the card's lead,
-- read at click time.
local ACTIONS = {
  {
    key = "greet",
    label = "Greet",
    run = function(card)
      ClickRouter.Handle("LeftButton", card.lead, card.shownAt)
    end,
  },
  {
    key = "whisper",
    label = "Whisper",
    run = function(card)
      GreetAction.Empty(card.lead)
    end,
  },
  {
    key = "dismiss",
    label = "Dismiss",
    run = function(card)
      Leads.Dismiss(card.lead.id)
    end,
  },
}

local function hideHover(card)
  for _, button in pairs(card.buttons) do
    button:Hide()
  end
  card:UnlockHighlight()
end

-- Shows this card's buttons and highlight, and hides them on every other card of the list.
function CardHover.Enter(card)
  for _, other in ipairs(card.list.rows) do
    if other ~= card then
      hideHover(other)
    end
  end
  for _, button in pairs(card.buttons) do
    button:Show()
  end
  card:LockHighlight()
end

-- The cursor left the card or one of its children: still inside the card (on a child, or a shared
-- edge) keeps them.
function CardHover.Leave(card)
  if not card:IsMouseOver() then
    hideHover(card)
  end
end

local function createButton(card, action, index, width)
  local layout = Theme.LAYOUT
  local button = _G["CreateFrame"]("Button", nil, card, "UIPanelButtonTemplate")
  button:SetSize(width, layout.BUTTON_HEIGHT)
  button:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", layout.PADDING + (index - 1) * (width + BUTTON_GAP), BUTTON_BOTTOM)
  button:SetText(Localization.Text(action.label))
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", function()
    if card.lead then
      action.run(card)
    end
  end)
  button:HookScript("OnEnter", function()
    CardHover.Enter(card)
  end)
  button:HookScript("OnLeave", function()
    CardHover.Leave(card)
  end)
  button:Hide()
  return button
end

-- Adds the three buttons (card.buttons, keyed greet, whisper, dismiss; hidden) and the hover scripts
-- to a card of `list`. The card's own scripts stay: HookScript runs after them. No card or button
-- registers a drag.
function CardHover.Attach(card, list)
  local layout = Theme.LAYOUT
  local count = #ACTIONS
  local width = (layout.CARD_LEFT_WIDTH - 2 * layout.PADDING - (count - 1) * BUTTON_GAP) / count
  card.list = list
  card.buttons = {}
  for index, action in ipairs(ACTIONS) do
    card.buttons[action.key] = createButton(card, action, index, width)
  end
  card:HookScript("OnEnter", CardHover.Enter)
  card:HookScript("OnLeave", CardHover.Leave)
  card:HookScript("OnHide", hideHover)
  -- A card hidden while hovered comes back without stale buttons; one shown under the cursor shows them.
  card:HookScript("OnShow", function()
    if card:IsMouseOver() then
      CardHover.Enter(card)
    end
  end)
end

ns.CardHover = CardHover
return CardHover
