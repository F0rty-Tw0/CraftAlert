-- A fake _G.WhisperMessengerAPI (version 1) for the bridge tests; the real one is the sibling WM
-- plan's (.claude/local/plans/2026-10-25-wm-addon-api). Never requires the real WhisperMessenger.
--   local api, wm = FakeWm.install(opts)   -- Wow.stub("WhisperMessengerAPI", api)
--   opts.version                           default 1
--   opts.without = { "ShowPreview" }       leaves those functions out of the API
--   wm.calls                               every call in order, { name, args... } (RegisterPanel included)
--   wm.callsTo(name)                       those entries
--   wm.refuse[name] = true                 that function records the call, changes nothing, returns false
--   wm.raise[name] = true                  that function records the call, then raises
--   wm.preview[key]                        the preview table while shown (ShowPreview sets it, HidePreview clears it)
--   wm.registered                          { { key, panel }, ... }; wm.panels[key] = panel
--   wm.shown[key]                          IsPanelShown
--   wm.badgeRefreshes                      RefreshPanelBadge call count
--   wm.info[key][playerName]               = text (nil removes)
--   wm.showPanel(key, host?)               sets wm.shown[key], runs panel.onShow(host or a 600x400 Frame on UIParent)
--   wm.hidePanel(key)                      clears it, runs panel.onHide()
-- ShowPanel (not refused) shows; TogglePanel (not refused) shows when hidden, hides when shown, and
-- returns true. An unknown panel key returns false, as the real one does.
local Wow = require("tests.helpers.wow")

local FakeWm = {}

local HOST_WIDTH, HOST_HEIGHT = 600, 400

function FakeWm.install(opts)
  opts = opts or {}
  local wm = { calls = {}, refuse = {}, raise = {}, preview = {}, registered = {}, panels = {}, shown = {}, info = {}, badgeRefreshes = 0 }
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

  function wm.showPanel(key, host)
    if host == nil then
      host = _G["CreateFrame"]("Frame", nil, _G["UIParent"])
      host:SetSize(HOST_WIDTH, HOST_HEIGHT)
    end
    wm.shown[key] = true
    wm.panels[key].onShow(host)
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
    wm.registered[#wm.registered + 1] = { key, panel }
    wm.panels[key] = panel
    return true
  end)
  define("ShowPanel", function(key)
    if wm.panels[key] == nil then
      return false
    end
    wm.showPanel(key)
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
  define("SetContactInfo", function(key, name, text)
    wm.info[key] = wm.info[key] or {}
    wm.info[key][name] = text
    return true
  end)

  for _, name in ipairs(opts.without or {}) do
    api[name] = nil
  end
  Wow.stub("WhisperMessengerAPI", api)
  return api, wm
end

return FakeWm
