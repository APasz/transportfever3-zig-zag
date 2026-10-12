local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local debugLoggingEnabled = ug_require(
"apasz_zigzag::/zigzag/logging_config.lua")

local logging = ug_require(
"apasz_zigzag::/zigzag/logging.lua")


local COST_MODE_PARAM_KEY = "apasz_zigzag_costs_enabled"
local DEFAULT_COST_MODE_INDEX = 3
local MAX_CAPTURE_PARAM_DEPTH = 16
local ZIGZAG_CONSTRUCTION_PATH = ug_require(
"apasz_zigzag::/zigzag/construction_path.lua")

local PASSENGER_PLATFORM_PATH_PREFIX =
"::/stations/rail/modular_station/platform_passenger_era_"
local CARGO_PLATFORM_PATH_PREFIX =
"::/stations/rail/modular_station/platform_cargo_era_"
local logger = logging.new("Zigzag Station", debugLoggingEnabled)

local COST_MODES = {
   "NO_COST",
   "TRACK_COST",
   "MODULE_COST",
   "STATION_COST",
}



































local function requireConstructionUpdateScript(
   construction)

   local updateScriptValue = construction.updateScript
   if updateScriptValue == nil then
      return logger.fail("construction update script was removed by another mod")
   end
   local updateScript = updateScriptValue
   if type(updateScript.fileName) ~= "string" or updateScript.fileName == "" then
      return logger.fail("construction update script has no valid file name")
   end
   return updateScript
end

local function dynamicTable(value)
   if type(value) == "table" then
      return value
   end
   return nil
end

local function isCostCaptureParams(params)
   return type(params.lengthsMetres) == "table" and
   type(params.trackCounts) == "table" and
   type(params.moduleLengthMetres) == "number" and
   type(params.costMode) == "string" and
   type(params.trackCostProfiles) == "table" and
   type(params.platformCostProfiles) == "table"
end

local function collectCostCaptureParams(
   value,
   depth,
   visited,
   matches)

   local candidate = dynamicTable(value)
   if candidate == nil or depth > MAX_CAPTURE_PARAM_DEPTH then
      return
   end
   local current = candidate
   if visited[current] then
      return
   end
   visited[current] = true
   if isCostCaptureParams(current) then
      matches[#matches + 1] = current
      return
   end
   for _, nestedValue in pairs(current) do
      collectCostCaptureParams(nestedValue, depth + 1, visited, matches)
   end
end

local function requireCostCaptureParams(
   rootParams,
   updateScriptName)

   local matches = {}
   collectCostCaptureParams(rootParams, 0, {}, matches)
   if #matches == 0 then
      return logger.fail(
      "could not locate Zigzag update parameters beneath " ..
      updateScriptName)

   end
   if #matches > 1 then
      return logger.fail(
      "found multiple Zigzag update parameter tables beneath " ..
      updateScriptName)

   end
   return matches[1]
end

local function costMode(allModParams)
   local selectedIndex = DEFAULT_COST_MODE_INDEX
   if allModParams ~= nil then
      local modParams = (allModParams)[getCurrentModId()]
      if modParams ~= nil and modParams[COST_MODE_PARAM_KEY] ~= nil then
         selectedIndex = modParams[COST_MODE_PARAM_KEY]
      end
   end

   local selectedMode = COST_MODES[selectedIndex]
   if selectedMode == nil then
      return logger.fail("invalid cost mode parameter " .. tostring(selectedIndex))
   end
   return selectedMode
end

local function isFiniteNonNegativeNumber(value)
   if type(value) ~= "number" then
      return false
   end
   local numericValue = value
   return numericValue == numericValue and
   numericValue ~= math.huge and
   numericValue ~= -math.huge and
   numericValue >= 0
end

local function requireNonNegativeNumber(value, context)
   if not isFiniteNonNegativeNumber(value) then
      return logger.fail(context .. " must be a finite non-negative number")
   end
   local numericValue = value
   return numericValue
end

local function requirePositiveNumber(value, context)
   local numericValue = requireNonNegativeNumber(value, context)
   if numericValue == 0 then
      return logger.fail(context .. " must be positive")
   end
   return numericValue
end

local function removeAppliedScale(
   value,
   scale,
   context)

   if scale == 0 then
      if value ~= 0 then
         return logger.fail(context .. " is non-zero despite a zero scale")
      end
      return 0
   end
   return value / scale
end

local function optionalCostRate(
   construction,
   maintenance)

   if not isFiniteNonNegativeNumber(construction) or
      not isFiniteNonNegativeNumber(maintenance) then

      return nil
   end
   return {
      construction = construction,
      maintenance = maintenance,
   }
end

local function removeAppliedScales(
   rate,
   constructionScale,
   maintenanceScale,
   context)

   return {
      construction = removeAppliedScale(
      rate.construction,
      constructionScale,
      context .. " construction cost"),

      maintenance = removeAppliedScale(
      rate.maintenance,
      maintenanceScale,
      context .. " maintenance cost"),

   }
end

local function requireModule(resourceName)
   local moduleId = api.res.moduleRep.find(resourceName)
   if moduleId == -1 then
      return logger.fail("missing cost module " .. resourceName)
   end
   return api.res.moduleRep.get(moduleId)
end

local function moduleCostRate(
   module,
   resourceName,
   constructionScale)

   local metadata = module.metadata

   return removeAppliedScales({
      construction = requireNonNegativeNumber(
      metadata.price,
      resourceName .. " construction cost"),

      maintenance = requireNonNegativeNumber(
      metadata.maintenanceCost,
      resourceName .. " maintenance cost"),

   }, constructionScale, 1, resourceName)
end

local function optionalModuleCostRate(
   module,
   constructionScale,
   resourceName)

   local metadata = module.metadata
   local rate = optionalCostRate(metadata.price, metadata.maintenanceCost)
   if rate == nil then
      return nil
   end
   return removeAppliedScales(rate, constructionScale, 1, resourceName)
end

local function generatedTrackModuleName(trackTemplateName)
   return "::/trainstation_" .. trackTemplateName:gsub("::", "__")
end

local function collectTrackCostProfiles(
   constructionScale,
   maintenanceScale)

   local profiles = {}
   for _, resourceName in pairs(api.res.streetTemplateRep.getAll()) do
      local templateId = api.res.streetTemplateRep.find(resourceName)
      if templateId ~= -1 then
         local template = api.res.streetTemplateRep.get(templateId)
         if template.roadType == api.type["enum"].RoadType.TRACK then
            local perMetre = optionalCostRate(
            template.cost,
            template.maintenanceCost)

            if perMetre ~= nil then
               perMetre = removeAppliedScales(
               perMetre,
               constructionScale,
               maintenanceScale,
               resourceName)

            end
            local moduleName = generatedTrackModuleName(resourceName)
            local moduleId = api.res.moduleRep.find(moduleName)
            local perModule = nil
            if moduleId ~= -1 then
               perModule = optionalModuleCostRate(
               api.res.moduleRep.get(moduleId),
               constructionScale,
               moduleName)

            end
            if perMetre ~= nil or perModule ~= nil then
               profiles[resourceName] = {
                  perMetre = perMetre,
                  perModule = perModule,
               }
            end
         end
      end
   end
   return profiles
end

local function platformModuleName(prefix, era)
   return prefix .. era .. ".module"
end

local function collectPlatformCostProfiles(
   constructionScale)

   local eraSuffixes = { "a", "b", "c" }
   local profiles = {}
   for _, eraSuffix in ipairs(eraSuffixes) do
      local passengerName = platformModuleName(
      PASSENGER_PLATFORM_PATH_PREFIX,
      eraSuffix)

      local cargoName = platformModuleName(
      CARGO_PLATFORM_PATH_PREFIX,
      eraSuffix)

      local passengerModule = requireModule(passengerName)
      local cargoModule = requireModule(cargoName)
      local yearFrom = passengerModule.availability.yearFrom
      if yearFrom ~= cargoModule.availability.yearFrom then
         return logger.fail(
         "platform-module availability differs for era " .. eraSuffix)

      end
      profiles[#profiles + 1] = {
         yearFrom = yearFrom,
         passenger = moduleCostRate(
         passengerModule,
         passengerName,
         constructionScale),

         cargo = moduleCostRate(cargoModule, cargoName, constructionScale),
      }
   end
   return profiles
end

local function infrastructureScale(
   baseConfig,
   key,
   context)

   if baseConfig == nil then
      return 1
   end
   local config = baseConfig
   return requireNonNegativeNumber(
   config.costs[key],
   context)

end

local function perMetreRate(
   profile)

   return profile.perMetre
end

local function perModuleRate(
   profile)

   return profile.perModule
end

local function rateBounds(
   trackProfiles,
   selectRate,
   missingMessage)

   local minimum = {
      construction = math.huge,
      maintenance = math.huge,
   }
   local maximum = { construction = 0, maintenance = 0 }
   local found = false
   for _, profile in pairs(trackProfiles) do
      local rate = selectRate(profile)
      if rate ~= nil then
         local selectedRate = rate
         minimum.construction = math.min(
         minimum.construction,
         selectedRate.construction)

         minimum.maintenance = math.min(
         minimum.maintenance,
         selectedRate.maintenance)

         maximum.construction = math.max(
         maximum.construction,
         selectedRate.construction)

         maximum.maintenance = math.max(
         maximum.maintenance,
         selectedRate.maintenance)

         found = true
      end
   end
   if not found then
      return logger.fail(missingMessage)
   end
   return minimum, maximum
end

local function maximumPlatformRate(
   platformProfiles)

   local maximum = { construction = 0, maintenance = 0 }
   for _, profile in ipairs(platformProfiles) do
      maximum.construction = math.max(
      maximum.construction,
      profile.passenger.construction + profile.cargo.construction)

      maximum.maintenance = math.max(
      maximum.maintenance,
      profile.passenger.maintenance + profile.cargo.maintenance)

   end
   return maximum
end

local function costBounds(
   mode,
   trackProfiles,
   platformProfiles,
   constructionScale,
   maintenanceScale,
   captureParams)

   if mode == "NO_COST" then
      local zero = { construction = 0, maintenance = 0 }
      return { minimum = zero, maximum = zero }
   end

   local minimumLength = requirePositiveNumber(
   captureParams.lengthsMetres[1],
   "minimum station length")

   local maximumLength = requirePositiveNumber(
   captureParams.lengthsMetres[#captureParams.lengthsMetres],
   "maximum station length")

   local minimumTrackCount = requirePositiveNumber(
   captureParams.trackCounts[1],
   "minimum station track count")

   local maximumTrackCount = requirePositiveNumber(
   captureParams.trackCounts[#captureParams.trackCounts],
   "maximum station track count")


   if mode == "TRACK_COST" then
      local minimumRate, maximumRate = rateBounds(
      trackProfiles,
      perMetreRate,
      "no track templates have cost data")

      return {
         minimum = {
            construction = minimumLength *
            minimumTrackCount *
            minimumRate.construction *
            constructionScale,
            maintenance = minimumLength *
            minimumTrackCount *
            minimumRate.maintenance *
            maintenanceScale,
         },
         maximum = {
            construction = maximumLength *
            maximumTrackCount *
            maximumRate.construction *
            constructionScale,
            maintenance = maximumLength *
            maximumTrackCount *
            maximumRate.maintenance *
            maintenanceScale,
         },
      }
   end

   if mode ~= "MODULE_COST" and mode ~= "STATION_COST" then
      return logger.fail("invalid cost mode " .. tostring(mode))
   end

   local minimumRate, maximumRate = rateBounds(
   trackProfiles,
   perModuleRate,
   "no generated track modules have cost data")

   local moduleLength = requirePositiveNumber(
   captureParams.moduleLengthMetres,
   "track-module length")

   local minimumModules = minimumLength / moduleLength * minimumTrackCount
   local maximumModules = maximumLength / moduleLength * maximumTrackCount
   local maximumConstruction = maximumModules *
   maximumRate.construction *
   constructionScale
   local maximumMaintenance = maximumModules *
   maximumRate.maintenance *
   maintenanceScale
   if mode == "STATION_COST" then
      local platformRate = maximumPlatformRate(platformProfiles)
      local platformRows = math.floor(maximumTrackCount / 2) + 1
      local maximumPlatformModules = maximumLength / moduleLength * platformRows
      maximumConstruction = maximumConstruction +
      maximumPlatformModules *
      platformRate.construction *
      constructionScale
      maximumMaintenance = maximumMaintenance +
      maximumPlatformModules * platformRate.maintenance * maintenanceScale
   end
   return {
      minimum = {
         construction = minimumModules *
         minimumRate.construction *
         constructionScale,
         maintenance = minimumModules * minimumRate.maintenance * maintenanceScale,
      },
      maximum = {
         construction = maximumConstruction,
         maintenance = maximumMaintenance,
      },
   }
end

local function configureConstruction(
   mode,
   baseConfig)

   local constructionName = getCurrentModId() .. ZIGZAG_CONSTRUCTION_PATH
   local constructionId = api.res.constructionRep.find(constructionName)
   if constructionId == -1 then
      logger.fail("missing construction " .. constructionName)
      return
   end
   local construction = api.res.constructionRep.get(constructionId)
   local existingUpdateScript = requireConstructionUpdateScript(
   construction)

   local rootParams = existingUpdateScript.params
   local params = requireCostCaptureParams(
   rootParams,
   existingUpdateScript.fileName)

   local constructionScale = infrastructureScale(
   baseConfig,
   "infrastructureCostScale",
   "infrastructure cost scale")

   local maintenanceScale = infrastructureScale(
   baseConfig,
   "infrastructureMaintenanceScale",
   "infrastructure maintenance scale")

   local trackProfiles = {}
   if mode ~= "NO_COST" then
      trackProfiles = collectTrackCostProfiles(
      constructionScale,
      maintenanceScale)

   end
   local platformProfiles = {}
   if mode == "STATION_COST" then
      platformProfiles = collectPlatformCostProfiles(constructionScale)
   end

   params.costMode = mode
   params.trackCostProfiles = trackProfiles
   params.platformCostProfiles = platformProfiles

   local updateScript = api.type.ScriptRef.new()
   updateScript.fileName = existingUpdateScript.fileName
   updateScript.params = rootParams
   construction.updateScript = updateScript

   local template = construction.constructionTemplates[1]
   if template == nil then
      logger.fail("construction has no template")
      return
   end
   local bounds = costBounds(
   mode,
   trackProfiles,
   platformProfiles,
   constructionScale,
   maintenanceScale,
   params)

   local attributes = template.desc.attributes
   attributes.cost = {
      bounds.minimum.construction,
      bounds.maximum.construction,
   }
   attributes.maintenanceCost = {
      bounds.minimum.maintenance,
      bounds.maximum.maintenance,
   }
   logger.info("Configured cost mode " .. mode)
end

function data()
   return {
      postRunFn = function(
         _captureParams,
         _configDict,
         allModParams,
         baseConfig)

         configureConstruction(costMode(allModParams), baseConfig)
      end,
   }
end
