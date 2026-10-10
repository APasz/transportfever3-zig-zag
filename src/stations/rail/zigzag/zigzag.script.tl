local lane_util = ug_require "::/scripts/construction/laneutil.lua" as LaneUtilSerialized
local param_util = ug_require "::/scripts/construction/param_util.tl" as ParamUtil

local CATENARY_DISABLED_INDEX: integer = 1
local CATENARY_ENABLED_INDEX: integer = 2
local SNAP_ANGLE_DEGREES: number = 60
local NODES_PER_TRACK: integer = 4
local NEGATIVE_SNAP_NODE_OFFSET: integer = 0
local TERMINAL_NODE_OFFSET: integer = 1
local POSITIVE_SNAP_NODE_OFFSET: integer = 3
local STATION_TAG: integer = 1
local NON_LOADING_LANE_EDGE_INDEX: integer = 0
local NON_LOADING_LANE_NODE_INDEX: integer = 0
local LANE_SPEED_LIMIT: number = 30
local PASSENGER_LANE_WIDTH_METRES: number = 2.4
local CARGO_LANE_WIDTH_METRES: number = 4
-- TpF3 rejects coincident transport-network edges even when their modes differ.
local SERVICE_LANE_OFFSET_METRES: number = 0.5
local ACCESS_LANE_WIDTH_METRES: number = 1
local ACCESS_EXTENSION_METRES: number = 10
local PASSENGER_CAPACITY_PER_METRE: number = 1.7

local type Vector3 = {number, number, number}
local type EdgeNode = {Vector3, Vector3}
local type IndexPair = {integer, integer}

local record CapturedParams
    lengthsMetres: {integer}
    legacyLengthsMetres: {integer}
    trackCounts: {integer}
    trackSpacingsMetres: {integer}
    catchmentRadiiMetres: {integer}
    passengerCapacityMultipliers: {number}
    defaultLengthMetres: integer
    defaultTrackCountIndex: integer
    defaultTrackSpacingIndex: integer
    defaultCatchmentRadiusMetres: integer
    defaultPassengerCapacityMultiplier: number
    defaultTrackTypeIndex: integer
    loadingDisabledIndex: integer
    loadingEnabledIndex: integer
    costPerMetre: number
    maintenanceCostPerMetre: number
end

local record UpgradeCapturedParams
    defaultTrackTypeIndex: integer
end

local record ConstructionParams
    tracks: integer | nil
    trackSpacingMetres: integer | nil
    lengthMetres: integer | nil
    length: integer | nil
    passengerLoadingEnabled: integer | nil
    passengerCapacityMultiplier: number | nil
    cargoLoadingEnabled: integer | nil
    catchmentRadiusMetres: integer | nil
    -- Retained to migrate stations saved with the original combined toggle.
    loadingEnabled: integer | nil
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

-- The shipped CatchmentArea definition uses the runtime Vec3 record, but
-- construction scripts serialize positions as three-element numeric arrays.
local record ZigzagCatchmentArea
    position: Vector3
    radius: number
end

local record ZigzagStation
    tag: integer
    terminals: {ZigzagTerminal}
    pool: StationPool
    catchmentAreas: {ZigzagCatchmentArea}
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

local function requireAllowedValue<T>(
    allowedValues: {T},
    value: T,
    valueName: string
): T
    for _, allowedValue in ipairs(allowedValues) do
        if value == allowedValue then
            return value
        end
    end
    error("Zigzag Station received invalid " .. valueName .. " " .. tostring(value))
end

local function requireIndexedPositiveValue(
    values: {integer},
    index: integer,
    valueName: string
): integer
    local value = values[index]
    if value == nil or value <= 0 then
        error(
            "Zigzag Station received invalid "
                .. valueName
                .. " index "
                .. tostring(index)
        )
    end
    return value
end

local function requireLength(captureParams: CapturedParams, params: ConstructionParams): integer
    if params.lengthMetres ~= nil then
        return requireAllowedValue(
            captureParams.lengthsMetres,
            params.lengthMetres,
            "length"
        )
    end

    local legacyLengthIndex = params.length
    if legacyLengthIndex ~= nil then
        return requireIndexedPositiveValue(
            captureParams.legacyLengthsMetres,
            legacyLengthIndex as integer,
            "legacy length"
        )
    end

    return requireAllowedValue(
        captureParams.lengthsMetres,
        captureParams.defaultLengthMetres,
        "default length"
    )
end

local function requireTrackCount(
    captureParams: CapturedParams,
    params: ConstructionParams
): integer
    local trackCountIndex = captureParams.defaultTrackCountIndex
    if params.tracks ~= nil then
        trackCountIndex = params.tracks
    end
    return requireIndexedPositiveValue(
        captureParams.trackCounts,
        trackCountIndex,
        "track-count"
    )
end

local function requireTrackSpacingMetres(
    captureParams: CapturedParams,
    params: ConstructionParams
): integer
    if params.trackSpacingMetres == nil then
        return requireIndexedPositiveValue(
            captureParams.trackSpacingsMetres,
            captureParams.defaultTrackSpacingIndex,
            "default track-spacing"
        )
    end
    return requireAllowedValue(
        captureParams.trackSpacingsMetres,
        params.trackSpacingMetres,
        "track spacing"
    )
end

local function requireToggleEnabled(
    captureParams: CapturedParams,
    selectedIndex: integer | nil,
    defaultIndex: integer,
    valueName: string
): boolean
    local loadingIndex = selectedIndex or defaultIndex
    if loadingIndex == captureParams.loadingDisabledIndex then
        return false
    end
    if loadingIndex == captureParams.loadingEnabledIndex then
        return true
    end
    error(
        "Zigzag Station received invalid "
            .. valueName
            .. " index "
            .. tostring(loadingIndex)
    )
end

local function requireLoadingModes(
    captureParams: CapturedParams,
    params: ConstructionParams
): boolean, boolean
    local legacyLoadingIndex = params.loadingEnabled
    local defaultLoadingIndex = captureParams.loadingDisabledIndex
    if legacyLoadingIndex ~= nil then
        requireToggleEnabled(
            captureParams,
            legacyLoadingIndex,
            captureParams.loadingDisabledIndex,
            "legacy loading"
        )
        defaultLoadingIndex = legacyLoadingIndex
    end
    return requireToggleEnabled(
        captureParams,
        params.passengerLoadingEnabled,
        defaultLoadingIndex,
        "passenger-loading"
    ), requireToggleEnabled(
        captureParams,
        params.cargoLoadingEnabled,
        defaultLoadingIndex,
        "cargo-loading"
    )
end

local function requirePassengerCapacityMultiplier(
    captureParams: CapturedParams,
    params: ConstructionParams
): number
    return requireAllowedValue(
        captureParams.passengerCapacityMultipliers,
        params.passengerCapacityMultiplier
            or captureParams.defaultPassengerCapacityMultiplier,
        "passenger capacity multiplier"
    )
end

local function requireCatchmentRadiusMetres(
    captureParams: CapturedParams,
    params: ConstructionParams
): integer
    return requireAllowedValue(
        captureParams.catchmentRadiiMetres,
        params.catchmentRadiusMetres
            or captureParams.defaultCatchmentRadiusMetres,
        "catchment radius"
    )
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

local function getTrackOffsetMetres(
    trackIndex: integer,
    trackCount: integer,
    trackSpacingMetres: number
): number
    return (trackIndex - (trackCount + 1) / 2) * trackSpacingMetres
end

local function makeTrackEdgeList(
    length: integer,
    trackType: string,
    trackCount: integer,
    trackSpacingMetres: number
): TrackEdgeList
    local halfLength = length / 2
    local tangent: Vector3 = { 0, halfLength, 0 }
    local edges: {EdgeNode} = {}
    local snapNodes: {integer} = {}
    for trackIndex = 1, trackCount do
        local trackOffsetMetres = getTrackOffsetMetres(
            trackIndex,
            trackCount,
            trackSpacingMetres
        )
        local firstNodeIndex = (trackIndex - 1) * NODES_PER_TRACK
        edges[#edges + 1] = { { trackOffsetMetres, -halfLength, 0 }, tangent }
        edges[#edges + 1] = { { trackOffsetMetres, 0, 0 }, tangent }
        edges[#edges + 1] = { { trackOffsetMetres, 0, 0 }, tangent }
        edges[#edges + 1] = { { trackOffsetMetres, halfLength, 0 }, tangent }
        snapNodes[#snapNodes + 1] = firstNodeIndex + NEGATIVE_SNAP_NODE_OFFSET
        snapNodes[#snapNodes + 1] = firstNodeIndex + POSITIVE_SNAP_NODE_OFFSET
    end
    return {
        type = "TRACK",
        params = {
            type = trackType,
        },
        edges = edges,
        snapNodes = snapNodes,
        tag2nodes = {},
        alignTerrain = true,
        maxNodeSnapAngle = SNAP_ANGLE_DEGREES,
    }
end

local function makeCombinedNonLoadingLane(
    trackOffsetMetres: number,
    transportMode: ConstructionUtilSerialized.TransportMode
): ConstructionUtilSerialized.LaneList
    return lane_util.createLane(
        {
            {
                { trackOffsetMetres - 0.5, 0, 0 },
                { trackOffsetMetres + 0.5, 0, 0 },
            },
        },
        { transportMode },
        1,
        0,
        false
    )
end

local function makeDisabledLoadingLane(
    laneOffsetMetres: number,
    transportMode: ConstructionUtilSerialized.TransportMode
): ConstructionUtilSerialized.LaneList
    return lane_util.createLane(
        {
            {
                { laneOffsetMetres, -0.5, 0 },
                { laneOffsetMetres, 0.5, 0 },
            },
        },
        { transportMode },
        1,
        0,
        false
    )
end

local function makeServiceLane(
    laneOffsetMetres: number,
    length: integer,
    transportMode: ConstructionUtilSerialized.TransportMode,
    widthMetres: number
): ConstructionUtilSerialized.LaneList
    local halfLength = length / 2
    return lane_util.createLane(
        {
            {
                { laneOffsetMetres, -halfLength, 0 },
                { laneOffsetMetres, 0, 0 },
            },
            {
                { laneOffsetMetres, 0, 0 },
                { laneOffsetMetres, halfLength, 0 },
            },
        },
        { transportMode },
        LANE_SPEED_LIMIT,
        widthMetres,
        false
    )
end

local function makePassengerAccessLane(
    firstTrackOffsetMetres: number,
    lastTrackOffsetMetres: number,
    passengerLaneOffsetsMetres: {number},
    longitudinalOffsetMetres: number
): ConstructionUtilSerialized.LaneList
    local accessPoints: {Vector3} = {
        {
            firstTrackOffsetMetres - ACCESS_EXTENSION_METRES,
            longitudinalOffsetMetres,
            0,
        },
    }
    for _, passengerLaneOffsetMetres in ipairs(passengerLaneOffsetsMetres) do
        accessPoints[#accessPoints + 1] = {
            passengerLaneOffsetMetres,
            longitudinalOffsetMetres,
            0,
        }
    end
    accessPoints[#accessPoints + 1] = {
        lastTrackOffsetMetres + ACCESS_EXTENSION_METRES,
        longitudinalOffsetMetres,
        0,
    }

    local accessSegments: {{Vector3}} = {}
    for pointIndex = 1, #accessPoints - 1 do
        accessSegments[#accessSegments + 1] = {
            accessPoints[pointIndex],
            accessPoints[pointIndex + 1],
        }
    end
    return lane_util.createLane(
        accessSegments,
        { "PERSON" },
        LANE_SPEED_LIMIT,
        ACCESS_LANE_WIDTH_METRES,
        true
    )
end

local function makeCargoTransferSpeed(
    cargoClass: string,
    length: integer
): ConstructionUtilSerialized.TerminalDef.CargoTransferSpeed
    return {
        cargoTypeSet = {
            cargoClassesIncluded = { cargoClass },
            cargoClassesExcluded = {},
            cargoTypesIncluded = {},
            cargoTypesExcluded = {},
        },
        loadSpeedModifier = 1,
        length = length,
    }
end

local function makeTerminal(
    tag: integer,
    laneListIndex: integer,
    vehicleNodeIndex: integer,
    passengers: boolean,
    cargo: boolean,
    capacity: integer,
    cargoTransferSpeeds: {ConstructionUtilSerialized.TerminalDef.CargoTransferSpeed},
    transportModes: {ConstructionUtilSerialized.TransportMode}
): ZigzagTerminal
    return {
        tag = tag,
        personEdges = {
            { laneListIndex, 0 },
            { laneListIndex, 1 },
        },
        personNodes = {
            { laneListIndex, 1 },
        },
        vehicleNode = { -1, vehicleNodeIndex },
        passengers = passengers,
        cargo = cargo,
        capacity = capacity,
        comfortFactor = 1,
        cargoTransferSpeeds = cargoTransferSpeeds,
        transportModes = transportModes,
    }
end

local function makeNonLoadingTerminal(
    tag: integer,
    laneListIndex: integer,
    vehicleNodeIndex: integer,
    passengers: boolean,
    cargo: boolean,
    transportModes: {ConstructionUtilSerialized.TransportMode}
): ZigzagTerminal
    return {
        tag = tag,
        personEdges = {
            { laneListIndex, NON_LOADING_LANE_EDGE_INDEX },
        },
        personNodes = {
            { laneListIndex, NON_LOADING_LANE_NODE_INDEX },
        },
        vehicleNode = { -1, vehicleNodeIndex },
        passengers = passengers,
        cargo = cargo,
        capacity = 0,
        comfortFactor = 1,
        cargoTransferSpeeds = {},
        transportModes = transportModes,
    }
end

local function passengerCapacity(length: integer, multiplier: number): integer
    local baseCapacity = math.max(
        math.floor(length * PASSENGER_CAPACITY_PER_METRE + 0.5),
        1
    )
    return math.max(math.floor(baseCapacity * multiplier + 0.5), 1)
end

local function makeStationSubconstruction(
    length: integer,
    trackCount: integer,
    trackSpacingMetres: number,
    passengerLoadingEnabled: boolean,
    cargoLoadingEnabled: boolean,
    passengerCapacityMultiplier: number,
    catchmentRadiusMetres: integer,
    transportModes: {ConstructionUtilSerialized.TransportMode}
): StationSubconstruction
    local laneLists: {ConstructionUtilSerialized.LaneList} = {}
    local terminals: {ZigzagTerminal} = {}
    local passengerLaneOffsetsMetres: {number} = {}
    local loadingEnabled = passengerLoadingEnabled or cargoLoadingEnabled
    for trackIndex = 1, trackCount do
        local zeroBasedTrackIndex = trackIndex - 1
        local trackOffsetMetres = getTrackOffsetMetres(
            trackIndex,
            trackCount,
            trackSpacingMetres
        )
        local vehicleNodeIndex = zeroBasedTrackIndex * NODES_PER_TRACK
            + TERMINAL_NODE_OFFSET
        local passengerLaneOffsetMetres = trackOffsetMetres
            - SERVICE_LANE_OFFSET_METRES
        local cargoLaneOffsetMetres = trackOffsetMetres
            + SERVICE_LANE_OFFSET_METRES
        if loadingEnabled then
            -- A disabled loading mode keeps a zero-capacity terminal so that
            -- its trains can still use the station as a reversing point.
            local passengerLaneIndex = #laneLists
            if passengerLoadingEnabled then
                passengerLaneOffsetsMetres[#passengerLaneOffsetsMetres + 1]
                    = passengerLaneOffsetMetres
                laneLists[#laneLists + 1] = makeServiceLane(
                    passengerLaneOffsetMetres,
                    length,
                    "PERSON",
                    PASSENGER_LANE_WIDTH_METRES
                )
                terminals[#terminals + 1] = makeTerminal(
                    zeroBasedTrackIndex * 2,
                    passengerLaneIndex,
                    vehicleNodeIndex,
                    true,
                    false,
                    passengerCapacity(length, passengerCapacityMultiplier),
                    { makeCargoTransferSpeed("PASSENGERS", length) },
                    transportModes
                )
            else
                laneLists[#laneLists + 1] = makeDisabledLoadingLane(
                    passengerLaneOffsetMetres,
                    "PERSON"
                )
                terminals[#terminals + 1] = makeNonLoadingTerminal(
                    zeroBasedTrackIndex * 2,
                    passengerLaneIndex,
                    vehicleNodeIndex,
                    true,
                    false,
                    transportModes
                )
            end

            local cargoLaneIndex = #laneLists
            if cargoLoadingEnabled then
                laneLists[#laneLists + 1] = makeServiceLane(
                    cargoLaneOffsetMetres,
                    length,
                    "CARGO",
                    CARGO_LANE_WIDTH_METRES
                )
                terminals[#terminals + 1] = makeTerminal(
                    zeroBasedTrackIndex * 2 + 1,
                    cargoLaneIndex,
                    vehicleNodeIndex,
                    false,
                    true,
                    0,
                    { makeCargoTransferSpeed("UNIVERSAL", length) },
                    transportModes
                )
            else
                laneLists[#laneLists + 1] = makeDisabledLoadingLane(
                    cargoLaneOffsetMetres,
                    "CARGO"
                )
                terminals[#terminals + 1] = makeNonLoadingTerminal(
                    zeroBasedTrackIndex * 2 + 1,
                    cargoLaneIndex,
                    vehicleNodeIndex,
                    false,
                    true,
                    transportModes
                )
            end
        else
            local laneListIndex = #laneLists
            laneLists[#laneLists + 1] = makeCombinedNonLoadingLane(
                trackOffsetMetres,
                "PERSON"
            )
            terminals[#terminals + 1] = makeNonLoadingTerminal(
                zeroBasedTrackIndex,
                laneListIndex,
                vehicleNodeIndex,
                true,
                true,
                transportModes
            )
        end
    end

    local catchmentAreas: {ZigzagCatchmentArea} = {}
    if loadingEnabled then
        local halfLength = length / 2
        local firstTrackOffsetMetres = getTrackOffsetMetres(
            1,
            trackCount,
            trackSpacingMetres
        )
        local lastTrackOffsetMetres = getTrackOffsetMetres(
            trackCount,
            trackCount,
            trackSpacingMetres
        )
        local accessLaneOffsetsMetres: {number} = { -halfLength, 0, halfLength }
        for _, longitudinalOffsetMetres in ipairs(accessLaneOffsetsMetres) do
            if passengerLoadingEnabled then
                laneLists[#laneLists + 1] = makePassengerAccessLane(
                    firstTrackOffsetMetres,
                    lastTrackOffsetMetres,
                    passengerLaneOffsetsMetres,
                    longitudinalOffsetMetres
                )
            end
            catchmentAreas[#catchmentAreas + 1] = {
                position = { 0.0, longitudinalOffsetMetres, 0.0 },
                radius = catchmentRadiusMetres,
            }
        end
    end
    return {
        tag = STATION_TAG,
        models = {},
        colliders = {},
        terrainAlignmentLists = {},
        groundFaces = {},
        -- TpF3 requires every terminal to reference lanes of one unambiguous
        -- service type, so loading mode uses separate passenger and cargo lanes.
        laneLists = laneLists,
        emissionEmitter = {},
        station = {
            tag = STATION_TAG,
            terminals = terminals,
            pool = {
                edges = {},
                capacity = 0,
            },
            catchmentAreas = catchmentAreas,
        },
    }
end

local function updateFn(captureParams: CapturedParams, params: ConstructionParams): UpdateResult
    local length = requireLength(captureParams, params)
    local trackCount = requireTrackCount(captureParams, params)
    local trackSpacingMetres = requireTrackSpacingMetres(captureParams, params)
    local passengerLoadingEnabled, cargoLoadingEnabled = requireLoadingModes(
        captureParams,
        params
    )
    local passengerCapacityMultiplier = requirePassengerCapacityMultiplier(
        captureParams,
        params
    )
    local catchmentRadiusMetres = requireCatchmentRadiusMetres(captureParams, params)
    local catenaryEnabled = requireCatenaryEnabled(params.catenary)
    local trackType = requireTrackType(
        params,
        captureParams.defaultTrackTypeIndex,
        catenaryEnabled
    )
    local transportModes = makeTrackTransportModes(catenaryEnabled)
    return {
        edgeLists = {
            makeTrackEdgeList(
                length,
                trackType,
                trackCount,
                trackSpacingMetres
            ),
        },
        subconstructions = {
            makeStationSubconstruction(
                length,
                trackCount,
                trackSpacingMetres,
                passengerLoadingEnabled,
                cargoLoadingEnabled,
                passengerCapacityMultiplier,
                catchmentRadiusMetres,
                transportModes
            ),
        },
        cost = length * trackCount * captureParams.costPerMetre,
        maintenanceCost = length * trackCount * captureParams.maintenanceCostPerMetre,
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
