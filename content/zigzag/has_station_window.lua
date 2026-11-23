local logger = ug_require("apasz_zigzag::/zigzag/logger.lua")

local function hasStationWindow(
   construction,
   sourceConstructionName)

   local expected = api.res.constructionRep.findAndGet(sourceConstructionName).entityWindowScript.fileName
   if expected == "" then
      return logger.fail("construction has no station window script; resource=" .. sourceConstructionName)
   end
   return api.res.constructionRep.findAndGet(construction.fileName).entityWindowScript.fileName == expected
end

return hasStationWindow
