local function assertEqual(actual, expected, context)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
    end
end

local function pointKey(point)
    return string.format("%.12g,%.12g,%.12g", point[1], point[2], point[3])
end

local function axisAlignedEdge(firstPoint, secondPoint)
    if firstPoint[3] ~= secondPoint[3] then
        return nil
    end
    if firstPoint[1] == secondPoint[1] and firstPoint[2] ~= secondPoint[2] then
        return {
            axis = "y",
            fixedCoordinate = firstPoint[1],
            elevation = firstPoint[3],
            minimum = math.min(firstPoint[2], secondPoint[2]),
            maximum = math.max(firstPoint[2], secondPoint[2]),
        }
    end
    if firstPoint[2] == secondPoint[2] and firstPoint[1] ~= secondPoint[1] then
        return {
            axis = "x",
            fixedCoordinate = firstPoint[2],
            elevation = firstPoint[3],
            minimum = math.min(firstPoint[1], secondPoint[1]),
            maximum = math.max(firstPoint[1], secondPoint[1]),
        }
    end
    return nil
end

local function assertNoOverlappingLaneEdges(laneLists, context)
    local seenEdges = {}
    local axisAlignedEdges = {}
    for laneListIndex, laneList in ipairs(laneLists) do
        assertEqual(#laneList.nodes % 2, 0, context .. " node-pair count")
        for firstNodeIndex = 1, #laneList.nodes, 2 do
            local firstPoint = laneList.nodes[firstNodeIndex][1]
            local secondPoint = laneList.nodes[firstNodeIndex + 1][1]
            local firstKey = pointKey(firstPoint)
            local secondKey = pointKey(secondPoint)
            if secondKey < firstKey then
                firstKey, secondKey = secondKey, firstKey
            end
            local edgeKey = firstKey .. ":" .. secondKey
            if seenEdges[edgeKey] ~= nil then
                error(
                    string.format(
                        "%s: lane %d edge %d duplicates %s",
                        context,
                        laneListIndex,
                        (firstNodeIndex + 1) / 2,
                        seenEdges[edgeKey]
                    )
                )
            end
            local edgeDescription = string.format(
                "lane %d edge %d",
                laneListIndex,
                (firstNodeIndex + 1) / 2
            )
            seenEdges[edgeKey] = edgeDescription

            local currentEdge = axisAlignedEdge(firstPoint, secondPoint)
            if currentEdge ~= nil then
                for _, previousEdge in ipairs(axisAlignedEdges) do
                    local overlap = math.min(currentEdge.maximum, previousEdge.maximum)
                        - math.max(currentEdge.minimum, previousEdge.minimum)
                    if currentEdge.axis == previousEdge.axis
                        and currentEdge.fixedCoordinate == previousEdge.fixedCoordinate
                        and currentEdge.elevation == previousEdge.elevation
                        and overlap > 0 then
                        error(string.format(
                            "%s: %s overlaps %s",
                            context,
                            edgeDescription,
                            previousEdge.description
                        ))
                    end
                end
                currentEdge.description = edgeDescription
                axisAlignedEdges[#axisAlignedEdges + 1] = currentEdge
            end
        end
    end
end

local function readTgaSize(path)
    local file = assert(io.open(path, "rb"))
    assert(file:seek("set", 12))
    local sizeBytes = assert(file:read(4))
    file:close()
    local widthLow, widthHigh, heightLow, heightHigh = sizeBytes:byte(1, 4)
    return widthLow + widthHigh * 256, heightLow + heightHigh * 256
end

local trackTypes = {
    plain = {
        "simple.track",
        "standard.track",
        "high_speed.track",
    },
    catenary = {
        "simple_catenary.track",
        "standard_catenary.track",
        "high_speed_catenary.track",
    },
}

local paramUtil = {
    makeTrackTypeDefaultParam = function()
        return { key = "trackType", defaultIndex = 1 }
    end,
    makeTrackTypeHighSpeedParam = function()
        return { key = "trackType", defaultIndex = 1 }
    end,
    makeTrackCatenaryParam = function()
        return { key = "catenary" }
    end,
    getRailTrackTypes = function(withCatenary)
        return withCatenary and trackTypes.catenary or trackTypes.plain
    end,
}

package.preload["::/scripts/construction/param_util.tl"] = function()
    return paramUtil
end
package.preload["::/scripts/mat4.tl"] = function()
    return {
        transl = function(position)
            return {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                position.x, position.y, position.z, 1,
            }
        end,
    }
end
package.preload["::/scripts/vec3.tl"] = function()
    return {
        new = function(x, y, z)
            return { x = x, y = y, z = z }
        end,
    }
end
package.preload["::/scripts/construction/laneutil.lua"] = function()
    return {
        createLane = function(curves, transportModes, speedLimit, width, linkable)
            local nodes = {}
            for _, curve in ipairs(curves) do
                local firstPoint = assert(curve[1], "lane curve has no first point")
                local lastPoint = assert(curve[#curve], "lane curve has no last point")
                local tangent = {
                    lastPoint[1] - firstPoint[1],
                    lastPoint[2] - firstPoint[2],
                    lastPoint[3] - firstPoint[3],
                }
                nodes[#nodes + 1] = { firstPoint, tangent, width }
                nodes[#nodes + 1] = { lastPoint, tangent, width }
            end
            return {
                nodes = nodes,
                transportModes = transportModes,
                speedLimit = speedLimit,
                linkable = linkable,
            }
        end,
    }
end

package.preload["apasz_zigzag::/zigzag/logging_config.lua"] = function()
    return false
end
package.preload["apasz_zigzag::/zigzag/logging.lua"] = function()
    return assert(loadfile("content/zigzag/logging.lua"))()
end

_G.ug_require = function(resourceName)
    return require(resourceName)
end

_G._ = function(value)
    return value
end

local TRAIN_MODE = "TRAIN"
local ELECTRIC_TRAIN_MODE = "ELECTRIC_TRAIN"

local function makeTrackTemplate(electrified, catenaryAdd, catenaryRemove)
    local transportModes = {
        [TRAIN_MODE] = true,
    }
    if electrified then
        transportModes[ELECTRIC_TRAIN_MODE] = true
    end
    return {
        roadType = 0,
        laneConfigs = {
            {
                transportModes = transportModes,
            },
        },
        catenaryAdd = catenaryAdd,
        catenaryRemove = catenaryRemove,
    }
end

local templates = {
    ["standard.track"] = makeTrackTemplate(false, "standard_catenary.track", nil),
    ["standard_catenary.track"] = makeTrackTemplate(true, nil, "standard.track"),
    ["high_speed.track"] = makeTrackTemplate(false, "high_speed_catenary.track", nil),
    ["high_speed_catenary.track"] = makeTrackTemplate(true, nil, "high_speed.track"),
    ["custom.track"] = makeTrackTemplate(false, "custom_catenary.track", nil),
    ["custom_catenary.track"] = makeTrackTemplate(true, nil, "custom.track"),
    ["third_rail.track"] = makeTrackTemplate(true, nil, nil),
    ["unpowered_unpaired.track"] = makeTrackTemplate(false, nil, nil),
    ["broken_catenary_pair.track"] = makeTrackTemplate(false, "road.street", nil),
    ["road.street"] = {
        roadType = 1,
        laneConfigs = {},
    },
}

local gameApi = {
    type = {
        ["enum"] = {
            RoadType = {
                TRACK = 0,
            },
            TransportMode = {
                TRAIN = TRAIN_MODE,
                ELECTRIC_TRAIN = ELECTRIC_TRAIN_MODE,
            },
        },
    },
    res = {
        streetTemplateRep = {
            find = function(resourceName)
                return resourceName
            end,
            get = function(resourceName)
                return assert(templates[resourceName], "unknown template " .. tostring(resourceName))
            end,
            findAndGet = function(resourceName)
                return assert(templates[resourceName], "unknown template " .. tostring(resourceName))
            end,
        },
    },
}

local function loadData(path)
    _G.data = nil
    assert(loadfile(path))()
    assert(type(_G.data) == "function", path .. " did not define data()")
    return _G.data()
end

_G.api = nil
local construction = loadData("content/stations/rail/zigzag/zigzag.con.lua")
local expectedLengthsMetres = {
    5, 10, 20, 40, 80, 120, 160, 200, 240, 280, 320, 360, 400, 440,
}
local expectedLegacyLengthsMetres = { 10, 40, 80, 120, 160, 240, 320 }
local expectedTrackCounts = { 1, 2, 3, 4, 5, 6, 7, 8 }
local expectedTrackSpacingsMetres = {
    3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
}
local expectedCatchmentRadiiMetres = {
    50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300,
}
local expectedPassengerCapacityMultipliers = {
    0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
}
local expectedTrackSpacingMetres = 5
local nodesPerTrack = 4
assertEqual(
    construction.namePrefix,
    "apasz_zigzag_name_prefix",
    "construction name localization key"
)
assertEqual(
    construction.description.name,
    "apasz_zigzag_name",
    "construction description name localization key"
)
assertEqual(
    construction.description.description,
    "apasz_zigzag_description",
    "construction description localization key"
)
assertEqual(#construction.constructionTemplates, 1, "template count")
assertEqual(
    construction.constructionTemplates[1].configureHudIconsScript.params.cargo,
    true,
    "cargo placement HUD icons"
)
assertEqual(construction.constructionTemplates[1].description.icon, "zigzag.tga", "menu icon")
assertEqual(
    construction.constructionTemplates[1].description.previewIcon,
    "zigzag_preview.tga",
    "menu preview icon"
)
assertEqual(#construction.constructionTemplates[1].data.params, 0, "template-specific parameter count")
assertEqual(#construction.params[1].values, #expectedTrackCounts, "track-count option count")
assertEqual(construction.params[1].name, "apasz_zigzag_tracks", "tracks localization key")
assertEqual(construction.params[1].defaultIndex, 1, "default one-track index")
assertEqual(construction.params[1].displayMode, "Horizontal", "track-count display mode")
for index, trackCount in ipairs(expectedTrackCounts) do
    assertEqual(
        construction.params[1].values[index],
        tostring(trackCount),
        "track-count label " .. tostring(index)
    )
end
local trackSpacingParam = construction.params[2]
assertEqual(trackSpacingParam.key, "trackSpacingMetres", "track-spacing parameter key")
assertEqual(trackSpacingParam.name, "apasz_zigzag_track_spacing", "track-spacing localization key")
assertEqual(trackSpacingParam.uiType, "Slider", "track-spacing UI type")
assertEqual(trackSpacingParam.defaultIndex, 3, "default 5-metre track-spacing index")
assertEqual(#trackSpacingParam.numbers, #expectedTrackSpacingsMetres, "track-spacing option count")
for index, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
    assertEqual(
        trackSpacingParam.numbers[index],
        trackSpacingMetres,
        "track-spacing value " .. tostring(index)
    )
    assertEqual(
        trackSpacingParam.values[index],
        tostring(trackSpacingMetres) .. " m",
        "track-spacing label " .. tostring(index)
    )
end
local lengthParam = construction.params[3]
assertEqual(lengthParam.key, "lengthMetres", "length parameter key")
assertEqual(lengthParam.name, "apasz_zigzag_length", "length localization key")
assertEqual(lengthParam.uiType, "Slider", "length UI type")
assertEqual(lengthParam.defaultIndex, 2, "default 10-metre length index")
assertEqual(#lengthParam.numbers, #expectedLengthsMetres, "length option count")
for index, lengthMetres in ipairs(expectedLengthsMetres) do
    assertEqual(
        lengthParam.numbers[index],
        lengthMetres,
        "length value " .. tostring(index)
    )
    assertEqual(
        lengthParam.values[index],
        tostring(lengthMetres) .. " m",
        "length label " .. tostring(index)
    )
end
assertEqual(construction.params[4].key, "trackType", "default track selector order")
assertEqual(construction.params[4].defaultIndex, 2, "default-era standard track")
assertEqual(construction.params[5].key, "trackType", "high-speed track selector order")
assertEqual(construction.params[5].defaultIndex, 2, "high-speed-era standard track")
assertEqual(construction.params[6].key, "catenary", "catenary selector order")

local passengerLoadingParam = construction.params[7]
assertEqual(
    passengerLoadingParam.key,
    "passengerLoadingEnabled",
    "passenger-loading parameter key"
)
assertEqual(
    passengerLoadingParam.name,
    "apasz_zigzag_passenger_loading_enabled",
    "passenger-loading localization key"
)
assertEqual(passengerLoadingParam.uiType, "CheckBox", "passenger-loading UI type")
assertEqual(passengerLoadingParam.defaultIndex, 1, "passenger loading disabled by default")
assertEqual(passengerLoadingParam.values[1], "apasz_zigzag_off", "passenger loading disabled label")
assertEqual(passengerLoadingParam.values[2], "apasz_zigzag_on", "passenger loading enabled label")

local passengerCapacityParam = construction.params[8]
assertEqual(
    passengerCapacityParam.key,
    "passengerCapacityMultiplier",
    "passenger-capacity parameter key"
)
assertEqual(
    passengerCapacityParam.name,
    "apasz_zigzag_passenger_capacity",
    "passenger-capacity localization key"
)
assertEqual(passengerCapacityParam.uiType, "Slider", "passenger-capacity UI type")
assertEqual(passengerCapacityParam.defaultIndex, 3, "default passenger-capacity index")
for index, multiplier in ipairs(expectedPassengerCapacityMultipliers) do
    assertEqual(
        passengerCapacityParam.numbers[index],
        multiplier,
        "passenger-capacity multiplier " .. tostring(index)
    )
    assertEqual(
        passengerCapacityParam.values[index],
        string.format("%g×", multiplier),
        "passenger-capacity label " .. tostring(index)
    )
end

local cargoLoadingParam = construction.params[9]
assertEqual(cargoLoadingParam.key, "cargoLoadingEnabled", "cargo-loading parameter key")
assertEqual(
    cargoLoadingParam.name,
    "apasz_zigzag_cargo_loading_enabled",
    "cargo-loading localization key"
)
assertEqual(cargoLoadingParam.uiType, "CheckBox", "cargo-loading UI type")
assertEqual(cargoLoadingParam.defaultIndex, 1, "cargo loading disabled by default")
assertEqual(cargoLoadingParam.values[1], "apasz_zigzag_off", "cargo loading disabled label")
assertEqual(cargoLoadingParam.values[2], "apasz_zigzag_on", "cargo loading enabled label")

local catchmentRadiusParam = construction.params[10]
assertEqual(catchmentRadiusParam.key, "catchmentRadiusMetres", "catchment parameter key")
assertEqual(
    catchmentRadiusParam.name,
    "apasz_zigzag_catchment_radius",
    "catchment localization key"
)
assertEqual(catchmentRadiusParam.uiType, "Slider", "catchment UI type")
assertEqual(catchmentRadiusParam.defaultIndex, 5, "default 150-metre catchment index")
for index, radiusMetres in ipairs(expectedCatchmentRadiiMetres) do
    assertEqual(catchmentRadiusParam.numbers[index], radiusMetres, "catchment radius " .. index)
    assertEqual(
        catchmentRadiusParam.values[index],
        tostring(radiusMetres) .. " m",
        "catchment label " .. index
    )
end

assertEqual(
    passengerCapacityParam.checkEnabledScript.fileName,
    "zigzag.params.gui@checkLoadingVisibility",
    "passenger-capacity visibility callback"
)
assertEqual(
    catchmentRadiusParam.checkEnabledScript.fileName,
    "zigzag.params.gui@checkLoadingVisibility",
    "catchment visibility callback"
)

local visibilityScript = loadData("content/stations/rail/zigzag/zigzag.params.gui.lua")
local function checkVisibility(parameter, params)
    return visibilityScript.checkLoadingVisibility(parameter.checkEnabledScript.params, params)
end

assertEqual(checkVisibility(passengerCapacityParam, {}), "InputActionOnly", "capacity hidden by default")
assertEqual(
    checkVisibility(passengerCapacityParam, {
        passengerLoadingEnabled = 1,
        cargoLoadingEnabled = 2,
    }),
    "InputActionOnly",
    "capacity hidden when only cargo loading is enabled"
)
assertEqual(
    checkVisibility(passengerCapacityParam, { passengerLoadingEnabled = 2 }),
    "Enabled",
    "capacity visible with passenger loading enabled"
)
assertEqual(checkVisibility(catchmentRadiusParam, {}), "InputActionOnly", "catchment hidden by default")
assertEqual(
    checkVisibility(catchmentRadiusParam, {
        passengerLoadingEnabled = 2,
        cargoLoadingEnabled = 1,
    }),
    "Enabled",
    "catchment visible with passenger loading enabled"
)
assertEqual(
    checkVisibility(catchmentRadiusParam, {
        passengerLoadingEnabled = 1,
        cargoLoadingEnabled = 2,
    }),
    "Enabled",
    "catchment visible with cargo loading enabled"
)
assertEqual(
    checkVisibility(catchmentRadiusParam, {
        passengerLoadingEnabled = 2,
        cargoLoadingEnabled = 2,
    }),
    "Enabled",
    "catchment visible with both loading modes enabled"
)
assertEqual(
    checkVisibility(catchmentRadiusParam, {
        passengerLoadingEnabled = 1,
        cargoLoadingEnabled = 1,
    }),
    "InputActionOnly",
    "catchment hidden with both loading modes disabled"
)

local templateAttributes = construction.constructionTemplates[1].description.attributes
assertEqual(templateAttributes.cost[1], 5 * 750, "minimum displayed cost")
assertEqual(templateAttributes.cost[2], 440 * 8 * 750, "maximum displayed cost")
assertEqual(templateAttributes.maintenanceCost[1], 5 * 12.5, "minimum displayed maintenance")
assertEqual(
    templateAttributes.maintenanceCost[2],
    440 * 8 * 12.5,
    "maximum displayed maintenance"
)

local iconWidth, iconHeight = readTgaSize(
    "content/stations/rail/zigzag/zigzag@2x.tga"
)
assertEqual(iconWidth, 240, "menu icon width")
assertEqual(iconHeight, 184, "menu icon height")
local previewWidth, previewHeight = readTgaSize(
    "content/stations/rail/zigzag/zigzag_preview@2x.tga"
)
assertEqual(previewWidth, 720, "preview icon width")
assertEqual(previewHeight, 405, "preview icon height")

_G.api = gameApi
local script = loadData("content/stations/rail/zigzag/zigzag.script.lua")
assertEqual(type(script.createTemplateFn), "function", "template callback")
assertEqual(next(script.createTemplateFn({}, {})), nil, "empty initial module set")
local captureParams = construction.updateScript.params
assertEqual(captureParams.defaultLengthMetres, 10, "captured default length")
for index, lengthMetres in ipairs(expectedLegacyLengthsMetres) do
    assertEqual(
        captureParams.legacyLengthsMetres[index],
        lengthMetres,
        "captured legacy length " .. tostring(index)
    )
end
assertEqual(captureParams.defaultTrackSpacingIndex, 3, "captured default track-spacing index")
assertEqual(captureParams.defaultCatchmentRadiusMetres, 150, "captured default catchment radius")
assertEqual(
    captureParams.defaultPassengerCapacityMultiplier,
    1,
    "captured default passenger-capacity multiplier"
)
assertEqual(captureParams.loadingDisabledIndex, 1, "captured loading-disabled index")
assertEqual(captureParams.loadingEnabledIndex, 2, "captured loading-enabled index")
for index, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
    assertEqual(
        captureParams.trackSpacingsMetres[index],
        trackSpacingMetres,
        "captured track-spacing value " .. tostring(index)
    )
end
for index, radiusMetres in ipairs(expectedCatchmentRadiiMetres) do
    assertEqual(
        captureParams.catchmentRadiiMetres[index],
        radiusMetres,
        "captured catchment radius " .. tostring(index)
    )
end
for index, multiplier in ipairs(expectedPassengerCapacityMultipliers) do
    assertEqual(
        captureParams.passengerCapacityMultipliers[index],
        multiplier,
        "captured passenger-capacity multiplier " .. tostring(index)
    )
end

local function runRestrictedUpdateWithCapture(updateCaptureParams, params)
    local resourceApi = _G.api.res
    _G.api.res = nil
    local ok, resultOrError = pcall(script.updateFn, updateCaptureParams, params)
    _G.api.res = resourceApi
    assert(ok, resultOrError)
    return resultOrError
end

local function runRestrictedUpdate(params)
    return runRestrictedUpdateWithCapture(captureParams, params)
end

local function assertLengthResult(params, lengthMetres, context)
    local lengthResult = runRestrictedUpdate(params)
    local lengthTrack = lengthResult.edgeLists[1]
    local halfLength = lengthMetres / 2
    assertEqual(
        lengthTrack.edges[1][1][2],
        -halfLength,
        "negative endpoint for " .. context
    )
    assertEqual(
        lengthTrack.edges[4][1][2],
        halfLength,
        "positive endpoint for " .. context
    )
    assertEqual(
        lengthResult.cost,
        lengthMetres * captureParams.costPerMetre,
        "cost for " .. context
    )
    assertEqual(
        lengthResult.maintenanceCost,
        lengthMetres * captureParams.maintenanceCostPerMetre,
        "maintenance cost for " .. context
    )
end

for _, lengthMetres in ipairs(expectedLengthsMetres) do
    assertLengthResult(
        { lengthMetres = lengthMetres },
        lengthMetres,
        "slider length " .. tostring(lengthMetres)
    )
end

for lengthIndex, lengthMetres in ipairs(expectedLegacyLengthsMetres) do
    assertLengthResult(
        { length = lengthIndex },
        lengthMetres,
        "legacy length index " .. tostring(lengthIndex)
    )
end

assertLengthResult(
    { length = #expectedLegacyLengthsMetres, lengthMetres = 20 },
    20,
    "slider value overriding legacy length"
)

for trackCountIndex, trackCount in ipairs(expectedTrackCounts) do
    local trackCountResult = runRestrictedUpdate({ tracks = trackCountIndex })
    local trackCountEdgeList = trackCountResult.edgeLists[1]
    local trackCountStation = trackCountResult.subconstructions[1]
    assertEqual(
        #trackCountEdgeList.edges,
        trackCount * nodesPerTrack,
        "node count for track count " .. trackCount
    )
    assertEqual(#trackCountEdgeList.snapNodes, trackCount * 2, "snap count for track count " .. trackCount)
    assertEqual(#trackCountStation.laneLists, trackCount, "lane count for track count " .. trackCount)
    assertEqual(
        #trackCountStation.station.terminals,
        trackCount,
        "terminal count for track count " .. trackCount
    )
    assertEqual(
        trackCountResult.cost,
        10 * trackCount * captureParams.costPerMetre,
        "cost for track count " .. trackCount
    )
    assertEqual(
        trackCountResult.maintenanceCost,
        10 * trackCount * captureParams.maintenanceCostPerMetre,
        "maintenance cost for track count " .. trackCount
    )

    for trackIndex = 1, trackCount do
        local zeroBasedTrackIndex = trackIndex - 1
        local firstNodeIndex = zeroBasedTrackIndex * nodesPerTrack
        local trackOffset = (trackIndex - (trackCount + 1) / 2) * expectedTrackSpacingMetres
        for nodeOffset = 1, nodesPerTrack do
            assertEqual(
                trackCountEdgeList.edges[firstNodeIndex + nodeOffset][1][1],
                trackOffset,
                "track offset for track " .. trackIndex .. " of " .. trackCount
            )
        end
        assertEqual(
            trackCountEdgeList.snapNodes[zeroBasedTrackIndex * 2 + 1],
            firstNodeIndex,
            "negative snap node for track " .. trackIndex .. " of " .. trackCount
        )
        assertEqual(
            trackCountEdgeList.snapNodes[zeroBasedTrackIndex * 2 + 2],
            firstNodeIndex + 3,
            "positive snap node for track " .. trackIndex .. " of " .. trackCount
        )

        local lane = trackCountStation.laneLists[trackIndex]
        assertEqual(lane.nodes[1][1][1], trackOffset - 0.5, "lane start for track " .. trackIndex)
        assertEqual(lane.nodes[2][1][1], trackOffset + 0.5, "lane end for track " .. trackIndex)
        assertEqual(lane.linkable, false, "lane linkage for track " .. trackIndex)

        local trackTerminal = trackCountStation.station.terminals[trackIndex]
        assertEqual(trackTerminal.tag, zeroBasedTrackIndex, "terminal tag for track " .. trackIndex)
        assertEqual(
            trackTerminal.personEdges[1][1],
            zeroBasedTrackIndex,
            "terminal lane index for track " .. trackIndex
        )
        assertEqual(
            trackTerminal.personNodes[1][1],
            zeroBasedTrackIndex,
            "terminal person-node lane index for track " .. trackIndex
        )
        assertEqual(
            trackTerminal.vehicleNode[1],
            -1,
            "terminal construction edge-list marker for track " .. trackIndex
        )
        assertEqual(
            trackTerminal.vehicleNode[2],
            firstNodeIndex + 1,
            "terminal centre node for track " .. trackIndex
        )
    end
end

for _, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
    local spacingResult = runRestrictedUpdate({
        tracks = 2,
        trackSpacingMetres = trackSpacingMetres,
    })
    local spacingTrack = spacingResult.edgeLists[1]
    local spacingStation = spacingResult.subconstructions[1]
    assertEqual(
        spacingTrack.edges[1][1][1],
        -trackSpacingMetres / 2,
        "first track offset at " .. trackSpacingMetres .. " metres"
    )
    assertEqual(
        spacingTrack.edges[nodesPerTrack + 1][1][1],
        trackSpacingMetres / 2,
        "second track offset at " .. trackSpacingMetres .. " metres"
    )
    assertEqual(
        spacingStation.laneLists[1].nodes[1][1][1],
        -trackSpacingMetres / 2 - 0.5,
        "first validation-lane offset at " .. trackSpacingMetres .. " metres"
    )
    assertEqual(
        spacingStation.laneLists[2].nodes[2][1][1],
        trackSpacingMetres / 2 + 0.5,
        "second validation-lane offset at " .. trackSpacingMetres .. " metres"
    )
end

local legacySpacingResult = runRestrictedUpdate({ tracks = 2 })
assertEqual(
    legacySpacingResult.edgeLists[1].edges[1][1][1],
    -expectedTrackSpacingMetres / 2,
    "missing track-spacing parameter uses the 5-metre default"
)

local result = runRestrictedUpdate({})

assertEqual(#result.edgeLists, 1, "track edge-list count")
local track = result.edgeLists[1]
assertEqual(track.type, "TRACK", "edge-list type")
assertEqual(track.params.type, "standard.track", "selected track type")
assertEqual(#track.edges, nodesPerTrack, "track node count")
assertEqual(track.edges[1][1][2], -5, "negative endpoint")
assertEqual(track.edges[1][2][2], 5, "negative endpoint tangent")
assertEqual(track.edges[2][1][2], 0, "negative half centre node")
assertEqual(track.edges[2][2][2], 5, "negative half tangent")
assertEqual(track.edges[3][1][2], 0, "positive half centre node")
assertEqual(track.edges[3][2][2], 5, "positive half tangent")
assertEqual(track.edges[4][1][2], 5, "positive endpoint")
assertEqual(track.edges[4][2][2], 5, "positive endpoint outward tangent")
assertEqual(track.snapNodes[1], 0, "negative snap node")
assertEqual(track.snapNodes[2], 3, "second snap node")

local stationSubconstruction = result.subconstructions[1]
assertEqual(#stationSubconstruction.laneLists, 1, "non-loading lane count")
local nonLoadingLane = stationSubconstruction.laneLists[1]
assertEqual(#nonLoadingLane.transportModes, 1, "non-loading lane mode count")
assertEqual(nonLoadingLane.transportModes[1], "PERSON", "non-loading lane mode")
assertEqual(nonLoadingLane.linkable, false, "non-loading lane linkage")

local station = stationSubconstruction.station
assertEqual(#station.terminals, 1, "terminal count")
local terminal = station.terminals[1]
assertEqual(#terminal.personEdges, 1, "terminal person edge count")
assertEqual(terminal.personEdges[1][1], 0, "terminal person lane index")
assertEqual(terminal.personEdges[1][2], 0, "terminal person edge index")
assertEqual(#terminal.personNodes, 1, "terminal person node count")
assertEqual(terminal.vehicleNode[1], -1, "terminal construction edge-list marker")
assertEqual(terminal.vehicleNode[2], 1, "terminal centre node")
assertEqual(terminal.passengers, true, "passenger-line compatibility")
assertEqual(terminal.cargo, true, "cargo-line compatibility")
assertEqual(terminal.capacity, 0, "terminal capacity")
assertEqual(#terminal.cargoTransferSpeeds, 0, "cargo transfer-speed count")
assertEqual(#terminal.transportModes, 1, "non-electrified terminal mode count")
assertEqual(terminal.transportModes[1], "TRAIN", "non-electrified terminal mode")
assertEqual(#station.catchmentAreas, 0, "catchment area count")
assertEqual(#station.pool.edges, 0, "station pool edge count")
assertEqual(station.pool.capacity, 0, "station pool capacity")
assertEqual(result.snapPoint, nil, "edge nodes are the only placement snap source")
assertEqual(result.cost, 7500, "construction cost")
assertEqual(result.maintenanceCost, 125, "maintenance cost")

local loadingResult = runRestrictedUpdate({
    tracks = 2,
    trackSpacingMetres = 6,
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    passengerCapacityMultiplier = 1.5,
    cargoLoadingEnabled = 2,
    catchmentRadiusMetres = 200,
})
local loadingSubconstruction = loadingResult.subconstructions[1]
local loadingStation = loadingSubconstruction.station
assertEqual(#loadingSubconstruction.laneLists, 7, "loading-mode lane count")
assertEqual(#loadingStation.terminals, 4, "loading-mode terminal count")
assertEqual(#loadingStation.catchmentAreas, 3, "loading-mode catchment count")
assertEqual(loadingStation.pool.capacity, 0, "loading-mode station pool capacity")

for trackIndex = 1, 2 do
    local zeroBasedTrackIndex = trackIndex - 1
    local passengerLaneIndex = zeroBasedTrackIndex * 2
    local cargoLaneIndex = passengerLaneIndex + 1
    local expectedTrackOffset = trackIndex == 1 and -3 or 3
    local expectedVehicleNode = zeroBasedTrackIndex * nodesPerTrack + 1

    local passengerLane = loadingSubconstruction.laneLists[passengerLaneIndex + 1]
    assertEqual(#passengerLane.nodes, 4, "passenger lane node count for track " .. trackIndex)
    assertEqual(passengerLane.transportModes[1], "PERSON", "passenger lane mode")
    assertEqual(passengerLane.nodes[1][1][1], expectedTrackOffset - 0.5, "passenger lane x position")
    assertEqual(passengerLane.nodes[1][1][2], -20, "passenger lane start")
    assertEqual(passengerLane.nodes[4][1][2], 20, "passenger lane end")
    assertEqual(passengerLane.nodes[1][3], 2.4, "passenger lane width")

    local passengerTerminal = loadingStation.terminals[passengerLaneIndex + 1]
    assertEqual(passengerTerminal.tag, passengerLaneIndex, "passenger terminal tag")
    assertEqual(passengerTerminal.passengers, true, "passenger terminal passenger support")
    assertEqual(passengerTerminal.cargo, false, "passenger terminal cargo support")
    assertEqual(passengerTerminal.capacity, 102, "passenger terminal capacity")
    assertEqual(#passengerTerminal.personEdges, 2, "passenger terminal edge count")
    assertEqual(passengerTerminal.personEdges[1][1], passengerLaneIndex, "passenger terminal lane")
    assertEqual(passengerTerminal.personEdges[1][2], 0, "passenger terminal first edge")
    assertEqual(passengerTerminal.personEdges[2][2], 1, "passenger terminal second edge")
    assertEqual(passengerTerminal.vehicleNode[2], expectedVehicleNode, "passenger vehicle node")
    assertEqual(#passengerTerminal.cargoTransferSpeeds, 1, "passenger transfer-speed count")
    local passengerTransfer = passengerTerminal.cargoTransferSpeeds[1]
    assertEqual(passengerTransfer.cargoTypeSet.cargoClassesIncluded[1], "PASSENGERS", "passenger cargo class")
    assertEqual(passengerTransfer.loadSpeedModifier, 1, "passenger load-speed modifier")
    assertEqual(passengerTransfer.length, 40, "passenger transfer length")

    local cargoLane = loadingSubconstruction.laneLists[cargoLaneIndex + 1]
    assertEqual(#cargoLane.nodes, 4, "cargo lane node count for track " .. trackIndex)
    assertEqual(cargoLane.transportModes[1], "CARGO", "cargo lane mode")
    assertEqual(cargoLane.nodes[1][1][1], expectedTrackOffset + 0.5, "cargo lane x position")
    assertEqual(cargoLane.nodes[1][3], 4, "cargo lane width")

    local cargoTerminal = loadingStation.terminals[cargoLaneIndex + 1]
    assertEqual(cargoTerminal.tag, cargoLaneIndex, "cargo terminal tag")
    assertEqual(cargoTerminal.passengers, false, "cargo terminal passenger support")
    assertEqual(cargoTerminal.cargo, true, "cargo terminal cargo support")
    assertEqual(cargoTerminal.capacity, 0, "cargo terminal capacity")
    assertEqual(cargoTerminal.personEdges[1][1], cargoLaneIndex, "cargo terminal lane")
    assertEqual(cargoTerminal.vehicleNode[2], expectedVehicleNode, "cargo vehicle node")
    assertEqual(#cargoTerminal.cargoTransferSpeeds, 1, "cargo transfer-speed count")
    local cargoTransfer = cargoTerminal.cargoTransferSpeeds[1]
    assertEqual(cargoTransfer.cargoTypeSet.cargoClassesIncluded[1], "UNIVERSAL", "cargo class")
    assertEqual(cargoTransfer.loadSpeedModifier, 1, "cargo load-speed modifier")
    assertEqual(cargoTransfer.length, 40, "cargo transfer length")
end

for accessLaneIndex, expectedLongitudinalOffset in ipairs({ -20, 0, 20 }) do
    local accessLane = loadingSubconstruction.laneLists[accessLaneIndex + 4]
    local catchmentArea = loadingStation.catchmentAreas[accessLaneIndex]
    assertEqual(accessLane.transportModes[1], "PERSON", "access lane mode")
    assertEqual(accessLane.linkable, true, "access lane linkage")
    assertEqual(#accessLane.nodes, 6, "access lane node count")
    assertEqual(accessLane.nodes[1][1][1], -13, "left access endpoint")
    assertEqual(accessLane.nodes[6][1][1], 13, "right access endpoint")
    assertEqual(
        accessLane.nodes[1][1][2],
        expectedLongitudinalOffset,
        "access lane longitudinal offset"
    )
    assertEqual(catchmentArea.position[1], 0, "catchment x position")
    assertEqual(catchmentArea.position[2], expectedLongitudinalOffset, "catchment y position")
    assertEqual(catchmentArea.radius, 200, "catchment radius")
end
assertNoOverlappingLaneEdges(loadingSubconstruction.laneLists, "loading-mode lanes")

local passengerOnlyResult = runRestrictedUpdate({
    tracks = 2,
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    cargoLoadingEnabled = 1,
})
local passengerOnlySubconstruction = passengerOnlyResult.subconstructions[1]
local passengerOnlyStation = passengerOnlySubconstruction.station
assertEqual(#passengerOnlySubconstruction.laneLists, 7, "passenger-only lane count")
assertEqual(#passengerOnlyStation.terminals, 4, "passenger-only terminal count")
assertEqual(#passengerOnlyStation.catchmentAreas, 3, "passenger-only catchment count")
for trackIndex = 1, 2 do
    local passengerTerminal = passengerOnlyStation.terminals[(trackIndex - 1) * 2 + 1]
    local nonLoadingCargoTerminal = passengerOnlyStation.terminals[(trackIndex - 1) * 2 + 2]
    assertEqual(passengerTerminal.tag, (trackIndex - 1) * 2, "passenger-only terminal tag")
    assertEqual(passengerTerminal.passengers, true, "passenger-only passenger support")
    assertEqual(passengerTerminal.cargo, false, "passenger-only cargo support")
    assertEqual(passengerTerminal.capacity, 68, "default passenger capacity")
    assertEqual(nonLoadingCargoTerminal.passengers, false, "disabled passenger support")
    assertEqual(nonLoadingCargoTerminal.cargo, true, "cargo reversing compatibility")
    assertEqual(#nonLoadingCargoTerminal.cargoTransferSpeeds, 0, "disabled cargo transfer")
end
assertNoOverlappingLaneEdges(passengerOnlySubconstruction.laneLists, "passenger-only lanes")

local cargoOnlyResult = runRestrictedUpdate({
    tracks = 2,
    lengthMetres = 40,
    passengerLoadingEnabled = 1,
    cargoLoadingEnabled = 2,
})
local cargoOnlySubconstruction = cargoOnlyResult.subconstructions[1]
local cargoOnlyStation = cargoOnlySubconstruction.station
assertEqual(#cargoOnlySubconstruction.laneLists, 4, "cargo-only lane count")
assertEqual(#cargoOnlyStation.terminals, 4, "cargo-only terminal count")
assertEqual(#cargoOnlyStation.catchmentAreas, 3, "cargo-only catchment count")
for trackIndex = 1, 2 do
    local nonLoadingPassengerTerminal = cargoOnlyStation.terminals[(trackIndex - 1) * 2 + 1]
    local cargoTerminal = cargoOnlyStation.terminals[(trackIndex - 1) * 2 + 2]
    assertEqual(nonLoadingPassengerTerminal.passengers, true, "passenger reversing compatibility")
    assertEqual(nonLoadingPassengerTerminal.cargo, false, "disabled cargo support")
    assertEqual(nonLoadingPassengerTerminal.capacity, 0, "disabled passenger capacity")
    assertEqual(#nonLoadingPassengerTerminal.cargoTransferSpeeds, 0, "disabled passenger transfer")
    assertEqual(cargoTerminal.tag, (trackIndex - 1) * 2 + 1, "cargo-only terminal tag")
    assertEqual(cargoTerminal.passengers, false, "cargo-only passenger support")
    assertEqual(cargoTerminal.cargo, true, "cargo-only cargo support")
    assertEqual(cargoTerminal.capacity, 0, "cargo-only terminal capacity")
end
assertNoOverlappingLaneEdges(cargoOnlySubconstruction.laneLists, "cargo-only lanes")

local legacyLoadingResult = runRestrictedUpdate({
    tracks = 2,
    lengthMetres = 40,
    loadingEnabled = 2,
})
local legacyLoadingSubconstruction = legacyLoadingResult.subconstructions[1]
assertEqual(#legacyLoadingSubconstruction.laneLists, 7, "legacy loading lane count")
assertEqual(#legacyLoadingSubconstruction.station.terminals, 4, "legacy loading terminal count")
assertEqual(
    legacyLoadingSubconstruction.station.terminals[1].capacity,
    68,
    "legacy loading default passenger capacity"
)
assertEqual(
    legacyLoadingSubconstruction.station.catchmentAreas[1].radius,
    150,
    "legacy loading default catchment radius"
)

local migratedCargoOnlyResult = runRestrictedUpdate({
    tracks = 2,
    lengthMetres = 40,
    loadingEnabled = 2,
    passengerLoadingEnabled = 1,
    cargoLoadingEnabled = 2,
})
assertEqual(
    #migratedCargoOnlyResult.subconstructions[1].laneLists,
    4,
    "new loading toggles override the legacy setting"
)

for _, multiplier in ipairs(expectedPassengerCapacityMultipliers) do
    local multiplierResult = runRestrictedUpdate({
        lengthMetres = 40,
        passengerLoadingEnabled = 2,
        passengerCapacityMultiplier = multiplier,
    })
    assertEqual(
        multiplierResult.subconstructions[1].station.terminals[1].capacity,
        math.floor(math.floor(40 * 1.7 + 0.5) * multiplier + 0.5),
        "passenger capacity at " .. tostring(multiplier) .. "x"
    )
end
local halfCapacityResult = runRestrictedUpdate({
    lengthMetres = 5,
    passengerLoadingEnabled = 2,
    passengerCapacityMultiplier = 0.5,
})
assertEqual(
    halfCapacityResult.subconstructions[1].station.terminals[1].capacity,
    5,
    "capacity multiplier applies to the rounded default capacity"
)

for _, radiusMetres in ipairs(expectedCatchmentRadiiMetres) do
    local radiusResult = runRestrictedUpdate({
        cargoLoadingEnabled = 2,
        catchmentRadiusMetres = radiusMetres,
    })
    for _, catchmentArea in ipairs(radiusResult.subconstructions[1].station.catchmentAreas) do
        assertEqual(
            catchmentArea.radius,
            radiusMetres,
            "selected catchment radius " .. tostring(radiusMetres)
        )
    end
end

local maximumLoadingResult = runRestrictedUpdate({
    tracks = 8,
    trackSpacingMetres = 20,
    lengthMetres = 440,
    passengerLoadingEnabled = 2,
    passengerCapacityMultiplier = 3,
    cargoLoadingEnabled = 2,
    catchmentRadiusMetres = 300,
})
local maximumLoadingSubconstruction = maximumLoadingResult.subconstructions[1]
local maximumLoadingStation = maximumLoadingSubconstruction.station
assertEqual(#maximumLoadingResult.edgeLists[1].edges, 8 * nodesPerTrack, "maximum track edge count")
assertEqual(#maximumLoadingSubconstruction.laneLists, 19, "maximum loading-mode lane count")
assertEqual(#maximumLoadingStation.terminals, 16, "maximum loading-mode terminal count")
assertEqual(#maximumLoadingStation.catchmentAreas, 3, "maximum loading-mode catchment count")
assertEqual(maximumLoadingStation.terminals[15].capacity, 2244, "maximum passenger capacity")
assertEqual(
    maximumLoadingStation.terminals[16].cargoTransferSpeeds[1].length,
    440,
    "maximum cargo transfer length"
)
for accessLaneIndex, expectedLongitudinalOffset in ipairs({ -220, 0, 220 }) do
    local maximumAccessLane = maximumLoadingSubconstruction.laneLists[accessLaneIndex + 16]
    assertEqual(#maximumAccessLane.nodes, 18, "maximum access lane node count")
    assertEqual(maximumAccessLane.nodes[1][1][1], -80, "maximum left access endpoint")
    assertEqual(maximumAccessLane.nodes[18][1][1], 80, "maximum right access endpoint")
    assertEqual(
        maximumAccessLane.nodes[1][1][2],
        expectedLongitudinalOffset,
        "maximum access lane longitudinal offset"
    )
    assertEqual(
        maximumLoadingStation.catchmentAreas[accessLaneIndex].radius,
        300,
        "maximum catchment radius"
    )
end
assertNoOverlappingLaneEdges(maximumLoadingSubconstruction.laneLists, "maximum loading-mode lanes")

local activeLoadingModes = {
    { name = "passenger and cargo", passenger = 2, cargo = 2, accessLaneCount = 3 },
    { name = "passenger only", passenger = 2, cargo = 1, accessLaneCount = 3 },
    { name = "cargo only", passenger = 1, cargo = 2, accessLaneCount = 0 },
}
for _, loadingMode in ipairs(activeLoadingModes) do
    for _, lengthMetres in ipairs(expectedLengthsMetres) do
        for trackCountIndex, trackCount in ipairs(expectedTrackCounts) do
            for _, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
                local context = string.format(
                    "%s, %d m, %d tracks, %d m spacing",
                    loadingMode.name,
                    lengthMetres,
                    trackCount,
                    trackSpacingMetres
                )
                local combinationResult = runRestrictedUpdate({
                    tracks = trackCountIndex,
                    trackSpacingMetres = trackSpacingMetres,
                    lengthMetres = lengthMetres,
                    passengerLoadingEnabled = loadingMode.passenger,
                    cargoLoadingEnabled = loadingMode.cargo,
                })
                local combinationSubconstruction = combinationResult.subconstructions[1]
                local combinationStation = combinationSubconstruction.station
                assertEqual(
                    #combinationSubconstruction.laneLists,
                    trackCount * 2 + loadingMode.accessLaneCount,
                    "loading lane count for " .. context
                )
                assertEqual(
                    #combinationStation.terminals,
                    trackCount * 2,
                    "loading terminal count for " .. context
                )
                assertEqual(
                    #combinationStation.catchmentAreas,
                    3,
                    "catchment count for " .. context
                )
                assertEqual(
                    combinationStation.catchmentAreas[1].position[2],
                    -lengthMetres / 2,
                    "negative catchment position for " .. context
                )
                assertEqual(
                    combinationStation.catchmentAreas[3].position[2],
                    lengthMetres / 2,
                    "positive catchment position for " .. context
                )
                assertNoOverlappingLaneEdges(
                    combinationSubconstruction.laneLists,
                    "loading lanes for " .. context
                )
            end
        end
    end
end

local customTrackResult = runRestrictedUpdate({
    tracks = 3,
    length = 1,
    streetTemplate = "custom.track",
    catenary = 1,
})
assertEqual(customTrackResult.edgeLists[1].params.type, "custom.track", "custom track template")
assertEqual(
    #customTrackResult.edgeLists[1].edges,
    3 * nodesPerTrack,
    "custom template applies to every track"
)
for _, customTrackTerminal in ipairs(customTrackResult.subconstructions[1].station.terminals) do
    assertEqual(
        #customTrackTerminal.transportModes,
        1,
        "non-electrified custom-track terminal mode count"
    )
end

local thirdRailResult = runRestrictedUpdate({
    length = 1,
    streetTemplate = "third_rail.track",
    catenary = 2,
})
local thirdRailTerminal = thirdRailResult.subconstructions[1].station.terminals[1]
assertEqual(#thirdRailTerminal.transportModes, 2, "third-rail terminal mode count")
assertEqual(thirdRailTerminal.transportModes[1], "TRAIN", "third-rail train mode")
assertEqual(thirdRailTerminal.transportModes[2], "ELECTRIC_TRAIN", "third-rail electric mode")

local catenaryResult = runRestrictedUpdate({
    tracks = 3,
    length = 1,
    trackType = 3,
    catenary = 2,
})
assertEqual(catenaryResult.edgeLists[1].params.type, "high_speed_catenary.track", "catenary track")
for _, catenaryTerminal in ipairs(catenaryResult.subconstructions[1].station.terminals) do
    assertEqual(#catenaryTerminal.transportModes, 2, "electrified terminal mode count")
    assertEqual(catenaryTerminal.transportModes[1], "TRAIN", "electrified train mode")
    assertEqual(catenaryTerminal.transportModes[2], "ELECTRIC_TRAIN", "electrified train mode")
end

assertEqual(
    script.isAffectedByToolFn(
        construction.isAffectedByToolScript.params,
        {},
        { streetTemplate = "standard.track" },
        {}
    ),
    true,
    "rail upgrade tool"
)
assertEqual(
    script.isAffectedByToolFn(
        construction.isAffectedByToolScript.params,
        {},
        { streetTemplate = "road.street" },
        {}
    ),
    false,
    "road upgrade tool"
)
assertEqual(
    script.isAffectedByToolFn(
        construction.isAffectedByToolScript.params,
        { streetTemplate = "standard.track", catenary = 1 },
        { catenary = 2 },
        { catenary = 1 }
    ),
    true,
    "paired catenary tool"
)
assertEqual(
    script.isAffectedByToolFn(
        construction.isAffectedByToolScript.params,
        { streetTemplate = "third_rail.track", catenary = 2 },
        { catenary = 2 },
        { catenary = 1 }
    ),
    false,
    "unpaired third-rail catenary tool"
)
assertEqual(
    script.isAffectedByToolFn(
        construction.isAffectedByToolScript.params,
        {},
        {},
        {}
    ),
    false,
    "unrelated upgrade tool"
)

local upgradedParams = script.upgradeFn(construction.upgradeScript.params, {
    tracks = 3,
    trackSpacingMetres = 12,
    lengthMetres = 400,
    passengerLoadingEnabled = 2,
    passengerCapacityMultiplier = 2.5,
    cargoLoadingEnabled = 2,
    catchmentRadiusMetres = 250,
    trackType = 2,
    catenary = 1,
}, 0, {
    catenary = 2,
})
assertEqual(upgradedParams.streetTemplate, "standard_catenary.track", "catenary upgrade template")
assertEqual(upgradedParams.catenary, 2, "catenary upgrade state")
assertEqual(upgradedParams.trackSpacingMetres, 12, "catenary upgrade preserves track spacing")
assertEqual(upgradedParams.lengthMetres, 400, "catenary upgrade preserves length")
assertEqual(upgradedParams.passengerLoadingEnabled, 2, "upgrade preserves passenger loading")
assertEqual(upgradedParams.passengerCapacityMultiplier, 2.5, "upgrade preserves passenger capacity")
assertEqual(upgradedParams.cargoLoadingEnabled, 2, "upgrade preserves cargo loading")
assertEqual(upgradedParams.catchmentRadiusMetres, 250, "upgrade preserves catchment radius")
local upgradedResult = runRestrictedUpdate(upgradedParams)
assertEqual(
    upgradedResult.edgeLists[1].params.type,
    "standard_catenary.track",
    "upgrade applies to the shared track edge list"
)
assertEqual(
    #upgradedResult.edgeLists[1].edges,
    3 * nodesPerTrack,
    "upgrade preserves every station track"
)
assertEqual(
    upgradedResult.edgeLists[1].edges[1][1][1],
    -12,
    "upgraded station retains selected track geometry"
)
assertEqual(
    upgradedResult.edgeLists[1].edges[1][1][2],
    -200,
    "upgraded station retains selected length"
)
assertEqual(
    #upgradedResult.subconstructions[1].station.terminals,
    6,
    "upgraded station retains loading terminals"
)
assertEqual(
    upgradedResult.subconstructions[1].station.terminals[1].capacity,
    1700,
    "upgraded station retains passenger capacity multiplier"
)
assertEqual(
    upgradedResult.subconstructions[1].station.catchmentAreas[1].radius,
    250,
    "upgraded station retains catchment radius"
)

local legacyUpgradeParams = script.upgradeFn(construction.upgradeScript.params, {
    tracks = 2,
    trackSpacingMetres = 6,
    length = 7,
    loadingEnabled = 2,
    trackType = 2,
    catenary = 1,
}, 0, {
    catenary = 2,
})
assertEqual(legacyUpgradeParams.length, 7, "upgrade preserves legacy length index")
assertEqual(legacyUpgradeParams.lengthMetres, nil, "upgrade does not invent slider length")
assertEqual(legacyUpgradeParams.loadingEnabled, 2, "upgrade preserves legacy loading mode")
local legacyUpgradeResult = runRestrictedUpdate(legacyUpgradeParams)
assertEqual(
    legacyUpgradeResult.edgeLists[1].edges[1][1][1],
    -3,
    "legacy upgrade preserves track spacing"
)
assertEqual(
    legacyUpgradeResult.edgeLists[1].edges[1][1][2],
    -160,
    "legacy upgrade resolves the original 320-metre preset"
)
assertEqual(
    #legacyUpgradeResult.subconstructions[1].station.terminals,
    4,
    "legacy upgrade enables passenger and cargo loading"
)

local downgradedParams = script.upgradeFn(construction.upgradeScript.params, {
    streetTemplate = "standard_catenary.track",
    catenary = 2,
}, 0, {
    catenary = 1,
})
assertEqual(downgradedParams.streetTemplate, "standard.track", "catenary removal template")
assertEqual(downgradedParams.catenary, 1, "catenary removal state")

local replacementParams = script.upgradeFn(construction.upgradeScript.params, {
    trackType = 2,
    catenary = 1,
}, 0, {
    streetTemplate = "custom.track",
})
assertEqual(replacementParams.streetTemplate, "custom.track", "track replacement template")
assertEqual(replacementParams.catenary, 1, "track replacement derives non-electric state")

local thirdRailReplacementParams = script.upgradeFn(construction.upgradeScript.params, {
    trackType = 2,
    catenary = 1,
}, 0, {
    streetTemplate = "third_rail.track",
})
assertEqual(
    thirdRailReplacementParams.streetTemplate,
    "third_rail.track",
    "third-rail replacement template"
)
assertEqual(thirdRailReplacementParams.catenary, 2, "third-rail replacement derives electric state")

local unsupportedRemovalParams = script.upgradeFn(construction.upgradeScript.params, {
    streetTemplate = "third_rail.track",
    catenary = 2,
}, 0, {
    catenary = 1,
})
assertEqual(
    unsupportedRemovalParams.streetTemplate,
    "third_rail.track",
    "unsupported catenary removal preserves template"
)
assertEqual(unsupportedRemovalParams.catenary, 2, "unsupported catenary removal preserves state")

local unsupportedAdditionParams = script.upgradeFn(construction.upgradeScript.params, {
    streetTemplate = "unpowered_unpaired.track",
    catenary = 1,
}, 0, {
    catenary = 2,
})
assertEqual(
    unsupportedAdditionParams.streetTemplate,
    "unpowered_unpaired.track",
    "unsupported catenary addition preserves template"
)
assertEqual(unsupportedAdditionParams.catenary, 1, "unsupported catenary addition preserves state")

local ok = pcall(script.updateFn, captureParams, {
    length = 99,
    trackType = 2,
    catenary = 1,
})
assertEqual(ok, false, "invalid length rejection")

local zeroLengthIndexOk = pcall(script.updateFn, captureParams, {
    length = 0,
    trackType = 2,
    catenary = 1,
})
assertEqual(zeroLengthIndexOk, false, "zero length index rejection")

for _, invalidLengthMetres in ipairs({ 4, 5.5, 15, 441 }) do
    local invalidLengthOk = pcall(script.updateFn, captureParams, {
        lengthMetres = invalidLengthMetres,
        trackType = 2,
        catenary = 1,
    })
    assertEqual(
        invalidLengthOk,
        false,
        "invalid slider length rejection for " .. tostring(invalidLengthMetres)
    )
end

local invalidTrackCountOk = pcall(script.updateFn, captureParams, {
    tracks = 99,
    length = 1,
    trackType = 2,
    catenary = 1,
})
assertEqual(invalidTrackCountOk, false, "invalid track-count rejection")

local zeroTrackCountIndexOk = pcall(script.updateFn, captureParams, {
    tracks = 0,
    length = 1,
    trackType = 2,
    catenary = 1,
})
assertEqual(zeroTrackCountIndexOk, false, "zero track-count index rejection")

for _, invalidTrackSpacingMetres in ipairs({ 2, 5.5, 21 }) do
    local invalidTrackSpacingOk = pcall(script.updateFn, captureParams, {
        tracks = 2,
        trackSpacingMetres = invalidTrackSpacingMetres,
        length = 1,
        trackType = 2,
        catenary = 1,
    })
    assertEqual(
        invalidTrackSpacingOk,
        false,
        "invalid track-spacing rejection for " .. tostring(invalidTrackSpacingMetres)
    )
end

for _, invalidLoadingIndex in ipairs({ 0, 3 }) do
    local invalidLegacyLoadingOk = pcall(script.updateFn, captureParams, {
        loadingEnabled = invalidLoadingIndex,
        length = 1,
        trackType = 2,
        catenary = 1,
    })
    assertEqual(
        invalidLegacyLoadingOk,
        false,
        "invalid legacy loading index rejection for " .. tostring(invalidLoadingIndex)
    )
    for _, key in ipairs({ "passengerLoadingEnabled", "cargoLoadingEnabled" }) do
        local invalidParams = {
            length = 1,
            trackType = 2,
            catenary = 1,
        }
        invalidParams[key] = invalidLoadingIndex
        local invalidLoadingOk = pcall(script.updateFn, captureParams, invalidParams)
        assertEqual(
            invalidLoadingOk,
            false,
            "invalid " .. key .. " index rejection for " .. tostring(invalidLoadingIndex)
        )
    end
end

for _, invalidMultiplier in ipairs({ 0.25, 0.6, 3.25 }) do
    local invalidMultiplierOk = pcall(script.updateFn, captureParams, {
        passengerCapacityMultiplier = invalidMultiplier,
    })
    assertEqual(
        invalidMultiplierOk,
        false,
        "invalid passenger-capacity multiplier rejection for " .. tostring(invalidMultiplier)
    )
end

for _, invalidRadiusMetres in ipairs({ 49, 75.5, 301 }) do
    local invalidRadiusOk = pcall(script.updateFn, captureParams, {
        catchmentRadiusMetres = invalidRadiusMetres,
    })
    assertEqual(
        invalidRadiusOk,
        false,
        "invalid catchment radius rejection for " .. tostring(invalidRadiusMetres)
    )
end

local invalidCatenaryOk = pcall(script.updateFn, captureParams, {
    length = 1,
    trackType = 2,
    catenary = 99,
})
assertEqual(invalidCatenaryOk, false, "invalid catenary rejection")

local invalidTrackOk = pcall(script.updateFn, captureParams, {
    length = 1,
    trackType = 99,
    catenary = 1,
})
assertEqual(invalidTrackOk, false, "invalid track-type rejection")

local invalidUpgradeCatenaryOk = pcall(script.upgradeFn, construction.upgradeScript.params, {
    trackType = 2,
    catenary = 1,
}, 0, {
    catenary = 99,
})
assertEqual(invalidUpgradeCatenaryOk, false, "invalid upgrade catenary rejection")

local roadReplacementOk = pcall(script.upgradeFn, construction.upgradeScript.params, {
    trackType = 2,
    catenary = 1,
}, 0, {
    streetTemplate = "road.street",
})
assertEqual(roadReplacementOk, false, "non-track replacement rejection")

local invalidPairOk = pcall(script.upgradeFn, construction.upgradeScript.params, {
    streetTemplate = "broken_catenary_pair.track",
    catenary = 1,
}, 0, {
    catenary = 2,
})
assertEqual(invalidPairOk, false, "invalid catenary pair rejection")

local currentModId = "apasz_zigzag"
local registeredConstructionModifier = nil
local loggedMessages = {}
_G.log = {
    verbose = function(message)
        error("unexpected debug log: " .. message)
    end,
    message = function(message)
        loggedMessages[#loggedMessages + 1] = message
    end,
    warning = function(message)
        error("unexpected warning log: " .. message)
    end,
    error = function(message)
        error("unexpected error log: " .. message)
    end,
}
_G.getCurrentModId = function()
    return currentModId
end
_G.addModifier = function(category, modifier)
    assertEqual(category, "loadConstruction", "costs modifier category")
    assertEqual(registeredConstructionModifier, nil, "single costs modifier")
    registeredConstructionModifier = modifier
end

local modScript = loadData("content/mod.script.lua")
assertEqual(
    assert(loadfile("content/zigzag/logging_config.lua"))(),
    false,
    "production debug logging default"
)
local function runModScript(allModParams)
    registeredConstructionModifier = nil
    loggedMessages = {}
    modScript.runFn({}, {}, allModParams, nil)
    return registeredConstructionModifier
end

assertEqual(runModScript(nil), nil, "missing mod parameters preserve default costs")
assertEqual(#loggedMessages, 0, "default costs produce no log noise")
assertEqual(
    runModScript({
        [currentModId] = {
            apasz_zigzag_costs_enabled = 2,
        },
    }),
    nil,
    "enabled costs avoid modifier registration"
)
assertEqual(#loggedMessages, 0, "enabled costs produce no log noise")

registeredConstructionModifier = nil
local invalidCostsParamOk, invalidCostsParamError = pcall(modScript.runFn, {}, {}, {
    [currentModId] = {
        apasz_zigzag_costs_enabled = 3,
    },
}, nil)
assertEqual(invalidCostsParamOk, false, "invalid costs mod parameter rejection")
assertEqual(
    string.find(
        tostring(invalidCostsParamError),
        "[Zigzag Station] ERROR: invalid costs mod parameter 3",
        1,
        true
    ) ~= nil,
    true,
    "invalid costs mod parameter log prefix"
)
assertEqual(registeredConstructionModifier, nil, "invalid costs parameter registers no modifier")

local disableCostsModifier = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 1,
    },
})
assertEqual(type(disableCostsModifier), "function", "disabled costs register modifier")
assertEqual(#loggedMessages, 1, "disabled costs log count")
assertEqual(
    loggedMessages[1],
    "[Zigzag Station] Costs disabled by mod setting",
    "disabled costs log message"
)

local unrelatedConstruction = {}
assertEqual(
    disableCostsModifier("other_mod::/stations/rail/zigzag/zigzag.con", unrelatedConstruction),
    unrelatedConstruction,
    "costs modifier ignores other constructions"
)

local noCostConstruction = loadData("content/stations/rail/zigzag/zigzag.con.lua")
local modifiedConstruction = disableCostsModifier(
    currentModId .. "::/stations/rail/zigzag/zigzag.con",
    noCostConstruction
)
assertEqual(modifiedConstruction, noCostConstruction, "costs modifier updates in place")
assertEqual(noCostConstruction.updateScript.params.costPerMetre, 0, "disabled construction cost rate")
assertEqual(
    noCostConstruction.updateScript.params.maintenanceCostPerMetre,
    0,
    "disabled maintenance cost rate"
)
local noCostAttributes = noCostConstruction.constructionTemplates[1].description.attributes
assertEqual(noCostAttributes.cost[1], 0, "disabled minimum displayed cost")
assertEqual(noCostAttributes.cost[2], 0, "disabled maximum displayed cost")
assertEqual(noCostAttributes.maintenanceCost[1], 0, "disabled minimum displayed maintenance")
assertEqual(noCostAttributes.maintenanceCost[2], 0, "disabled maximum displayed maintenance")

local noCostResult = runRestrictedUpdateWithCapture(
    noCostConstruction.updateScript.params,
    {
        tracks = 8,
        lengthMetres = 440,
    }
)
assertEqual(noCostResult.cost, 0, "disabled construction cost")
assertEqual(noCostResult.maintenanceCost, 0, "disabled maintenance cost")
assertEqual(#noCostResult.edgeLists[1].edges, 8 * nodesPerTrack, "disabled costs preserve geometry")

print("zigzag_check: ok")
