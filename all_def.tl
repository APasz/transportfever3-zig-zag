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

global record ZigzagPlatformCostProfile
    yearFrom: integer
    passenger: ZigzagCostRate
    cargo: ZigzagCostRate
end

global data: function(): any
