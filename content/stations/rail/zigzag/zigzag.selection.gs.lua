local constructionPath = ug_require(
"apasz_zigzag::/zigzag/construction_path.lua")

local CALLBACK_PREFIX = "zigzag.selection.script@"

function data()
   local descriptor = {
      updateScript = {
         fileName = CALLBACK_PREFIX .. "update",
      },

      handleEventScript = {
         fileName = CALLBACK_PREFIX .. "handleEvent",
      },
      guiHandleEventScript = {
         fileName = CALLBACK_PREFIX .. "guiHandleEvent",
         params = {
            constructionFileName = getOwningModId() .. constructionPath,
         },
      },
   }
   return descriptor
end
