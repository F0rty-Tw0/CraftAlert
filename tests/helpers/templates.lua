-- Fakes of the Blizzard frame templates the addon creates by name, so UI modules run in plain Lua.
--   Templates.Apply(frame, name)   gives `frame` what template `name` adds; an unknown name does nothing
--   Templates.fakes[name]          function(frame) that installs one template's children and methods
-- Widgets.extend calls Apply once the frame's own widget methods exist, before CreateFrame returns it.
-- That is earlier than newFrame (tests/helpers/wow.lua) defines SetScript/HookScript/Show/Hide, so a
-- fake that needs a script writes `frame.scripts.X` (and `frame.hooks.X`) directly.
local Templates = { fakes = {} }

local unpack = unpack

-- Backdrop calls the frame forwards to its NineSlice child: frame method, NineSlice method.
local BACKDROP_FORWARDS = {
  { "SetBackdropColor", "SetCenterColor" },
  { "GetBackdropColor", "GetCenterColor" },
  { "SetBackdropBorderColor", "SetBorderColor" },
  { "GetBackdropBorderColor", "GetBorderColor" },
  { "SetBorderBlendMode", "SetBorderBlendMode" },
}

-- The child is a plain table, not a stub frame, so it stays out of Wow.frames.
local function newNineSlice()
  local nineSlice = {}

  function nineSlice:SetCenterColor(r, g, b, a)
    self.centerColor = { r, g, b, a }
  end

  function nineSlice:GetCenterColor()
    return unpack(self.centerColor or {})
  end

  function nineSlice:SetBorderColor(r, g, b, a)
    self.borderColor = { r, g, b, a }
  end

  function nineSlice:GetBorderColor()
    return unpack(self.borderColor or {})
  end

  function nineSlice:SetBorderBlendMode(mode)
    self.borderBlendMode = mode
  end

  return nineSlice
end

-- Blizzard_SharedXML/SharedTooltipTemplates.xml:111-121 (the NineSlice child, parentKey="NineSlice")
-- and SharedTooltipTemplates.lua:226-261 (TooltipBackdropTemplateMixin forwards each call to
-- self.NineSlice; the same mixin sits in ui_forever :232 and in ui_classic and ui_classic_era :226).
function Templates.fakes.TooltipBackdropTemplate(frame)
  frame.NineSlice = newNineSlice()
  for _, forward in ipairs(BACKDROP_FORWARDS) do
    local frameMethod, nineSliceMethod = forward[1], forward[2]
    frame[frameMethod] = function(self, ...)
      local nineSlice = self.NineSlice

      return nineSlice[nineSliceMethod](nineSlice, ...)
    end
  end
end

function Templates.Apply(frame, templateName)
  local fake = Templates.fakes[templateName]
  if fake == nil then
    return
  end
  fake(frame)
end

return Templates
