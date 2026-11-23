local lane_util = ug_require "::/scripts/construction/laneutil.lua" as LaneUtilSerialized
local street_util = ug_require(
    "::/scripts/construction/street_util_serialized.tl"
) as StreetUtilSerialized
local validationMetadata = ug_require(
    "apasz_zigzag::/zigzag/validation_metadata.lua"
) as MetadataAccessor<ConstructionInstanceMetadata, {string}>
local param_util = ug_require "::/scripts/construction/param_util.tl" as ParamUtil
local trackSelection = ug_require(
    "apasz_zigzag::/zigzag/track_selection.lua"
) as ZigzagTrackSelection
local logging = ug_require(
    "apasz_zigzag::/zigzag/logging.lua"
) as ModLogging.Module
local logger = logging.new("Zigzag Station", false)

local requireCatenaryEnabled = trackSelection.catenaryEnabled
local SNAP_ANGLE_DEGREES: number = 60
local MAX_SEGMENT_TURN_RADIANS: number = math.rad(10)
local MAX_END_TURN_RADIANS: number = math.pi / 2
local TERMINAL_NODE_SEPARATION_METRES: number = 1
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
-- Track nodes omit width; service-lane nodes include it.
local type GeometryNode = {Vector3, Vector3, number | nil}
local type IndexPair = {integer, integer}

local record CapturedParams
    lengthsMetres: {integer}
    legacyLengthsMetres: {integer}
    trackCounts: {integer}
    trackSpacingsMetres: {integer}
    curveRadiiMetres: {integer}
    trackMinimumRadiiMetres: {string: number}
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
    moduleLengthMetres: integer
    costMode: ZigzagCostMode
    trackCostProfiles: {string: ZigzagTrackCostProfile}
    platformCostProfiles: {ZigzagPlatformCostProfile}
end

local record UpgradeCapturedParams
    defaultTrackTypeIndex: integer
end

local type ConstructionParams = ZigzagConstructionParams

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
    edges: {GeometryNode}
    snapNodes: {integer}
    tag2nodes: {string: {integer}}
    alignTerrain: boolean
    maxNodeSnapAngle: number
end

local record CurveGeometry
    startCurvaturePerMetre: number
    endCurvaturePerMetre: number
    lengthMetres: number
end

local record TrackGeometry
    offsetMetres: number
    lengthMetres: number
    passengerNodeIndex: integer
    centreNodeIndex: integer
    cargoNodeIndex: integer
end

local record TrackLayout
    edgeList: TrackEdgeList
    tracks: {TrackGeometry}
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
    metadata: ConstructionInstanceMetadata | nil
end

local function addCost(
    total: ZigzagCostRate,
    rate: ZigzagCostRate,
    quantity: number
)
    total.construction = total.construction + rate.construction * quantity
    total.maintenance = total.maintenance + rate.maintenance * quantity
end

local function trackCostRate(
    captureParams: CapturedParams,
    trackType: string
): ZigzagCostRate
    local profile = captureParams.trackCostProfiles[trackType]
    local rate = trackSelection.costRate(profile, captureParams.costMode)
    if rate ~= nil then
        return rate
    end
    local costType = captureParams.costMode == "TRACK_COST" and "per-metre" or "generated module"
    logger.warnOnce(
        costType .. ":" .. trackType,
        "Missing or invalid " .. costType .. " cost for track " .. trackType
            .. "; using zero track construction and maintenance costs"
    )
    return trackSelection.zeroCostRate
end

local function requirePlatformCostProfile(
    captureParams: CapturedParams,
    year: integer
): ZigzagPlatformCostProfile
    local selectedProfile: ZigzagPlatformCostProfile | nil = nil
    for _, profile in ipairs(captureParams.platformCostProfiles) do
        if profile.yearFrom <= year then
            if selectedProfile == nil
                or profile.yearFrom
                    > (selectedProfile as ZigzagPlatformCostProfile).yearFrom
            then
                selectedProfile = profile
            end
        end
    end
    if selectedProfile == nil then
        error("Zigzag Station has no platform cost profile for year " .. tostring(year))
    end
    return selectedProfile
end

local function calculateCosts(
    captureParams: CapturedParams,
    params: ConstructionParams,
    length: integer,
    trackCount: integer,
    trackType: string,
    passengerLoadingEnabled: boolean,
    cargoLoadingEnabled: boolean
): ZigzagCostRate
    local mode = captureParams.costMode
    if mode == "NO_COST" then
        return trackSelection.zeroCostRate
    end

    local total: ZigzagCostRate = { construction = 0, maintenance = 0 }
    if mode == "TRACK_COST" then
        local trackRate = trackCostRate(captureParams, trackType)
        addCost(total, trackRate, length * trackCount)
        return total
    end
    if mode ~= "MODULE_COST" and mode ~= "STATION_COST" then
        error("Zigzag Station received invalid cost mode " .. tostring(mode))
    end

    local trackModuleRate = trackCostRate(captureParams, trackType)
    if captureParams.moduleLengthMetres <= 0 then
        error("Zigzag Station requires a positive module length")
    end
    local moduleCountAlongLength = length / captureParams.moduleLengthMetres
    addCost(total, trackModuleRate, moduleCountAlongLength * trackCount)

    if mode == "STATION_COST"
        and (passengerLoadingEnabled or cargoLoadingEnabled)
    then
        local platformProfile = requirePlatformCostProfile(
            captureParams,
            params.year or 0
        )
        local platformRows = math.floor(trackCount / 2) + 1
        local platformModuleCount = moduleCountAlongLength * platformRows
        if passengerLoadingEnabled then
            addCost(total, platformProfile.passenger, platformModuleCount)
        end
        if cargoLoadingEnabled then
            addCost(total, platformProfile.cargo, platformModuleCount)
        end
    end

    return total
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

local function isElectrifiedTrack(streetTemplate: StreetTemplate): boolean
    return trackSelection.supportsTransportMode(
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

local function requireEndCurvature(
    captureParams: CapturedParams,
    signedRadius: integer,
    minimumRadius: number,
    endName: string,
    validationErrors: {string}
): number
    if signedRadius == 0 then
        return 0
    end
    local radius = requireAllowedValue(
        captureParams.curveRadiiMetres,
        signedRadius < 0 and -signedRadius or signedRadius,
        endName
    )
    if radius < minimumRadius then
        validationErrors[#validationErrors + 1] = endName .. ": " .. string.format(
            _("apasz_zigzag_curve_radius_too_small"),
            radius,
            math.ceil(minimumRadius)
        )
    end
    return -1 / signedRadius
end

local function makeCurveGeometry(
    captureParams: CapturedParams,
    params: ConstructionParams,
    length: integer,
    trackCount: integer,
    trackSpacingMetres: number,
    trackType: string
): CurveGeometry, {string}
    local startRadius = params.signedStartCurveRadiusMetres or 0
    local endRadius = params.signedEndCurveRadiusMetres or 0
    local minimumRadius: number = 0
    if startRadius ~= 0 or endRadius ~= 0 then
        local minimumTrackRadius = captureParams.trackMinimumRadiiMetres[trackType]
        if minimumTrackRadius == nil then
            error("Zigzag Station has no minimum-radius data for track " .. trackType)
        end
        local halfWidth = (trackCount - 1) * trackSpacingMetres / 2
        -- Access lanes extend beyond the outer tracks and need positive radii too.
        minimumRadius = math.max(
            minimumTrackRadius + halfWidth,
            (length / 2) / MAX_END_TURN_RADIANS,
            math.floor(halfWidth + ACCESS_EXTENSION_METRES) + 1
        )
    end
    local validationErrors: {string} = {}
    return {
        startCurvaturePerMetre = requireEndCurvature(
            captureParams, startRadius, minimumRadius, _("apasz_zigzag_start_curve_radius"),
            validationErrors
        ),
        endCurvaturePerMetre = requireEndCurvature(
            captureParams, endRadius, minimumRadius, _("apasz_zigzag_end_curve_radius"),
            validationErrors
        ),
        lengthMetres = length,
    }, validationErrors
end

local function curvatureAt(curve: CurveGeometry, longitudinalMetres: number): number
    if longitudinalMetres < 0 then
        return curve.startCurvaturePerMetre
    end
    return curve.endCurvaturePerMetre
end

local function longitudinalScale(curvaturePerMetre: number, offsetMetres: number): number
    return 1 + curvaturePerMetre * offsetMetres
end

local function curvePosition(
    curve: CurveGeometry,
    offsetMetres: number,
    longitudinalMetres: number
): Vector3
    local curvature = curvatureAt(curve, longitudinalMetres)
    if curvature == 0 then
        return { offsetMetres, longitudinalMetres, 0 }
    end
    local angle = curvature * longitudinalMetres
    -- This form avoids cancellation in 1 - cos(angle) near the stop nodes.
    local lateral = -2 * math.sin(angle / 2) ^ 2 / curvature
    return {
        lateral + offsetMetres * math.cos(angle),
        math.sin(angle) / curvature + offsetMetres * math.sin(angle),
        0,
    }
end

local function addCurveNodes(
    nodes: {GeometryNode},
    curve: CurveGeometry,
    trackOffsetMetres: number,
    firstLongitudinalOffsetMetres: number,
    secondLongitudinalOffsetMetres: number,
    widthMetres?: number
)
    if firstLongitudinalOffsetMetres < 0 and secondLongitudinalOffsetMetres > 0 then
        addCurveNodes(nodes, curve, trackOffsetMetres, firstLongitudinalOffsetMetres, 0, widthMetres)
        addCurveNodes(nodes, curve, trackOffsetMetres, 0, secondLongitudinalOffsetMetres, widthMetres)
        return
    end
    local curvature = curvatureAt(
        curve, (firstLongitudinalOffsetMetres + secondLongitudinalOffsetMetres) / 2
    )
    local span = secondLongitudinalOffsetMetres - firstLongitudinalOffsetMetres
    if curvature == 0 then
        local tangent: Vector3 = { 0, span, 0 }
        nodes[#nodes + 1] = { { trackOffsetMetres, firstLongitudinalOffsetMetres, 0 }, tangent, widthMetres }
        nodes[#nodes + 1] = { { trackOffsetMetres, secondLongitudinalOffsetMetres, 0 }, tangent, widthMetres }
        return
    end
    local segmentCount = math.max(1, math.ceil(
        math.abs(curvature * span) / MAX_SEGMENT_TURN_RADIANS
    ))
    for segmentIndex = 1, segmentCount do
        local first = firstLongitudinalOffsetMetres + span * (segmentIndex - 1) / segmentCount
        local last = secondLongitudinalOffsetMetres
        if segmentIndex < segmentCount then
            last = firstLongitudinalOffsetMetres + span * segmentIndex / segmentCount
        end
        local firstPosition = curvePosition(curve, trackOffsetMetres, first)
        local lastPosition = curvePosition(curve, trackOffsetMetres, last)
        local deltaX = lastPosition[1] - firstPosition[1]
        local deltaY = lastPosition[2] - firstPosition[2]
        local tangentLength = street_util.calcScale(
            math.sqrt(deltaX * deltaX + deltaY * deltaY),
            math.abs(curvature * (last - first))
        )
        local firstAngle = curvature * first
        local lastAngle = curvature * last
        nodes[#nodes + 1] = {
            firstPosition,
            { -math.sin(firstAngle) * tangentLength, math.cos(firstAngle) * tangentLength, 0 },
            widthMetres,
        }
        nodes[#nodes + 1] = {
            lastPosition,
            { -math.sin(lastAngle) * tangentLength, math.cos(lastAngle) * tangentLength, 0 },
            widthMetres,
        }
    end
end

local function makeTrackLayout(
    curve: CurveGeometry,
    trackType: string,
    trackCount: integer,
    trackSpacingMetres: number
): TrackLayout
    local halfLength = curve.lengthMetres / 2
    local edges: {GeometryNode} = {}
    local snapNodes: {integer} = {}
    local tracks: {TrackGeometry} = {}
    for trackIndex = 1, trackCount do
        local trackOffsetMetres = getTrackOffsetMetres(
            trackIndex,
            trackCount,
            trackSpacingMetres
        )
        local startScale = longitudinalScale(curve.startCurvaturePerMetre, trackOffsetMetres)
        local endScale = longitudinalScale(curve.endCurvaturePerMetre, trackOffsetMetres)
        local startStopOffsetMetres = -TERMINAL_NODE_SEPARATION_METRES / (2 * startScale)
        local endStopOffsetMetres = TERMINAL_NODE_SEPARATION_METRES / (2 * endScale)
        snapNodes[#snapNodes + 1] = #edges
        addCurveNodes(
            edges,
            curve,
            trackOffsetMetres,
            -halfLength,
            startStopOffsetMetres
        )
        local passengerNodeIndex = #edges - 1
        addCurveNodes(
            edges,
            curve,
            trackOffsetMetres,
            startStopOffsetMetres,
            0
        )
        local centreNodeIndex = #edges - 1
        addCurveNodes(
            edges,
            curve,
            trackOffsetMetres,
            0,
            endStopOffsetMetres
        )
        local cargoNodeIndex = #edges - 1
        addCurveNodes(
            edges,
            curve,
            trackOffsetMetres,
            endStopOffsetMetres,
            halfLength
        )
        snapNodes[#snapNodes + 1] = #edges - 1
        tracks[#tracks + 1] = {
            offsetMetres = trackOffsetMetres,
            lengthMetres = halfLength * (startScale + endScale),
            passengerNodeIndex = passengerNodeIndex,
            centreNodeIndex = centreNodeIndex,
            cargoNodeIndex = cargoNodeIndex,
        }
    end
    return {
        tracks = tracks,
        edgeList = {
            type = "TRACK",
            params = {
                type = trackType,
            },
            edges = edges,
            snapNodes = snapNodes,
            tag2nodes = {},
            alignTerrain = true,
            maxNodeSnapAngle = SNAP_ANGLE_DEGREES,
        },
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
    curve: CurveGeometry,
    laneOffsetMetres: number,
    transportMode: ConstructionUtilSerialized.TransportMode
): ConstructionUtilSerialized.LaneList
    return lane_util.createLane(
        {
            {
                curvePosition(curve, laneOffsetMetres, -0.5),
                curvePosition(curve, laneOffsetMetres, 0.5),
            },
        },
        { transportMode },
        1,
        0,
        false
    )
end

local function makeServiceLane(
    curve: CurveGeometry,
    laneOffsetMetres: number,
    transportMode: ConstructionUtilSerialized.TransportMode,
    widthMetres: number
): ConstructionUtilSerialized.LaneList, integer
    local halfLength = curve.lengthMetres / 2
    local nodes: {GeometryNode} = {}
    addCurveNodes(nodes, curve, laneOffsetMetres, -halfLength, 0, widthMetres)
    local centreNodeIndex = #nodes - 1
    addCurveNodes(nodes, curve, laneOffsetMetres, 0, halfLength, widthMetres)
    return {
        -- The shipped LaneList type uses Vec3 records; the converter accepts arrays.
        nodes = nodes as {{Vec3Serialized.Vec3, Vec3Serialized.Vec3, number}},
        transportModes = { transportMode },
        speedLimit = LANE_SPEED_LIMIT,
        linkable = false,
    }, centreNodeIndex
end

local function makePassengerAccessLane(
    curve: CurveGeometry,
    firstTrackOffsetMetres: number,
    lastTrackOffsetMetres: number,
    passengerLaneOffsetsMetres: {number},
    longitudinalOffsetMetres: number
): ConstructionUtilSerialized.LaneList
    local accessPoints: {Vector3} = {
        curvePosition(curve, firstTrackOffsetMetres - ACCESS_EXTENSION_METRES, longitudinalOffsetMetres),
    }
    for _, passengerLaneOffsetMetres in ipairs(passengerLaneOffsetsMetres) do
        accessPoints[#accessPoints + 1] = curvePosition(
            curve, passengerLaneOffsetMetres, longitudinalOffsetMetres
        )
    end
    accessPoints[#accessPoints + 1] = curvePosition(
        curve, lastTrackOffsetMetres + ACCESS_EXTENSION_METRES, longitudinalOffsetMetres
    )

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
    length: number
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
    lane: ConstructionUtilSerialized.LaneList,
    centreLaneNodeIndex: integer,
    vehicleNodeIndex: integer,
    passengers: boolean,
    cargo: boolean,
    capacity: integer,
    cargoTransferSpeeds: {ConstructionUtilSerialized.TerminalDef.CargoTransferSpeed},
    transportModes: {ConstructionUtilSerialized.TransportMode}
): ZigzagTerminal
    local personEdges: {IndexPair} = {}
    for edgeIndex = 0, math.floor(#lane.nodes / 2) - 1 do
        personEdges[#personEdges + 1] = { laneListIndex, edgeIndex }
    end
    return {
        tag = tag,
        personEdges = personEdges,
        personNodes = {
            { laneListIndex, centreLaneNodeIndex },
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

local function passengerCapacity(length: number, multiplier: number): integer
    local baseCapacity = math.max(
        math.floor(length * PASSENGER_CAPACITY_PER_METRE + 0.5),
        1
    )
    return math.max(math.floor(baseCapacity * multiplier + 0.5), 1)
end

local function makeStationSubconstruction(
    curve: CurveGeometry,
    tracks: {TrackGeometry},
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
    for trackIndex, track in ipairs(tracks) do
        local zeroBasedTrackIndex = trackIndex - 1
        local trackOffsetMetres = track.offsetMetres
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
                local lane, centreLaneNodeIndex = makeServiceLane(
                    curve,
                    passengerLaneOffsetMetres,
                    "PERSON",
                    PASSENGER_LANE_WIDTH_METRES
                )
                laneLists[#laneLists + 1] = lane
                terminals[#terminals + 1] = makeTerminal(
                    zeroBasedTrackIndex * 2,
                    passengerLaneIndex,
                    lane,
                    centreLaneNodeIndex,
                    track.passengerNodeIndex,
                    true,
                    false,
                    passengerCapacity(track.lengthMetres, passengerCapacityMultiplier),
                    { makeCargoTransferSpeed("PASSENGERS", track.lengthMetres) },
                    transportModes
                )
            else
                laneLists[#laneLists + 1] = makeDisabledLoadingLane(
                    curve,
                    passengerLaneOffsetMetres,
                    "PERSON"
                )
                terminals[#terminals + 1] = makeNonLoadingTerminal(
                    zeroBasedTrackIndex * 2,
                    passengerLaneIndex,
                    track.passengerNodeIndex,
                    true,
                    false,
                    transportModes
                )
            end

            local cargoLaneIndex = #laneLists
            if cargoLoadingEnabled then
                local lane, centreLaneNodeIndex = makeServiceLane(
                    curve,
                    cargoLaneOffsetMetres,
                    "CARGO",
                    CARGO_LANE_WIDTH_METRES
                )
                laneLists[#laneLists + 1] = lane
                terminals[#terminals + 1] = makeTerminal(
                    zeroBasedTrackIndex * 2 + 1,
                    cargoLaneIndex,
                    lane,
                    centreLaneNodeIndex,
                    track.cargoNodeIndex,
                    false,
                    true,
                    0,
                    { makeCargoTransferSpeed("UNIVERSAL", track.lengthMetres) },
                    transportModes
                )
            else
                laneLists[#laneLists + 1] = makeDisabledLoadingLane(
                    curve,
                    cargoLaneOffsetMetres,
                    "CARGO"
                )
                terminals[#terminals + 1] = makeNonLoadingTerminal(
                    zeroBasedTrackIndex * 2 + 1,
                    cargoLaneIndex,
                    track.cargoNodeIndex,
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
                track.centreNodeIndex,
                true,
                true,
                transportModes
            )
        end
    end

    local catchmentAreas: {ZigzagCatchmentArea} = {}
    if loadingEnabled then
        local halfLength = curve.lengthMetres / 2
        local firstTrackOffsetMetres = tracks[1].offsetMetres
        local lastTrackOffsetMetres = tracks[#tracks].offsetMetres
        local accessLaneOffsetsMetres: {number} = { -halfLength, 0, halfLength }
        for _, longitudinalOffsetMetres in ipairs(accessLaneOffsetsMetres) do
            if passengerLoadingEnabled then
                laneLists[#laneLists + 1] = makePassengerAccessLane(
                    curve,
                    firstTrackOffsetMetres,
                    lastTrackOffsetMetres,
                    passengerLaneOffsetsMetres,
                    longitudinalOffsetMetres
                )
            end
            catchmentAreas[#catchmentAreas + 1] = {
                position = curvePosition(curve, 0, longitudinalOffsetMetres),
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
    local curve, validationErrors = makeCurveGeometry(
        captureParams, params, length, trackCount, trackSpacingMetres, trackType
    )
    local layout = makeTrackLayout(curve, trackType, trackCount, trackSpacingMetres)
    local costs = calculateCosts(
        captureParams,
        params,
        length,
        trackCount,
        trackType,
        passengerLoadingEnabled,
        cargoLoadingEnabled
    )
    local result: UpdateResult = {
        edgeLists = {
            layout.edgeList,
        },
        subconstructions = {
            makeStationSubconstruction(
                curve,
                layout.tracks,
                passengerLoadingEnabled,
                cargoLoadingEnabled,
                passengerCapacityMultiplier,
                catchmentRadiusMetres,
                transportModes
            ),
        },
        cost = costs.construction,
        maintenanceCost = costs.maintenance,
    }
    if #validationErrors > 0 then
        -- Builder events display these as normal build errors, without Lua exceptions.
        result.metadata = {} as ConstructionInstanceMetadata
        validationMetadata.set(result.metadata, validationErrors)
    end
    return result
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
        return trackSelection.isRailwayTrack(streetTemplate)
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
        if not trackSelection.isRailwayTrack(streetTemplate) then
            error("Zigzag Station requires a train-capable railway template")
        end
        params.streetTemplate = constructionConfig.streetTemplate
        params.catenary = trackSelection.catenaryIndex(isElectrifiedTrack(streetTemplate))
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
            if not trackSelection.isRailwayTrack(upgradedStreetTemplate)
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
