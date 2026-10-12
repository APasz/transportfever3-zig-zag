local constructionPath = ug_require(
    "apasz_zigzag::/zigzag/construction_path.lua"
) as string
local CALLBACK_PREFIX = "zigzag.selection.script@"

function data(): any
    local descriptor: api.type.GameScriptDesc = {
        updateScript = {
            fileName = CALLBACK_PREFIX .. "update",
        },
        -- The engine requires a simulation event handler to dispatch GUI events.
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
