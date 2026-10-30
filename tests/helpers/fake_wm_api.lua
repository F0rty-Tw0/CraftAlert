-- A fake _G.WhisperMessengerAPI (version 1) for the bridge tests; the real one is the sibling WM
-- plan's (.claude/local/plans/2026-10-25-wm-addon-api). Never requires the real WhisperMessenger.
--   local api, wm = FakeWm.install(opts)   -- Wow.stub("WhisperMessengerAPI", api)
--   opts.version                           default 1
--   opts.without = { "ShowPreview" }       leaves those functions out of the API
--   wm.calls                               every call in order, { name, args... } (RegisterPanel included)
--   wm.callsTo(name)                       those entries
--   wm.refuse[name] = true                 that function records the call, changes nothing, returns false
--   wm.raise[name] = true                  that function records the call, then raises
--   wm.look                                what GetLook answers (nil: no look); GetLook is not recorded in
--                                            wm.calls, and honours wm.refuse.GetLook (false) and wm.raise.GetLook
--   wm.preview[key]                        the preview table while shown (ShowPreview sets it, HidePreview clears it)
--   wm.registered                          { { key, panel }, ... }; wm.panels[key] = a copy of the panel's
--                                            fields taken at RegisterPanel, as WM's copyPanel does
--   wm.shown[key]                          IsPanelShown
--   wm.badgeRefreshes                      RefreshPanelBadge call count
--   wm.unread[name]                        = the count GetUnreadCount answers for that name (0 for non-string,
--                                            blank and unknown names, as WM's UnreadCount.lua does)
--   wm.unreadChanged(key)                  runs the panel's onUnreadChanged when it has one (WM calls it
--                                            with no arguments); RegisterPanel keeps it only when nil or a function
--   wm.info[key][playerName]               = text (nil removes)
--   wm.tips[key][playerName]               = the tooltip lines (nil clears); SetContactInfo returns false,
--                                            changing nothing, unless lines is nil or 1-10 non-empty strings
--   wm.showPanel(key, host?, listWidth?)   sets wm.shown[key], runs panel.onShow(host or a 600x400 Frame on UIParent),
--                                          then panel.onSplit(host, listWidth) when both exist; wm.hosts[key] = host
--   wm.split(key, listWidth)               runs panel.onSplit on the host showPanel last used
--   wm.hidePanel(key)                      clears it, runs panel.onHide()
-- ShowPanel (not refused) shows; on a panel already shown it returns true without running onShow, as
-- WM's does (UI/MessengerWindow/MessengerWindow/WindowVisibility.lua:116-117, WM). TogglePanel (not
-- refused) shows when hidden, hides when shown, and returns true. An unknown panel key returns
-- false, as the real one does. OpenConversation (not refused) hides every shown panel (wm.hidePanel)
-- and returns true: WM shows the conversation in the panel's place (Core/PublicApi.lua:52, WM).
local Wow = require("tests.helpers.wow")

local FakeWm = {}

local HOST_WIDTH, HOST_HEIGHT = 600, 400
local MAX_TOOLTIP_LINES = 10

-- WM's isValidTooltip (Model/ContactInfo.lua): nil, or an array of 1..10 non-empty strings.
local function validTooltip(lines)
  if lines == nil then
    return true
  end
  if type(lines) ~= "table" or #lines < 1 or #lines > MAX_TOOLTIP_LINES then
    return false
  end
  local count = 0
  for _, line in pairs(lines) do
    if type(line) ~= "string" or line == "" then
      return false
    end
    count = count + 1
  end
  return count == #lines
end

function FakeWm.install(opts)
  opts = opts or {}
  local wm = {
    calls = {},
    refuse = {},
    raise = {},
    preview = {},
    registered = {},
    panels = {},
    shown = {},
    hosts = {},
    info = {},
    tips = {},
    badgeRefreshes = 0,
    unread = {},
  }
  ---@type table<string, any>
  local api = { version = opts.version or 1 }

  function wm.callsTo(name)
    local found = {}
    for _, call in ipairs(wm.calls) do
      if call[1] == name then
        found[#found + 1] = call
      end
    end
    return found
  end

  function wm.showPanel(key, host, listWidth)
    if host == nil then
      host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
      host:SetSize(HOST_WIDTH, HOST_HEIGHT)
    end
    wm.shown[key] = true
    wm.hosts[key] = host
    local panel = wm.panels[key]
    panel.onShow(host)
    if listWidth ~= nil and panel.onSplit then
      panel.onSplit(host, listWidth)
    end
  end

  function wm.split(key, listWidth)
    wm.panels[key].onSplit(wm.hosts[key], listWidth)
  end

  function wm.unreadChanged(key)
    local callback = wm.panels[key].onUnreadChanged
    if callback then
      callback()
    end
  end

  function wm.hidePanel(key)
    wm.shown[key] = false
    wm.panels[key].onHide()
  end

  -- Records the call, then answers false when refused, else runs `effect`, which returns the result.
  local function define(name, effect)
    api[name] = function(...)
      wm.calls[#wm.calls + 1] = { name, ... }
      if wm.raise[name] then
        error("WhisperMessengerAPI." .. name .. " raised")
      end
      if wm.refuse[name] then
        return false
      end
      return effect(...)
    end
  end

  define("OpenConversation", function()
    for key, shown in pairs(wm.shown) do
      if shown then
        wm.hidePanel(key)
      end
    end
    return true
  end)
  define("ShowPreview", function(key, preview)
    wm.preview[key] = preview
    return true
  end)
  define("HidePreview", function(key)
    wm.preview[key] = nil
    return true
  end)
  define("IsPreviewShown", function(key)
    return wm.preview[key] ~= nil
  end)
  define("RegisterPanel", function(key, panel)
    -- WM's isOptionalFunction (Core/PublicApi/Panels.lua): anything but nil or a function is refused.
    if panel.onUnreadChanged ~= nil and type(panel.onUnreadChanged) ~= "function" then
      return false
    end
    wm.registered[#wm.registered + 1] = { key, panel }
    -- WM keeps a copy read once (copyPanel): fields the caller sets after registering never reach it.
    wm.panels[key] = {
      title = panel.title,
      onShow = panel.onShow,
      onHide = panel.onHide,
      onSplit = panel.onSplit,
      badge = panel.badge,
      onMarkAllRead = panel.onMarkAllRead,
      onUnreadChanged = panel.onUnreadChanged,
    }
    return true
  end)
  define("ShowPanel", function(key)
    if wm.panels[key] == nil then
      return false
    end
    if not wm.shown[key] then
      wm.showPanel(key)
    end
    return true
  end)
  define("TogglePanel", function(key)
    if wm.panels[key] == nil then
      return false
    end
    if wm.shown[key] then
      wm.hidePanel(key)
    else
      wm.showPanel(key)
    end
    return true
  end)
  define("IsPanelShown", function(key)
    return wm.shown[key] == true
  end)
  define("RefreshPanelBadge", function()
    wm.badgeRefreshes = wm.badgeRefreshes + 1
    return true
  end)
  define("SetContactInfo", function(key, name, text, lines)
    if not validTooltip(lines) then
      return false
    end
    wm.info[key] = wm.info[key] or {}
    wm.info[key][name] = text
    wm.tips[key] = wm.tips[key] or {}
    wm.tips[key][name] = lines
    return true
  end)

  define("GetUnreadCount", function(name)
    if type(name) ~= "string" or name:match("^%s*$") then
      return 0
    end
    return wm.unread[name] or 0
  end)

  api.GetLook = function()
    if wm.raise.GetLook then
      error("WhisperMessengerAPI.GetLook raised")
    end
    if wm.refuse.GetLook then
      return false
    end
    return wm.look
  end

  for _, name in ipairs(opts.without or {}) do
    api[name] = nil
  end
  Wow.stub("WhisperMessengerAPI", api)
  return api, wm
end

return FakeWm
