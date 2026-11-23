local logger = ug_require "apasz_zigzag::/zigzag/logger.lua" as ModLogging.Logger

local function hasStationWindow(
    construction: Engine.Component.Construction,
    sourceConstructionName: ResName
): boolean
    local expected = api.res.constructionRep.findAndGet(sourceConstructionName).entityWindowScript.fileName
    if expected == "" then
        return logger.fail("construction has no station window script; resource=" .. sourceConstructionName)
    end
    return api.res.constructionRep.findAndGet(construction.fileName).entityWindowScript.fileName == expected
end

return hasStationWindow
