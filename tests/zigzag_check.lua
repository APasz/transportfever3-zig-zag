local loggedWarnings = {}
_G.log = {
    warning = function(message)
        loggedWarnings[#loggedWarnings + 1] = message
    end,
}

local function assertEqual(actual, expected, context)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
    end
end

local function assertSameResult(actual, expected, context)
    if type(expected) ~= "table" then
        assertEqual(actual, expected, context)
        return
    end
    assertEqual(type(actual), "table", context .. " type")
    for key, value in pairs(expected) do
        assertSameResult(actual[key], value, context .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        assert(expected[key] ~= nil, context .. " unexpected field " .. tostring(key))
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
                error(string.format("%s: lane %d edge %d duplicates %s", context, laneListIndex, (firstNodeIndex + 1) / 2, seenEdges[edgeKey]))
            end
            local edgeDescription = string.format("lane %d edge %d", laneListIndex, (firstNodeIndex + 1) / 2)
            seenEdges[edgeKey] = edgeDescription

            local currentEdge = axisAlignedEdge(firstPoint, secondPoint)
            if currentEdge ~= nil then
                for _, previousEdge in ipairs(axisAlignedEdges) do
                    local overlap = math.min(currentEdge.maximum, previousEdge.maximum) - math.max(currentEdge.minimum, previousEdge.minimum)
                    if
                        currentEdge.axis == previousEdge.axis
                        and currentEdge.fixedCoordinate == previousEdge.fixedCoordinate
                        and currentEdge.elevation == previousEdge.elevation
                        and overlap > 0
                    then
                        error(string.format("%s: %s overlaps %s", context, edgeDescription, previousEdge.description))
                    end
                end
                currentEdge.description = edgeDescription
                axisAlignedEdges[#axisAlignedEdges + 1] = currentEdge
            end
        end
    end
end

local function assertUniqueTerminalVehicleNodes(terminals, trackEdgeList, context)
    local seenPositions = {}
    for terminalIndex, terminal in ipairs(terminals) do
        assertEqual(terminal.vehicleNode[1], -1, context .. " terminal " .. terminalIndex .. " edge-list marker")
        local edgeNode = assert(trackEdgeList.edges[terminal.vehicleNode[2] + 1], context .. " terminal has an invalid vehicle-node index")
        local position = pointKey(edgeNode[1])
        if seenPositions[position] ~= nil then
            error(string.format("%s: terminal %d shares its vehicle node with terminal %d", context, terminalIndex, seenPositions[position]))
        end
        seenPositions[position] = terminalIndex
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
                1,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                1,
                0,
                position.x,
                position.y,
                position.z,
                1,
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
package.preload["/scripts/vec3.tl"] = package.preload["::/scripts/vec3.tl"]
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

package.preload["::/scripts/construction/street_util_serialized.tl"] = function()
    if arg[1] ~= nil and arg[1] ~= "" then
        return assert(loadfile(arg[1]))()
    end
    return {
        calcScale = function(chord, angle)
            assert(angle <= math.rad(10) + 1e-12, "curve segment exceeds ten degrees")
            return angle < 0.001 and chord or chord * angle / (2 * math.sin(angle / 2))
        end,
    }
end

for _, moduleName in ipairs({ "track_selection", "station_definition", "validation_metadata", "cargo_storage", "logger", "has_station_window" }) do
    package.preload["apasz_zigzag::/zigzag/" .. moduleName .. ".lua"] = function()
        return assert(loadfile("content/zigzag/" .. moduleName .. ".lua"))()
    end
end

package.preload["::/scripts/metadata_util.tl"] = function()
    return {
        constructionInstance = {
            register = function(key)
                return {
                    set = function(container, value)
                        container[key] = value
                    end,
                    get = function(container)
                        return container and container[key]
                    end,
                }
            end,
        },
    }
end

package.preload["apasz_zigzag::/zigzag/logging_config.lua"] = function()
    return false
end
package.preload["apasz_zigzag::/zigzag/construction_path.lua"] = function()
    return assert(loadfile("content/zigzag/construction_path.lua"))()
end
package.preload["apasz_zigzag::/zigzag/logging.lua"] = function()
    return assert(loadfile("content/zigzag/logging.lua"))()
end

_G.ug_require = function(resourceName)
    return require(resourceName)
end

do
    local previousLog = _G.log
    local messages = {}
    _G.log = { verbose = function(message) messages[#messages + 1] = message end }
    local logging = require("apasz_zigzag::/zigzag/logging.lua")
    for _, enabled in ipairs({ false, true }) do
        local logger = assert(loadfile("content/zigzag/logger.lua", "t", setmetatable({
            ug_require = function(name)
                if name == "apasz_zigzag::/zigzag/logging_config.lua" then return enabled end
                assertEqual(name, "apasz_zigzag::/zigzag/logging.lua", "logger uses the shared logging module")
                return logging
            end,
        }, { __index = _G })))()
        logger.debug("debug setting check")
        assertEqual(#messages, enabled and 1 or 0, "shared logger honours the mod debug setting")
    end
    assertEqual(messages[1], "[Zigzag Station] debug setting check", "shared logger identifies the mod")
    _G.log = previousLog
end

_G._ = function(value)
    if value == "apasz_zigzag_curve_radius_too_small" then
        return "Curve radius %d m is too small. Use at least %d m for this track, station width and length."
    end
    if value == "apasz_zigzag_storage_bay_too_small" then
        return "Storage bay %d holds %d cargo units; its proposed capacity is %d. Collect or discard enough cargo before reducing capacity or changing warehouse type."
    end
    if value == "apasz_zigzag_cargo_storage_too_small" then
        return "Warehouse holds %d cargo units; selected capacity is %d. Collect or discard enough cargo before reducing capacity or removing storage."
    end
    return value
end

local TRAIN_MODE = "TRAIN"
local ELECTRIC_TRAIN_MODE = "ELECTRIC_TRAIN"

local function makeTrackTemplate(electrified, catenaryAdd, catenaryRemove, constructionCost, maintenanceCost)
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
        cost = constructionCost,
        maintenanceCost = maintenanceCost,
        minCurveRadius = 40,
        minCurveRadiusBuild = 55,
    }
end

local templates = {
    ["standard.track"] = makeTrackTemplate(false, "standard_catenary.track", nil, 180, 30),
    ["standard_catenary.track"] = makeTrackTemplate(true, nil, "standard.track", 180, 30),
    ["high_speed.track"] = makeTrackTemplate(false, "high_speed_catenary.track", nil, 540, 90),
    ["high_speed_catenary.track"] = makeTrackTemplate(true, nil, "high_speed.track", 540, 90),
    ["custom.track"] = makeTrackTemplate(false, "custom_catenary.track", nil, 250, 40),
    ["custom_catenary.track"] = makeTrackTemplate(true, nil, "custom.track", 275, 45),
    ["third_rail.track"] = makeTrackTemplate(true, nil, nil, 300, 50),
    ["unpowered_unpaired.track"] = makeTrackTemplate(false, nil, nil, 120, 20),
    ["broken_catenary_pair.track"] = makeTrackTemplate(false, "road.street", nil, 90, 15),
    ["other_mod::/modded.track"] = makeTrackTemplate(false, nil, nil, 225, 35),
    ["zero_cost.track"] = makeTrackTemplate(false, nil, nil, 0, 0),
    ["malformed_module.track"] = makeTrackTemplate(false, nil, nil, 210, 31),
    ["tram_only.track"] = {
        roadType = 0,
        laneConfigs = { { transportModes = { TRAM_TRACK = true } } },
        cost = 50,
        maintenanceCost = 5,
    },
    ["::/industries/shared/industry_track/industry.street_template"] = makeTrackTemplate(false, nil, nil, 0, nil),
    ["road.street"] = {
        roadType = 1,
        laneConfigs = {},
    },
}

local templateResourceNames = {}
local templateIds = {}
local hiddenTemplates = {}
for resourceName, template in pairs(templates) do
    templateResourceNames[#templateResourceNames + 1] = resourceName
    template.description = { name = resourceName, icon = resourceName .. ".tga" }
    template.availability = { yearFrom = 0, yearTo = 0 }
    template.menuCategory = {
        categories = template.roadType == 0 and { { category = "tracks", order = 0 } } or {},
    }
end
table.sort(templateResourceNames)
for index, resourceName in ipairs(templateResourceNames) do
    templateIds[resourceName] = index - 1
end
templates["::/industries/shared/industry_track/industry.street_template"].menuCategory.categories = {}

local activeInfrastructureCostScale = 1
local activeInfrastructureMaintenanceScale = 1

local function scaledTrackTemplate(resourceName)
    local template = assert(templates[resourceName], "unknown template " .. tostring(resourceName))
    local scaledTemplate = {}
    for key, value in pairs(template) do
        scaledTemplate[key] = value
    end
    if type(scaledTemplate.cost) == "number" then
        scaledTemplate.cost = scaledTemplate.cost * activeInfrastructureCostScale
    end
    if type(scaledTemplate.maintenanceCost) == "number" then
        scaledTemplate.maintenanceCost = scaledTemplate.maintenanceCost * activeInfrastructureMaintenanceScale
    end
    return scaledTemplate
end

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
                return templateIds[resourceName] or -1
            end,
            get = function(templateId)
                return scaledTrackTemplate(assert(templateResourceNames[templateId + 1]))
            end,
            isVisible = function(templateId)
                return not hiddenTemplates[assert(templateResourceNames[templateId + 1])]
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
local constructionTemplate = loadData("content/stations/rail/zigzag/zigzag.metacon.lua")
local expectedLengthsMetres = {
    5,
    10,
    20,
    40,
    80,
    120,
    160,
    200,
    240,
    280,
    320,
    360,
    400,
    440,
}
local expectedLegacyLengthsMetres = { 10, 40, 80, 120, 160, 240, 320 }
local expectedTrackCounts = { 1, 2, 3, 4, 5, 6, 7, 8 }
local expectedTrackSpacingsMetres = {
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
}
local expectedCatchmentRadiiMetres = {
    50,
    75,
    100,
    125,
    150,
    175,
    200,
    225,
    250,
    275,
    300,
}
local expectedPassengerCapacityMultipliers = {
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    1.75,
    2,
    2.25,
    2.5,
    2.75,
    3,
}
local expectedTrackSpacingMetres = 5
local nodesPerTrack = 8
assertEqual(construction.namePrefix, "apasz_zigzag_name_prefix", "construction name localization key")
assertEqual(construction.description.name, "apasz_zigzag_name", "construction description name localization key")
assertEqual(construction.description.description, "apasz_zigzag_description", "construction description localization key")
assertEqual(construction.constructionTemplates, nil, "legacy construction has no duplicate build entry")
assertEqual(construction.createTemplateScript, nil, "new builds use the standalone metaconstruction")
assertEqual(constructionTemplate.configureHudIconsScript.params.cargo, true, "cargo placement HUD icons")
assertEqual(constructionTemplate.description.icon, "zigzag.tga", "menu icon")
assertEqual(constructionTemplate.description.previewIcon, "zigzag_preview.tga", "menu preview icon")
assertEqual(#constructionTemplate.params, 12, "build-template parameter count")
assertEqual(#construction.params[1].values, #expectedTrackCounts, "track-count option count")
assertEqual(construction.params[1].name, "apasz_zigzag_tracks", "tracks localization key")
assertEqual(construction.params[1].defaultIndex, 1, "default one-track index")
assertEqual(construction.params[1].displayMode, "Horizontal", "track-count display mode")
for index, trackCount in ipairs(expectedTrackCounts) do
    assertEqual(construction.params[1].values[index], tostring(trackCount), "track-count label " .. tostring(index))
end
local trackSpacingParam = construction.params[2]
assertEqual(trackSpacingParam.key, "trackSpacingMetres", "track-spacing parameter key")
assertEqual(trackSpacingParam.name, "apasz_zigzag_track_spacing", "track-spacing localization key")
assertEqual(trackSpacingParam.uiType, "Slider", "track-spacing UI type")
assertEqual(trackSpacingParam.defaultIndex, 3, "default 5-metre track-spacing index")
assertEqual(#trackSpacingParam.numbers, #expectedTrackSpacingsMetres, "track-spacing option count")
for index, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
    assertEqual(trackSpacingParam.numbers[index], trackSpacingMetres, "track-spacing value " .. tostring(index))
    assertEqual(trackSpacingParam.values[index], tostring(trackSpacingMetres) .. " m", "track-spacing label " .. tostring(index))
end
local lengthParam = construction.params[3]
assertEqual(lengthParam.key, "lengthMetres", "length parameter key")
assertEqual(lengthParam.name, "apasz_zigzag_length", "length localization key")
assertEqual(lengthParam.uiType, "Slider", "length UI type")
assertEqual(lengthParam.defaultIndex, 2, "default 10-metre length index")
assertEqual(#lengthParam.numbers, #expectedLengthsMetres, "length option count")
for index, lengthMetres in ipairs(expectedLengthsMetres) do
    assertEqual(lengthParam.numbers[index], lengthMetres, "length value " .. tostring(index))
    assertEqual(lengthParam.values[index], tostring(lengthMetres) .. " m", "length label " .. tostring(index))
end
assertEqual(construction.params[6].key, "trackType", "default track selector order")
assertEqual(construction.params[6].defaultIndex, 2, "default-era standard track")
assertEqual(construction.params[7].key, "trackType", "high-speed track selector order")
assertEqual(construction.params[7].defaultIndex, 2, "high-speed-era standard track")
assertEqual(construction.params[8].key, "catenary", "catenary selector order")

local passengerLoadingParam = construction.params[9]
assertEqual(passengerLoadingParam.key, "passengerLoadingEnabled", "passenger-loading parameter key")
assertEqual(passengerLoadingParam.name, "apasz_zigzag_passenger_loading_enabled", "passenger-loading localization key")
assertEqual(passengerLoadingParam.uiType, "CheckBox", "passenger-loading UI type")
assertEqual(passengerLoadingParam.defaultIndex, 1, "passenger loading disabled by default")
assertEqual(passengerLoadingParam.values[1], "apasz_zigzag_off", "passenger loading disabled label")
assertEqual(passengerLoadingParam.values[2], "apasz_zigzag_on", "passenger loading enabled label")

local passengerCapacityParam = construction.params[10]
assertEqual(passengerCapacityParam.key, "passengerCapacityMultiplier", "passenger-capacity parameter key")
assertEqual(passengerCapacityParam.name, "apasz_zigzag_passenger_capacity", "passenger-capacity localization key")
assertEqual(passengerCapacityParam.uiType, "Slider", "passenger-capacity UI type")
assertEqual(passengerCapacityParam.defaultIndex, 3, "default passenger-capacity index")
for index, multiplier in ipairs(expectedPassengerCapacityMultipliers) do
    assertEqual(passengerCapacityParam.numbers[index], multiplier, "passenger-capacity multiplier " .. tostring(index))
    assertEqual(passengerCapacityParam.values[index], string.format("%g×", multiplier), "passenger-capacity label " .. tostring(index))
end

local cargoLoadingParam = construction.params[11]
assertEqual(cargoLoadingParam.key, "cargoLoadingEnabled", "cargo-loading parameter key")
assertEqual(cargoLoadingParam.name, "apasz_zigzag_cargo_loading_enabled", "cargo-loading localization key")
assertEqual(cargoLoadingParam.uiType, "CheckBox", "cargo-loading UI type")
assertEqual(cargoLoadingParam.defaultIndex, 1, "cargo loading disabled by default")
assertEqual(cargoLoadingParam.values[1], "apasz_zigzag_off", "cargo loading disabled label")
assertEqual(cargoLoadingParam.values[2], "apasz_zigzag_on", "cargo loading enabled label")

local catchmentRadiusParam = construction.params[12]
assertEqual(catchmentRadiusParam.key, "catchmentRadiusMetres", "catchment parameter key")
assertEqual(catchmentRadiusParam.name, "apasz_zigzag_catchment_radius", "catchment localization key")
assertEqual(catchmentRadiusParam.uiType, "Slider", "catchment UI type")
assertEqual(catchmentRadiusParam.defaultIndex, 5, "default 150-metre catchment index")
for index, radiusMetres in ipairs(expectedCatchmentRadiiMetres) do
    assertEqual(catchmentRadiusParam.numbers[index], radiusMetres, "catchment radius " .. index)
    assertEqual(catchmentRadiusParam.values[index], tostring(radiusMetres) .. " m", "catchment label " .. index)
end

assertEqual(passengerCapacityParam.checkEnabledScript.fileName, "zigzag.params.gui@checkLoadingVisibility", "passenger-capacity visibility callback")
assertEqual(catchmentRadiusParam.checkEnabledScript.fileName, "zigzag.params.gui@checkLoadingVisibility", "catchment visibility callback")

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
assertEqual(checkVisibility(passengerCapacityParam, { passengerLoadingEnabled = 2 }), "Enabled", "capacity visible with passenger loading enabled")
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

do
    local constructionEntity = 101
    local stationEntity = 102
    local stationGroupEntity = 103
    local constructionComponent = { stations = { stationEntity } }
    local resolvedStationGroup = stationGroupEntity
    local gameContext = {}
    local actionFunctionAndProxy = { function() end, "action-proxy" }
    local closeConditionAndProxy = {
        function()
            return false
        end,
        "close-proxy",
    }
    local stationRecipe = function() end
    local nativeActions = { fn = function() end, proxy = {} }
    local actionHelperCalls = 0

    package.preload["::/gui/entity_window/station_group/station_group.tl"] = function()
        return stationRecipe
    end
    package.preload["::/gui/entity_window/make_entity_window.tl"] = function()
        return {
            makeEntityWindowContent = function()
                error("station content must not re-enter global window factory wrappers")
            end,
            makeSetActionFnWithCombinedKey = function(recipe, actions)
                actionHelperCalls = actionHelperCalls + 1
                assertEqual(recipe, stationRecipe, "native action recipe identity")
                assertEqual(actions, actionFunctionAndProxy, "native window selection actions")
                return nativeActions
            end,
        }
    end
    _G.api = {
        type = { ComponentType = { CONSTRUCTION = "CONSTRUCTION" } },
        engine = {
            getComponent = function(entity, componentType)
                assertEqual(entity, constructionEntity, "selected Zigzag construction")
                assertEqual(componentType, "CONSTRUCTION", "selected entity component")
                return constructionComponent
            end,
            system = {
                stationGroupSystem = {
                    getStationGroup = function(entity)
                        assertEqual(entity, stationEntity, "Zigzag station group lookup")
                        return resolvedStationGroup
                    end,
                },
            },
        },
    }

    local resourceName, callbackName = construction.entityWindowScript.fileName:match("^(.-)@([^@]+)$")
    assert(resourceName, "station window must reference a script callback")
    local windowScript = loadData("content/stations/rail/zigzag/" .. resourceName .. ".lua")
    local openStationWindow = assert(windowScript[callbackName], "missing station window callback")
    local expectedMode
    local function openWindow()
        return openStationWindow(
            construction.entityWindowScript.params,
            constructionEntity,
            "test.zigzag.",
            gameContext,
            expectedMode[1],
            expectedMode[2],
            actionFunctionAndProxy,
            closeConditionAndProxy
        )
    end

    for _, mode in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
        expectedMode = mode
        local result = openWindow()
        assertEqual(result.recipe, stationRecipe, "reuse native station content")
        assertEqual(result.param.meta.tag, "test.zigzag.station", "native station content tag")
        assertEqual(result.param.keyEntity, stationGroupEntity, "native content station identity")
        assertEqual(result.param.gameCtx, gameContext, "native window game context")
        assertEqual(result.param.isMapEditor, mode[1], "native window map-editor mode")
        assertEqual(result.param.isSandboxMode, mode[2], "native window sandbox mode")
        assertEqual(result.param.setActionFn, nativeActions.fn, "native window action callback")
        assertEqual(result.param.setActionFn_compareProxy, nativeActions.proxy, "native action proxy")
        assertEqual(result.autoCloseCondition, closeConditionAndProxy[1], "native window lifetime")
        assertEqual(result.autoCloseCondition_compareProxy, closeConditionAndProxy[2], "native window lifetime proxy")
        assertEqual(result.fallbackTitle, "Station", "native station fallback title")
        assertEqual(result.replacedEntity, constructionEntity, "rename the construction name stem")
    end
    assertEqual(actionHelperCalls, 4, "one native action binding per selection")

    local function assertInvalidWindowState(expectedError)
        local ok, message = pcall(openWindow)
        assertEqual(ok, false, "invalid station window state is rejected")
        assert(tostring(message):find(expectedError, 1, true), tostring(message))
        assert(tostring(message):find("[Zigzag Station] ERROR:", 1, true), "window errors use the shared logger")
        assert(tostring(message):find("construction=101", 1, true)
            or tostring(message):find("entity=101", 1, true), "window errors identify the selected construction")
        assertEqual(actionHelperCalls, 4, "invalid state never binds native actions")
    end

    constructionComponent = nil
    assertInvalidWindowState("requires a construction")
    for _, stations in ipairs({ {}, { stationEntity, stationEntity + 1 } }) do
        constructionComponent = { stations = stations }
        assertInvalidWindowState("requires exactly one station")
    end
    constructionComponent = { stations = { stationEntity } }
    resolvedStationGroup = -1
    assertInvalidWindowState("has no station group")
    resolvedStationGroup = nil
    assertInvalidWindowState("has no station group")
    _G.api = nil
end

do
    _G.getOwningModId = function()
        return "apasz_zigzag"
    end
    local descriptor = loadData("content/stations/rail/zigzag/zigzag.selection.gs.lua")
    _G.getOwningModId = nil
    local selection = loadData("content/stations/rail/zigzag/zigzag.selection.script.lua")
    local function registeredCallback(scriptRef)
        local scriptName, callbackName = scriptRef.fileName:match("^(.-)@([^@]+)$")
        assertEqual(scriptName, "zigzag.selection.script", "selection callback resource")
        return assert(selection[callbackName], "missing registered selection callback")
    end
    local update = registeredCallback(descriptor.updateScript)
    local handleEvent = registeredCallback(descriptor.handleEventScript)
    local guiHandleEvent = registeredCallback(descriptor.guiHandleEventScript)
    local subscriptions = {}
    local savedState = {}
    local state = {
        get = function()
            return savedState
        end,
        set = function(_, value)
            savedState = value
        end,
        hasEventSubscriptions = function()
            return #subscriptions > 0
        end,
        subscribeToEvent = function(_, name)
            subscriptions[#subscriptions + 1] = name
        end,
    }
    update({}, state, 0)
    update({}, state, 0)
    assertEqual(#subscriptions, 3, "subscribe to selection and build validation once")
    assertEqual(subscriptions[1], "select", "subscribe to the native selection event")
    assertEqual(subscriptions[2], "builder.proposalCreate", "validate construction previews")
    assertEqual(subscriptions[3], "builder.proposalPrepareForApply", "validate before applying construction")
    subscriptions, savedState = { "select" }, {}
    update({}, state, 0)
    assertEqual(#subscriptions, 4, "existing selection subscriptions gain build validation")
    subscriptions = {}
    update({}, state, 0)
    assertEqual(#subscriptions, 3, "restore event subscriptions when the engine resets them")
    assertEqual(handleEvent({}, state, "", "mainView", "select", 104), nil, "simulation handler leaves selection unchanged")

    local params = descriptor.guiHandleEventScript.params
    assertEqual(
        params.constructionFileName,
        "apasz_zigzag" .. require("apasz_zigzag::/zigzag/construction_path.lua"),
        "selection uses the shared Zigzag construction identity"
    )
    local windowScriptName = "apasz_zigzag::/stations/rail/zigzag/" .. construction.entityWindowScript.fileName
    local generatedConstructionName = "generated-zigzag"
    local descriptions = {
        [params.constructionFileName] = { entityWindowScript = { fileName = windowScriptName } },
        [generatedConstructionName] = { entityWindowScript = { fileName = windowScriptName } },
        ["other_mod::/other.con"] = {
            entityWindowScript = { fileName = "other_mod::/other.window.script@open" },
        },
        ["other_mod::/empty.con"] = { entityWindowScript = { fileName = "" } },
    }
    local components = {
        [101] = { CONSTRUCTION = { fileName = generatedConstructionName } },
        [102] = { STATION = {} },
        [104] = { BASE_EDGE = {} },
        [105] = { BASE_EDGE = {} },
        [106] = { BASE_EDGE = {} },
        [107] = { BASE_EDGE = {} },
        [201] = { CONSTRUCTION = { fileName = "other_mod::/other.con" } },
        [202] = { CONSTRUCTION = { fileName = "other_mod::/empty.con" } },
    }
    local owners = { [104] = 101, [106] = 201, [107] = 202 }
    local events = {}
    _G.api = {
        type = { ComponentType = { BASE_EDGE = "BASE_EDGE", CONSTRUCTION = "CONSTRUCTION" } },
        res = {
            constructionRep = {
                findAndGet = function(resourceName)
                    return assert(descriptions[resourceName])
                end,
            },
        },
        engine = {
            entityExists = function(entity)
                return components[entity] ~= nil
            end,
            getComponent = function(entity, kind)
                return components[entity][kind]
            end,
            system = {
                streetConnectorSystem = {
                    getConstructionEntityForEdge = function(entity)
                        return owners[entity] or -1
                    end,
                },
            },
        },
        gui = {
            fireReactEvent = function(name, param)
                events[#events + 1] = { name = name, entity = param.entity }
            end,
        },
    }
    local function selectEntity(entity, id, name)
        return guiHandleEvent(params, {}, {}, "", id or "mainView", name or "select", entity)
    end
    selectEntity(104)
    assertEqual(#events, 1, "one window request for a track in a generated Zigzag construction")
    assertEqual(events[1].name, "selectEntity", "use native entity-window dispatch")
    assertEqual(events[1].entity, 101, "open the owning construction's station window")
    for _, entity in ipairs({ -1, 999, 101, 102, 105, 106, 107 }) do
        selectEntity(entity)
    end
    selectEntity(104, "otherView")
    selectEntity(104, "mainView", "select-world")
    assertEqual(#events, 1, "ignore unrelated selections and avoid duplicate construction windows")
    for _, invalidEntity in ipairs({ "104", 104.5 }) do
        local ok, message = pcall(selectEntity, invalidEntity)
        assertEqual(ok, false, "invalid selection entity is rejected")
        assert(tostring(message):find("requires an integer entity ID", 1, true), tostring(message))
    end
    descriptions[params.constructionFileName].entityWindowScript.fileName = ""
    local ok, message = pcall(selectEntity, 104)
    assertEqual(ok, false, "missing Zigzag window hook is rejected")
    assert(tostring(message):find("has no station window script", 1, true), tostring(message))
    descriptions[params.constructionFileName].entityWindowScript.fileName = windowScriptName
    components[101].CONSTRUCTION = nil
    ok, message = pcall(selectEntity, 104)
    assertEqual(ok, false, "inconsistent track ownership is rejected")
    assert(tostring(message):find("owner has no construction component", 1, true), tostring(message))
    assertEqual(#events, 1, "invalid selections never open a window")
    _G.api = nil
end

local templateAttributes = constructionTemplate.description.attributes
assertEqual(templateAttributes.cost[1], 0, "unconfigured minimum displayed cost")
assertEqual(templateAttributes.cost[2], 0, "unconfigured maximum displayed cost")
assertEqual(templateAttributes.maintenanceCost[1], 0, "unconfigured minimum displayed maintenance")
assertEqual(templateAttributes.maintenanceCost[2], 0, "unconfigured maximum displayed maintenance")

local iconWidth, iconHeight = readTgaSize("content/stations/rail/zigzag/zigzag@2x.tga")
assertEqual(iconWidth, 240, "menu icon width")
assertEqual(iconHeight, 184, "menu icon height")
local previewWidth, previewHeight = readTgaSize("content/stations/rail/zigzag/zigzag_preview@2x.tga")
assertEqual(previewWidth, 720, "preview icon width")
assertEqual(previewHeight, 405, "preview icon height")

_G.api = gameApi
local script = loadData("content/stations/rail/zigzag/zigzag.script.lua")
assertEqual(type(script.createTemplateFn), "function", "template callback")
assertEqual(next(script.createTemplateFn({}, {})), nil, "empty initial module set")
local captureParams = construction.updateScript.params
local moduleCostRates = {
    ["standard.track"] = { construction = 80000, maintenance = 8000 },
    ["standard_catenary.track"] = { construction = 90000, maintenance = 9000 },
    ["high_speed.track"] = { construction = 120000, maintenance = 12000 },
    ["high_speed_catenary.track"] = { construction = 130000, maintenance = 13000 },
    ["custom.track"] = { construction = 100000, maintenance = 10000 },
    ["custom_catenary.track"] = { construction = 110000, maintenance = 11000 },
    ["third_rail.track"] = { construction = 115000, maintenance = 11500 },
    ["unpowered_unpaired.track"] = { construction = 70000, maintenance = 7000 },
    ["broken_catenary_pair.track"] = { construction = 60000, maintenance = 6000 },
    ["other_mod::/modded.track"] = { construction = 95000, maintenance = 9500 },
    ["::/industries/shared/industry_track/industry.street_template"] = {
        construction = 50000,
        maintenance = 5000,
    },
}
captureParams.trackCostProfiles = {}
for resourceName, template in pairs(templates) do
    if template.roadType == gameApi.type["enum"].RoadType.TRACK then
        local perMetre = nil
        if type(template.cost) == "number" and type(template.maintenanceCost) == "number" then
            perMetre = {
                construction = template.cost,
                maintenance = template.maintenanceCost,
            }
        end
        local perModule = moduleCostRates[resourceName]
        if perMetre ~= nil or perModule ~= nil then
            captureParams.trackCostProfiles[resourceName] = {
                perMetre = perMetre,
                perModule = perModule,
            }
        end
    end
end
captureParams.platformCostProfiles = {
    {
        yearFrom = 0,
        passenger = { construction = 60000, maintenance = 10000 },
        cargo = { construction = 30000, maintenance = 5000 },
    },
    {
        yearFrom = 1950,
        passenger = { construction = 90000, maintenance = 15000 },
        cargo = { construction = 45000, maintenance = 7500 },
    },
    {
        yearFrom = 1990,
        passenger = { construction = 120000, maintenance = 20000 },
        cargo = { construction = 60000, maintenance = 10000 },
    },
}
assertEqual(captureParams.defaultLengthMetres, 10, "captured default length")
assertEqual(captureParams.moduleLengthMetres, 40, "captured vanilla module length")
assertEqual(captureParams.costMode, "MODULE_COST", "captured default cost mode")
for index, lengthMetres in ipairs(expectedLegacyLengthsMetres) do
    assertEqual(captureParams.legacyLengthsMetres[index], lengthMetres, "captured legacy length " .. tostring(index))
end
assertEqual(captureParams.defaultTrackSpacingIndex, 3, "captured default track-spacing index")
assertEqual(captureParams.defaultCatchmentRadiusMetres, 150, "captured default catchment radius")
assertEqual(captureParams.defaultPassengerCapacityMultiplier, 1, "captured default passenger-capacity multiplier")
assertEqual(captureParams.loadingDisabledIndex, 1, "captured loading-disabled index")
assertEqual(captureParams.loadingEnabledIndex, 2, "captured loading-enabled index")
for index, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
    assertEqual(captureParams.trackSpacingsMetres[index], trackSpacingMetres, "captured track-spacing value " .. tostring(index))
end
for index, radiusMetres in ipairs(expectedCatchmentRadiiMetres) do
    assertEqual(captureParams.catchmentRadiiMetres[index], radiusMetres, "captured catchment radius " .. tostring(index))
end
for index, multiplier in ipairs(expectedPassengerCapacityMultipliers) do
    assertEqual(captureParams.passengerCapacityMultipliers[index], multiplier, "captured passenger-capacity multiplier " .. tostring(index))
end

local function runRestrictedCallback(callback, updateCaptureParams, params)
    local resourceApi = _G.api.res
    _G.api.res = nil
    local ok, resultOrError = pcall(callback, updateCaptureParams, params)
    _G.api.res = resourceApi
    assert(ok, resultOrError)
    return resultOrError
end

local function runRestrictedUpdateWithCapture(updateCaptureParams, params)
    return runRestrictedCallback(script.updateFn, updateCaptureParams, params)
end

local function runRestrictedUpdate(params)
    return runRestrictedUpdateWithCapture(captureParams, params)
end

local function assertLengthResult(params, lengthMetres, context)
    local lengthResult = runRestrictedUpdate(params)
    local lengthTrack = lengthResult.edgeLists[1]
    local halfLength = lengthMetres / 2
    assertEqual(lengthTrack.edges[1][1][2], -halfLength, "negative endpoint for " .. context)
    assertEqual(lengthTrack.edges[nodesPerTrack][1][2], halfLength, "positive endpoint for " .. context)
    assertEqual(lengthResult.cost, lengthMetres / 40 * moduleCostRates["standard.track"].construction, "cost for " .. context)
    assertEqual(lengthResult.maintenanceCost, lengthMetres / 40 * moduleCostRates["standard.track"].maintenance, "maintenance cost for " .. context)
end

for _, lengthMetres in ipairs(expectedLengthsMetres) do
    assertLengthResult({ lengthMetres = lengthMetres }, lengthMetres, "slider length " .. tostring(lengthMetres))
end

for lengthIndex, lengthMetres in ipairs(expectedLegacyLengthsMetres) do
    assertLengthResult({ length = lengthIndex }, lengthMetres, "legacy length index " .. tostring(lengthIndex))
end

assertLengthResult({ length = #expectedLegacyLengthsMetres, lengthMetres = 20 }, 20, "slider value overriding legacy length")

for trackCountIndex, trackCount in ipairs(expectedTrackCounts) do
    local trackCountResult = runRestrictedUpdate({ tracks = trackCountIndex })
    local trackCountEdgeList = trackCountResult.edgeLists[1]
    local trackCountStation = trackCountResult.subconstructions[1]
    assertEqual(#trackCountEdgeList.edges, trackCount * nodesPerTrack, "node count for track count " .. trackCount)
    assertEqual(#trackCountEdgeList.snapNodes, trackCount * 2, "snap count for track count " .. trackCount)
    assertEqual(#trackCountStation.laneLists, trackCount, "lane count for track count " .. trackCount)
    assertEqual(#trackCountStation.station.terminals, trackCount, "terminal count for track count " .. trackCount)
    assertEqual(trackCountResult.cost, 10 / 40 * trackCount * moduleCostRates["standard.track"].construction, "cost for track count " .. trackCount)
    assertEqual(
        trackCountResult.maintenanceCost,
        10 / 40 * trackCount * moduleCostRates["standard.track"].maintenance,
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
            firstNodeIndex + nodesPerTrack - 1,
            "positive snap node for track " .. trackIndex .. " of " .. trackCount
        )

        local lane = trackCountStation.laneLists[trackIndex]
        assertEqual(lane.nodes[1][1][1], trackOffset - 0.5, "lane start for track " .. trackIndex)
        assertEqual(lane.nodes[2][1][1], trackOffset + 0.5, "lane end for track " .. trackIndex)
        assertEqual(lane.linkable, false, "lane linkage for track " .. trackIndex)

        local trackTerminal = trackCountStation.station.terminals[trackIndex]
        assertEqual(trackTerminal.tag, zeroBasedTrackIndex, "terminal tag for track " .. trackIndex)
        assertEqual(trackTerminal.personEdges[1][1], zeroBasedTrackIndex, "terminal lane index for track " .. trackIndex)
        assertEqual(trackTerminal.personNodes[1][1], zeroBasedTrackIndex, "terminal person-node lane index for track " .. trackIndex)
        assertEqual(trackTerminal.vehicleNode[1], -1, "terminal construction edge-list marker for track " .. trackIndex)
        assertEqual(trackTerminal.vehicleNode[2], firstNodeIndex + 3, "terminal centre node for track " .. trackIndex)
    end
end

for _, trackSpacingMetres in ipairs(expectedTrackSpacingsMetres) do
    local spacingResult = runRestrictedUpdate({
        tracks = 2,
        trackSpacingMetres = trackSpacingMetres,
    })
    local spacingTrack = spacingResult.edgeLists[1]
    local spacingStation = spacingResult.subconstructions[1]
    assertEqual(spacingTrack.edges[1][1][1], -trackSpacingMetres / 2, "first track offset at " .. trackSpacingMetres .. " metres")
    assertEqual(spacingTrack.edges[nodesPerTrack + 1][1][1], trackSpacingMetres / 2, "second track offset at " .. trackSpacingMetres .. " metres")
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
assertEqual(legacySpacingResult.edgeLists[1].edges[1][1][1], -expectedTrackSpacingMetres / 2, "missing track-spacing parameter uses the 5-metre default")

local result = runRestrictedUpdate({})

assertEqual(#result.edgeLists, 1, "track edge-list count")
local track = result.edgeLists[1]
assertEqual(track.type, "TRACK", "edge-list type")
assertEqual(track.params.type, "standard.track", "selected track type")
assertEqual(#track.edges, nodesPerTrack, "track node count")
assertEqual(track.edges[1][1][2], -5, "negative endpoint")
assertEqual(track.edges[1][2][2], 4.5, "negative outer edge tangent")
assertEqual(track.edges[2][1][2], -0.5, "passenger stop node")
assertEqual(track.edges[3][1][2], -0.5, "passenger stop connection node")
assertEqual(track.edges[3][2][2], 0.5, "negative inner edge tangent")
assertEqual(track.edges[4][1][2], 0, "non-loading centre node")
assertEqual(track.edges[5][1][2], 0, "non-loading centre connection node")
assertEqual(track.edges[6][1][2], 0.5, "cargo stop node")
assertEqual(track.edges[7][1][2], 0.5, "cargo stop connection node")
assertEqual(track.edges[8][1][2], 5, "positive endpoint")
assertEqual(track.edges[8][2][2], 4.5, "positive outer edge tangent")
assertEqual(track.snapNodes[1], 0, "negative snap node")
assertEqual(track.snapNodes[2], 7, "positive snap node")

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
assertEqual(terminal.vehicleNode[2], 3, "terminal centre node")
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
assertEqual(result.cost, 20000, "default module construction cost")
assertEqual(result.maintenanceCost, 2000, "default module maintenance cost")

local function captureWithCostMode(costMode)
    local configuredCapture = {}
    for key, value in pairs(captureParams) do
        configuredCapture[key] = value
    end
    configuredCapture.costMode = costMode
    return configuredCapture
end

local noCostResult = runRestrictedUpdateWithCapture(captureWithCostMode("NO_COST"), {
    tracks = 8,
    lengthMetres = 440,
    passengerLoadingEnabled = 2,
    cargoLoadingEnabled = 2,
})
assertEqual(noCostResult.cost, 0, "no-cost construction cost")
assertEqual(noCostResult.maintenanceCost, 0, "no-cost maintenance cost")
assertEqual(#noCostResult.edgeLists[1].edges, 8 * nodesPerTrack, "no-cost geometry")

local trackCostResult = runRestrictedUpdateWithCapture(captureWithCostMode("TRACK_COST"), {
    tracks = 3,
    lengthMetres = 40,
    streetTemplate = "custom.track",
    catenary = 1,
})
assertEqual(trackCostResult.cost, 40 * 3 * 250, "selected track construction cost")
assertEqual(trackCostResult.maintenanceCost, 40 * 3 * 40, "selected track maintenance cost")

local zeroTrackCostResult = runRestrictedUpdateWithCapture(captureWithCostMode("TRACK_COST"), {
    lengthMetres = 40,
    streetTemplate = "zero_cost.track",
    catenary = 1,
})
assertEqual(zeroTrackCostResult.cost, 0, "explicit zero track construction cost")
assertEqual(zeroTrackCostResult.maintenanceCost, 0, "explicit zero track maintenance cost")

local proportionalModuleResult = runRestrictedUpdateWithCapture(captureWithCostMode("MODULE_COST"), {
    lengthMetres = 5,
    streetTemplate = "custom.track",
    catenary = 1,
})
assertEqual(proportionalModuleResult.cost, 100000 / 8, "proportional module construction cost")
assertEqual(proportionalModuleResult.maintenanceCost, 10000 / 8, "proportional module maintenance cost")

local stationPassengerResult = runRestrictedUpdateWithCapture(captureWithCostMode("STATION_COST"), {
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    year = 1949,
})
assertEqual(stationPassengerResult.cost, 80000 + 60000, "one-track passenger station construction cost")
assertEqual(stationPassengerResult.maintenanceCost, 8000 + 10000, "one-track passenger station maintenance cost")

local stationBothResult = runRestrictedUpdateWithCapture(captureWithCostMode("STATION_COST"), {
    tracks = 3,
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    cargoLoadingEnabled = 2,
    year = 1949,
})
assertEqual(stationBothResult.cost, 3 * 80000 + 2 * (60000 + 30000), "station cost uses vanilla platform rows and both loading types")
assertEqual(stationBothResult.maintenanceCost, 3 * 8000 + 2 * (10000 + 5000), "station maintenance uses vanilla platform rows and both loading types")

local eraStationResult = runRestrictedUpdateWithCapture(captureWithCostMode("STATION_COST"), {
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    cargoLoadingEnabled = 2,
    year = 1950,
})
assertEqual(eraStationResult.cost, 80000 + 90000 + 45000, "station cost uses the current platform era")
assertEqual(eraStationResult.maintenanceCost, 8000 + 15000 + 7500, "station maintenance uses the current platform era")

local proportionalStationResult = runRestrictedUpdateWithCapture(captureWithCostMode("STATION_COST"), {
    lengthMetres = 10,
    passengerLoadingEnabled = 2,
    year = 0,
})
assertEqual(proportionalStationResult.cost, (80000 + 60000) / 4, "sub-module station construction cost is proportional")
assertEqual(proportionalStationResult.maintenanceCost, (8000 + 10000) / 4, "sub-module station maintenance cost is proportional")

local stationWithoutLoadingResult = runRestrictedUpdateWithCapture(captureWithCostMode("STATION_COST"), { tracks = 4, lengthMetres = 40 })
assertEqual(stationWithoutLoadingResult.cost, 4 * 80000, "station cost without loading matches module cost")

local fourTrackPassengerResult = runRestrictedUpdateWithCapture(captureWithCostMode("STATION_COST"), {
    tracks = 4,
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    year = 0,
})
assertEqual(fourTrackPassengerResult.cost, 4 * 80000 + 3 * 60000, "four tracks use three vanilla platform rows")

local invalidCostModeOk = pcall(script.updateFn, captureWithCostMode("INVALID_COST_MODE"), {})
assertEqual(invalidCostModeOk, false, "invalid captured cost mode rejection")

local missingTrackModuleCapture = captureWithCostMode("MODULE_COST")
missingTrackModuleCapture.trackCostProfiles = {}
for resourceName, profile in pairs(captureParams.trackCostProfiles) do
    missingTrackModuleCapture.trackCostProfiles[resourceName] = profile
end
missingTrackModuleCapture.trackCostProfiles["custom.track"] = {
    perMetre = captureParams.trackCostProfiles["custom.track"].perMetre,
    perModule = nil,
}
local missingTrackModuleResult = runRestrictedUpdateWithCapture(missingTrackModuleCapture, { streetTemplate = "custom.track", catenary = 1 })
assertEqual(missingTrackModuleResult.cost, 0, "missing module price falls back to zero")
assertEqual(missingTrackModuleResult.maintenanceCost, 0, "missing module maintenance falls back to zero")
assertEqual(#loggedWarnings, 1, "missing module price is logged")
assert(loggedWarnings[1]:find("custom.track", 1, true), "missing module log names the track")
runRestrictedUpdateWithCapture(missingTrackModuleCapture, { streetTemplate = "custom.track", catenary = 1 })
assertEqual(#loggedWarnings, 1, "preview updates do not repeat missing module warnings")

local missingPerMetreCapture = captureWithCostMode("TRACK_COST")
local incompleteTrackName = "::/industries/shared/industry_track/industry.street_template"
local missingPerMetreResult = runRestrictedUpdateWithCapture(missingPerMetreCapture, { streetTemplate = incompleteTrackName, catenary = 1 })
assertEqual(missingPerMetreResult.cost, 0, "missing per-metre price falls back to zero")
assertEqual(missingPerMetreResult.maintenanceCost, 0, "missing per-metre maintenance falls back to zero")
assertEqual(#loggedWarnings, 2, "missing per-metre price is logged")
assert(loggedWarnings[2]:find(incompleteTrackName, 1, true), "missing per-metre log names the track")

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
    local expectedPassengerVehicleNode = zeroBasedTrackIndex * nodesPerTrack + 1
    local expectedCargoVehicleNode = zeroBasedTrackIndex * nodesPerTrack + 5

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
    assertEqual(passengerTerminal.vehicleNode[2], expectedPassengerVehicleNode, "passenger vehicle node")
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
    assertEqual(cargoTerminal.vehicleNode[2], expectedCargoVehicleNode, "cargo vehicle node")
    assertEqual(#cargoTerminal.cargoTransferSpeeds, 1, "cargo transfer-speed count")
    local cargoTransfer = cargoTerminal.cargoTransferSpeeds[1]
    assertEqual(cargoTransfer.cargoTypeSet.cargoClassesIncluded[1], "UNIVERSAL", "cargo class")
    assertEqual(cargoTransfer.loadSpeedModifier, 1, "cargo load-speed modifier")
    assertEqual(cargoTransfer.length, 40, "cargo transfer length")
end
assertUniqueTerminalVehicleNodes(loadingStation.terminals, loadingResult.edgeLists[1], "loading-mode terminals")

for accessLaneIndex, expectedLongitudinalOffset in ipairs({ -20, 0, 20 }) do
    local accessLane = loadingSubconstruction.laneLists[accessLaneIndex + 4]
    local catchmentArea = loadingStation.catchmentAreas[accessLaneIndex]
    assertEqual(accessLane.transportModes[1], "PERSON", "access lane mode")
    assertEqual(accessLane.linkable, true, "access lane linkage")
    assertEqual(#accessLane.nodes, 6, "access lane node count")
    assertEqual(accessLane.nodes[1][1][1], -13, "left access endpoint")
    assertEqual(accessLane.nodes[6][1][1], 13, "right access endpoint")
    assertEqual(accessLane.nodes[1][1][2], expectedLongitudinalOffset, "access lane longitudinal offset")
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
assertEqual(legacyLoadingSubconstruction.station.terminals[1].capacity, 68, "legacy loading default passenger capacity")
assertEqual(legacyLoadingSubconstruction.station.catchmentAreas[1].radius, 150, "legacy loading default catchment radius")

local migratedCargoOnlyResult = runRestrictedUpdate({
    tracks = 2,
    lengthMetres = 40,
    loadingEnabled = 2,
    passengerLoadingEnabled = 1,
    cargoLoadingEnabled = 2,
})
assertEqual(#migratedCargoOnlyResult.subconstructions[1].laneLists, 4, "new loading toggles override the legacy setting")

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
assertEqual(halfCapacityResult.subconstructions[1].station.terminals[1].capacity, 5, "capacity multiplier applies to the rounded default capacity")

for _, radiusMetres in ipairs(expectedCatchmentRadiiMetres) do
    local radiusResult = runRestrictedUpdate({
        cargoLoadingEnabled = 2,
        catchmentRadiusMetres = radiusMetres,
    })
    for _, catchmentArea in ipairs(radiusResult.subconstructions[1].station.catchmentAreas) do
        assertEqual(catchmentArea.radius, radiusMetres, "selected catchment radius " .. tostring(radiusMetres))
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
assertEqual(maximumLoadingStation.terminals[16].cargoTransferSpeeds[1].length, 440, "maximum cargo transfer length")
for accessLaneIndex, expectedLongitudinalOffset in ipairs({ -220, 0, 220 }) do
    local maximumAccessLane = maximumLoadingSubconstruction.laneLists[accessLaneIndex + 16]
    assertEqual(#maximumAccessLane.nodes, 18, "maximum access lane node count")
    assertEqual(maximumAccessLane.nodes[1][1][1], -80, "maximum left access endpoint")
    assertEqual(maximumAccessLane.nodes[18][1][1], 80, "maximum right access endpoint")
    assertEqual(maximumAccessLane.nodes[1][1][2], expectedLongitudinalOffset, "maximum access lane longitudinal offset")
    assertEqual(maximumLoadingStation.catchmentAreas[accessLaneIndex].radius, 300, "maximum catchment radius")
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
                local context = string.format("%s, %d m, %d tracks, %d m spacing", loadingMode.name, lengthMetres, trackCount, trackSpacingMetres)
                local combinationResult = runRestrictedUpdate({
                    tracks = trackCountIndex,
                    trackSpacingMetres = trackSpacingMetres,
                    lengthMetres = lengthMetres,
                    passengerLoadingEnabled = loadingMode.passenger,
                    cargoLoadingEnabled = loadingMode.cargo,
                })
                local combinationSubconstruction = combinationResult.subconstructions[1]
                local combinationStation = combinationSubconstruction.station
                assertEqual(#combinationSubconstruction.laneLists, trackCount * 2 + loadingMode.accessLaneCount, "loading lane count for " .. context)
                assertEqual(#combinationStation.terminals, trackCount * 2, "loading terminal count for " .. context)
                assertEqual(#combinationStation.catchmentAreas, 3, "catchment count for " .. context)
                assertEqual(combinationStation.catchmentAreas[1].position[2], -lengthMetres / 2, "negative catchment position for " .. context)
                assertEqual(combinationStation.catchmentAreas[3].position[2], lengthMetres / 2, "positive catchment position for " .. context)
                assertNoOverlappingLaneEdges(combinationSubconstruction.laneLists, "loading lanes for " .. context)
                assertUniqueTerminalVehicleNodes(combinationStation.terminals, combinationResult.edgeLists[1], "loading terminals for " .. context)
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
assertEqual(#customTrackResult.edgeLists[1].edges, 3 * nodesPerTrack, "custom template applies to every track")
for _, customTrackTerminal in ipairs(customTrackResult.subconstructions[1].station.terminals) do
    assertEqual(#customTrackTerminal.transportModes, 1, "non-electrified custom-track terminal mode count")
end
assertEqual(customTrackResult.cost, 10 / 40 * 3 * 100000, "custom track uses its generated module cost")

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
assertEqual(catenaryResult.cost, 10 / 40 * 3 * 130000, "catenary track uses its generated module cost")
for _, catenaryTerminal in ipairs(catenaryResult.subconstructions[1].station.terminals) do
    assertEqual(#catenaryTerminal.transportModes, 2, "electrified terminal mode count")
    assertEqual(catenaryTerminal.transportModes[1], "TRAIN", "electrified train mode")
    assertEqual(catenaryTerminal.transportModes[2], "ELECTRIC_TRAIN", "electrified train mode")
end

assertEqual(script.isAffectedByToolFn(construction.isAffectedByToolScript.params, {}, { streetTemplate = "standard.track" }, {}), true, "rail upgrade tool")
assertEqual(script.isAffectedByToolFn(construction.isAffectedByToolScript.params, {}, { streetTemplate = "road.street" }, {}), false, "road upgrade tool")
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
assertEqual(script.isAffectedByToolFn(construction.isAffectedByToolScript.params, {}, {}, {}), false, "unrelated upgrade tool")

local upgradedParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        tracks = 3,
        trackSpacingMetres = 12,
        lengthMetres = 400,
        passengerLoadingEnabled = 2,
        passengerCapacityMultiplier = 2.5,
        cargoLoadingEnabled = 2,
        catchmentRadiusMetres = 250,
        trackType = 2,
        catenary = 1,
    },
    0,
    {
        catenary = 2,
    }
)
assertEqual(upgradedParams.streetTemplate, "standard_catenary.track", "catenary upgrade template")
assertEqual(upgradedParams.catenary, 2, "catenary upgrade state")
assertEqual(upgradedParams.trackSpacingMetres, 12, "catenary upgrade preserves track spacing")
assertEqual(upgradedParams.lengthMetres, 400, "catenary upgrade preserves length")
assertEqual(upgradedParams.passengerLoadingEnabled, 2, "upgrade preserves passenger loading")
assertEqual(upgradedParams.passengerCapacityMultiplier, 2.5, "upgrade preserves passenger capacity")
assertEqual(upgradedParams.cargoLoadingEnabled, 2, "upgrade preserves cargo loading")
assertEqual(upgradedParams.catchmentRadiusMetres, 250, "upgrade preserves catchment radius")
local upgradedResult = runRestrictedUpdate(upgradedParams)
assertEqual(upgradedResult.edgeLists[1].params.type, "standard_catenary.track", "upgrade applies to the shared track edge list")
assertEqual(#upgradedResult.edgeLists[1].edges, 3 * nodesPerTrack, "upgrade preserves every station track")
assertEqual(upgradedResult.edgeLists[1].edges[1][1][1], -12, "upgraded station retains selected track geometry")
assertEqual(upgradedResult.edgeLists[1].edges[1][1][2], -200, "upgraded station retains selected length")
assertEqual(#upgradedResult.subconstructions[1].station.terminals, 6, "upgraded station retains loading terminals")
assertEqual(upgradedResult.subconstructions[1].station.terminals[1].capacity, 1700, "upgraded station retains passenger capacity multiplier")
assertEqual(upgradedResult.subconstructions[1].station.catchmentAreas[1].radius, 250, "upgraded station retains catchment radius")

local legacyUpgradeParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        tracks = 2,
        trackSpacingMetres = 6,
        length = 7,
        loadingEnabled = 2,
        trackType = 2,
        catenary = 1,
    },
    0,
    {
        catenary = 2,
    }
)
assertEqual(legacyUpgradeParams.length, 7, "upgrade preserves legacy length index")
assertEqual(legacyUpgradeParams.lengthMetres, nil, "upgrade does not invent slider length")
assertEqual(legacyUpgradeParams.loadingEnabled, 2, "upgrade preserves legacy loading mode")
local legacyUpgradeResult = runRestrictedUpdate(legacyUpgradeParams)
assertEqual(legacyUpgradeResult.edgeLists[1].edges[1][1][1], -3, "legacy upgrade preserves track spacing")
assertEqual(legacyUpgradeResult.edgeLists[1].edges[1][1][2], -160, "legacy upgrade resolves the original 320-metre preset")
assertEqual(#legacyUpgradeResult.subconstructions[1].station.terminals, 4, "legacy upgrade enables passenger and cargo loading")

local downgradedParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        streetTemplate = "standard_catenary.track",
        catenary = 2,
    },
    0,
    {
        catenary = 1,
    }
)
assertEqual(downgradedParams.streetTemplate, "standard.track", "catenary removal template")
assertEqual(downgradedParams.catenary, 1, "catenary removal state")

local replacementParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        trackType = 2,
        catenary = 1,
    },
    0,
    {
        streetTemplate = "custom.track",
    }
)
assertEqual(replacementParams.streetTemplate, "custom.track", "track replacement template")
assertEqual(replacementParams.catenary, 1, "track replacement derives non-electric state")

local thirdRailReplacementParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        trackType = 2,
        catenary = 1,
    },
    0,
    {
        streetTemplate = "third_rail.track",
    }
)
assertEqual(thirdRailReplacementParams.streetTemplate, "third_rail.track", "third-rail replacement template")
assertEqual(thirdRailReplacementParams.catenary, 2, "third-rail replacement derives electric state")

local unsupportedRemovalParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        streetTemplate = "third_rail.track",
        catenary = 2,
    },
    0,
    {
        catenary = 1,
    }
)
assertEqual(unsupportedRemovalParams.streetTemplate, "third_rail.track", "unsupported catenary removal preserves template")
assertEqual(unsupportedRemovalParams.catenary, 2, "unsupported catenary removal preserves state")

local unsupportedAdditionParams = script.upgradeFn(
    construction.upgradeScript.params,
    {
        streetTemplate = "unpowered_unpaired.track",
        catenary = 1,
    },
    0,
    {
        catenary = 2,
    }
)
assertEqual(unsupportedAdditionParams.streetTemplate, "unpowered_unpaired.track", "unsupported catenary addition preserves template")
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
    assertEqual(invalidLengthOk, false, "invalid slider length rejection for " .. tostring(invalidLengthMetres))
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
    assertEqual(invalidTrackSpacingOk, false, "invalid track-spacing rejection for " .. tostring(invalidTrackSpacingMetres))
end

for _, invalidLoadingIndex in ipairs({ 0, 3 }) do
    local invalidLegacyLoadingOk = pcall(script.updateFn, captureParams, {
        loadingEnabled = invalidLoadingIndex,
        length = 1,
        trackType = 2,
        catenary = 1,
    })
    assertEqual(invalidLegacyLoadingOk, false, "invalid legacy loading index rejection for " .. tostring(invalidLoadingIndex))
    for _, key in ipairs({ "passengerLoadingEnabled", "cargoLoadingEnabled" }) do
        local invalidParams = {
            length = 1,
            trackType = 2,
            catenary = 1,
        }
        invalidParams[key] = invalidLoadingIndex
        local invalidLoadingOk = pcall(script.updateFn, captureParams, invalidParams)
        assertEqual(invalidLoadingOk, false, "invalid " .. key .. " index rejection for " .. tostring(invalidLoadingIndex))
    end
end

for _, invalidMultiplier in ipairs({ 0.25, 0.6, 3.25 }) do
    local invalidMultiplierOk = pcall(script.updateFn, captureParams, {
        passengerCapacityMultiplier = invalidMultiplier,
    })
    assertEqual(invalidMultiplierOk, false, "invalid passenger-capacity multiplier rejection for " .. tostring(invalidMultiplier))
end

for _, invalidRadiusMetres in ipairs({ 49, 75.5, 301 }) do
    local invalidRadiusOk = pcall(script.updateFn, captureParams, {
        catchmentRadiusMetres = invalidRadiusMetres,
    })
    assertEqual(invalidRadiusOk, false, "invalid catchment radius rejection for " .. tostring(invalidRadiusMetres))
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

local invalidUpgradeCatenaryOk = pcall(
    script.upgradeFn,
    construction.upgradeScript.params,
    {
        trackType = 2,
        catenary = 1,
    },
    0,
    {
        catenary = 99,
    }
)
assertEqual(invalidUpgradeCatenaryOk, false, "invalid upgrade catenary rejection")

local roadReplacementOk = pcall(
    script.upgradeFn,
    construction.upgradeScript.params,
    {
        trackType = 2,
        catenary = 1,
    },
    0,
    {
        streetTemplate = "road.street",
    }
)
assertEqual(roadReplacementOk, false, "non-track replacement rejection")

assertEqual(
    script.isAffectedByToolFn(construction.isAffectedByToolScript.params, { trackType = 2, catenary = 1 }, { streetTemplate = "tram_only.track" }, {}),
    false,
    "tram-only replacement is not offered for railway stations"
)
local tramReplacementParams = { trackType = 2, catenary = 1 }
local tramReplacementOk = pcall(script.upgradeFn, construction.upgradeScript.params, tramReplacementParams, -1, { streetTemplate = "tram_only.track" })
assertEqual(tramReplacementOk, false, "tram-only replacement rejection")
assertEqual(tramReplacementParams.streetTemplate, nil, "rejected replacement preserves the original track")

do
    local originalReplacement = templates["custom_catenary.track"].catenaryRemove
    templates["custom_catenary.track"].catenaryRemove = "tram_only.track"
    local invalidRailwayPairOk = pcall(
        script.upgradeFn,
        construction.upgradeScript.params,
        { streetTemplate = "custom_catenary.track", catenary = 2 },
        -1,
        { catenary = 1 }
    )
    templates["custom_catenary.track"].catenaryRemove = originalReplacement
    assertEqual(invalidRailwayPairOk, false, "tram-only catenary replacement rejection")
end

local invalidPairOk = pcall(
    script.upgradeFn,
    construction.upgradeScript.params,
    {
        streetTemplate = "broken_catenary_pair.track",
        catenary = 1,
    },
    0,
    {
        catenary = 2,
    }
)
assertEqual(invalidPairOk, false, "invalid catenary pair rejection")

local currentModId = "apasz_zigzag"
local loggedMessages = {}
_G.log = {
    verbose = function(message)
        error("unexpected debug log: " .. message)
    end,
    message = function(message)
        loggedMessages[#loggedMessages + 1] = message
    end,
    warning = function(message)
        loggedWarnings[#loggedWarnings + 1] = message
    end,
    error = function(message)
        error("unexpected error log: " .. message)
    end,
}
_G.getCurrentModId = function()
    return currentModId
end

local moduleResources = {}
for _, profile in ipairs(require("apasz_zigzag::/zigzag/cargo_storage.lua").profiles) do
    local factor = profile.mixedTypes and 1 or 2
    moduleResources[profile.moduleName] = { metadata = { price = 150000 * factor, maintenanceCost = 25000 * factor } }
end
for trackResourceName, costRate in pairs(moduleCostRates) do
    moduleResources["::/trainstation_" .. trackResourceName:gsub("::", "__")] = {
        metadata = {
            price = costRate.construction,
            maintenanceCost = costRate.maintenance,
        },
    }
end
moduleResources["::/trainstation_malformed_module.track"] = {
    metadata = {
        price = 75000,
        maintenanceCost = nil,
    },
}
for eraSuffix, rates in pairs({
    a = captureParams.platformCostProfiles[1],
    b = captureParams.platformCostProfiles[2],
    c = captureParams.platformCostProfiles[3],
}) do
    moduleResources["::/stations/rail/modular_station/platform_passenger_era_" .. eraSuffix .. ".module"] = {
        availability = { yearFrom = rates.yearFrom },
        metadata = {
            price = rates.passenger.construction,
            maintenanceCost = rates.passenger.maintenance,
        },
    }
    moduleResources["::/stations/rail/modular_station/platform_cargo_era_" .. eraSuffix .. ".module"] = {
        availability = { yearFrom = rates.yearFrom },
        metadata = {
            price = rates.cargo.construction,
            maintenanceCost = rates.cargo.maintenance,
        },
    }
end

local configuredConstruction = nil
local configuredSingleBayConstruction = nil
local configuredTemplate = nil
local configuredBuilders = {}
local addedTemplates = {}
local nativeScriptParams = {}
gameApi.type["enum"].ScriptParamType = {
    Button = "native:Button",
    Slider = "native:Slider",
    ComboBox = "native:ComboBox",
    IconButton = "native:IconButton",
    CheckBox = "native:CheckBox",
}
gameApi.type.ScriptParam = {
    new = function()
        local param = setmetatable({}, {
            __newindex = function(target, key, value)
                if key == "uiType" then
                    assert(value:match("^native:"), "native ScriptParam requires a native enum value")
                end
                rawset(target, key, value)
            end,
        })
        nativeScriptParams[param] = true
        return param
    end,
}
gameApi.type.ScriptRef = {
    new = function()
        return {}
    end,
}
gameApi.res.streetTemplateRep.getAll = function(includeInvisible)
    local resourceNames = {}
    for templateId, resourceName in ipairs(templateResourceNames) do
        if includeInvisible or not hiddenTemplates[resourceName] then
            resourceNames[templateId - 1] = resourceName
        end
    end
    return resourceNames
end
local menuCategories = {
    { type = "menu_category", data = { category = "tracks", menu = "TRACKS" } },
    { type = "menu_category", data = { category = "custom_tracks", menu = "TRACKS" } },
    { type = "menu_category", data = { category = "custom_roads", menu = "STREETS" } },
}
gameApi.res.genericRep = {
    getAllOfType = function(kind)
        assertEqual(kind, "menu_category", "track menu category resource type")
        local ids = {}
        for index in ipairs(menuCategories) do ids[#ids + 1] = index - 1 end
        return ids
    end,
    get = function(id) return assert(menuCategories[id + 1], "unknown menu category") end,
}
gameApi.res.moduleRep = {
    find = function(resourceName)
        return moduleResources[resourceName] ~= nil and resourceName or -1
    end,
    get = function(resourceName)
        local module = assert(moduleResources[resourceName], "unknown module " .. tostring(resourceName))
        return {
            availability = module.availability,
            metadata = {
                price = module.metadata.price * activeInfrastructureCostScale,
                maintenanceCost = module.metadata.maintenanceCost,
            },
        }
    end,
}
gameApi.res.constructionRep = {
    find = function(resourceName)
        if
            resourceName == currentModId .. "::/stations/rail/zigzag/zigzag.con"
            or resourceName == currentModId .. "::/stations/rail/zigzag/zigzag_single_bay.con"
        then
            return resourceName
        end
        return -1
    end,
    get = function(resourceName)
        if resourceName == currentModId .. "::/stations/rail/zigzag/zigzag_single_bay.con" then
            return assert(configuredSingleBayConstruction)
        end
        assertEqual(resourceName, currentModId .. "::/stations/rail/zigzag/zigzag.con", "configured construction resource")
        return assert(configuredConstruction)
    end,
}

local function copyResourceValue(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = nativeScriptParams[value] and gameApi.type.ScriptParam.new() or {}
    seen[value] = copy
    for key, nestedValue in pairs(value) do
        copy[key] = copyResourceValue(nestedValue, seen)
    end
    return copy
end

gameApi.res.metaConstructionRep = {
    find = function(resourceName)
        return resourceName == currentModId .. "::/stations/rail/zigzag/zigzag.metacon" and 0 or -1
    end,
    get = function(templateId)
        assertEqual(templateId, 0, "configured metaconstruction resource")
        return setmetatable({}, {
            __index = function(_, key)
                return configuredTemplate[key]
            end,
            __newindex = function(_, key, value)
                if key == "params" then
                    for _, param in ipairs(value) do
                        assert(nativeScriptParams[param], "native parameter assignment requires ScriptParam objects")
                    end
                end
                configuredTemplate[key] = value
            end,
            __pairs = function()
                return pairs(configuredTemplate)
            end,
        })
    end,
    setVisible = function(templateId, visible)
        if templateId == 0 then
            configuredTemplate.visible = visible
        else
            addedTemplates[templateId].visible = visible
        end
    end,
    isVisible = function(templateId)
        assertEqual(templateId, 0, "metaconstruction visibility lookup")
        return configuredTemplate.visible ~= false
    end,
    add = function(resourceName, template, visible)
        addedTemplates[#addedTemplates + 1] = { name = resourceName, template = copyResourceValue(template), visible = visible }
        return #addedTemplates
    end,
    setAsTable = function()
        return false
    end,
}

local modScript = loadData("content/mod.script.lua")
assertEqual(assert(loadfile("content/zigzag/logging_config.lua"))(), false, "production debug logging default")
assertEqual(type(modScript.postRunFn), "function", "cost configuration post-run callback")
assertEqual(modScript.runFn, nil, "cost configuration needs loaded resources")

local function runModScript(allModParams, infrastructureCostScale, infrastructureMaintenanceScale, updateScriptWrapper, templateScriptWrapper)
    activeInfrastructureCostScale = infrastructureCostScale or 1
    activeInfrastructureMaintenanceScale = infrastructureMaintenanceScale or 1
    configuredConstruction = loadData("content/stations/rail/zigzag/zigzag.con.lua")
    configuredSingleBayConstruction = loadData("content/stations/rail/zigzag/zigzag_single_bay.con.lua")
    configuredTemplate = loadData("content/stations/rail/zigzag/zigzag.metacon.lua")
    addedTemplates = {}
    if updateScriptWrapper ~= nil then
        updateScriptWrapper(configuredConstruction)
        updateScriptWrapper(configuredSingleBayConstruction)
    end
    if templateScriptWrapper ~= nil then
        templateScriptWrapper(configuredTemplate)
    end
    for index, param in ipairs(configuredTemplate.params) do
        local native = gameApi.type.ScriptParam.new()
        for key, value in pairs(param) do
            if key == "uiType" then
                value = gameApi.type["enum"].ScriptParamType[value]
            end
            native[key] = value
        end
        configuredTemplate.params[index] = native
    end
    loggedMessages = {}
    local baseConfig = nil
    if infrastructureCostScale ~= nil or infrastructureMaintenanceScale ~= nil then
        baseConfig = {
            costs = {
                infrastructureCostScale = activeInfrastructureCostScale,
                infrastructureMaintenanceScale = activeInfrastructureMaintenanceScale,
            },
        }
    end
    modScript.postRunFn({}, {}, allModParams, baseConfig)
    configuredBuilders[configuredConstruction] = configuredTemplate
    configuredBuilders[configuredSingleBayConstruction] = configuredTemplate
    return configuredConstruction
end

local defaultCostConstruction = runModScript(nil)
local defaultCostParams = defaultCostConstruction.updateScript.params
assertEqual(defaultCostParams.costMode, "MODULE_COST", "new games default to module cost")
assertEqual(#loggedMessages, 1, "cost-mode configuration log count")
assertEqual(loggedMessages[1], "[Zigzag Station] Configured cost mode MODULE_COST", "default cost-mode log message")
assertEqual(defaultCostParams.trackCostProfiles["custom.track"].perMetre, nil, "module mode does not capture unused track rates")
assertEqual(defaultCostParams.trackCostProfiles["custom.track"].perModule.construction, 100000, "generated track-module construction rate")
assertEqual(
    defaultCostParams.trackCostProfiles["other_mod::/modded.track"].perModule.construction,
    95000,
    "namespaced generated track-module construction rate"
)
local incompleteTrackProfile = defaultCostParams.trackCostProfiles["::/industries/shared/industry_track/industry.street_template"]
assertEqual(incompleteTrackProfile.perMetre, nil, "incomplete per-metre costs are ignored")
assertEqual(incompleteTrackProfile.perModule.construction, 50000, "an incomplete track can still use its valid module cost")
assertEqual(defaultCostParams.trackCostProfiles["zero_cost.track"].perModule, nil, "missing generated-module cost is left for the logged fallback")
assertEqual(defaultCostParams.trackCostProfiles["malformed_module.track"].perModule, nil, "incomplete generated-module costs are ignored")
assertEqual(#defaultCostParams.platformCostProfiles, 0, "module mode does not capture unused platform costs")

local wrappedCostConstruction = runModScript(
    {
        [currentModId] = {
            apasz_zigzag_costs_enabled = 3,
        },
    },
    nil,
    nil,
    function(candidate)
        local original = candidate.updateScript
        local inner = {
            fileName = "compatibility_test::/inner.script@update",
            params = {
                callback = original.fileName,
                arguments = original.params,
            },
        }
        local outerParams = {
            callback = inner.fileName,
            arguments = inner.params,
        }
        outerParams.self = outerParams
        candidate.updateScript = {
            fileName = "compatibility_test::/outer.script@update",
            params = outerParams,
        }
    end
)
local wrappedRootParams = wrappedCostConstruction.updateScript.params
local wrappedCostParams = wrappedRootParams.arguments.arguments
assertEqual(wrappedCostConstruction.updateScript.fileName, "compatibility_test::/outer.script@update", "wrapped update script is preserved")
assertEqual(wrappedRootParams.callback, "compatibility_test::/inner.script@update", "outer wrapper callback is preserved")
assertEqual(wrappedRootParams.arguments.callback, "zigzag.script@updateFn", "inner wrapper callback is preserved")
assertEqual(wrappedRootParams.costMode, nil, "wrapper parameters are not polluted")
assertEqual(wrappedCostParams.costMode, "MODULE_COST", "nested Zigzag parameters receive the cost mode")
assertEqual(wrappedCostParams.trackCostProfiles["custom.track"].perModule.construction, 100000, "nested Zigzag parameters receive cost profiles")
local wrappedCostResult = runRestrictedUpdateWithCapture(wrappedCostParams, {})
assertEqual(wrappedCostResult.cost, 20000, "nested cost profile reaches update script")

local discardedParamsOk, discardedParamsError = pcall(runModScript, nil, nil, nil, function(candidate)
    candidate.updateScript = {
        fileName = "broken_mod::/replacement.script@update",
        params = {},
    }
end)
assertEqual(discardedParamsOk, false, "discarded update parameters are rejected")
assertEqual(
    string.find(tostring(discardedParamsError), "could not locate Zigzag update parameters beneath " .. "broken_mod::/replacement.script@update", 1, true)
        ~= nil,
    true,
    "discarded update parameters produce a compatibility error"
)

local removedScriptOk, removedScriptError = pcall(runModScript, nil, nil, nil, function(candidate)
    candidate.updateScript = nil
end)
assertEqual(removedScriptOk, false, "removed update script is rejected")
assertEqual(
    string.find(tostring(removedScriptError), "construction update script was removed by another mod", 1, true) ~= nil,
    true,
    "removed update script produces a compatibility error"
)

local defaultAttributes = configuredBuilders[defaultCostConstruction].description.attributes
assertEqual(defaultAttributes.cost[1], 0, "module-mode menu includes zero-price fallback")
assertEqual(defaultAttributes.cost[2], 130000 * 440 / 40 * 8 + 300000 * 5000 / 500, "module-mode maximum menu cost")
assertEqual(defaultAttributes.maintenanceCost[1], 0, "module-mode minimum menu maintenance")
assertEqual(defaultAttributes.maintenanceCost[2], 13000 * 440 / 40 * 8 + 50000 * 5000 / 500, "module-mode maximum menu maintenance")

local zeroModuleName = "::/trainstation_zero_cost.track"
moduleResources[zeroModuleName] = {
    metadata = {
        price = 0,
        maintenanceCost = 0,
    },
}
local zeroModuleConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 3,
    },
})
local zeroModuleProfile = zeroModuleConstruction.updateScript.params.trackCostProfiles["zero_cost.track"]
assertEqual(zeroModuleProfile.perModule.construction, 0, "explicit zero module price")
assertEqual(zeroModuleProfile.perModule.maintenance, 0, "explicit zero module maintenance")
local zeroModuleResult = runRestrictedUpdateWithCapture(zeroModuleConstruction.updateScript.params, {
    lengthMetres = 40,
    streetTemplate = "zero_cost.track",
    catenary = 1,
})
assertEqual(zeroModuleResult.cost, 0, "explicit zero module construction result")
assertEqual(zeroModuleResult.maintenanceCost, 0, "explicit zero module maintenance result")
moduleResources[zeroModuleName] = nil

local noCostConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 1,
    },
})
assertEqual(noCostConstruction.updateScript.params.costMode, "NO_COST", "index one is no cost")
assertEqual(next(noCostConstruction.updateScript.params.trackCostProfiles), nil, "no-cost mode does not capture unused track costs")
local noCostAttributes = configuredBuilders[noCostConstruction].description.attributes
assertEqual(noCostAttributes.cost[1], 0, "no-cost minimum menu cost")
assertEqual(noCostAttributes.cost[2], 0, "no-cost maximum menu cost")
assertEqual(noCostAttributes.maintenanceCost[1], 0, "no-cost minimum menu maintenance")
assertEqual(noCostAttributes.maintenanceCost[2], 0, "no-cost maximum menu maintenance")
local configuredNoCostResult = runRestrictedUpdateWithCapture(noCostConstruction.updateScript.params, {
    tracks = 8,
    lengthMetres = 440,
})
assertEqual(configuredNoCostResult.cost, 0, "configured no-cost construction cost")
assertEqual(configuredNoCostResult.maintenanceCost, 0, "configured no-cost maintenance cost")

local zeroScaleNoCostConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 1,
    },
}, 0)
assertEqual(configuredBuilders[zeroScaleNoCostConstruction].description.attributes.cost[2], 0, "no-cost mode accepts a zero infrastructure scale")

local migratedOnConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 2,
    },
}, 1.5, 2)
local migratedOnParams = migratedOnConstruction.updateScript.params
assertEqual(migratedOnParams.costMode, "TRACK_COST", "old On setting migrates to track cost")
assertEqual(migratedOnParams.trackCostProfiles["zero_cost.track"].perMetre.construction, 0, "explicit zero track construction cost is retained")
assertEqual(migratedOnParams.trackCostProfiles["zero_cost.track"].perMetre.maintenance, 0, "explicit zero track maintenance cost is retained")
assertEqual(#migratedOnParams.platformCostProfiles, 0, "track mode does not capture unused platform costs")
assertEqual(migratedOnParams.trackCostProfiles["custom.track"].perMetre.construction, 250, "post-run track construction rate removes the applied scale")
assertEqual(migratedOnParams.trackCostProfiles["custom.track"].perMetre.maintenance, 40, "post-run track maintenance rate removes the applied scale")
local trackAttributes = configuredBuilders[migratedOnConstruction].description.attributes
assertEqual(trackAttributes.cost[1], 0, "track-mode menu includes explicit zero construction costs")
assertEqual(trackAttributes.cost[2], 440 * 8 * 540 * 1.5, "track-mode maximum menu cost includes infrastructure scale")
assertEqual(trackAttributes.maintenanceCost[1], 0, "track-mode menu includes explicit zero maintenance costs")
assertEqual(trackAttributes.maintenanceCost[2], 440 * 8 * 90 * 2, "track-mode maximum maintenance includes the vanilla scale")

local configuredScaledTrackResult = runRestrictedUpdateWithCapture(migratedOnParams, {
    tracks = 3,
    lengthMetres = 40,
    streetTemplate = "custom.track",
    catenary = 1,
})
assertEqual(configuredScaledTrackResult.cost, 40 * 3 * 250, "post-run track cost removes the already-applied construction scale")
assertEqual(configuredScaledTrackResult.maintenanceCost, 40 * 3 * 40, "post-run track cost removes the already-applied maintenance scale")

local explicitModuleConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 3,
    },
}, 1.5, 2)
assertEqual(explicitModuleConstruction.updateScript.params.costMode, "MODULE_COST", "index three is module cost")
local explicitModuleParams = explicitModuleConstruction.updateScript.params
assertEqual(
    explicitModuleParams.trackCostProfiles["custom.track"].perModule.construction,
    100000,
    "post-run module price removes the applied construction scale"
)
local explicitModuleAttributes = configuredBuilders[explicitModuleConstruction].description.attributes
assertEqual(explicitModuleAttributes.cost[2], (130000 * 440 / 40 * 8 + 300000 * 5000 / 500) * 1.5, "module-mode menu uses the vanilla-scaled module price")
assertEqual(
    explicitModuleAttributes.maintenanceCost[2],
    (13000 * 440 / 40 * 8 + 50000 * 5000 / 500) * 2,
    "module-mode menu applies the vanilla maintenance scale"
)
local configuredScaledModuleResult = runRestrictedUpdateWithCapture(explicitModuleConstruction.updateScript.params, {})
assertEqual(configuredScaledModuleResult.cost, 20000, "scaled module construction result")
assertEqual(configuredScaledModuleResult.maintenanceCost, 2000, "scaled module maintenance result remains unscaled for vanilla")

local zeroScaleModuleConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 3,
    },
}, 0)
local configuredZeroScaleModuleResult = runRestrictedUpdateWithCapture(zeroScaleModuleConstruction.updateScript.params, {})
assertEqual(configuredZeroScaleModuleResult.cost, 0, "module-cost mode supports a zero infrastructure scale")

local stationCostConstruction = runModScript({
    [currentModId] = {
        apasz_zigzag_costs_enabled = 4,
    },
}, 1.5, 2)
assertEqual(stationCostConstruction.updateScript.params.costMode, "STATION_COST", "index four is station cost")
assertEqual(stationCostConstruction.updateScript.params.platformCostProfiles[2].passenger.construction, 90000, "passenger platform-module construction rate")
assertEqual(stationCostConstruction.updateScript.params.platformCostProfiles[3].cargo.maintenance, 10000, "cargo platform-module maintenance rate")
local stationAttributes = configuredBuilders[stationCostConstruction].description.attributes
assertEqual(stationAttributes.cost[1], 0, "station-mode minimum menu cost")
assertEqual(stationAttributes.cost[2], (130000 * 440 / 40 * 8 + 300000 * 5000 / 500 + (120000 + 60000) * 440 / 40 * 5) * 1.5, "station-mode maximum menu cost")
assertEqual(
    stationAttributes.maintenanceCost[2],
    (13000 * 440 / 40 * 8 + 50000 * 5000 / 500 + (20000 + 10000) * 440 / 40 * 5) * 2,
    "station-mode maximum menu maintenance"
)

local configuredStationResult = runRestrictedUpdateWithCapture(stationCostConstruction.updateScript.params, {
    lengthMetres = 40,
    passengerLoadingEnabled = 2,
    year = 0,
})
assertEqual(configuredStationResult.cost, 80000 + 60000, "post-run station profile reaches update script")
assertEqual(configuredStationResult.maintenanceCost, 8000 + 10000, "post-run station maintenance remains unscaled for vanilla")

local invalidCostsParamOk, invalidCostsParamError = pcall(modScript.postRunFn, {}, {}, {
    [currentModId] = {
        apasz_zigzag_costs_enabled = 5,
    },
}, nil)
assertEqual(invalidCostsParamOk, false, "invalid cost-mode parameter rejection")
assertEqual(
    string.find(tostring(invalidCostsParamError), "[Zigzag Station] ERROR: invalid cost mode parameter 5", 1, true) ~= nil,
    true,
    "invalid cost-mode parameter log prefix"
)

do
    local templateScript = loadData("content/stations/rail/zigzag/zigzag.template.script.lua")
    local selection = require("apasz_zigzag::/zigzag/track_selection.lua")

    local function trackIndex(builder, resourceName)
        for index, track in ipairs(builder.createTemplateScript.params.tracks) do
            if track.resourceName == resourceName then
                return index
            end
        end
        return nil
    end

    local function pickerAt(builder, year)
        local selected = nil
        for _, param in ipairs(builder.params) do
            if param.key == selection.paramKey and param.yearFrom <= year and (param.yearTo == 0 or year < param.yearTo) then
                assertEqual(selected, nil, "only one track picker is active in each year")
                selected = param
            end
        end
        return selected
    end

    local function pickerIncludes(builder, year, resourceName)
        local picker = pickerAt(builder, year)
        local index = trackIndex(builder, resourceName)
        if picker ~= nil then
            for _, value in ipairs(picker.numbers) do
                if value == index then
                    return true
                end
            end
        end
        return false
    end

    local function configureMode(modeIndex)
        return runModScript({
            [currentModId] = { apasz_zigzag_costs_enabled = modeIndex },
        })
    end

    do
        local categories = templates["third_rail.track"].menuCategory.categories
        for _, category in ipairs({ "custom_tracks", "custom_roads", "unregistered" }) do
            templates["third_rail.track"].menuCategory.categories = { { category = category, order = -10 } }
            local configured = configureMode(3)
            local builder = configuredBuilders[configured]
            if category == "custom_tracks" then
                assertEqual(trackIndex(builder, "third_rail.track"), 1, "custom Tracks menu categories retain native entry order")
                assert(pickerIncludes(builder, 2020, "third_rail.track"), "custom Tracks menu categories are selectable")
            else
                assertEqual(trackIndex(builder, "third_rail.track"), nil, "non-Track menu categories are excluded")
            end
        end
        templates["third_rail.track"].menuCategory.categories = categories
    end

    do
        local builder = configuredBuilders[defaultCostConstruction]
        assertEqual(trackIndex(builder, "road.street"), nil, "roads are excluded from the railway picker")
        assertEqual(trackIndex(builder, "tram_only.track"), nil, "tram-only templates are excluded")
        assertEqual(
            trackIndex(builder, "::/industries/shared/industry_track/industry.street_template"),
            nil,
            "internal templates without a native track-menu entry are excluded"
        )
        assert(pickerIncludes(builder, 2020, "standard_catenary.track"), "electrified variants are listed directly")
        assert(pickerIncludes(builder, 2020, "third_rail.track"), "unpaired third rail is selectable")
        assert(nativeScriptParams[pickerAt(builder, 2020)], "picker uses a native ScriptParam object")
        assertEqual(pickerAt(builder, 2020).uiType, gameApi.type["enum"].ScriptParamType.ComboBox, "picker uses a native enum value")
        local picker = pickerAt(builder, 2020)
        for index, trackIndex in ipairs(picker.numbers) do
            local resourceName = builder.createTemplateScript.params.tracks[trackIndex].resourceName
            assertEqual(picker.images[index], templates[resourceName].description.icon, "native picker icons follow exact catalogue IDs")
        end
        for _, param in ipairs(builder.params) do
            assert(param.key ~= "trackType" and param.key ~= "catenary", "new builds have no legacy track controls")
        end

        local input = {
            apasz_zigzag_track_variant = assert(trackIndex(builder, "third_rail.track")),
            year = 2020,
            lengthMetres = 40,
            tracks = 2,
            passengerLoadingEnabled = 2,
            compatibility_test = { marker = true },
        }
        local proposal = runRestrictedCallback(templateScript.createTemplateFn, builder.createTemplateScript.params, input)
        local station = proposal.constructions[1]
        assertEqual(#proposal.constructions, 1, "template places one station")
        assertEqual(station.constructionFileName, currentModId .. "::/stations/rail/zigzag/zigzag.con", "saved construction path is unchanged")
        assertEqual(next(station.modules), nil, "platform-free station has no placed modules")
        assertEqual(station.params.streetTemplate, "third_rail.track", "template saves the exact resource path")
        assertEqual(station.params.catenary, 2, "third-rail electric capability is persisted")
        assertEqual(station.params.apasz_zigzag_track_variant, nil, "transient picker index is not saved")
        assertEqual(station.params.trackType, nil, "new stations do not save a legacy track index")
        assertEqual(station.params.compatibility_test, input.compatibility_test, "other parameter fields are preserved")
        assert(input.apasz_zigzag_track_variant ~= nil, "template does not mutate the preview parameters")
        local result = runRestrictedUpdateWithCapture(defaultCostParams, station.params)
        assertEqual(result.edgeLists[1].params.type, "third_rail.track", "selected track reaches station geometry")
        assertEqual(result.subconstructions[1].station.terminals[1].transportModes[2], "ELECTRIC_TRAIN", "third-rail terminals allow electric trains")

        templates["third_rail.track"].menuCategory.categories[1].order = -10
        local reordered = configureMode(3)
        assertEqual(trackIndex(configuredBuilders[reordered], "third_rail.track"), 1, "native menu order is respected")
        hiddenTemplates["third_rail.track"] = true
        local hidden = configureMode(3)
        assertEqual(trackIndex(configuredBuilders[hidden], "third_rail.track"), nil, "hidden third rail is not offered for new builds")
        local savedResult = runRestrictedUpdateWithCapture(hidden.updateScript.params, station.params)
        assertEqual(savedResult.edgeLists[1].params.type, "third_rail.track", "saved identity survives catalogue reordering and hiding")
        assertEqual(savedResult.cost, result.cost, "hidden saved tracks retain their real module cost")
        templates["third_rail.track"].menuCategory.categories[1].order = 0
        hiddenTemplates["third_rail.track"] = nil
    end

    do
        local warningsBefore = #loggedWarnings
        hiddenTemplates["standard_catenary.track"] = true
        for modeIndex, expectedCost in ipairs({ 0, 7200, 90000, 90000 }) do
            local configured = configureMode(modeIndex)
            local builder = configuredBuilders[configured]
            assertEqual(trackIndex(builder, "standard_catenary.track"), nil, "hidden vanilla track is excluded from the picker")
            local result = runRestrictedUpdateWithCapture(configured.updateScript.params, { trackType = 2, catenary = 2, lengthMetres = 40 })
            assertEqual(result.edgeLists[1].params.type, "standard_catenary.track", "legacy track index remains unchanged")
            assertEqual(result.cost, expectedCost, "hidden legacy track has the correct cost in each mode")
            if modeIndex > 1 then
                local upgraded = script.upgradeFn(construction.upgradeScript.params, { trackType = 2, catenary = 1, lengthMetres = 40 }, -1, { catenary = 2 })
                local upgradedResult = runRestrictedUpdateWithCapture(configured.updateScript.params, upgraded)
                assertEqual(upgraded.streetTemplate, "standard_catenary.track", "hidden catenary counterpart remains usable")
                assertEqual(upgradedResult.cost, expectedCost, "hidden counterpart retains its captured costs")
            end
        end
        assertEqual(#loggedWarnings, warningsBefore, "hidden tracks with costs do not trigger fallback warnings")
        hiddenTemplates["standard_catenary.track"] = nil
    end

    do
        templates["custom.track"].availability = { yearFrom = 1850, yearTo = 1900 }
        local configured = configureMode(3)
        local builder = configuredBuilders[configured]
        assertEqual(pickerIncludes(builder, 1849, "custom.track"), false, "future tracks are excluded")
        assertEqual(pickerIncludes(builder, 1850, "custom.track"), true, "track availability starts inclusively")
        assertEqual(pickerIncludes(builder, 1899, "custom.track"), true, "track remains available before retirement")
        assertEqual(pickerIncludes(builder, 1900, "custom.track"), false, "track retirement is exclusive")
        for _, year in ipairs({ 1849, 1850, 1899, 1900 }) do
            local picker = pickerAt(builder, year)
            for position, trackIndex in ipairs(picker.numbers) do
                local resourceName = builder.createTemplateScript.params.tracks[trackIndex].resourceName
                assertEqual(picker.images[position], templates[resourceName].description.icon, "availability filtering preserves icon associations")
            end
        end
        local index = assert(trackIndex(builder, "custom.track"))
        local available =
            runRestrictedCallback(templateScript.createTemplateFn, builder.createTemplateScript.params, { apasz_zigzag_track_variant = index, year = 1850 })
        assertEqual(available.constructions[1].params.catenary, 1, "non-electric track capability is persisted")
        local expired =
            runRestrictedCallback(templateScript.createTemplateFn, builder.createTemplateScript.params, { apasz_zigzag_track_variant = index, year = 1900 })
        local firstAvailable = pickerAt(builder, 1900).numbers[1]
        local firstAvailableTrack = builder.createTemplateScript.params.tracks[firstAvailable]
        assertEqual(
            expired.constructions[1].params.streetTemplate,
            firstAvailableTrack.resourceName,
            "expired selections use the first available track for new placements"
        )
        local future =
            runRestrictedCallback(templateScript.createTemplateFn, builder.createTemplateScript.params, { apasz_zigzag_track_variant = index, year = 1849 })
        local firstEarlier = pickerAt(builder, 1849).numbers[1]
        assertEqual(
            future.constructions[1].params.streetTemplate,
            builder.createTemplateScript.params.tracks[firstEarlier].resourceName,
            "moving the date backwards also selects an available track"
        )
        local invalidOk = pcall(templateScript.createTemplateFn, builder.createTemplateScript.params, { apasz_zigzag_track_variant = 9999, year = 1850 })
        assertEqual(invalidOk, false, "template rejects an invalid variant index")
        local existing = runRestrictedUpdateWithCapture(configured.updateScript.params, { streetTemplate = "custom.track", catenary = 1, year = 1900 })
        assertEqual(existing.edgeLists[1].params.type, "custom.track", "retirement does not replace saved tracks")
        templates["custom.track"].availability = { yearFrom = 0, yearTo = 0 }
    end

    do
        local warningsBefore = #loggedWarnings
        local result = runRestrictedUpdateWithCapture(stationCostConstruction.updateScript.params, {
            streetTemplate = "zero_cost.track",
            catenary = 1,
            lengthMetres = 40,
            tracks = 2,
            passengerLoadingEnabled = 2,
            cargoLoadingEnabled = 2,
            year = 1950,
        })
        assertEqual(result.cost, 2 * (90000 + 45000), "missing track-module price preserves platform construction costs")
        assertEqual(result.maintenanceCost, 2 * (15000 + 7500), "missing track-module price preserves platform maintenance")
        assertEqual(#loggedWarnings, warningsBefore + 1, "zero fallback is logged once for the selected track")
        local zeroResult = runRestrictedUpdateWithCapture(zeroModuleConstruction.updateScript.params, { streetTemplate = "zero_cost.track", catenary = 1 })
        assertEqual(zeroResult.cost, 0, "explicit zero module price remains valid")
        assertEqual(#loggedWarnings, warningsBefore + 1, "explicit zero prices produce no warning")
    end

    do
        local originalHidden = hiddenTemplates
        hiddenTemplates = {}
        for resourceName in pairs(templates) do
            hiddenTemplates[resourceName] = true
        end
        local configured = configureMode(3)
        assertEqual(configuredBuilders[configured].visible, false, "builder is hidden when no tracks are offered")
        local existing = runRestrictedUpdateWithCapture(configured.updateScript.params, {})
        assertEqual(existing.cost, 20000, "existing stations work when every track is hidden")
        hiddenTemplates = originalHidden
    end

    do
        local capture = captureWithCostMode("MODULE_COST")
        capture.trackCostProfiles = {}
        local warningsBefore = #loggedWarnings
        local result = runRestrictedUpdateWithCapture(capture, { streetTemplate = "other_mod::/modded.track", catenary = 1 })
        assertEqual(result.cost, 0, "a missing entire cost profile falls back to zero")
        assertEqual(result.maintenanceCost, 0, "a missing profile has zero track maintenance")
        assertEqual(#loggedWarnings, warningsBefore + 1, "missing profile is logged with its track")
        assert(loggedWarnings[#loggedWarnings]:find("other_mod::/modded.track", 1, true), "missing-profile warning identifies the resource")
    end

    do
        local originalHidden = hiddenTemplates
        hiddenTemplates = {}
        for resourceName in pairs(templates) do
            hiddenTemplates[resourceName] = resourceName ~= "custom.track" and resourceName ~= "third_rail.track"
        end
        templates["custom.track"].availability = { yearFrom = 1850, yearTo = 1900 }
        templates["third_rail.track"].availability = { yearFrom = 1950, yearTo = 0 }
        local configured = configureMode(3)
        local builder = configuredBuilders[configured]
        assertEqual(builder.availability.yearFrom, 1850, "build entry starts with the first available track")
        assertEqual(builder.availability.yearTo, 1900, "build entry ends when no tracks remain")
        assertEqual(#addedTemplates, 1, "a later availability period gets its own build entry")
        assertEqual(addedTemplates[1].template.availability.yearFrom, 1950, "later build entry starts after the gap")
        assertEqual(addedTemplates[1].template.availability.yearTo, 0, "later build entry remains available")
        assertEqual(
            addedTemplates[1].template.description.attributes.cost[2],
            builder.description.attributes.cost[2],
            "period entries retain the configured cost attributes"
        )
        assertEqual(addedTemplates[1].visible, true, "later build entry inherits visibility")
        assertEqual(pickerAt(builder, 1920), nil, "availability gaps have no track selector")
        templates["custom.track"].availability = { yearFrom = 0, yearTo = 0 }
        templates["third_rail.track"].availability = { yearFrom = 0, yearTo = 0 }
        hiddenTemplates = originalHidden
    end

    do
        local originalFind = gameApi.res.moduleRep.find
        gameApi.res.moduleRep.find = function()
            error("unexpected generated-module lookup")
        end
        local ok, configured = pcall(configureMode, 2)
        gameApi.res.moduleRep.find = originalFind
        assert(ok, "track-cost mode must not read module costs: " .. tostring(configured))
        assertEqual(configured.updateScript.params.trackCostProfiles["custom.track"].perModule, nil, "track mode does not capture unused module prices")

        local originalGet = gameApi.res.streetTemplateRep.get
        gameApi.res.streetTemplateRep.get = function(id)
            local template = originalGet(id)
            return setmetatable({}, {
                __index = function(_, key)
                    assert(key ~= "cost" and key ~= "maintenanceCost", "unexpected per-metre cost read")
                    return template[key]
                end,
            })
        end
        local moduleOk, moduleConfigured = pcall(configureMode, 3)
        gameApi.res.streetTemplateRep.get = originalGet
        assert(moduleOk, "module-cost mode must not read per-metre prices: " .. tostring(moduleConfigured))
        assertEqual(
            moduleConfigured.updateScript.params.trackCostProfiles["custom.track"].perMetre,
            nil,
            "module mode does not capture unused per-metre prices"
        )
    end

    do
        local wrapped = runModScript(nil, nil, nil, nil, function(builder)
            local original = builder.createTemplateScript
            builder.createTemplateScript = {
                fileName = "compatibility_test::/template.script@create",
                params = { callback = original.fileName, arguments = original.params },
            }
            builder.params[#builder.params + 1] = { key = "other_mod_param", values = { "Preserved" } }
        end)
        local builder = configuredBuilders[wrapped]
        assertEqual(builder.createTemplateScript.fileName, "compatibility_test::/template.script@create", "template wrapper is preserved")
        assertEqual(builder.createTemplateScript.params.callback, "zigzag.template.script@createTemplateFn", "wrapped callback is preserved")
        assert(#builder.createTemplateScript.params.arguments.tracks > 0, "wrapped template captures receive track choices")
        assertEqual(builder.params[#builder.params].key, "other_mod_param", "other mods' builder controls are preserved")
    end

    do
        local originalCost = templates["custom.track"].cost
        templates["custom.track"].cost = -1
        local configured = configureMode(2)
        local warningsBefore = #loggedWarnings
        local result = runRestrictedUpdateWithCapture(configured.updateScript.params, { streetTemplate = "custom.track", catenary = 1 })
        assertEqual(result.cost, 0, "unusable track cost uses the logged zero-price fallback")
        assertEqual(#loggedWarnings, warningsBefore + 1, "unusable selected cost is logged")
        templates["custom.track"].cost = originalCost
    end

    do
        local template = templates["custom.track"]
        local originalRadius = template.minCurveRadius
        for _, invalidRadius in ipairs({ -1, math.huge, 0 / 0, "55" }) do
            template.minCurveRadius = invalidRadius
            local configured = configureMode(1)
            assertEqual(configured.updateScript.params.trackMinimumRadiiMetres["custom.track"], nil, "invalid radius metadata is not captured")
            assert(
                runRestrictedUpdateWithCapture(configured.updateScript.params, { streetTemplate = "custom.track" }),
                "invalid modded radius metadata preserves straight stations"
            )
            local ok, message =
                pcall(runRestrictedUpdateWithCapture, configured.updateScript.params, { streetTemplate = "custom.track", signedStartCurveRadiusMetres = 300 })
            assert(not ok and tostring(message):find("no minimum-radius data", 1, true), "curved stations require valid selected-track radius data")
        end
        template.minCurveRadius = originalRadius
    end
end

(function()
    local function assertNear(actual, expected, tolerance, context)
        assert(math.abs(actual - expected) <= tolerance, string.format("%s: expected %.12g, got %.12g", context, expected, actual))
    end

    local curveCapture = defaultCostConstruction.updateScript.params
    local radiusErrorTemplate = _("apasz_zigzag_curve_radius_too_small")
    local validationMetadata = require("apasz_zigzag::/zigzag/validation_metadata.lua")
    local validator = loadData("content/stations/rail/zigzag/zigzag.selection.script.lua")
    local function validateResults(results, expectedMessages)
        local additions = {}
        for _, result in ipairs(results) do
            additions[#additions + 1] = { construction = { persistentMetadata = result.metadata } }
        end
        local proposal = {
            old2new = {},
            toRemove_native = {
                size = function()
                    return 0
                end,
            },
            toAdd_native = {
                size = function()
                    return #additions
                end,
                at = function(_, index)
                    return additions[index]
                end,
            },
        }
        for _, event in ipairs({ "builder.proposalCreate", "builder.proposalPrepareForApply" }) do
            local result = validator.guiHandleEvent({}, {}, {}, "", "constructionBuilder", event, { proposal, {} })
            if expectedMessages == nil then
                assertEqual(result, nil, "valid and unrelated proposals are left unchanged")
            else
                local expected = {}
                for _, message in ipairs(expectedMessages) do
                    expected[message] = true
                end
                assertSameResult(result.errorMessages, expected, "native builder errors")
            end
        end
        assertEqual(
            validator.guiHandleEvent({}, {}, {}, "", "constructionBuilder", "builder.proposalApply", { proposal, {} }),
            nil,
            "completed builds are left unchanged"
        )
    end
    validateResults({}, nil)
    validateResults({ {}, { metadata = { unrelated = { "Other mod" } } } }, nil)
    local startParam, endParam = construction.params[4], construction.params[5]
    assertEqual(startParam.key, "signedStartCurveRadiusMetres", "start radius control follows length")
    assertEqual(endParam.key, "signedEndCurveRadiusMetres", "end radius control follows start")
    assertEqual(startParam.name, "apasz_zigzag_start_curve_radius", "start control label")
    assertEqual(endParam.name, "apasz_zigzag_end_curve_radius", "end control label")
    for _, param in ipairs({ startParam, endParam }) do
        assertEqual(param.uiType, "Slider", "independent curve slider")
        assertEqual(param.numbers[param.defaultIndex], 0, "straight by default")
        assertEqual(param.checkEnabledScript, nil, "curve slider is always visible")
        assertEqual(param.numbers[1], -2000, "left endpoint of curve slider")
        assertEqual(param.numbers[#param.numbers], 2000, "right endpoint of curve slider")
        assertEqual(param.values[1], "-2000 m", "negative radius label")
        assertEqual(param.values[#param.values], "+2000 m", "positive radius label")
        assertEqual(param.values[param.defaultIndex], "0 (apasz_zigzag_straight)", "straight label")
        assertSameResult(param.numbers, startParam.numbers, "both controls use the same steps")
        for index, radius in ipairs(param.numbers) do
            assertEqual(radius, -param.numbers[#param.numbers + 1 - index], "symmetric curve steps")
            if index > 1 then
                assert(radius > param.numbers[index - 1], "curve slider is sorted")
            end
        end
    end
    assertEqual(curveCapture.trackMinimumRadiiMetres["standard.track"], 55, "native build-radius limit")
    assertEqual(curveCapture.trackMinimumRadiiMetres["::/industries/shared/industry_track/industry.street_template"], 55, "hidden saved track has radius data")

    local function assertPointOnHalf(point, offset, radius, tolerance)
        assertNear(point[3], 0, 1e-12, "track stays level")
        if radius == 0 then
            assertNear(point[1], offset, tolerance, "straight half stays straight")
        else
            local distance = math.sqrt((point[1] - radius) ^ 2 + point[2] ^ 2)
            assertNear(distance, math.abs(radius - offset), tolerance, "concentric half radius")
        end
    end

    local function assertNodeOnHalf(node, offset, radius)
        local point, tangent = node[1], node[2]
        assertPointOnHalf(point, offset, radius, 1e-9)
        if radius == 0 then
            assertNear(tangent[1], 0, 1e-12, "straight half tangent")
        else
            assertNear((point[1] - radius) * tangent[1] + point[2] * tangent[2], 0, 1e-7, "tangent follows half circle")
        end
    end

    local function distanceFromMidpoint(point, offset, radius)
        if radius == 0 then
            return math.abs(point[2])
        end
        local physicalRadius = math.abs(radius - offset)
        local chord = math.sqrt((point[1] - offset) ^ 2 + point[2] ^ 2)
        return 2 * physicalRadius * math.asin(chord / (2 * physicalRadius))
    end

    local function halfLengthScale(radius, offset)
        return radius == 0 and 1 or math.abs(radius - offset) / math.abs(radius)
    end

    local function checkLayout(params)
        local result = runRestrictedUpdateWithCapture(curveCapture, params)
        local track = result.edgeLists[1]
        local sub = result.subconstructions[1]
        local station = sub.station
        local startRadius, endRadius = params.signedStartCurveRadiusMetres or 0, params.signedEndCurveRadiusMetres or 0
        local trackCount, spacing, length = params.tracks, params.trackSpacingMetres, params.lengthMetres
        local loading = params.passengerLoadingEnabled == 2 or params.cargoLoadingEnabled == 2
        local function radiusAt(y)
            return y < 0 and startRadius or endRadius
        end
        assertEqual(#track.snapNodes, trackCount * 2, "two endpoints per track")
        assertEqual(#station.terminals, trackCount * (loading and 2 or 1), "terminal count")
        assertUniqueTerminalVehicleNodes(station.terminals, track, "independent stop nodes")
        assertNoOverlappingLaneEdges(sub.laneLists, "independent loading lanes")
        assertNear(result.cost, length * trackCount / 40 * moduleCostRates["standard.track"].construction, 1e-7, "independent curves preserve total track cost")
        for i = 1, trackCount do
            local offset = (i - (trackCount + 1) / 2) * spacing
            local physicalLength = length / 2 * (halfLengthScale(startRadius, offset) + halfLengthScale(endRadius, offset))
            local first, last = track.snapNodes[2 * i - 1] + 1, track.snapNodes[2 * i] + 1
            assert(first < last and first % 2 == 1 and last % 2 == 0, "valid endpoint indices")
            local centreNodeCount = 0
            for nodeIndex = first, last do
                local node = track.edges[nodeIndex]
                assertNodeOnHalf(node, offset, radiusAt(node[1][2]))
                if node[1][2] == 0 then
                    centreNodeCount = centreNodeCount + 1
                    assertNear(node[1][1], offset, 1e-12, "shared midpoint")
                    assertNear(node[2][1], 0, 1e-12, "shared midpoint heading")
                    assert(node[2][2] > 0, "midpoint tangent has forward direction")
                end
            end
            assertEqual(centreNodeCount, 2, "both halves meet at the midpoint")
            for nodeIndex = first, last - 1, 2 do
                local a, b = track.edges[nodeIndex], track.edges[nodeIndex + 1]
                local radius = radiusAt((a[1][2] + b[1][2]) / 2)
                local ta, tb = math.atan(a[2][1], a[2][2]), math.atan(b[2][1], b[2][2])
                assert(math.abs(tb - ta) <= math.rad(10) + 1e-12, "bounded segment turn")
                if nodeIndex + 2 <= last then
                    local following = track.edges[nodeIndex + 2]
                    for axis = 1, 3 do
                        assertNear(b[1][axis], following[1][axis], 1e-9, "continuous edge positions")
                    end
                    local cross = b[2][1] * following[2][2] - b[2][2] * following[2][1]
                    local dot = b[2][1] * following[2][1] + b[2][2] * following[2][2]
                    assert(dot > 0 and math.abs(cross) <= 1e-9 * dot, "no tangent kink between edges")
                end
                for sample = 1, 3 do
                    local t = sample / 4
                    local h0, h1 = 2 * t ^ 3 - 3 * t ^ 2 + 1, t ^ 3 - 2 * t ^ 2 + t
                    local h2, h3 = -2 * t ^ 3 + 3 * t ^ 2, t ^ 3 - t ^ 2
                    local point = {}
                    for axis = 1, 3 do
                        point[axis] = h0 * a[1][axis] + h1 * a[2][axis] + h2 * b[1][axis] + h3 * b[2][axis]
                    end
                    assertPointOnHalf(point, offset, radius, math.max(math.abs(radius - offset) * 3e-6, 1e-9))
                end
            end
            for endpoint, radius in ipairs({ startRadius, endRadius }) do
                local nodeIndex = endpoint == 1 and first or last
                assertNear(
                    distanceFromMidpoint(track.edges[nodeIndex][1], offset, radius),
                    length / 2 * halfLengthScale(radius, offset),
                    1e-9,
                    "physical half length"
                )
                if i > 1 then
                    local previousIndex = track.snapNodes[2 * (i - 1) - (2 - endpoint)] + 1
                    local previous, current = track.edges[previousIndex][1], track.edges[nodeIndex][1]
                    assertNear(
                        math.sqrt((current[1] - previous[1]) ^ 2 + (current[2] - previous[2]) ^ 2),
                        spacing,
                        1e-9,
                        "constant track spacing at both endpoints"
                    )
                end
            end
            if loading then
                local passenger, cargo = station.terminals[2 * i - 1], station.terminals[2 * i]
                local passengerStop = track.edges[passenger.vehicleNode[2] + 1][1]
                local cargoStop = track.edges[cargo.vehicleNode[2] + 1][1]
                assert(passengerStop[2] < 0 and cargoStop[2] > 0, "stops straddle the midpoint")
                assertNear(distanceFromMidpoint(passengerStop, offset, startRadius), 0.5, 1e-9, "passenger stop offset")
                assertNear(distanceFromMidpoint(cargoStop, offset, endRadius), 0.5, 1e-9, "cargo stop offset")
                for _, terminal in ipairs({ passenger, cargo }) do
                    local lane = sub.laneLists[terminal.personNodes[1][1] + 1]
                    if #terminal.cargoTransferSpeeds > 0 then
                        assertEqual(#terminal.personEdges, #lane.nodes / 2, "all loading edges referenced")
                        local centre = lane.nodes[terminal.personNodes[1][2] + 1][1]
                        assertNear(centre[2], 0, 1e-12, "loading centre-node reference")
                        assertNear(terminal.cargoTransferSpeeds[1].length, physicalLength, 1e-9, "physical loading length")
                        local laneOffset = offset + (terminal.passengers and -0.5 or 0.5)
                        for _, node in ipairs(lane.nodes) do
                            assertNodeOnHalf(node, laneOffset, radiusAt(node[1][2]))
                        end
                    end
                end
            else
                local stop = track.edges[station.terminals[i].vehicleNode[2] + 1][1]
                assertNear(stop[1], offset, 1e-12, "non-loading stop stays centred")
                assertNear(stop[2], 0, 1e-12, "non-loading stop stays at origin heading")
            end
        end
        if loading then
            for index, catchment in ipairs(station.catchmentAreas) do
                local radius = radiusAt(catchment.position[2])
                assertPointOnHalf(catchment.position, 0, radius, 1e-9)
                assertNear(distanceFromMidpoint(catchment.position, 0, radius), index == 2 and 0 or length / 2, 1e-9, "catchment follows each half")
            end
        end
        if params.passengerLoadingEnabled == 2 then
            for accessIndex = trackCount * 2 + 1, #sub.laneLists do
                local access = sub.laneLists[accessIndex]
                for _, node in ipairs(access.nodes) do
                    local connections = 0
                    for laneIndex = 1, trackCount * 2, 2 do
                        for _, serviceNode in ipairs(sub.laneLists[laneIndex].nodes) do
                            if pointKey(node[1]) == pointKey(serviceNode[1]) then
                                connections = connections + 1
                            end
                        end
                    end
                    if node ~= access.nodes[1] and node ~= access.nodes[#access.nodes] then
                        assert(connections > 0, "passenger access connects to each service lane")
                    end
                end
            end
        end
        return result
    end

    for _, startRadius in ipairs(startParam.numbers) do
        for _, endRadius in ipairs(endParam.numbers) do
            for _, length in ipairs({ 5, 440 }) do
                for _, count in ipairs({ 1, 8 }) do
                    for passengerMode = 1, 2 do
                        for cargoMode = 1, 2 do
                            local params = {
                                signedStartCurveRadiusMetres = startRadius,
                                signedEndCurveRadiusMetres = endRadius,
                                lengthMetres = length,
                                tracks = count,
                                trackSpacingMetres = 20,
                                passengerLoadingEnabled = passengerMode,
                                cargoLoadingEnabled = cargoMode,
                            }
                            local requiredRadius = math.max(55 + (count - 1) * 10, length / math.pi)
                            local rejectedEnd = startRadius ~= 0 and math.abs(startRadius) < requiredRadius and "start"
                                or (endRadius ~= 0 and math.abs(endRadius) < requiredRadius and "end" or nil)
                            local result = checkLayout(params)
                            if rejectedEnd == nil then
                                assertEqual(result.metadata, nil, "valid curves need no validation metadata")
                            else
                                local messages = validationMetadata.get(result.metadata)
                                local expected = {}
                                for _, side in ipairs({ { "start", startRadius }, { "end", endRadius } }) do
                                    if side[2] ~= 0 and math.abs(side[2]) < requiredRadius then
                                        expected[#expected + 1] = "apasz_zigzag_"
                                            .. side[1]
                                            .. "_curve_radius: "
                                            .. string.format(radiusErrorTemplate, math.abs(side[2]), math.ceil(requiredRadius))
                                    end
                                end
                                assertSameResult(messages, expected, "validation identifies each rejected end and minimum radius")
                                validateResults({ {}, result, result }, messages)
                                assertEqual(params.signedStartCurveRadiusMetres, startRadius, "start radius is never changed")
                                assertEqual(params.signedEndCurveRadiusMetres, endRadius, "end radius is never changed")
                            end
                        end
                    end
                end
            end
        end
    end

    for passengerMode = 1, 2 do
        for cargoMode = 1, 2 do
            local params = {
                signedStartCurveRadiusMetres = 0,
                signedEndCurveRadiusMetres = 0,
                lengthMetres = 440,
                tracks = 8,
                trackSpacingMetres = 20,
                passengerLoadingEnabled = passengerMode,
                cargoLoadingEnabled = cargoMode,
            }
            local straight = runRestrictedUpdateWithCapture(curveCapture, params)
            params.signedStartCurveRadiusMetres, params.signedEndCurveRadiusMetres = nil, nil
            assertSameResult(straight, runRestrictedUpdateWithCapture(curveCapture, params), "zero radii preserve the straight layout")
        end
    end
    do
        local committedCapture = {}
        for key, value in pairs(curveCapture) do
            committedCapture[key] = value
        end
        committedCapture.curveRadiiMetres, committedCapture.trackMinimumRadiiMetres = nil, nil
        assertSameResult(
            runRestrictedUpdateWithCapture(committedCapture, {}),
            runRestrictedUpdateWithCapture(curveCapture, {}),
            "committed capture parameters still build straight stations"
        )
    end
    for _, key in ipairs({ startParam.key, endParam.key }) do
        for _, radius in ipairs({ -99, 99, -2001, 2001 }) do
            assertEqual(pcall(script.updateFn, curveCapture, { [key] = radius }), false, "invalid end radius rejected")
        end
    end

    local function buildShape(startRadius, endRadius)
        return checkLayout({
            signedStartCurveRadiusMetres = startRadius,
            signedEndCurveRadiusMetres = endRadius,
            lengthMetres = 120,
            tracks = 3,
            trackSpacingMetres = 20,
            passengerLoadingEnabled = 2,
            cargoLoadingEnabled = 2,
        })
    end
    local left, right = buildShape(-300, -300), buildShape(300, 300)
    for i, leftIndex in ipairs(left.edgeLists[1].snapNodes) do
        local reversedTrack = 3 - math.floor((i - 1) / 2)
        local rightIndex = right.edgeLists[1].snapNodes[2 * reversedTrack - (i % 2)]
        local a, b = left.edgeLists[1].edges[leftIndex + 1], right.edgeLists[1].edges[rightIndex + 1]
        assertNear(a[1][1], -b[1][1], 1e-9, "left and right endpoint mirror")
        assertNear(a[1][2], b[1][2], 1e-9, "left and right longitudinal mirror")
    end
    local oneEnd, sCurve = buildShape(0, -300), buildShape(-300, 300)
    buildShape(-500, 0)
    local centreStartIndex, centreEndIndex = sCurve.edgeLists[1].snapNodes[3] + 1, sCurve.edgeLists[1].snapNodes[4] + 1
    assert(sCurve.edgeLists[1].edges[centreStartIndex][1][1] < 0 and sCurve.edgeLists[1].edges[centreEndIndex][1][1] > 0, "opposite signs make an S-curve")
    for index, expected in ipairs({ 197, 204, 211 }) do
        assertEqual(oneEnd.subconstructions[1].station.terminals[2 * index - 1].capacity, expected, "asymmetric passenger capacity")
        assertEqual(
            sCurve.subconstructions[1].station.terminals[2 * index - 1].cargoTransferSpeeds[1].length,
            120,
            "equal opposite curves balance physical track length"
        )
    end
    for _, signedRadius in ipairs({ 300, 500 }) do
        local mixed = buildShape(signedRadius, -150)
        local changedEnd = buildShape(signedRadius, 1000)
        local changedStart = buildShape(-1000, -150)
        local function centreTrackEndpoints(result)
            local track = result.edgeLists[1]
            return track.edges[track.snapNodes[3] + 1][1], track.edges[track.snapNodes[4] + 1][1]
        end
        local first, last = centreTrackEndpoints(mixed)
        local fixedStart, movedEnd = centreTrackEndpoints(changedEnd)
        local movedStart, fixedEnd = centreTrackEndpoints(changedStart)
        for axis = 1, 3 do
            assertEqual(first[axis], fixedStart[axis], "changing end leaves start fixed")
            assertEqual(last[axis], fixedEnd[axis], "changing start leaves end fixed")
        end
        assert(first[1] ~= movedStart[1] and last[1] ~= movedEnd[1], "each slider changes its own end")
    end

    local params =
        { signedStartCurveRadiusMetres = -300, signedEndCurveRadiusMetres = 500, lengthMetres = 120, streetTemplate = "standard.track", catenary = 1 }
    script.upgradeFn(construction.upgradeScript.params, params, 0, { catenary = 2 })
    assertEqual(params.signedStartCurveRadiusMetres, -300, "catenary upgrade preserves start radius")
    assertEqual(params.signedEndCurveRadiusMetres, 500, "catenary upgrade preserves end radius")
    assertEqual(runRestrictedUpdateWithCapture(curveCapture, params).edgeLists[1].params.type, "standard_catenary.track", "asymmetric catenary upgrade")
    do
        local capture = {}
        for key, value in pairs(curveCapture) do
            capture[key] = value
        end
        capture.trackMinimumRadiiMetres = { ["high_speed.track"] = 350 }
        script.upgradeFn(construction.upgradeScript.params, params, 0, { streetTemplate = "high_speed.track" })
        local result = runRestrictedUpdateWithCapture(capture, params)
        local messages = validationMetadata.get(result.metadata)
        assertEqual(#messages, 1, "upgrades validate the new track's radius at each end")
        assert(messages[1]:find("Use at least 350 m", 1, true), "upgrade uses new track minimum")
        validateResults({ result }, messages)
        assertEqual(params.signedStartCurveRadiusMetres, -300, "rejected upgrade preserves start radius")
        assertEqual(params.signedEndCurveRadiusMetres, 500, "rejected upgrade preserves end radius")
    end

    local builder = configuredBuilders[defaultCostConstruction]
    local templateScript = loadData("content/stations/rail/zigzag/zigzag.template.script.lua")
    local built = runRestrictedCallback(
        templateScript.createTemplateFn,
        builder.createTemplateScript.params,
        { signedStartCurveRadiusMetres = -500, signedEndCurveRadiusMetres = 300, lengthMetres = 440 }
    )
    local saved = built.constructions[1].params
    assertEqual(saved.signedStartCurveRadiusMetres, -500, "template persists start radius")
    assertEqual(saved.signedEndCurveRadiusMetres, 300, "template persists end radius")
    assert(#runRestrictedUpdateWithCapture(curveCapture, saved).edgeLists[1].edges > 8, "saved asymmetric placement regenerates subdivided geometry")
end)()

do
    local function checkCargoStorage()
        local storage = require("apasz_zigzag::/zigzag/cargo_storage.lua")
        local validationMetadata = require("apasz_zigzag::/zigzag/validation_metadata.lua")
        local expectedCapacities = { 0, 250, 500, 1000, 2000, 5000 }
        local control = constructionTemplate.params[#constructionTemplate.params]
        assertEqual(control.key, "cargoStorageCapacity", "shared warehouse control")
        assertSameResult(control.numbers, expectedCapacities, "warehouse capacity choices")
        assertEqual(control.numbers[control.defaultIndex], 0, "warehouse defaults to off")
        assertEqual(control.checkEnabledScript, nil, "warehouse capacity is always visible")
        assertEqual(control.uiType, "Slider", "warehouse uses a numeric slider")
        assertEqual(control.values[1], "0 (apasz_zigzag_off)", "disabled capacity label")

        for _, invalid in ipairs({ -1, 1, 499, 5001, math.huge, 0 / 0, false, true, "500" }) do
            local ok, message = pcall(runRestrictedUpdateWithCapture, defaultCostParams, { cargoStorageCapacity = invalid })
            assert(not ok and tostring(message):find("invalid cargo storage capacity", 1, true), "invalid storage capacity fails loudly")
        end
        assertSameResult(
            runRestrictedUpdateWithCapture(defaultCostParams, { cargoStorageCapacity = 0 }),
            runRestrictedUpdateWithCapture(defaultCostParams, {}),
            "off preserves existing station results"
        )

        for modeIndex, mode in ipairs({ "NO_COST", "TRACK_COST", "MODULE_COST", "STATION_COST" }) do
            local configured = runModScript({ [currentModId] = { apasz_zigzag_costs_enabled = modeIndex } }, 1.5, 2)
            local capture = configured.updateScript.params
            assertEqual(capture.costMode, mode, "warehouse cost mode")
            local charged = mode == "MODULE_COST" or mode == "STATION_COST"
            if charged then
                assertEqual(capture.cargoStorageCostProfiles.UNIVERSAL.construction, 300, "vanilla warehouse construction rate removes scale")
                assertEqual(capture.cargoStorageCostProfiles.UNIVERSAL.maintenance, 50, "vanilla warehouse maintenance rate")
            else
                assertEqual(next(capture.cargoStorageCostProfiles), nil, "uncharged modes capture no warehouse prices")
            end
            for _, capacity in ipairs(expectedCapacities) do
                for _, tracks in ipairs({ 1, 8 }) do
                    for passenger = 1, 2 do
                        for cargo = 1, 2 do
                            local params = {
                                cargoStorageCapacity = capacity,
                                tracks = tracks,
                                lengthMetres = 120,
                                signedStartCurveRadiusMetres = -300,
                                signedEndCurveRadiusMetres = 500,
                                passengerLoadingEnabled = passenger,
                                cargoLoadingEnabled = cargo,
                            }
                            local result = runRestrictedUpdateWithCapture(capture, params)
                            local stored = result.subconstructions[2]
                            params.cargoStorageCapacity = nil
                            local without = runRestrictedUpdateWithCapture(capture, params)
                            assertSameResult(result.edgeLists, without.edgeLists, "storage preserves track geometry")
                            assertSameResult(result.subconstructions[1], without.subconstructions[1], "storage preserves terminals and loading lanes")
                            assertEqual(result.cost - without.cost, charged and capacity * 300 or 0, "warehouse construction cost is station-wide")
                            assertEqual(result.maintenanceCost - without.maintenanceCost, charged and capacity * 50 or 0, "warehouse upkeep is station-wide")
                            if capacity == 0 then
                                assertEqual(stored, nil, "off adds no warehouse")
                            else
                                assertEqual(#result.subconstructions, 2, "one shared warehouse for every track")
                                assertEqual(storage.metadata.get(result.metadata), capacity, "storage capacity is persisted for validation")
                                assertEqual(stored.tag, storage.subconstructionTag, "stable warehouse identity")
                                assertEqual(type(stored.warehouse), "table", "native warehouse marker")
                                for _, key in ipairs({ "colliders", "terrainAlignmentLists", "groundFaces", "laneLists" }) do
                                    assertEqual(#stored[key], 0, "storage has no extra visible footprint or duplicate lanes")
                                end
                                assertEqual(#stored.models, 1, "warehouse has one invisible location anchor")
                                assertEqual(stored.models[1].id, "apasz_zigzag::/zigzag/cargo_storage.mdl", "warehouse uses its own invisible model")
                                assertSameResult(
                                    stored.models[1].transf,
                                    { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
                                    "warehouse stays at station midpoint"
                                )
                                assertEqual(#stored.stocks, 1, "one universal stock")
                                local stock = stored.stocks[1]
                                assertEqual(stock.tag, storage.stockTag, "stable stock identity")
                                assertEqual(stock.type, "STORAGE_STOCK", "native storage stock")
                                assertEqual(stock.capacity, capacity, "total shared capacity")
                                assertEqual(stock.mixedTypes, true, "mixed freight shares capacity")
                                assertEqual(stock.loadSpeedModifier, 1, "native universal loading modifier")
                                assertSameResult(
                                    stock.cargoTypes,
                                    { cargoClassesIncluded = { "UNIVERSAL" }, cargoTypesExcluded = { "::/cargos/passengers/passengers.cargo" } },
                                    "freight-only universal stock"
                                )
                            end
                        end
                    end
                end
            end
        end
        do
            local anchor = loadData("content/zigzag/cargo_storage.mdl")
            assertEqual(anchor.version, 2, "native model format")
            assertEqual(anchor.collider.type, "NONE", "warehouse anchor has no collision")
            assertEqual(#anchor.lods, 1, "warehouse anchor has a valid LOD")
            assertEqual(#anchor.lods[1].node.children, 0, "warehouse anchor has no visible mesh")
            for axis = 1, 3 do
                assert(anchor.boundingInfo.bbMin[axis] < 0 and anchor.boundingInfo.bbMax[axis] > 0, "warehouse has finite bounds centred on the station")
            end
        end
        do
            local originalFind = gameApi.res.moduleRep.find
            gameApi.res.moduleRep.find = function(name)
                assert(name ~= storage.profiles[1].moduleName, "free and track modes must not read warehouse pricing")
                return originalFind(name)
            end
            for mode = 1, 2 do
                runModScript({ [currentModId] = { apasz_zigzag_costs_enabled = mode } })
            end
            gameApi.res.moduleRep.find = originalFind
        end
        do
            local module = moduleResources[storage.profiles[1].moduleName]
            local previousMetadata = module.metadata
            for _, rate in ipairs({ { construction = 0, maintenance = 0 }, { construction = 225000, maintenance = 40000 } }) do
                module.metadata = { price = rate.construction, maintenanceCost = rate.maintenance }
                local configured = runModScript({ [currentModId] = { apasz_zigzag_costs_enabled = 3 } }, 1.5, 2)
                local capture = configured.updateScript.params
                local without = runRestrictedUpdateWithCapture(capture, {})
                local withStorage = runRestrictedUpdateWithCapture(capture, { cargoStorageCapacity = 1000 })
                assertEqual(withStorage.cost - without.cost, rate.construction * 2, "storage follows modified and zero-price vanilla module costs")
                assertEqual(
                    withStorage.maintenanceCost - without.maintenanceCost,
                    rate.maintenance * 2,
                    "storage follows modified and zero-price vanilla module upkeep"
                )
            end
            module.metadata = previousMetadata
        end
        do
            local params = { cargoStorageCapacity = 500, cargoLoadingEnabled = 2, signedStartCurveRadiusMetres = -300, signedEndCurveRadiusMetres = 500 }
            local before = runRestrictedUpdateWithCapture(defaultCostParams, params).subconstructions[2]
            script.upgradeFn(construction.upgradeScript.params, params, 0, { catenary = 2 })
            params.tracks, params.lengthMetres = 8, 440
            params.signedStartCurveRadiusMetres, params.signedEndCurveRadiusMetres = 1000, -1000
            params.cargoLoadingEnabled = 1
            local after = runRestrictedUpdateWithCapture(defaultCostParams, params).subconstructions[2]
            assertSameResult(after, before, "warehouse identity survives loading, track, length, curve and catenary edits")
            local builder = configuredBuilders[defaultCostConstruction]
            local template = loadData("content/stations/rail/zigzag/zigzag.template.script.lua")
            local built = runRestrictedCallback(template.createTemplateFn, builder.createTemplateScript.params, params)
            assertEqual(built.constructions[1].params.cargoStorageCapacity, 500, "template persists warehouse capacity")
        end

        local previousApi = _G.api
        local components, amounts, owners, names = {}, {}, {}, {}
        local countReads = 0
        local function existingStore(parent, child, stockList, capacity, amount)
            local metadata = {}
            storage.metadata.set(metadata, capacity)
            components[parent] = { CONSTRUCTION = { persistentMetadata = metadata, subconstructions = { child }, params = {} } }
            components[child] = { SUBCONSTRUCTION = { tag = storage.subconstructionTag }, WAREHOUSE = { stockList = stockList } }
            components[stockList] = { STOCK_LIST = { stocks = { { tag = storage.stockTag } } } }
            amounts[stockList], names[parent] = amount, "Zigzag " .. tostring(parent)
        end
        existingStore(101, 201, 301, 1000, 600)
        existingStore(102, 202, 302, 500, 300)
        components[103] = { CONSTRUCTION = { persistentMetadata = {}, subconstructions = {}, params = {} } }
        components[401] = { STATION_GROUP = { stations = { 501, 501, 502, 503 } } }
        owners[501], owners[502], owners[503] = 101, 102, 103
        local editable = { [101] = true, [102] = false }
        _G.api = {
            type = {
                ComponentType = {
                    CONSTRUCTION = "CONSTRUCTION",
                    SUBCONSTRUCTION = "SUBCONSTRUCTION",
                    STOCK_LIST = "STOCK_LIST",
                    WAREHOUSE = "WAREHOUSE",
                    STATION_GROUP = "STATION_GROUP",
                },
            },
            engine = {
                entityExists = function(entity)
                    return components[entity] ~= nil
                end,
                getComponent = function(entity, kind)
                    return components[entity] and components[entity][kind]
                end,
                util = {
                    getEntityName = function(entity)
                        return names[entity]
                    end,
                },
                system = {
                    simEntityAtStockSystem = {
                        getStockCount = function(entity, stockId)
                            assertEqual(stockId, 0, "native stock IDs start at zero")
                            countReads = countReads + 1
                            return assert(amounts[entity])
                        end,
                    },
                    streetConnectorSystem = {
                        getConstructionEntityForStation = function(entity)
                            return owners[entity]
                        end,
                    },
                },
            },
        }
        local function vector(values)
            return {
                size = function()
                    return #values
                end,
                at = function(_, index)
                    return assert(values[index])
                end,
            }
        end
        local function added(capacity, radiusError)
            local metadata = {}
            if capacity > 0 then
                storage.metadata.set(metadata, capacity)
            end
            if radiusError then
                validationMetadata.set(metadata, { radiusError })
            end
            return { construction = { persistentMetadata = metadata } }
        end
        local function proposal(capacity, radiusError)
            return {
                toAdd_native = vector({ added(0), added(capacity, radiusError) }),
                old2new = { [101] = 1 },
                toRemove_native = vector({ 101, 201, 103 }),
            }
        end
        local validator = loadData("content/stations/rail/zigzag/zigzag.selection.script.lua")
        local function validate(value, event)
            return validator.guiHandleEvent({}, {}, {}, "", "constructionBuilder", event or "builder.proposalCreate", { value, {} })
        end
        local messageTemplate = _("apasz_zigzag_cargo_storage_too_small")
        for _, event in ipairs({ "builder.proposalCreate", "builder.proposalPrepareForApply" }) do
            local result = validate(proposal(500, "Radius rejected"), event)
            assertSameResult(
                result.errorMessages,
                { [string.format(messageTemplate, 600, 500)] = true, ["Radius rejected"] = true },
                "capacity and curve validation combine"
            )
            local readsBefore = countReads
            assertEqual(validate(proposal(1000), event), nil, "unchanged storage survives edits")
            assertEqual(validate(proposal(2000), event), nil, "capacity can increase")
            assertEqual(countReads, readsBefore, "unchanged or larger capacity needs no cargo query")
            amounts[301] = 500
            assertEqual(validate(proposal(500), event), nil, "capacity equal to current contents is allowed")
            amounts[301] = 0
            assertEqual(validate(proposal(0), event), nil, "empty warehouse can be disabled")
            amounts[301] = 600
        end
        amounts[301] = 400
        assertEqual(validate(proposal(500)), nil, "preview can be valid before a delivery")
        amounts[301] = 600
        assert(validate(proposal(500), "builder.proposalPrepareForApply"), "new deliveries are checked again before applying")
        local demolition = { toAdd_native = vector({}), old2new = {}, toRemove_native = vector({ 101 }) }
        assert(validate(demolition), "filled warehouse cannot be removed by bulldozing")
        amounts[301] = 0
        assertEqual(validate(demolition), nil, "empty warehouse can be bulldozed")
        amounts[301] = 600
        local multiple = { toAdd_native = vector({ added(500), added(250) }), old2new = { [101] = 0, [102] = 1 }, toRemove_native = vector({ 101, 102 }) }
        local readsBefore = countReads
        local errors = validate(multiple).errorMessages
        assertEqual(countReads - readsBefore, 2, "each replaced warehouse is checked once")
        assertSameResult(
            errors,
            { [string.format(messageTemplate, 600, 500)] = true, [string.format(messageTemplate, 300, 250)] = true },
            "multiple warehouses are independently protected"
        )
        local stock = components[301].STOCK_LIST.stocks[1]
        stock.tag = -1
        assertEqual(pcall(validate, proposal(500)), false, "mismatched stock identities fail loudly")
        stock.tag = storage.stockTag
        local parent = components[101].CONSTRUCTION
        local previousSubconstructions = parent.subconstructions
        for _, invalid in ipairs({
            { children = {}, message = "no warehouse" },
            { children = { 201, 201 }, message = "multiple storage warehouses" },
            { children = { 299 }, message = "missing subconstruction" },
        }) do
            parent.subconstructions = invalid.children
            local ok, message = pcall(storage.removalErrors, parent, nil)
            assert(not ok and tostring(message):find(invalid.message, 1, true), "invalid storage layout fails with an explicit error")
        end
        parent.subconstructions = previousSubconstructions

        local point = {}
        local stockWidget = function() end
        local dependencies = {
            ["::/gui/main/builtin.lua"] = {
                type = { Orientation = { Vertical = "Vertical" } },
                BoxLayout = function(params)
                    return { params = params }
                end,
            },
            ["::/gui/main/react.lua"] = {
                RegisterPluginRecipe = function(extension, name, body)
                    assertEqual(extension, point, "use the native station window extension point")
                    assertEqual(name, "ZigzagCargoStocks", "namespaced stock recipe")
                    return body
                end,
            },
            ["::/gui/main/engine_react_util.tl"] = {
                useStepState = function(makeState)
                    return { old = makeState }
                end,
            },
            ["::/gui/main/content_card.tl"] = {
                ContentCard = function(params)
                    return { params = params }
                end,
                makeRecipeAndParam = function(recipe, params)
                    return { recipe = recipe, param = params }
                end,
            },
            ["::/gui/entity_window/entity_window_util.tl"] = { EntityStockCountsWidget = stockWidget },
            ["::/scripts/entity_util.tl"] = {
                isOwnedByPlayerOrNotOwned = function(entity)
                    assert(editable[entity] ~= nil, "ownership is checked for each warehouse's construction")
                    return editable[entity]
                end,
            },
            ["::/gui/entity_window/station_group/station_group_eow.script.tl"] = { StationGroupEowExtensionPoint = point },
            ["apasz_zigzag::/zigzag/cargo_storage.lua"] = storage,
            ["apasz_zigzag::/zigzag/logger.lua"] = require("apasz_zigzag::/zigzag/logger.lua"),
        }
        local previousRequire = _G.ug_require
        _G.ug_require = function(name)
            return assert(dependencies[name], name)
        end
        local gui = loadData("content/gui/zigzag/cargo_storage.script.lua")
        _G.ug_require = previousRequire
        local config = loadData("content/gui/zigzag/cargo_storage.res.lua")
        assertEqual(config.type, "react-plugin ::StationGroupEowExtensionPoint", "stock panel resource type")
        assertEqual(config.data.filePath, "apasz_zigzag::/gui/zigzag/cargo_storage.script@Stocks", "stock panel callback resource")
        local params = { entityId = 401, gameCtx = {}, showCalloutOnRightSide = true }
        local cards = gui.Stocks(params).params.children
        assertEqual(#cards, 2, "grouped Zigzags have one stock card each; other stations have none")
        for index, card in ipairs(cards) do
            assertEqual(card.params.recipeAndParamPermanent.recipe, stockWidget, "reuse the native stock display")
            local widget = card.params.recipeAndParamPermanent.param
            assertEqual(widget.entityId, 300 + index, "stock widget receives stock list entity")
            assertEqual(widget.addDiscardCargoButtons, editable[100 + index], "discard permissions follow each warehouse's owner")
            assertEqual(card.params.hasPermanentFocusables, editable[100 + index], "read-only cards have no editing focus targets")
            assertEqual(card.params.title, "apasz_zigzag_cargo_storage — Zigzag " .. tostring(100 + index), "stock cards identify their own construction")
            assertEqual(widget.addButtonsToSetStockCargoType, false, "mixed universal stock has no specialization picker")
            assertEqual(card.params.gameCtx, params.gameCtx, "native game context is preserved")
        end
        assert(cards[1].params.meta.localKey ~= cards[2].params.meta.localKey, "grouped storage cards have distinct identities")
        components[101].CONSTRUCTION.params.cargoStorageType = 2
        assertEqual(
            gui.Stocks(params).params.children[1].params.recipeAndParamPermanent.param.addButtonsToSetStockCargoType,
            true,
            "specialised storage exposes the native cargo selector"
        )
        editable[101] = false
        assertEqual(
            gui.Stocks(params).params.children[1].params.recipeAndParamPermanent.param.addButtonsToSetStockCargoType,
            false,
            "foreign specialised storage cannot change cargo selections"
        )
        assertEqual(gui.Stocks(params).params.children[1].params.recipeAndParamPermanent.param.addDiscardCargoButtons, false, "foreign storage is read-only")
        components[401].STATION_GROUP.stations = { 503 }
        assertEqual(gui.Stocks(params), nil, "unrelated station groups have no storage panel")
        components[401] = nil
        assertEqual(gui.Stocks(params), nil, "closed or removed groups have no storage panel")
        _G.api = previousApi
    end
    checkCargoStorage()
end

do
    local function checkSpecialisedStorage()
        local storage = require("apasz_zigzag::/zigzag/cargo_storage.lua")
        local typeControl = constructionTemplate.params[#constructionTemplate.params - 1]
        assertEqual(typeControl.key, "cargoStorageType", "warehouse selector precedes capacity")
        assertEqual(typeControl.defaultIndex, 1, "universal storage remains the default")
        assertEqual(#typeControl.values, 5, "all native warehouse categories are available")
        local specialisedBays = storage.makeBays(500, 2, "MODULE_BAYS")
        for _, invalid in ipairs({ false, true, 0, "" }) do
            local ok, message = pcall(storage.makeStocks, specialisedBays, storage.profiles[2], {
                [specialisedBays[1].tag] = invalid,
            })
            assert(not ok and tostring(message):find("invalid pinned cargo", 1, true),
                "invalid cargo selections must not silently become unrestricted storage")
        end
        assert(not pcall(storage.makeStocks, specialisedBays, storage.profiles[2], false),
            "invalid cargo selection maps fail explicitly")
        for _, invalid in ipairs({ 0, -1, 6, 1.5, math.huge, 0 / 0, false, true, "2" }) do
            local ok, message = pcall(runRestrictedUpdateWithCapture, defaultCostParams, { cargoStorageType = invalid })
            assert(not ok and tostring(message):find("invalid cargo storage type", 1, true), "invalid warehouse types fail loudly")
        end
        for modeIndex, mode in ipairs({ "NO_COST", "TRACK_COST", "MODULE_COST", "STATION_COST" }) do
            for layoutIndex, layout in ipairs(storage.bayLayouts) do
                local configured = runModScript({
                    [currentModId] = {
                        apasz_zigzag_costs_enabled = modeIndex,
                        apasz_zigzag_storage_bay_layout = layoutIndex,
                    },
                })
                local single = configuredSingleBayConstruction
                local selected = layout == "SINGLE_BAY" and single or configured
                assertEqual(configured.updateScript.params.storageBayLayout, "MODULE_BAYS", "original construction keeps modular bays")
                assertEqual(single.updateScript.params.storageBayLayout, "SINGLE_BAY", "single-bay construction keeps its layout")
                local builder = configuredBuilders[selected]
                local placed = runRestrictedCallback(
                    loadData("content/stations/rail/zigzag/zigzag.template.script.lua").createTemplateFn,
                    builder.createTemplateScript.params,
                    { cargoStorageType = 2, cargoStorageCapacity = 1000 }
                )
                assert(
                    placed.constructions[1].constructionFileName:find(layout == "SINGLE_BAY" and "zigzag_single_bay.con" or "zigzag.con", 1, true),
                    "mod setting chooses a persistent construction resource for new stations"
                )
                local capture = selected.updateScript.params
                local charged = mode == "MODULE_COST" or mode == "STATION_COST"
                local noStore = runRestrictedUpdateWithCapture(capture, {})
                for typeIndex, profile in ipairs(storage.profiles) do
                    for _, capacity in ipairs(storage.capacities) do
                        local result = runRestrictedUpdateWithCapture(capture, { cargoStorageType = typeIndex, cargoStorageCapacity = capacity })
                        local factor = profile.mixedTypes and 1 or 2
                        assertEqual(result.cost - noStore.cost, charged and capacity * 300 * factor or 0, "type-specific storage construction rate")
                        assertEqual(result.maintenanceCost - noStore.maintenanceCost, charged and capacity * 50 * factor or 0, "type-specific storage upkeep")
                        if capacity > 0 then
                            local stocks = result.subconstructions[2].stocks
                            local count = 1
                            if not profile.mixedTypes and layout == "MODULE_BAYS" then
                                count = math.ceil(capacity / 500)
                            end
                            assertEqual(#stocks, count, "selected bay layout")
                            local total = 0
                            local tags = {}
                            for _, stock in ipairs(stocks) do
                                assertEqual(stock.cargoTypes.cargoClassesIncluded[1], profile.kind, "native specialised cargo class")
                                assertEqual(stock.mixedTypes, profile.mixedTypes, "specialised bays hold one cargo type")
                                assertEqual(stock.loadSpeedModifier, profile.loadSpeedModifier, "native loading speed")
                                assert(not tags[stock.tag], "each bay has a unique stock tag")
                                tags[stock.tag], total = true, total + stock.capacity
                            end
                            assertEqual(total, capacity, "bay capacity sums to selected station capacity")
                            local params = { cargoStorageType = typeIndex, cargoStorageCapacity = capacity, tagToCargoType = {} }
                            params.tagToCargoType[stocks[1].tag] = "test::/chosen.cargo"
                            local pinned = runRestrictedUpdateWithCapture(capture, params).subconstructions[2].stocks
                            local expectedCargo
                            if not profile.mixedTypes then
                                expectedCargo = "test::/chosen.cargo"
                            end
                            assertEqual(pinned[1].cargoType, expectedCargo, "native cargo selections survive regeneration")
                            params.tracks, params.lengthMetres, params.catenary = 8, 440, 2
                            assertSameResult(
                                runRestrictedUpdateWithCapture(capture, params).subconstructions[2].stocks,
                                pinned,
                                "layout, length and electrification edits preserve stock identities and selections"
                            )
                        end
                    end
                end
            end
        end
        for _, invalid in ipairs({ 0, 3, 1.5 }) do
            assert(not pcall(runModScript, { [currentModId] = { apasz_zigzag_storage_bay_layout = invalid } }), "invalid bay mod setting fails loudly")
        end
        local function result(capacity, kind)
            return runRestrictedUpdateWithCapture(defaultCostParams, { cargoStorageCapacity = capacity, cargoStorageType = kind or 2 })
        end
        local original = result(1000)
        local proposed = { result(0), result(250), result(500), result(1000, 3), result(2000) }
        local previousApi = _G.api
        local parent = { persistentMetadata = original.metadata, subconstructions = { 201 } }
        local stockList = { stocks = { original.subconstructions[2].stocks[2], original.subconstructions[2].stocks[1] } }
        local amounts, reads = { [0] = 100, [1] = 0 }, 0
        _G.api = {
            type = { ComponentType = { SUBCONSTRUCTION = "SUBCONSTRUCTION", WAREHOUSE = "WAREHOUSE", STOCK_LIST = "STOCK_LIST" } },
            engine = {
                getComponent = function(entity, kind)
                    if kind == "SUBCONSTRUCTION" then
                        return { tag = storage.subconstructionTag }
                    end
                    if kind == "WAREHOUSE" then
                        return { stockList = 301 }
                    end
                    if kind == "STOCK_LIST" then
                        return stockList
                    end
                    error("unexpected storage query")
                end,
                system = {
                    simEntityAtStockSystem = {
                        getStockCount = function(entity, stockId)
                            assertEqual(entity, 301, "read the warehouse stock list")
                            reads = reads + 1
                            return assert(amounts[stockId])
                        end,
                    },
                },
            },
        }
        local before = reads
        assertEqual(#storage.removalErrors(parent, proposed[5].metadata), 0, "capacity increases preserve every bay")
        assertEqual(reads, before, "unchanged bays need no live cargo query")
        assertEqual(
            #storage.removalErrors(parent, proposed[3].metadata),
            1,
            "occupied removed bay is blocked even when total cargo fits the new capacity and stocks are reordered"
        )
        assertEqual(
            storage.removalErrors(parent, proposed[3].metadata)[1],
            string.format(_("apasz_zigzag_storage_bay_too_small"), 2, 100, 0),
            "error identifies the affected bay and its contents"
        )
        assertEqual(#storage.removalErrors(parent, proposed[4].metadata), 1, "changing category cannot remove occupied bays")
        assertEqual(#storage.removalErrors(parent, proposed[1].metadata), 1, "disabling occupied specialised storage is blocked")
        amounts[0], amounts[1] = 0, 100
        assertEqual(#storage.removalErrors(parent, proposed[3].metadata), 0, "empty trailing bays can be removed")
        assertEqual(#storage.removalErrors(parent, proposed[2].metadata), 0, "partial bay can shrink to fit its contents")
        amounts[1] = 300
        assertEqual(#storage.removalErrors(parent, proposed[2].metadata), 1, "partial bay shrink is checked independently")
        amounts[1] = 0
        assertEqual(#storage.removalErrors(parent, proposed[4].metadata), 0, "empty warehouse can change category")
        assertEqual(#storage.removalErrors(parent, nil), 0, "empty specialised warehouse can be demolished")
        _G.api = previousApi
    end
    checkSpecialisedStorage()
end

if arg[2] then
    assert(loadfile("tests/mod_compatibility_check.lua"))()({
        api = gameApi,
        templates = templates,
        templateResourceNames = templateResourceNames,
        templateIds = templateIds,
        menuCategories = menuCategories,
        builders = configuredBuilders,
        runModScript = runModScript,
        runUpdate = runRestrictedUpdateWithCapture,
        assertSameResult = assertSameResult,
    }, assert(loadfile(arg[2]))())
end

print("zigzag_check: ok")
