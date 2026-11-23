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
    makeConstruction: function(ZigzagStorageBayLayout): table
    makeTemplate: function(): MetaConstructionDesc
end

global record ZigzagPlatformCostProfile
    yearFrom: integer
    passenger: ZigzagCostRate
    cargo: ZigzagCostRate
end

global enum ZigzagStorageType
    "UNIVERSAL"
    "BULK"
    "FLATBED"
    "GOODS"
    "LIQUID"
end

global enum ZigzagStorageBayLayout
    "MODULE_BAYS"
    "SINGLE_BAY"
end

global record ZigzagStorageProfile
    kind: ZigzagStorageType
    moduleName: ResName
    labelKey: string
    mixedTypes: boolean
    loadSpeedModifier: number
end

global record ZigzagStorageBay
    tag: integer
    capacity: integer
end

global record ZigzagStorageStock
    tag: integer
    type: ConstructionUtilSerialized.Stocks.StockType
    cargoTypes: ConstructionUtilSerialized.CargoTypeSet
    mixedTypes: boolean
    capacity: integer
    loadSpeedModifier: number
    cargoType: ResName | nil
end

global record ZigzagCargoStorage
    capacities: {integer}
    profiles: {ZigzagStorageProfile}
    bayLayouts: {ZigzagStorageBayLayout}
    moduleCapacity: integer
    subconstructionTag: integer
    stockTag: integer
    metadata: MetadataAccessor<ConstructionInstanceMetadata, integer>
    baysMetadata: MetadataAccessor<ConstructionInstanceMetadata, {ZigzagStorageBay}>
    requireCapacity: function(integer | nil): integer
    requireProfile: function(integer | nil): ZigzagStorageProfile
    makeBays: function(integer, integer | nil, ZigzagStorageBayLayout): {ZigzagStorageBay}
    makeStocks: function({ZigzagStorageBay}, ZigzagStorageProfile, {integer: ResName} | nil): {ZigzagStorageStock}
    requireStockList: function(Engine.Component.Construction): Engine.Entity
    removalErrors: function(Engine.Component.Construction, ConstructionInstanceMetadata | nil): {string}
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
    cargoStorageCapacity: integer | nil
    cargoStorageType: integer | nil
    tagToCargoType: {integer: ResName} | nil
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
