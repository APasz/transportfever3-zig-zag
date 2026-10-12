local param_util = ug_require "::/scripts/construction/param_util.tl" as ParamUtil

local LENGTHS_METRES: {integer} = {
    5, 10, 20, 40, 80, 120, 160, 200, 240, 280, 320, 360, 400, 440,
}
-- Preserve the original index mapping for constructions saved before the numeric slider.
local LEGACY_LENGTHS_METRES: {integer} = { 10, 40, 80, 120, 160, 240, 320 }
local TRACK_COUNTS: {integer} = { 1, 2, 3, 4, 5, 6, 7, 8 }
local TRACK_SPACINGS_METRES: {integer} = {
    3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
}
local CATCHMENT_RADII_METRES: {integer} = {
    50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300,
}
local PASSENGER_CAPACITY_MULTIPLIERS: {number} = {
    0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
}
local DEFAULT_LENGTH_METRES: integer = 10
local DEFAULT_TRACK_COUNT_INDEX: integer = 1
local DEFAULT_TRACK_SPACING_METRES: integer = 5
local DEFAULT_CATCHMENT_RADIUS_METRES: integer = 150
local DEFAULT_PASSENGER_CAPACITY_MULTIPLIER: number = 1
local DEFAULT_TRACK_TYPE_INDEX: integer = 2
local LOADING_DISABLED_INDEX: integer = 1
local LOADING_ENABLED_INDEX: integer = 2
local MODULE_LENGTH_METRES: integer = 40
local PASSENGER_LOADING_PARAM_KEY: string = "passengerLoadingEnabled"
local CARGO_LOADING_PARAM_KEY: string = "cargoLoadingEnabled"
local LOADING_VISIBILITY_SCRIPT: string = "zigzag.params.gui@checkLoadingVisibility"
local ICON_FILE: string = "zigzag.tga"
local PREVIEW_ICON_FILE: string = "zigzag_preview.tga"
local STATION_NAME_KEY: string = "apasz_zigzag_name"
local STATION_DESCRIPTION_KEY: string = "apasz_zigzag_description"
local STATION_NAME_PREFIX_KEY: string = "apasz_zigzag_name_prefix"
local LENGTH_KEY: string = "apasz_zigzag_length"
local TRACKS_KEY: string = "apasz_zigzag_tracks"
local TRACK_SPACING_KEY: string = "apasz_zigzag_track_spacing"
local PASSENGER_LOADING_KEY: string = "apasz_zigzag_passenger_loading_enabled"
local PASSENGER_CAPACITY_KEY: string = "apasz_zigzag_passenger_capacity"
local CARGO_LOADING_KEY: string = "apasz_zigzag_cargo_loading_enabled"
local CATCHMENT_RADIUS_KEY: string = "apasz_zigzag_catchment_radius"
local OFF_KEY: string = "apasz_zigzag_off"
local ON_KEY: string = "apasz_zigzag_on"

local function makeNumberLabels<T>(values: {T}, suffix: string): {string}
    local labels: {string} = {}
    for _, value in ipairs(values) do
        labels[#labels + 1] = tostring(value) .. suffix
    end
    return labels
end

local function makeMultiplierLabels(values: {number}): {string}
    local labels: {string} = {}
    for _, value in ipairs(values) do
        labels[#labels + 1] = string.format("%g×", value)
    end
    return labels
end

local function requireValueIndex<T>(values: {T}, requiredValue: T): integer
    for index, value in ipairs(values) do
        if value == requiredValue then
            return index
        end
    end
    error("Missing required parameter value " .. tostring(requiredValue))
end

local DEFAULT_LENGTH_INDEX: integer = requireValueIndex(
    LENGTHS_METRES,
    DEFAULT_LENGTH_METRES
)
local DEFAULT_TRACK_SPACING_INDEX: integer = requireValueIndex(
    TRACK_SPACINGS_METRES,
    DEFAULT_TRACK_SPACING_METRES
)
local DEFAULT_CATCHMENT_RADIUS_INDEX: integer = requireValueIndex(
    CATCHMENT_RADII_METRES,
    DEFAULT_CATCHMENT_RADIUS_METRES
)
local DEFAULT_PASSENGER_CAPACITY_MULTIPLIER_INDEX: integer = requireValueIndex(
    PASSENGER_CAPACITY_MULTIPLIERS,
    DEFAULT_PASSENGER_CAPACITY_MULTIPLIER
)

local function makeDefaultTrackTypeParam(highSpeedAvailable: boolean): ScriptParam
    local param: ScriptParam
    if highSpeedAvailable then
        param = param_util.makeTrackTypeHighSpeedParam()
    else
        param = param_util.makeTrackTypeDefaultParam()
    end
    param.defaultIndex = DEFAULT_TRACK_TYPE_INDEX
    return param
end

local function makeLoadingVisibilityCheck(
    enabledParamKeys: {string}
): api.type.ScriptRef
    return {
        fileName = LOADING_VISIBILITY_SCRIPT,
        params = {
            enabledParamKeys = enabledParamKeys,
            enabledIndex = LOADING_ENABLED_INDEX,
        },
    }
end

local function makeTemplates(): {any}
    return {
        {
            type = "DYNAMIC",
            configureLayerScript = {
                fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
                params = {
                    heightmapContours = true,
                },
            },
            configureHudIconsScript = {
                fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
                params = {
                    cargo = true,
                    rail = true,
                },
            },
            availability = {
                yearFrom = 0,
                yearTo = 0,
            },
            description = {
                name = _(STATION_NAME_KEY),
                description = _(STATION_DESCRIPTION_KEY),
                icon = ICON_FILE,
                previewIcon = PREVIEW_ICON_FILE,
                attributes = {
                    maintenanceCost = { 0, 0 },
                    cost = { 0, 0 },
                },
            },
            data = {
                params = {},
            },
            menuCategory = {
                categories = {
                    {
                        category = "rail_buildings",
                        order = 4500,
                    },
                },
            },
        },
    }
end

function data(): any
    return {
        configureLayerScript = {
            fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
            params = {
                heightmapContours = true,
            },
        },
        namePrefix = _(STATION_NAME_PREFIX_KEY),
        subConstructionNamePrefix = "{constructionName}",
        description = {
            name = _(STATION_NAME_KEY),
            description = _(STATION_DESCRIPTION_KEY),
            icon = ICON_FILE,
            previewIcon = PREVIEW_ICON_FILE,
        },
        availability = {
            yearFrom = 0,
            yearTo = 0,
        },
        order = 4500,
        constructionTemplates = makeTemplates(),
        createTemplateScript = {
            fileName = "zigzag.script@createTemplateFn",
            params = {},
        },
        updateScript = {
            fileName = "zigzag.script@updateFn",
            params = {
                lengthsMetres = LENGTHS_METRES,
                legacyLengthsMetres = LEGACY_LENGTHS_METRES,
                trackCounts = TRACK_COUNTS,
                trackSpacingsMetres = TRACK_SPACINGS_METRES,
                catchmentRadiiMetres = CATCHMENT_RADII_METRES,
                passengerCapacityMultipliers = PASSENGER_CAPACITY_MULTIPLIERS,
                defaultLengthMetres = DEFAULT_LENGTH_METRES,
                defaultTrackCountIndex = DEFAULT_TRACK_COUNT_INDEX,
                defaultTrackSpacingIndex = DEFAULT_TRACK_SPACING_INDEX,
                defaultCatchmentRadiusMetres = DEFAULT_CATCHMENT_RADIUS_METRES,
                defaultPassengerCapacityMultiplier = DEFAULT_PASSENGER_CAPACITY_MULTIPLIER,
                defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
                loadingDisabledIndex = LOADING_DISABLED_INDEX,
                loadingEnabledIndex = LOADING_ENABLED_INDEX,
                moduleLengthMetres = MODULE_LENGTH_METRES,
                costMode = "MODULE_COST" as ZigzagCostMode,
                trackCostProfiles = {},
                platformCostProfiles = {},
            },
        },
        upgradeScript = {
            fileName = "zigzag.script@upgradeFn",
            params = {
                defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
            },
        },
        isAffectedByToolScript = {
            fileName = "zigzag.script@isAffectedByToolFn",
            params = {
                defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
            },
        },
        params = {
            {
                key = "tracks",
                name = _(TRACKS_KEY),
                values = makeNumberLabels(TRACK_COUNTS, ""),
                defaultIndex = DEFAULT_TRACK_COUNT_INDEX,
                displayMode = "Horizontal",
            },
            {
                key = "trackSpacingMetres",
                name = _(TRACK_SPACING_KEY),
                values = makeNumberLabels(TRACK_SPACINGS_METRES, " m"),
                numbers = TRACK_SPACINGS_METRES,
                defaultIndex = DEFAULT_TRACK_SPACING_INDEX,
                uiType = "Slider" as api.type.enum.ScriptParamType,
            },
            {
                key = "lengthMetres",
                name = _(LENGTH_KEY),
                values = makeNumberLabels(LENGTHS_METRES, " m"),
                numbers = LENGTHS_METRES,
                defaultIndex = DEFAULT_LENGTH_INDEX,
                uiType = "Slider" as api.type.enum.ScriptParamType,
            },
            makeDefaultTrackTypeParam(false),
            makeDefaultTrackTypeParam(true),
            param_util.makeTrackCatenaryParam(),
            {
                key = PASSENGER_LOADING_PARAM_KEY,
                name = _(PASSENGER_LOADING_KEY),
                values = { _(OFF_KEY), _(ON_KEY) },
                defaultIndex = LOADING_DISABLED_INDEX,
                uiType = "CheckBox" as api.type.enum.ScriptParamType,
            },
            {
                key = "passengerCapacityMultiplier",
                name = _(PASSENGER_CAPACITY_KEY),
                values = makeMultiplierLabels(PASSENGER_CAPACITY_MULTIPLIERS),
                numbers = PASSENGER_CAPACITY_MULTIPLIERS,
                defaultIndex = DEFAULT_PASSENGER_CAPACITY_MULTIPLIER_INDEX,
                uiType = "Slider" as api.type.enum.ScriptParamType,
                checkEnabledScript = makeLoadingVisibilityCheck({
                    PASSENGER_LOADING_PARAM_KEY,
                }),
            },
            {
                key = CARGO_LOADING_PARAM_KEY,
                name = _(CARGO_LOADING_KEY),
                values = { _(OFF_KEY), _(ON_KEY) },
                defaultIndex = LOADING_DISABLED_INDEX,
                uiType = "CheckBox" as api.type.enum.ScriptParamType,
            },
            {
                key = "catchmentRadiusMetres",
                name = _(CATCHMENT_RADIUS_KEY),
                values = makeNumberLabels(CATCHMENT_RADII_METRES, " m"),
                numbers = CATCHMENT_RADII_METRES,
                defaultIndex = DEFAULT_CATCHMENT_RADIUS_INDEX,
                uiType = "Slider" as api.type.enum.ScriptParamType,
                checkEnabledScript = makeLoadingVisibilityCheck({
                    PASSENGER_LOADING_PARAM_KEY,
                    CARGO_LOADING_PARAM_KEY,
                }),
            },
        },
    }
end
