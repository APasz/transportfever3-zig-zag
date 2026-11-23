local debugLoggingEnabled = ug_require(
    "apasz_zigzag::/zigzag/logging_config.lua"
) as boolean
local logging = ug_require(
    "apasz_zigzag::/zigzag/logging.lua"
) as ModLogging.Module
local trackSelection = ug_require(
    "apasz_zigzag::/zigzag/track_selection.lua"
) as ZigzagTrackSelection
local cargoStorage = ug_require(
    "apasz_zigzag::/zigzag/cargo_storage.lua"
) as ZigzagCargoStorage

local COST_MODE_PARAM_KEY = "apasz_zigzag_costs_enabled"
local DEFAULT_COST_MODE_INDEX: integer = 3
local STORAGE_LAYOUT_PARAM_KEY = "apasz_zigzag_storage_bay_layout"
local DEFAULT_STORAGE_LAYOUT_INDEX: integer = 1
local MAX_CAPTURE_PARAM_DEPTH: integer = 16
local ZIGZAG_CONSTRUCTION_PATH = ug_require(
    "apasz_zigzag::/zigzag/construction_path.lua"
) as string
local PASSENGER_PLATFORM_PATH_PREFIX =
    "::/stations/rail/modular_station/platform_passenger_era_"
local CARGO_PLATFORM_PATH_PREFIX =
    "::/stations/rail/modular_station/platform_cargo_era_"
local logger = logging.new("Zigzag Station", debugLoggingEnabled)

local COST_MODES: {ZigzagCostMode} = {
    "NO_COST",
    "TRACK_COST",
    "MODULE_COST",
    "STATION_COST",
}

local type ModParams = {string: integer}
local type AllModParams = {string: ModParams}
local type DynamicTable = {any: any}
local type TableSet = {any: boolean}

local record ModuleCostMetadata
    price: number | nil
    maintenanceCost: number | nil
end

local record CostAttributes
    cost: {number, number}
    maintenanceCost: {number, number}
end

local record CostBounds
    minimum: ZigzagCostRate
    maximum: ZigzagCostRate
end

local record CostCaptureParams
    lengthsMetres: {integer}
    trackCounts: {integer}
    moduleLengthMetres: integer
    costMode: ZigzagCostMode
    trackCostProfiles: {string: ZigzagTrackCostProfile}
    platformCostProfiles: {ZigzagPlatformCostProfile}
    trackMinimumRadiiMetres: {string: number}
    cargoStorageCostProfiles: {ZigzagStorageType: ZigzagCostRate}
end

local record TrackCatalog
    profiles: {string: ZigzagTrackCostProfile}
    choices: {ZigzagTrackChoice}
    minimumRadiiMetres: {string: number}
end

local record TrackMenuCategory
    category: string
    menu: string
end

local record ConstructionUpdateScript
    fileName: string
    params: any
end

local function requireConstructionUpdateScript(
    construction: DynamicTable
): ConstructionUpdateScript
    local updateScriptValue = construction.updateScript
    if updateScriptValue == nil then
        return logger.fail("construction update script was removed by another mod")
    end
    local updateScript = updateScriptValue as DynamicTable
    if type(updateScript.fileName) ~= "string" or updateScript.fileName == "" then
        return logger.fail("construction update script has no valid file name")
    end
    return updateScript as ConstructionUpdateScript
end

local function dynamicTable(value: any): DynamicTable | nil
    if type(value) == "table" then
        return value as DynamicTable
    end
    return nil
end

local function isCostCaptureParams(params: DynamicTable): boolean
    return type(params.lengthsMetres) == "table"
        and type(params.trackCounts) == "table"
        and type(params.moduleLengthMetres) == "number"
        and type(params.costMode) == "string"
        and type(params.trackCostProfiles) == "table"
        and type(params.platformCostProfiles) == "table"
end

local function collectCaptureParams<T>(
    value: any,
    depth: integer,
    visited: TableSet,
    matches: {T},
    isMatch: function(DynamicTable): boolean
)
    local candidate = dynamicTable(value)
    if candidate == nil or depth > MAX_CAPTURE_PARAM_DEPTH then
        return
    end
    local current = candidate as DynamicTable
    if visited[current] then
        return
    end
    visited[current] = true
    if isMatch(current) then
        matches[#matches + 1] = current as T
        return
    end
    for _, nestedValue in pairs(current) do
        collectCaptureParams(nestedValue, depth + 1, visited, matches, isMatch)
    end
end

local function requireCaptureParams<T>(
    rootParams: any,
    scriptName: string,
    context: string,
    isMatch: function(DynamicTable): boolean
): T
    local matches: {T} = {}
    collectCaptureParams(rootParams, 0, {}, matches, isMatch)
    if #matches == 0 then
        return logger.fail(
            "could not locate Zigzag " .. context .. " parameters beneath "
                .. scriptName
        )
    end
    if #matches > 1 then
        return logger.fail(
            "found multiple Zigzag " .. context .. " parameter tables beneath "
                .. scriptName
        )
    end
    return matches[1]
end

local function modParam(allModParams: AllModParams | nil, key: string, defaultIndex: integer): integer
    if allModParams ~= nil then
        local params = (allModParams as AllModParams)[getCurrentModId()]
        if params ~= nil and params[key] ~= nil then
            return params[key]
        end
    end
    return defaultIndex
end

local function costMode(allModParams: AllModParams | nil): ZigzagCostMode
    local index = modParam(allModParams, COST_MODE_PARAM_KEY, DEFAULT_COST_MODE_INDEX)
    local mode = COST_MODES[index]
    if mode == nil then
        return logger.fail("invalid cost mode parameter " .. tostring(index))
    end
    return mode
end

local function storageLayout(allModParams: AllModParams | nil): ZigzagStorageBayLayout
    local index = modParam(allModParams, STORAGE_LAYOUT_PARAM_KEY, DEFAULT_STORAGE_LAYOUT_INDEX)
    local layout = cargoStorage.bayLayouts[index]
    if layout == nil then
        return logger.fail("invalid storage bay layout parameter " .. tostring(index))
    end
    return layout
end

local function isFiniteNonNegativeNumber(value: any): boolean
    if type(value) ~= "number" then
        return false
    end
    local numericValue = value as number
    return numericValue == numericValue
        and numericValue ~= math.huge
        and numericValue ~= -math.huge
        and numericValue >= 0
end

local function requireNonNegativeNumber(value: any, context: string): number
    if not isFiniteNonNegativeNumber(value) then
        return logger.fail(context .. " must be a finite non-negative number")
    end
    local numericValue = value as number
    return numericValue
end

local function requirePositiveNumber(value: any, context: string): number
    local numericValue = requireNonNegativeNumber(value, context)
    if numericValue == 0 then
        return logger.fail(context .. " must be positive")
    end
    return numericValue
end

local function removeAppliedScale(
    value: number,
    scale: number,
    context: string
): number
    if scale == 0 then
        if value ~= 0 then
            return logger.fail(context .. " is non-zero despite a zero scale")
        end
        return 0
    end
    return value / scale
end

local function optionalCostRate(
    construction: any,
    maintenance: any
): ZigzagCostRate | nil
    if not isFiniteNonNegativeNumber(construction)
        or not isFiniteNonNegativeNumber(maintenance)
    then
        return nil
    end
    return {
        construction = construction as number,
        maintenance = maintenance as number,
    }
end

local function removeAppliedScales(
    rate: ZigzagCostRate,
    constructionScale: number,
    maintenanceScale: number,
    context: string
): ZigzagCostRate
    return {
        construction = removeAppliedScale(
            rate.construction,
            constructionScale,
            context .. " construction cost"
        ),
        maintenance = removeAppliedScale(
            rate.maintenance,
            maintenanceScale,
            context .. " maintenance cost"
        ),
    }
end

local function requireModule(resourceName: string): ModuleDesc
    local moduleId = api.res.moduleRep.find(resourceName)
    if moduleId == -1 then
        return logger.fail("missing cost module " .. resourceName)
    end
    return api.res.moduleRep.get(moduleId)
end

local function moduleCostRate(
    module: ModuleDesc,
    resourceName: string,
    constructionScale: number
): ZigzagCostRate
    local metadata = module.metadata as ModuleCostMetadata
    -- Vanilla scales module prices in-place, but applies maintenance scaling later.
    return removeAppliedScales({
        construction = requireNonNegativeNumber(
            metadata.price,
            resourceName .. " construction cost"
        ),
        maintenance = requireNonNegativeNumber(
            metadata.maintenanceCost,
            resourceName .. " maintenance cost"
        ),
    }, constructionScale, 1, resourceName)
end

local function optionalModuleCostRate(
    module: ModuleDesc,
    constructionScale: number,
    resourceName: string
): ZigzagCostRate | nil
    local metadata = module.metadata as ModuleCostMetadata
    local rate = optionalCostRate(metadata.price, metadata.maintenanceCost)
    if rate == nil then
        return nil
    end
    return removeAppliedScales(rate, constructionScale, 1, resourceName)
end

local function generatedTrackModuleName(trackTemplateName: string): string
    return "::/trainstation_" .. trackTemplateName:gsub("::", "__")
end

local function trackMenuCategories(): {string: boolean}
    local categories: {string: boolean} = {}
    for _, id in ipairs(api.res.genericRep.getAllOfType("menu_category")) do
        local category = api.res.genericRep.get(id).data as TrackMenuCategory
        if category.menu == "TRACKS" then
            categories[category.category] = true
        end
    end
    return categories
end

local function trackMenuOrder(template: StreetTemplate, trackCategories: {string: boolean}): number | nil
    for _, category in ipairs(template.menuCategory.categories) do
        if trackCategories[category.category] then
            return category.order
        end
    end
    return nil
end

local function collectTrackCatalog(
    mode: ZigzagCostMode,
    constructionScale: number,
    maintenanceScale: number
): TrackCatalog
    local profiles: {string: ZigzagTrackCostProfile} = {}
    local choices: {ZigzagTrackChoice} = {}
    local minimumRadiiMetres: {string: number} = {}
    local trackCategories = trackMenuCategories()
    -- Invisible templates can still be referenced by saved stations and upgrades.
    for templateId, resourceName in pairs(api.res.streetTemplateRep.getAll(true)) do
        local template = api.res.streetTemplateRep.get(templateId)
        if trackSelection.isRailwayTrack(template) then
            if isFiniteNonNegativeNumber(template.minCurveRadius)
                and isFiniteNonNegativeNumber(template.minCurveRadiusBuild)
            then
                minimumRadiiMetres[resourceName] = math.max(
                    template.minCurveRadius, template.minCurveRadiusBuild
                )
            else
                logger.warnOnce(
                    "minimum-radius:" .. resourceName,
                    "Missing or invalid minimum radius for track " .. resourceName
                        .. "; curved stations require valid minimum-radius data"
                )
            end
            if mode ~= "NO_COST" then
                local profile: ZigzagTrackCostProfile = {}
                if mode == "TRACK_COST" then
                    local rate = optionalCostRate(
                        template.cost,
                        template.maintenanceCost
                    )
                    if rate ~= nil then
                        profile.perMetre = removeAppliedScales(
                            rate,
                            constructionScale,
                            maintenanceScale,
                            resourceName
                        )
                    end
                else
                    local moduleName = generatedTrackModuleName(resourceName)
                    local moduleId = api.res.moduleRep.find(moduleName)
                    if moduleId ~= -1 then
                        profile.perModule = optionalModuleCostRate(
                            api.res.moduleRep.get(moduleId),
                            constructionScale,
                            moduleName
                        )
                    end
                end
                profiles[resourceName] = profile
            end
            local order = trackMenuOrder(template, trackCategories)
            if order ~= nil
                and api.res.streetTemplateRep.isVisible(templateId)
            then
                choices[#choices + 1] = {
                    resourceName = resourceName,
                    name = template.description.name,
                    icon = template.description.icon,
                    order = order as number,
                    yearFrom = template.availability.yearFrom,
                    yearTo = template.availability.yearTo,
                    electrified = trackSelection.supportsTransportMode(
                        template,
                        api.type["enum"].TransportMode.ELECTRIC_TRAIN
                    ),
                }
            end
        end
    end
    table.sort(choices, function(first: ZigzagTrackChoice, second: ZigzagTrackChoice): boolean
        if first.order ~= second.order then
            return first.order < second.order
        end
        return first.resourceName < second.resourceName
    end)
    return { profiles = profiles, choices = choices, minimumRadiiMetres = minimumRadiiMetres }
end

local function platformModuleName(prefix: string, era: string): string
    return prefix .. era .. ".module"
end

local function collectPlatformCostProfiles(
    constructionScale: number
): {ZigzagPlatformCostProfile}
    local eraSuffixes = { "a", "b", "c" }
    local profiles: {ZigzagPlatformCostProfile} = {}
    for _, eraSuffix in ipairs(eraSuffixes) do
        local passengerName = platformModuleName(
            PASSENGER_PLATFORM_PATH_PREFIX,
            eraSuffix
        )
        local cargoName = platformModuleName(
            CARGO_PLATFORM_PATH_PREFIX,
            eraSuffix
        )
        local passengerModule = requireModule(passengerName)
        local cargoModule = requireModule(cargoName)
        local yearFrom = passengerModule.availability.yearFrom
        if yearFrom ~= cargoModule.availability.yearFrom then
            return logger.fail(
                "platform-module availability differs for era " .. eraSuffix
            )
        end
        profiles[#profiles + 1] = {
            yearFrom = yearFrom,
            passenger = moduleCostRate(
                passengerModule,
                passengerName,
                constructionScale
            ),
            cargo = moduleCostRate(cargoModule, cargoName, constructionScale),
        }
    end
    return profiles
end

local function infrastructureScale(
    baseConfig: BaseConfig | nil,
    key: string,
    context: string
): number
    if baseConfig == nil then
        return 1
    end
    local config = baseConfig as BaseConfig
    return requireNonNegativeNumber(
        config.costs[key],
        context
    )
end

local function rateBounds(
    catalog: TrackCatalog,
    mode: ZigzagCostMode
): ZigzagCostRate, ZigzagCostRate
    local minimum: ZigzagCostRate = {
        construction = math.huge,
        maintenance = math.huge,
    }
    local maximum: ZigzagCostRate = { construction = 0, maintenance = 0 }
    local found = false
    for _, choice in ipairs(catalog.choices) do
        local profile = catalog.profiles[choice.resourceName]
        local selectedRate = trackSelection.costRate(profile, mode) or trackSelection.zeroCostRate
        minimum.construction = math.min(
            minimum.construction,
            selectedRate.construction
        )
        minimum.maintenance = math.min(
            minimum.maintenance,
            selectedRate.maintenance
        )
        maximum.construction = math.max(
            maximum.construction,
            selectedRate.construction
        )
        maximum.maintenance = math.max(
            maximum.maintenance,
            selectedRate.maintenance
        )
        found = true
    end
    if not found then
        return trackSelection.zeroCostRate, trackSelection.zeroCostRate
    end
    return minimum, maximum
end

local function maximumPlatformRate(
    platformProfiles: {ZigzagPlatformCostProfile}
): ZigzagCostRate
    local maximum: ZigzagCostRate = { construction = 0, maintenance = 0 }
    for _, profile in ipairs(platformProfiles) do
        maximum.construction = math.max(
            maximum.construction,
            profile.passenger.construction + profile.cargo.construction
        )
        maximum.maintenance = math.max(
            maximum.maintenance,
            profile.passenger.maintenance + profile.cargo.maintenance
        )
    end
    return maximum
end

local function costBounds(
    mode: ZigzagCostMode,
    catalog: TrackCatalog,
    platformProfiles: {ZigzagPlatformCostProfile},
    storageRate: ZigzagCostRate,
    constructionScale: number,
    maintenanceScale: number,
    captureParams: CostCaptureParams
): CostBounds
    if mode == "NO_COST" then
        local zero = trackSelection.zeroCostRate
        return { minimum = zero, maximum = zero }
    end

    local minimumLength = requirePositiveNumber(
        captureParams.lengthsMetres[1],
        "minimum station length"
    )
    local maximumLength = requirePositiveNumber(
        captureParams.lengthsMetres[#captureParams.lengthsMetres],
        "maximum station length"
    )
    local minimumTrackCount = requirePositiveNumber(
        captureParams.trackCounts[1],
        "minimum station track count"
    )
    local maximumTrackCount = requirePositiveNumber(
        captureParams.trackCounts[#captureParams.trackCounts],
        "maximum station track count"
    )

    if mode == "TRACK_COST" then
        local minimumRate, maximumRate = rateBounds(
            catalog,
            mode
        )
        return {
            minimum = {
                construction = minimumLength
                    * minimumTrackCount
                    * minimumRate.construction
                    * constructionScale,
                maintenance = minimumLength
                    * minimumTrackCount
                    * minimumRate.maintenance
                    * maintenanceScale,
            },
            maximum = {
                construction = maximumLength
                    * maximumTrackCount
                    * maximumRate.construction
                    * constructionScale,
                maintenance = maximumLength
                    * maximumTrackCount
                    * maximumRate.maintenance
                    * maintenanceScale,
            },
        }
    end

    if mode ~= "MODULE_COST" and mode ~= "STATION_COST" then
        return logger.fail("invalid cost mode " .. tostring(mode))
    end

    local minimumRate, maximumRate = rateBounds(
        catalog,
        mode
    )
    local moduleLength = requirePositiveNumber(
        captureParams.moduleLengthMetres,
        "track-module length"
    )
    local minimumModules = minimumLength / moduleLength * minimumTrackCount
    local maximumModules = maximumLength / moduleLength * maximumTrackCount
    local maximumConstruction = maximumModules
        * maximumRate.construction
        * constructionScale
    local maximumMaintenance = maximumModules
        * maximumRate.maintenance
        * maintenanceScale
    local maximumStorageCapacity = cargoStorage.capacities[#cargoStorage.capacities]
    maximumConstruction = maximumConstruction
        + maximumStorageCapacity * storageRate.construction * constructionScale
    maximumMaintenance = maximumMaintenance
        + maximumStorageCapacity * storageRate.maintenance * maintenanceScale
    if mode == "STATION_COST" then
        local platformRate = maximumPlatformRate(platformProfiles)
        local platformRows = math.floor(maximumTrackCount / 2) + 1
        local maximumPlatformModules = maximumLength / moduleLength * platformRows
        maximumConstruction = maximumConstruction
            + maximumPlatformModules
                * platformRate.construction
                * constructionScale
        maximumMaintenance = maximumMaintenance
            + maximumPlatformModules * platformRate.maintenance * maintenanceScale
    end
    return {
        minimum = {
            construction = minimumModules
                * minimumRate.construction
                * constructionScale,
            maintenance = minimumModules * minimumRate.maintenance * maintenanceScale,
        },
        maximum = {
            construction = maximumConstruction,
            maintenance = maximumMaintenance,
        },
    }
end

local function isTemplateCaptureParams(params: DynamicTable): boolean
    return type(params.constructionName) == "string"
        and type(params.tracks) == "table"
end

local function storeTemplatePeriods(
    templateName: string,
    templateId: integer,
    template: MetaConstructionDesc,
    trackParams: {ConstructionScriptParam}
)
    local periods: {ModelMetadata.Availability} = {}
    for _, param in ipairs(trackParams) do
        local previous = periods[#periods]
        if previous ~= nil and previous.yearTo == param.yearFrom then
            previous.yearTo = param.yearTo
        else
            periods[#periods + 1] = { yearFrom = param.yearFrom, yearTo = param.yearTo }
        end
    end
    local firstPeriod = periods[1]
    if firstPeriod ~= nil then
        template.availability.yearFrom = firstPeriod.yearFrom
        template.availability.yearTo = firstPeriod.yearTo
    end
    if firstPeriod == nil then
        api.res.metaConstructionRep.setVisible(templateId, false)
        return
    end
    -- Disjoint availability needs separate menu entries, as with vanilla station eras.
    local visible = api.res.metaConstructionRep.isVisible(templateId)
    for periodIndex = 2, #periods do
        local period = periods[periodIndex]
        local source = api.res.metaConstructionRep.get(templateId)
        source.availability.yearFrom = period.yearFrom
        source.availability.yearTo = period.yearTo
        local variantName = templateName:gsub(
            "%.metacon$",
            "_period_" .. tostring(periodIndex) .. ".metacon"
        )
        local variantId = api.res.metaConstructionRep.add(
            variantName,
            source,
            visible
        )
        if variantId == -1 then
            logger.fail("could not add construction template " .. variantName)
            return
        end
    end
    -- Adding resources may invalidate native references into the repository.
    local original = api.res.metaConstructionRep.get(templateId)
    original.availability.yearFrom = firstPeriod.yearFrom
    original.availability.yearTo = firstPeriod.yearTo
end

local function makeNativeTrackParam(param: ConstructionScriptParam): ScriptParam
    local native = api.type.ScriptParam.new()
    native.key = param.key
    native.name = param.name
    native.values = param.values
    native.images = param.images
    native.numbers = param.numbers
    native.defaultIndex = param.defaultIndex
    native.uiType = api.type["enum"].ScriptParamType.ComboBox
    native.yearFrom = param.yearFrom
    native.yearTo = param.yearTo
    return native
end

local function configureTemplate(
    constructionName: string,
    catalog: TrackCatalog,
    bounds: CostBounds
)
    local templateName = (getCurrentModId() .. ZIGZAG_CONSTRUCTION_PATH):gsub("%.con$", ".metacon")
    local templateId = api.res.metaConstructionRep.find(templateName)
    if templateId == -1 then
        logger.fail("missing construction template " .. templateName)
        return
    end
    local template = api.res.metaConstructionRep.get(templateId)
    local existingScript = template.createTemplateScript
    local rootParams = existingScript.params
    local captureParams: ZigzagTemplateCaptureParams = requireCaptureParams(
        rootParams,
        existingScript.fileName,
        "template",
        isTemplateCaptureParams
    )
    captureParams.constructionName = constructionName
    captureParams.tracks = catalog.choices
    local scriptRef = api.type.ScriptRef.new()
    scriptRef.fileName = existingScript.fileName
    scriptRef.params = rootParams
    template.createTemplateScript = scriptRef

    local trackParams = trackSelection.makeParams(catalog.choices)
    local nativeTemplate = template as ZigzagNativeTemplateParams
    local params: {ScriptParam} = {}
    local replaced = false
    for _, param in ipairs(nativeTemplate.params) do
        if param.key == trackSelection.paramKey then
            if not replaced then
                for _, trackParam in ipairs(trackParams) do
                    params[#params + 1] = makeNativeTrackParam(trackParam)
                end
                replaced = true
            end
        else
            params[#params + 1] = param
        end
    end
    if not replaced then
        logger.fail("construction template track parameter was removed by another mod")
        return
    end
    nativeTemplate.params = params

    local attributes = template.description.attributes as CostAttributes
    attributes.cost = { bounds.minimum.construction, bounds.maximum.construction }
    attributes.maintenanceCost = { bounds.minimum.maintenance, bounds.maximum.maintenance }
    storeTemplatePeriods(templateName, templateId, template, trackParams)
end

local function captureConstructionCosts(
    constructionName: string,
    mode: ZigzagCostMode,
    catalog: TrackCatalog,
    platformProfiles: {ZigzagPlatformCostProfile},
    storageProfiles: {ZigzagStorageType: ZigzagCostRate}
): CostCaptureParams
    local constructionId = api.res.constructionRep.find(constructionName)
    if constructionId == -1 then
        return logger.fail("missing construction " .. constructionName)
    end
    local construction = api.res.constructionRep.get(constructionId)
    local existingUpdateScript = requireConstructionUpdateScript(
        construction as DynamicTable
    )
    local rootParams = existingUpdateScript.params
    local params: CostCaptureParams = requireCaptureParams(
        rootParams,
        existingUpdateScript.fileName,
        "update",
        isCostCaptureParams
    )
    params.costMode = mode
    params.trackCostProfiles = catalog.profiles
    params.platformCostProfiles = platformProfiles
    params.trackMinimumRadiiMetres = catalog.minimumRadiiMetres
    params.cargoStorageCostProfiles = storageProfiles
    local updateScript = api.type.ScriptRef.new()
    updateScript.fileName = existingUpdateScript.fileName
    updateScript.params = rootParams as table
    construction.updateScript = updateScript
    return params
end

local function configureConstruction(
    mode: ZigzagCostMode,
    baseConfig: BaseConfig | nil,
    bayLayout: ZigzagStorageBayLayout
)
    local constructionScale = infrastructureScale(
        baseConfig,
        "infrastructureCostScale",
        "infrastructure cost scale"
    )
    local maintenanceScale = infrastructureScale(
        baseConfig,
        "infrastructureMaintenanceScale",
        "infrastructure maintenance scale"
    )
    local catalog = collectTrackCatalog(mode, constructionScale, maintenanceScale)
    local platformProfiles: {ZigzagPlatformCostProfile} = {}
    if mode == "STATION_COST" then
        platformProfiles = collectPlatformCostProfiles(constructionScale)
    end

    local storageProfiles: {ZigzagStorageType: ZigzagCostRate} = {}
    local storageRate: ZigzagCostRate = { construction = 0, maintenance = 0 }
    if mode == "MODULE_COST" or mode == "STATION_COST" then
        for _, profile in ipairs(cargoStorage.profiles) do
            local moduleRate = moduleCostRate(
                requireModule(profile.moduleName), profile.moduleName, constructionScale
            )
            local rate: ZigzagCostRate = {
                construction = moduleRate.construction / cargoStorage.moduleCapacity,
                maintenance = moduleRate.maintenance / cargoStorage.moduleCapacity,
            }
            storageProfiles[profile.kind] = rate
            storageRate.construction = math.max(storageRate.construction, rate.construction)
            storageRate.maintenance = math.max(storageRate.maintenance, rate.maintenance)
        end
    end
    local baseName = getCurrentModId() .. ZIGZAG_CONSTRUCTION_PATH
    local singleBayName = baseName:gsub("%.con$", "_single_bay.con")
    local params = captureConstructionCosts(baseName, mode, catalog, platformProfiles, storageProfiles)
    captureConstructionCosts(singleBayName, mode, catalog, platformProfiles, storageProfiles)
    local constructionName = bayLayout == "SINGLE_BAY" and singleBayName or baseName

    local bounds = costBounds(
        mode,
        catalog,
        platformProfiles,
        storageRate,
        constructionScale,
        maintenanceScale,
        params
    )
    configureTemplate(constructionName, catalog, bounds)
    logger.info("Configured cost mode " .. mode)
end

function data(): any
    return {
        postRunFn = function(
            _captureParams: table,
            _configDict: table,
            allModParams: AllModParams | nil,
            baseConfig: BaseConfig | nil
        )
            configureConstruction(costMode(allModParams), baseConfig, storageLayout(allModParams))
        end,
    }
end
