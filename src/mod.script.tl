local debugLoggingEnabled = ug_require(
    "apasz_zigzag::/zigzag/logging_config.lua"
) as boolean
local logging = ug_require(
    "apasz_zigzag::/zigzag/logging.lua"
) as ModLogging.Module

local COSTS_ENABLED_PARAM_KEY = "apasz_zigzag_costs_enabled"
local COSTS_DISABLED_INDEX: integer = 1
local COSTS_ENABLED_INDEX: integer = 2
local ZIGZAG_CONSTRUCTION_PATH = "::/stations/rail/zigzag/zigzag.con"
local logger = logging.new("Zigzag Station", debugLoggingEnabled)

local type ModParams = {string: integer}
local type AllModParams = {string: ModParams}
local type ConfigDict = {string: string}

local record CostCaptureParams
    costPerMetre: number
    maintenanceCostPerMetre: number
end

local record UpdateScript
    params: CostCaptureParams
end

local record CostAttributes
    cost: {number}
    maintenanceCost: {number}
end

local record TemplateDescription
    attributes: CostAttributes
end

local record ZigzagConstructionTemplate
    description: TemplateDescription
end

local record ZigzagConstruction
    updateScript: UpdateScript
    constructionTemplates: {ZigzagConstructionTemplate}
end

local function costsEnabled(allModParams: AllModParams | nil): boolean
    if allModParams == nil then
        return true
    end

    local modParams = (allModParams as AllModParams)[getCurrentModId()]
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

local function disableCosts(fileName: string, resourceData: any): any
    if fileName ~= getCurrentModId() .. ZIGZAG_CONSTRUCTION_PATH then
        return resourceData
    end

    local construction = resourceData as ZigzagConstruction
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

function data(): any
    return {
        runFn = function(
            _captureParams: table,
            _configDict: ConfigDict,
            allModParams: AllModParams | nil,
            _baseConfig: BaseConfig | nil
        )
            if costsEnabled(allModParams) then
                return
            end
            logger.info("Costs disabled by mod setting")
            addModifier("loadConstruction", disableCosts)
        end,
    }
end
