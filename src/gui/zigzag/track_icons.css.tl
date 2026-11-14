local type Size = {integer, integer}

local record TrackStyle
    size: Size | nil
    minSize: Size | nil
    maxSize: Size | nil
    innerSpacing: Size | nil
    gravity: {number, number}
    textAutoWrap: boolean | nil
    textAlignment: {number, number} | nil
end

local record SelectorLevel
    classList: {string}
end

local record StyleRule
    levels: {SelectorLevel}
    styleSheet: TrackStyle
end

local record StylesheetUtil
    makeAdder: function({StyleRule}): function(string, TrackStyle)
end

local record ConstructionSizes
    ParamsWindowWidth: number
end

local type LuaChunk = function(): any

local record FileResolver
    loadfile: function(string): LuaChunk | nil, string | nil
end

global resolveutil: FileResolver

local stylesheetUtil = ug_require "::/gui/main/stylesheetutil.lua" as StylesheetUtil
local CONSTRUCTION_SIZES_PATH = "::/gui/construction/construction_sizes.lua"
-- Build 40425 hardcodes this panel width and has no construction_sizes.lua.
local FALLBACK_PARAMS_WINDOW_WIDTH = 400
local ICON_SIZE: Size = { 48, 30 }
local ROW_GAP = 8
-- Reserve the native entry padding, dropdown arrow and panel insets.
local DROPDOWN_CHROME_WIDTH = 64

local function paramsWindowWidth(): number
    -- A failed require leaves the native loader's path stack unbalanced.
    local chunk, loadError = resolveutil.loadfile(CONSTRUCTION_SIZES_PATH)
    if chunk == nil then
        if loadError == "Could not find file " .. CONSTRUCTION_SIZES_PATH then
            return FALLBACK_PARAMS_WINDOW_WIDTH
        end
        error(loadError or "Unable to load " .. CONSTRUCTION_SIZES_PATH)
    end

    local sizes = ug_require(CONSTRUCTION_SIZES_PATH) as ConstructionSizes
    local width = sizes.ParamsWindowWidth
    if type(width) ~= "number" or not (width > 0 and width < math.huge) then
        error("Zigzag Station requires a finite positive ParamsWindowWidth")
    end
    return width
end

local TRACK_NAME_MAX_WIDTH = math.floor(
    paramsWindowWidth() - ICON_SIZE[1] - ROW_GAP - DROPDOWN_CHROME_WIDTH
)

function data(): {StyleRule}
    local rules: {StyleRule} = {}
    local add = stylesheetUtil.makeAdder(rules)
    add("!apasz-zigzag-track-row", { innerSpacing = { ROW_GAP, 0 }, gravity = { -1, 0.5 } })
    add("TextView!apasz-zigzag-track-name", {
        maxSize = { TRACK_NAME_MAX_WIDTH, -1 },
        textAutoWrap = true,
        textAlignment = { 0, 0.5 },
        gravity = { -1, 0.5 },
    })
    add("!apasz-zigzag-track-icon", {
        size = ICON_SIZE,
        minSize = ICON_SIZE,
        maxSize = ICON_SIZE,
        gravity = { 0, 0.5 },
    })
    return rules
end
