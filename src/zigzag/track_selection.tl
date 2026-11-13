local TRACK_PARAM_KEY = "apasz_zigzag_track_variant"
local CATENARY_DISABLED_INDEX: integer = 1
local CATENARY_ENABLED_INDEX: integer = 2
local ZERO_COST_RATE: ZigzagCostRate = { construction = 0, maintenance = 0 }

local function costRate(
    profile: ZigzagTrackCostProfile | nil,
    mode: ZigzagCostMode
): ZigzagCostRate | nil
    if mode == "NO_COST" then
        return ZERO_COST_RATE
    end
    if mode ~= "TRACK_COST" and mode ~= "MODULE_COST" and mode ~= "STATION_COST" then
        error("Zigzag Station received invalid cost mode " .. tostring(mode))
    end
    if profile == nil then
        return nil
    end
    local availableProfile = profile as ZigzagTrackCostProfile
    if mode == "TRACK_COST" then
        return availableProfile.perMetre
    end
    return availableProfile.perModule
end

local function catenaryIndex(enabled: boolean): integer
    return enabled and CATENARY_ENABLED_INDEX or CATENARY_DISABLED_INDEX
end

local function catenaryEnabled(index: integer | nil): boolean
    local catenary = index or CATENARY_DISABLED_INDEX
    if catenary ~= CATENARY_DISABLED_INDEX and catenary ~= CATENARY_ENABLED_INDEX then
        error("Zigzag Station received invalid catenary index " .. tostring(catenary))
    end
    return catenary == CATENARY_ENABLED_INDEX
end

local function supportsTransportMode(
    template: StreetTemplate,
    transportMode: TransportMode
): boolean
    for _, lane in ipairs(template.laneConfigs) do
        if lane.transportModes[transportMode] then
            return true
        end
    end
    return false
end

local function isRailwayTrack(template: StreetTemplate): boolean
    return template.roadType == api.type["enum"].RoadType.TRACK
        and supportsTransportMode(template, api.type["enum"].TransportMode.TRAIN)
end

local function isAvailable(track: ZigzagTrackChoice, year: integer): boolean
    return (track.yearFrom == 0 or track.yearFrom <= year)
        and (track.yearTo == 0 or year < track.yearTo)
end

local function makeParams(tracks: {ZigzagTrackChoice}): {ConstructionScriptParam}
    local boundaries: {integer} = { 0 }
    local seen: {integer: boolean} = { [0] = true }
    for _, track in ipairs(tracks) do
        for _, year in ipairs({ track.yearFrom, track.yearTo }) do
            if not seen[year] then
                seen[year] = true
                boundaries[#boundaries + 1] = year
            end
        end
    end
    table.sort(boundaries)

    local params: {ConstructionScriptParam} = {}
    for boundaryIndex, yearFrom in ipairs(boundaries) do
        local labels: {string} = {}
        local numbers: {number} = {}
        for trackIndex, track in ipairs(tracks) do
            if isAvailable(track, yearFrom) then
                labels[#labels + 1] = track.name
                numbers[#numbers + 1] = trackIndex
            end
        end
        if #numbers > 0 then
            params[#params + 1] = {
                key = TRACK_PARAM_KEY,
                name = _("Track Type"),
                values = labels,
                numbers = numbers,
                defaultIndex = 1,
                uiType = "ComboBox" as ConstructionScriptParam.Type,
                yearFrom = yearFrom,
                yearTo = boundaries[boundaryIndex + 1] or 0,
            }
        end
    end
    return params
end

local function resolveTrack(
    tracks: {ZigzagTrackChoice},
    selectedIndex: integer | nil,
    year: integer
): ZigzagTrackChoice
    if selectedIndex ~= nil then
        local track = tracks[selectedIndex as integer]
        if track == nil then
            error("Zigzag Station received invalid track variant " .. tostring(selectedIndex))
        end
        if not isAvailable(track, year) then
            error("Zigzag Station track is unavailable in year "
                .. tostring(year) .. ": " .. track.resourceName)
        end
        return track
    end
    for _, track in ipairs(tracks) do
        if isAvailable(track, year) then
            return track
        end
    end
    error("Zigzag Station has no available railway tracks in year " .. tostring(year))
end

local selection: ZigzagTrackSelection = {
    paramKey = TRACK_PARAM_KEY,
    zeroCostRate = ZERO_COST_RATE,
    costRate = costRate,
    supportsTransportMode = supportsTransportMode,
    isRailwayTrack = isRailwayTrack,
    catenaryIndex = catenaryIndex,
    catenaryEnabled = catenaryEnabled,
    isAvailable = isAvailable,
    makeParams = makeParams,
    resolve = resolveTrack,
}

return selection
