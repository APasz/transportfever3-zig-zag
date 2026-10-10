local function assertEqual(actual, expected, context)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
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
            local firstCurve = assert(curves[1], "lane has no curve")
            local firstPoint = assert(firstCurve[1], "lane has no first point")
            local lastPoint = assert(firstCurve[#firstCurve], "lane has no last point")
            local tangent = {
                lastPoint[1] - firstPoint[1],
                lastPoint[2] - firstPoint[2],
                lastPoint[3] - firstPoint[3],
            }
            return {
                nodes = {
                    { firstPoint, tangent, width },
                    { lastPoint, tangent, width },
                },
                transportModes = transportModes,
                speedLimit = speedLimit,
                linkable = linkable,
            }
        end,
    }
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

_G.api = {
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

local construction = loadData("content/stations/rail/zigzag/zigzag.con.lua")
local expectedLengthsMetres = { 10, 40, 80, 120, 160, 240, 320 }
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
assertEqual(construction.constructionTemplates[1].description.icon, "zigzag.tga", "menu icon")
assertEqual(
    construction.constructionTemplates[1].description.previewIcon,
    "zigzag_preview.tga",
    "menu preview icon"
)
assertEqual(#construction.constructionTemplates[1].data.params, 0, "template-specific parameter count")
assertEqual(#construction.params[1].values, #expectedLengthsMetres, "length option count")
assertEqual(construction.params[1].name, "apasz_zigzag_length", "length localization key")
assertEqual(construction.params[1].defaultIndex, 1, "default 10-metre length index")
for index, lengthMetres in ipairs(expectedLengthsMetres) do
    assertEqual(
        construction.params[1].values[index],
        tostring(lengthMetres) .. " m",
        "length label " .. tostring(index)
    )
end
assertEqual(construction.params[2].defaultIndex, 2, "default-era standard track")
assertEqual(construction.params[3].defaultIndex, 2, "high-speed-era standard track")

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

local script = loadData("content/stations/rail/zigzag/zigzag.script.lua")
assertEqual(type(script.createTemplateFn), "function", "template callback")
assertEqual(next(script.createTemplateFn({}, {})), nil, "empty initial module set")
local captureParams = construction.updateScript.params

local function runRestrictedUpdate(params)
    local resourceApi = _G.api.res
    _G.api.res = nil
    local ok, resultOrError = pcall(script.updateFn, captureParams, params)
    _G.api.res = resourceApi
    assert(ok, resultOrError)
    return resultOrError
end

for lengthIndex, lengthMetres in ipairs(expectedLengthsMetres) do
    local lengthResult = runRestrictedUpdate({ length = lengthIndex })
    local lengthTrack = lengthResult.edgeLists[1]
    local halfLength = lengthMetres / 2
    assertEqual(
        lengthTrack.edges[1][1][2],
        -halfLength,
        "negative endpoint for length option " .. tostring(lengthIndex)
    )
    assertEqual(
        lengthTrack.edges[4][1][2],
        halfLength,
        "positive endpoint for length option " .. tostring(lengthIndex)
    )
    assertEqual(
        lengthResult.cost,
        lengthMetres * captureParams.costPerMetre,
        "cost for length option " .. tostring(lengthIndex)
    )
    assertEqual(
        lengthResult.maintenanceCost,
        lengthMetres * captureParams.maintenanceCostPerMetre,
        "maintenance cost for length option " .. tostring(lengthIndex)
    )
end

local result = runRestrictedUpdate({})

assertEqual(#result.edgeLists, 1, "track edge-list count")
local track = result.edgeLists[1]
assertEqual(track.type, "TRACK", "edge-list type")
assertEqual(track.params.type, "standard.track", "selected track type")
assertEqual(#track.edges, 4, "track node count")
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

local customTrackResult = runRestrictedUpdate({
    length = 1,
    streetTemplate = "custom.track",
    catenary = 1,
})
assertEqual(customTrackResult.edgeLists[1].params.type, "custom.track", "custom track template")
assertEqual(
    #customTrackResult.subconstructions[1].station.terminals[1].transportModes,
    1,
    "non-electrified custom-track terminal mode count"
)

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
    length = 1,
    trackType = 3,
    catenary = 2,
})
assertEqual(catenaryResult.edgeLists[1].params.type, "high_speed_catenary.track", "catenary track")
local catenaryTerminal = catenaryResult.subconstructions[1].station.terminals[1]
assertEqual(#catenaryTerminal.transportModes, 2, "electrified terminal mode count")
assertEqual(catenaryTerminal.transportModes[1], "TRAIN", "electrified train mode")
assertEqual(catenaryTerminal.transportModes[2], "ELECTRIC_TRAIN", "electrified train mode")

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
    trackType = 2,
    catenary = 1,
}, 0, {
    catenary = 2,
})
assertEqual(upgradedParams.streetTemplate, "standard_catenary.track", "catenary upgrade template")
assertEqual(upgradedParams.catenary, 2, "catenary upgrade state")

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

print("zigzag_check: ok")
