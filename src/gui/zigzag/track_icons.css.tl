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

local stylesheetUtil = ug_require "::/gui/main/stylesheetutil.lua" as StylesheetUtil
local constructionSizes = ug_require "::/gui/construction/construction_sizes.lua" as ConstructionSizes
local ICON_SIZE: Size = { 48, 30 }
local ROW_GAP = 8
-- Reserve the native entry padding, dropdown arrow and panel insets.
local DROPDOWN_CHROME_WIDTH = 64
local TRACK_NAME_MAX_WIDTH = math.floor(
    constructionSizes.ParamsWindowWidth - ICON_SIZE[1] - ROW_GAP - DROPDOWN_CHROME_WIDTH
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
