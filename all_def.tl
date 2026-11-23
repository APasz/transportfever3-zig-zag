require "api_def"
require "content_def"
require "logging_def"

global enum ZigzagCostMode
    "NO_COST"
    "TRACK_COST"
    "MODULE_COST"
    "STATION_COST"
end

global record ZigzagCostRate
    construction: number
    maintenance: number
end

global record ZigzagTrackCostProfile
    perMetre: ZigzagCostRate | nil
    perModule: ZigzagCostRate | nil
end

global record ZigzagTrackChoice
    resourceName: string
    name: string
    icon: string
    order: number
    yearFrom: integer
    yearTo: integer
    electrified: boolean
end

-- The installed binding exposes native ScriptParam objects on metaconstructions.
global record ZigzagNativeTemplateParams
    params: {ScriptParam}
end

global record ZigzagTemplateCaptureParams
    constructionName: string
    tracks: {ZigzagTrackChoice}
end

global record ZigzagTrackSelection
    paramKey: string
    zeroCostRate: ZigzagCostRate
    costRate: function(ZigzagTrackCostProfile | nil, ZigzagCostMode): ZigzagCostRate | nil
    supportsTransportMode: function(StreetTemplate, TransportMode): boolean
    isRailwayTrack: function(StreetTemplate): boolean
    catenaryIndex: function(boolean): integer
    catenaryEnabled: function(integer | nil): boolean
    isAvailable: function(ZigzagTrackChoice, integer): boolean
    makeParams: function({ZigzagTrackChoice}): {ConstructionScriptParam}
    resolve: function({ZigzagTrackChoice}, integer | nil, integer): ZigzagTrackChoice
end

global record ZigzagStationDefinition
    makeConstruction: function(): table
    makeTemplate: function(): MetaConstructionDesc
end

global record ZigzagPlatformCostProfile
    yearFrom: integer
    passenger: ZigzagCostRate
    cargo: ZigzagCostRate
end

global record ZigzagConstructionParams
    tracks: integer | nil
    trackSpacingMetres: integer | nil
    lengthMetres: integer | nil
    length: integer | nil
    signedStartCurveRadiusMetres: integer | nil
    signedEndCurveRadiusMetres: integer | nil
    passengerLoadingEnabled: integer | nil
    passengerCapacityMultiplier: number | nil
    cargoLoadingEnabled: integer | nil
    catchmentRadiusMetres: integer | nil
    -- Retained to migrate stations saved with the original combined toggle.
    loadingEnabled: integer | nil
    trackType: integer | nil
    catenary: integer | nil
    streetTemplate: string | nil
    year: integer | nil
    apasz_zigzag_track_variant: integer | nil
end

global data: function(): any
