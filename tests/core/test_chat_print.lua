local Assert = require("tests.helpers.assert")
local Wow = require("tests.helpers.wow")
local ChatPrint = require("CraftAlert.Core.ChatPrint")

return function()
  Wow.reset()

  Assert.truthy(ChatPrint.Line("hello"))
  Assert.equal(#Wow.chat, 1)
  Assert.equal(Wow.chat[1], "|cffffd100Craft Alert:|r hello")

  -- No chat frame (or one without AddMessage) is not an error.
  Wow.stub("DEFAULT_CHAT_FRAME", nil)
  Assert.falsy(ChatPrint.Line("lost"))
  Wow.stub("DEFAULT_CHAT_FRAME", {})
  Assert.falsy(ChatPrint.Line("lost"))

  Wow.reset()
end
