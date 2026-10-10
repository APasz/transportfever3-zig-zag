local lane_util = ug_require "::/scripts/construction/laneutil.lua" as LaneUtilSerialized
local param_util = ug_require "::/scripts/construction/param_util.tl" as ParamUtil

local CATENARY_DISABLED_INDEX: integer = 1
local CATENARY_ENABLED_INDEX: integer = 2
local SNAP_ANGLE_DEGREES: number = 60
local NEGATIVE_TRACK_SNAP_NODE_INDEX: integer = 0
local TERMINAL_TRACK_NODE_INDEX: integer = 1
local POSITIVE_TRACK_SNAP_NODE_INDEX: integer = 3
local STATION_TAG: integer = 1
local NON_LOADING_LANE_INDEX: integer = 0
local NON_LOADING_LANE_EDGE_INDEX: integer = 0
local NON_LOADING_LANE_NODE_INDEX: integer = 0

local type Vector3 = {number, number, number}
local type EdgeNode = {Vector3, Vector3}
local type IndexPair = {integer, integer}

local record CapturedParams
    lengthsMetres: {integer}
    defaultLengthIndex: integer
    defaultTrackTypeIndex: integer
    costPerMetre: number
    maintenanceCostPerMetre: number
end

local record UpgradeCapturedParams
    defaultTrackTypeIndex: integer
end

local record ConstructionParams
    length: integer | nil
    trackType: integer | nil
    catenary: integer | nil
    streetTemplate: string | nil
end

local record ConstructionConfig
    streetTemplate: string | nil
    catenary: integer | nil
end

local record EdgeParams
    type: string
end

local record TrackEdgeList
    type: string
    params: EdgeParams
    edges: {EdgeNode}
    snapNodes: {integer}
    tag2nodes: {string: {integer}}
    alignTerrain: boolean
    maxNodeSnapAngle: number
end

local record ZigzagTerminal
    tag: integer
    personEdges: {IndexPair}
    personNodes: {IndexPair}
    vehicleNode: IndexPair
    passengers: boolean
    cargo: boolean
    capacity: integer
    comfortFactor: number
    cargoTransferSpeeds: {ConstructionUtilSerialized.TerminalDef.CargoTransferSpeed}
    transportModes: {ConstructionUtilSerialized.TransportMode}
end

local record StationPool
    edges: {IndexPair}
    capacity: integer
end

local record ZigzagStation
    tag: integer
    terminals: {ZigzagTerminal}
    pool: StationPool
    catchmentAreas: {ConstructionUtilSerialized.CatchmentArea}
end

local record StationSubconstruction
    tag: integer
    models: {ConstructionUtilSerialized.TransformedModel}
    colliders: {ColliderUtilSerialized.Collider}
    terrainAlignmentLists: {ConstructionUtilSerialized.TerrainAlignmentList}
    groundFaces: {ConstructionUtilSerialized.GroundFace}
    laneLists: {ConstructionUtilSerialized.LaneList}
    emissionEmitter: {any}
    station: ZigzagStation
end

local record UpdateResult
    edgeLists: {TrackEdgeList}
    subconstructions: {StationSubconstruction}
    cost: number
    maintenanceCost: number
end

local function requireLength(captureParams: CapturedParams, params: ConstructionParams): integer
    local lengthIndex = captureParams.defaultLengthIndex
    if params.length ~= nil then
        lengthIndex = params.length
    end
    local length = captureParams.lengthsMetres[lengthIndex]
    if length == nil or length <= 0 then
        error("Zigzag Station received invalid length index " .. tostring(lengthIndex))
    end
    return length
end

local function requireStreetTemplate(resourceName: string): StreetTemplate
    return api.res.streetTemplateRep.findAndGet(resourceName)
end

local function supportsTransportMode(
    streetTemplate: StreetTemplate,
    transportMode: TransportMode
): boolean
    for _, laneConfig in ipairs(streetTemplate.laneConfigs) do
        if laneConfig.transportModes[transportMode] then
            return true
        end
    end
    return false
end

local function isElectrifiedTrack(streetTemplate: StreetTemplate): boolean
    return supportsTransportMode(
        streetTemplate,
        api.type["enum"].TransportMode.ELECTRIC_TRAIN
    )
end

local function makeTrackTransportModes(
    catenaryEnabled: boolean
): {ConstructionUtilSerialized.TransportMode}
    local transportModes: {ConstructionUtilSerialized.TransportMode} = { "TRAIN" }
    if catenaryEnabled then
        transportModes[#transportModes + 1] = "ELECTRIC_TRAIN"
    end
    return transportModes
end

local function requireCatenaryEnabled(catenaryIndex: integer | nil): boolean
    local catenary: integer = catenaryIndex or CATENARY_DISABLED_INDEX
    if catenary ~= CATENARY_DISABLED_INDEX and catenary ~= CATENARY_ENABLED_INDEX then
        error("Zigzag Station received invalid catenary index " .. tostring(catenary))
    end
    return catenary == CATENARY_ENABLED_INDEX
end

local function requireTrackType(
    params: ConstructionParams,
    defaultTrackTypeIndex: integer,
    catenaryEnabled: boolean
): string
    if params.streetTemplate ~= nil then
        return params.streetTemplate
    end

    local trackTypes = param_util.getRailTrackTypes(catenaryEnabled)
    local trackTypeIndex = defaultTrackTypeIndex
    if params.trackType ~= nil then
        trackTypeIndex = params.trackType
    end
    local trackType = trackTypes[trackTypeIndex]
    if trackType == nil then
        error("Zigzag Station received invalid track type index " .. tostring(trackTypeIndex))
    end
    return trackType
end

local function getCatenaryReplacement(
    streetTemplate: StreetTemplate,
    catenaryEnabled: boolean
): string | nil
    local replacement: string
    if catenaryEnabled then
        replacement = streetTemplate.catenaryAdd
    else
        replacement = streetTemplate.catenaryRemove
    end
    if replacement == nil or replacement == "" then
        return nil
    end
    return replacement
end

local function supportsCatenaryConfig(
    streetTemplate: StreetTemplate,
    constructionConfig: ConstructionConfig
): boolean
    if constructionConfig.catenary == nil then
        return false
    end
    local catenaryEnabled = requireCatenaryEnabled(constructionConfig.catenary)
    return getCatenaryReplacement(streetTemplate, catenaryEnabled) ~= nil
end

local function makeTrackEdgeList(length: integer, trackType: string): TrackEdgeList
    local halfLength = length / 2
    local tangent: Vector3 = { 0, halfLength, 0 }
    return {
        type = "TRACK",
        params = {
            type = trackType,
        },
        edges = {
            { { 0, -halfLength, 0 }, tangent },
            { { 0, 0, 0 }, tangent },
            { { 0, 0, 0 }, tangent },
            { { 0, halfLength, 0 }, tangent },
        },
        snapNodes = {
            NEGATIVE_TRACK_SNAP_NODE_INDEX,
            POSITIVE_TRACK_SNAP_NODE_INDEX,
        },
        tag2nodes = {},
        alignTerrain = true,
        maxNodeSnapAngle = SNAP_ANGLE_DEGREES,
    }
end

local function makeNonLoadingPersonLane(): ConstructionUtilSerialized.LaneList
    return lane_util.createLane(
        {
            {
                { -0.5, 0, 0 },
                { 0.5, 0, 0 },
            },
        },
        { "PERSON" },
        1,
        0,
        false
    )
end

local function makeStationSubconstruction(
    transportModes: {ConstructionUtilSerialized.TransportMode}
): StationSubconstruction
    return {
        tag = STATION_TAG,
        models = {},
        colliders = {},
        terrainAlignmentLists = {},
        groundFaces = {},
        -- TpF3 requires every terminal to reference an unambiguous PERSON or
        -- CARGO lane. This one exists only for validation, not for access.
        laneLists = {
            makeNonLoadingPersonLane(),
        },
        emissionEmitter = {},
        station = {
            tag = STATION_TAG,
            terminals = {
                {
                    tag = 0,
                    personEdges = {
                        { NON_LOADING_LANE_INDEX, NON_LOADING_LANE_EDGE_INDEX },
                    },
                    personNodes = {
                        { NON_LOADING_LANE_INDEX, NON_LOADING_LANE_NODE_INDEX },
                    },
                    vehicleNode = { -1, TERMINAL_TRACK_NODE_INDEX },
                    -- Both flags prevent line-manager incompatibility errors;
                    -- zero capacity and no catchment keep this a reversing stop.
                    passengers = true,
                    cargo = true,
                    capacity = 0,
                    comfortFactor = 1,
                    cargoTransferSpeeds = {},
                    transportModes = transportModes,
                },
            },
            pool = {
                edges = {},
                capacity = 0,
            },
            catchmentAreas = {},
        },
    }
end

local function updateFn(captureParams: CapturedParams, params: ConstructionParams): UpdateResult
    local length = requireLength(captureParams, params)
    local catenaryEnabled = requireCatenaryEnabled(params.catenary)
    local trackType = requireTrackType(
        params,
        captureParams.defaultTrackTypeIndex,
        catenaryEnabled
    )
    local transportModes = makeTrackTransportModes(catenaryEnabled)
    return {
        edgeLists = {
            makeTrackEdgeList(length, trackType),
        },
        subconstructions = {
            makeStationSubconstruction(transportModes),
        },
        cost = length * captureParams.costPerMetre,
        maintenanceCost = length * captureParams.maintenanceCostPerMetre,
    }
end

local function createTemplateFn(_captureParams: table, _params: ConstructionParams): {integer: string}
    return {}
end

local function isAffectedByToolFn(
    captureParams: UpgradeCapturedParams,
    params: ConstructionParams,
    conConfigAdd: ConstructionConfig,
    conConfigRemove: ConstructionConfig
): boolean
    if conConfigAdd.streetTemplate ~= nil then
        local streetTemplate = requireStreetTemplate(conConfigAdd.streetTemplate)
        return streetTemplate.roadType == api.type["enum"].RoadType.TRACK
    end

    if conConfigAdd.catenary == nil and conConfigRemove.catenary == nil then
        return false
    end

    local catenaryEnabled = requireCatenaryEnabled(params.catenary)
    local trackType = requireTrackType(
        params,
        captureParams.defaultTrackTypeIndex,
        catenaryEnabled
    )
    local streetTemplate = requireStreetTemplate(trackType)
    return supportsCatenaryConfig(streetTemplate, conConfigAdd)
        or supportsCatenaryConfig(streetTemplate, conConfigRemove)
end

local function upgradeFn(
    captureParams: UpgradeCapturedParams,
    params: ConstructionParams,
    _slotId: integer,
    constructionConfig: ConstructionConfig
): ConstructionParams
    if constructionConfig.streetTemplate ~= nil then
        if constructionConfig.catenary ~= nil then
            requireCatenaryEnabled(constructionConfig.catenary)
        end
        local streetTemplate = requireStreetTemplate(constructionConfig.streetTemplate)
        if streetTemplate.roadType ~= api.type["enum"].RoadType.TRACK then
            error("Zigzag Station cannot use a non-track street template")
        end
        params.streetTemplate = constructionConfig.streetTemplate
        params.catenary = isElectrifiedTrack(streetTemplate)
            and CATENARY_ENABLED_INDEX
            or CATENARY_DISABLED_INDEX
    elseif constructionConfig.catenary ~= nil then
        local catenaryEnabled = requireCatenaryEnabled(constructionConfig.catenary)
        local currentCatenaryEnabled = requireCatenaryEnabled(params.catenary)
        local trackType = requireTrackType(
            params,
            captureParams.defaultTrackTypeIndex,
            currentCatenaryEnabled
        )
        local streetTemplate = requireStreetTemplate(trackType)
        if isElectrifiedTrack(streetTemplate) == catenaryEnabled then
            params.catenary = constructionConfig.catenary
            return params
        end

        local upgradedTrackType = getCatenaryReplacement(streetTemplate, catenaryEnabled)
        if upgradedTrackType ~= nil then
            local upgradedStreetTemplate = requireStreetTemplate(upgradedTrackType)
            if upgradedStreetTemplate.roadType ~= api.type["enum"].RoadType.TRACK
                or isElectrifiedTrack(upgradedStreetTemplate) ~= catenaryEnabled then
                error("Track template " .. trackType .. " has an invalid catenary replacement")
            end
            params.streetTemplate = upgradedTrackType
            params.catenary = constructionConfig.catenary
        end
    end
    return params
end

function data(): any
    return {
        createTemplateFn = createTemplateFn,
        updateFn = updateFn,
        isAffectedByToolFn = isAffectedByToolFn,
        upgradeFn = upgradeFn,
    }
end
