local debugLoggingEnabled = ug_require(
"apasz_zigzag::/zigzag/logging_config.lua")

local logging = ug_require(
"apasz_zigzag::/zigzag/logging.lua")


local COSTS_ENABLED_PARAM_KEY = "apasz_zigzag_costs_enabled"
local COSTS_DISABLED_INDEX = 1
local COSTS_ENABLED_INDEX = 2
local ZIGZAG_CONSTRUCTION_PATH = "::/stations/rail/zigzag/zigzag.con"
local logger = logging.new("Zigzag Station", debugLoggingEnabled)
































local function costsEnabled(allModParams)
   if allModParams == nil then
      return true
   end

   local modParams = (allModParams)[getCurrentModId()]
   if modParams == nil or modParams[COSTS_ENABLED_PARAM_KEY] == nil then
      return true
   end

   local selectedIndex = modParams[COSTS_ENABLED_PARAM_KEY]
   if selectedIndex == COSTS_ENABLED_INDEX then
      return true
   end
   if selectedIndex == COSTS_DISABLED_INDEX then
      return false
   end
   return logger.fail("invalid costs mod parameter " .. tostring(selectedIndex))
end

local function disableCosts(fileName, resourceData)
   if fileName ~= getCurrentModId() .. ZIGZAG_CONSTRUCTION_PATH then
      return resourceData
   end

   local construction = resourceData
   construction.updateScript.params.costPerMetre = 0
   construction.updateScript.params.maintenanceCostPerMetre = 0

   local template = construction.constructionTemplates[1]
   if template == nil then
      return logger.fail("construction has no template")
   end
   template.description.attributes.cost = { 0, 0 }
   template.description.attributes.maintenanceCost = { 0, 0 }
   logger.debug("Disabled construction and maintenance costs for " .. fileName)
   return construction
end

function data()
   return {
      runFn = function(
         _captureParams,
         _configDict,
         allModParams,
         _baseConfig)

         if costsEnabled(allModParams) then
            return
         end
         logger.info("Costs disabled by mod setting")
         addModifier("loadConstruction", disableCosts)
      end,
   }
end
