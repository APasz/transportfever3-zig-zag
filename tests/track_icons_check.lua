local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function loadData(path)
    _G.data = nil
    assert(loadfile(path))()
    assert(type(_G.data) == "function", path .. " requires data()")
    return data()
end

local builtin = { type = { Orientation = { Horizontal = "horizontal", Vertical = "vertical" }, ImageViewScaling = { AutoFit = "fit" } } }
for _, kind in ipairs({ "Component", "BoxLayout", "TextView", "ImageView", "ComboBoxItem", "ComboBox" }) do
    builtin[kind] = function(params) return { kind = kind, params = params } end
end
local componentKinds = { Component = true, TextView = true, ImageView = true, ComboBox = true }
local comboBoxItem = builtin.ComboBoxItem
builtin.ComboBoxItem = function(params)
    assert(componentKinds[params.content.kind], "ComboBoxItem content must be a UI component, not a layout")
    return comboBoxItem(params)
end
local stepCallbacks = {}
local react = {
    onStep = function(callback) stepCallbacks[#stepCallbacks + 1] = callback end,
    RegisterRecipe = function(name, body)
        local function render(...)
            local child = body(...)
            assert(child == nil or child.kind == "BoxLayout", name .. ": recipe child must be a layout")
            return child
        end
        return function(params, ...)
            return { kind = name, params = params, body = render, extra = table.pack(...) }
        end
    end,
}
local selection = assert(loadfile("content/zigzag/track_selection.lua"))()
local dependencies = {
    ["::/gui/main/builtin.lua"] = builtin,
    ["/gui/main/builtin.lua"] = builtin,
    ["::/gui/main/react.lua"] = react,
    ["/scripts/table_util.tl"] = { shallowCopy = copy },
    ["::/scripts/table_util.tl"] = { shallowCopy = copy },
    ["/gui/main/engine_react_util.tl"] = {},
    ["/gui/main/callout_react_util.tl"] = {},
    ["/scripts/lang_util.tl"] = {},
    ["/scripts/mathutil.lua"] = {},
    ["apasz_zigzag::/zigzag/track_selection.lua"] = selection,
    ["apasz_zigzag::/zigzag/logging.lua"] = assert(loadfile("content/zigzag/logging.lua"))(),
}
_G.ug_require = function(name) return assert(dependencies[name], name) end
_G.api = { type = { ["enum"] = { ScriptParamType = { ComboBox = 3, Button = 1, Slider = 2, IconButton = 4, CheckBox = 5 } } } }

local nativeRendererPath = assert(arg[1], "run through tests/track_icons_check.py")
local util = assert(loadfile(nativeRendererPath))()
local nativeRenderer = util.buildScriptParamCompSimple
local priorRenderCalls = 0
util.buildScriptParamCompSimple = function(...)
    priorRenderCalls = priorRenderCalls + 1
    return nativeRenderer(...)
end

local function buildSelector(param)
    stepCallbacks = {}
    local node = util.buildScriptParamCompSimple(param)
    local localKey
    if node.kind == "ZigzagTrackSelector" then
        localKey = node.params.meta.localKey
        node = node.body(node.params)
        assert(#node.params.children == 1, "selector recipe has one native control")
        node = node.params.children[1]
    end
    return node, stepCallbacks, localKey
end

local owned = {
    key = selection.paramKey, name = "Track Type", values = {
        "Standard", "1435 mm Y-shaped steel sleepers – von Roll rack railway with third rail", "No image",
    },
    numbers = { 4, 12, 30 }, tooltips = { "Normal track", "Electric track" },
    defaultIndex = 1, uiType = 3, yearFrom = 1900, yearTo = 0,
}
local earlier = copy(owned)
earlier.numbers, earlier.values, earlier.yearFrom, earlier.yearTo = { 4 }, { "Early track" }, 1850, 1900
local unrelated = copy(owned)
unrelated.key = "other_mod_track"
unrelated.makeCompactButtonFn = function() error("unrelated compact icon callback was invoked") end
local definitions = {
    { resName = "apasz_zigzag::/stations/rail/zigzag/zigzag.metacon", params = { owned, earlier, unrelated } },
    { resName = "another_mod::/station.metacon", params = { unrelated } },
}
local definitionCalls = 0
local construction = { getConstructionDefinitions = function()
    definitionCalls = definitionCalls + 1
    return definitions
end }
local metadataReads = 0
local function sourceParams()
    metadataReads = metadataReads + 1
    local currentSource = copy(owned)
    -- Metadata order differs from the menu, and the selected values are not row indices.
    currentSource.numbers, currentSource.images = { 30, 4, 12 }, { "", "base::/standard.tga", "pack::/third_rail.tga" }
    local earlySource = copy(earlier)
    earlySource.images = { "pack::/early.tga" }
    return { earlySource, currentSource }
end

local warnings = {}
_G.log = { warning = function(message) warnings[#warnings + 1] = message end }
api.res = {
    metaConstructionRep = {
        find = function(name)
            assert(name == definitions[1].resName, "unrelated resource was queried")
            return 0
        end,
        get = function(id)
            assert(id == 0, "native metaconstruction lookup accepts resource ID zero")
            return { params = sourceParams() }
        end,
    },
}
dependencies["::/gui/construction/construction_react_util.tl"] = construction
dependencies["::/gui/main/script_param_util.tl"] = util

local function uiParams(param, options)
    -- These are exactly the fields forwarded by the archived construction UI.
    local result = {
        scriptParam = { name = param.name, values = param.values, numbers = param.numbers,
            tooltips = param.tooltips, defaultIndex = param.defaultIndex, uiType = param.uiType,
            makeCompactButtonFn = param.makeCompactButtonFn, hideLabel = false },
        currentValue = 12,
        onValueChange = function(value) _G.selectedTrack = value end,
    }
    for key, value in pairs(options or {}) do result[key] = value end
    return result
end

local before = buildSelector(uiParams(owned))
assert(before.kind == "ComboBox" and before.params.items[1].params.content.kind == "TextView")
local config = loadData("content/gui/zigzag/track_icons.res.lua")
assert(config.type == "react-replacement-config", "GUI bootstrap resource type")
assert(config.data.filePath == "apasz_zigzag::/gui/zigzag/track_icons.script", "namespaced GUI bootstrap callback")
local extension = loadData("content/gui/zigzag/track_icons.script.lua")
extension[config.data.doReplaceFn]({})
local installedBuild, installedDefinitions = util.buildScriptParamCompSimple, construction.getConstructionDefinitions
extension.install({})
assert(util.buildScriptParamCompSimple == installedBuild and construction.getConstructionDefinitions == installedDefinitions, "installation is idempotent")
local decorated = construction.getConstructionDefinitions()[1].params
assert(metadataReads == 1, "metadata is read once for all availability periods")
assert(decorated[3] == unrelated and definitions[2].params[1] == unrelated, "other mods' parameters remain unchanged")
assert(decorated[1] ~= owned and owned.makeCompactButtonFn == nil, "the source menu parameter is preserved")

local attention = function() end
local result, _, currentPeriodKey = buildSelector(uiParams(decorated[1], { onHover = attention }))
assert(result.kind == "ComboBox" and result.params.value == 12)
assert(result.params.meta.onAttention == attention, "native focus/hover callback is retained")
for index, expected in ipairs({ "base::/standard.tga", "pack::/third_rail.tga" }) do
    local item = result.params.items[index]
    assert(item.params.value == owned.numbers[index], "catalogue IDs remain unchanged")
    local row = item.params.content
    assert(row.kind == "Component" and row.params.layout.kind == "BoxLayout")
    assert(row.params.layout.params.meta.class == "apasz-zigzag-track-row", "row spacing targets the layout")
    local children = row.params.layout.params.children
    assert(children[1].kind == "ImageView" and children[1].params.path == expected, "icon matches the catalogue ID")
    assert(children[2].kind == "TextView" and children[2].params.text == owned.values[index], "track name remains visible")
    assert(children[2].params.tooltipWhenClipped == owned.values[index], "full track name remains available if clipped")
    assert(row.params.meta.tooltip == owned.tooltips[index])
end
assert(result.params.items[3].params.content.kind == "TextView", "missing icon falls back to text")
result.params.onValueChange(30)
assert(selectedTrack == 30, "native callback receives the exact catalogue ID")
assert(not pcall(result.params.onValueChange, "30"), "invalid numeric selection is rejected")
assert(metadataReads == 1, "rendering performs no resource lookups")

local early, _, earlyPeriodKey = buildSelector(uiParams(decorated[2], { currentValue = 4 }))
assert(early.params.items[1].params.content.params.layout.params.children[1].params.path == "pack::/early.tga", "availability periods have their own icons")
assert(currentPeriodKey ~= earlyPeriodKey, "period changes reset native compact-button state")
local expired, expirySteps = buildSelector(uiParams(decorated[2], { currentValue = 12 }))
assert(expired.params.value == 4, "expired selections display the first available track")
assert(selectedTrack == 30, "rendering does not mutate native selection state")
for _, step in ipairs(expirySteps) do step() end
assert(selectedTrack == 4, "the next UI step updates native stored selection")
local retained, retainedSteps = buildSelector(uiParams(decorated[1], { currentValue = selectedTrack }))
for _, step in ipairs(retainedSteps) do step() end
assert(retained.params.value == 4 and selectedTrack == 4, "the replacement remains selected when more tracks become available")
local expiredCompact = buildSelector(uiParams(decorated[2], { currentValue = 12, compact = true }))
assert(expiredCompact.params.currentValue == 4, "compact selectors normalize expired selections")
local expiredCompactRow = decorated[2].makeCompactButtonFn(12)
assert(expiredCompactRow.params.layout.params.children[2].params.text == "Early track", "retained native compact state also uses the first available track")
assert(not pcall(expired.params.onValueChange, 12), "new selections must belong to the current availability period")

local callsBefore = priorRenderCalls
local other = buildSelector(uiParams(unrelated))
assert(other.params.items[1].params.content.kind == "TextView")
assert(priorRenderCalls == callsBefore + 1, "same-name foreign selector delegates to the existing renderer")

local compact = buildSelector(uiParams(decorated[1], { compact = true }))
assert(compact.kind == "ScriptParamToggleCalloutButton", "native compact callout remains in use")
assert(compact.params.compact == false)
local compactRow = compact.params.scriptParam.makeCompactButtonFn(compact.params.currentValue)
assert(componentKinds[compactRow.kind], "compact button content must also be a UI component")
assert(compactRow.params.layout.params.children[1].params.path == "pack::/third_rail.tga", "compact button shows the selected track icon")
local compactContent = buildSelector(compact.params)
assert(compactContent.kind == "ComboBox" and compactContent.params.items[1].params.content.kind == "Component", "native callout receives icon rows")

local wrapped = buildSelector(uiParams(decorated[1], { vertical = true, addSpacer = true, onHover = attention }))
assert(wrapped.kind == "Component" and wrapped.params.meta.class == "script-param-wrap,script-param-wrap-combobox")
local wrappedChildren = wrapped.params.layout.params.children
assert(wrappedChildren[1].params.meta.onAttention == attention)
assert(wrappedChildren[2].kind == "ComboBox" and wrappedChildren[3].params.meta.class == "settings-spacer-right", "native label layout and spacer remain in use")

construction.getConstructionDefinitions()
assert(metadataReads == 1, "cached definitions do not recreate renderers")
assert(definitionCalls == 2, "definition wrapper preserves the previous implementation")
assert(#warnings == 0, "normal icon metadata produces no warnings")

do
    local previousBuild = util.buildScriptParamCompSimple
    local laterCalls = 0
    util.buildScriptParamCompSimple = function(...)
        laterCalls = laterCalls + 1
        return previousBuild(...)
    end
    local later = buildSelector(uiParams(decorated[1]))
    assert(laterCalls == 1 and later.params.items[1].params.content.kind == "Component", "later GUI wrappers can delegate to the icon renderer")
end

do
    local noIcons = copy(owned)
    noIcons.images = { "", "", "" }
    definitions[1].params = { copy(owned) }
    api.res.metaConstructionRep.get = function() return { params = { noIcons } } end
    local withoutIcons = construction.getConstructionDefinitions()[1].params[1]
    local plain = buildSelector(uiParams(withoutIcons))
    for _, item in ipairs(plain.params.items) do
        assert(item.params.content.kind == "TextView", "empty icons use text-only rows")
    end
    local compactText = withoutIcons.makeCompactButtonFn(12)
    assert(compactText.kind == "TextView" and compactText.params.text == owned.values[2], "compact mode also falls back to text when all icons are empty")
    assert(compactText.params.tooltipWhenClipped == owned.values[2], "text-only selectors retain the full name tooltip")
end

do
    local duplicate = copy(owned)
    duplicate.numbers = { 4, 4, 30 }
    definitions[1].params = { duplicate }
    api.res.metaConstructionRep.get = function() return { params = sourceParams() } end
    local ok, message = pcall(construction.getConstructionDefinitions)
    assert(not ok and tostring(message):find("duplicate track selector value", 1, true), "duplicate numeric IDs cannot silently overwrite rows")
end

do
    definitions[1].params = { copy(owned) }
    api.res.metaConstructionRep.find = function() return -1 end
    local stale = construction.getConstructionDefinitions()[1].params[1]
    local staleDropdown = buildSelector(uiParams(stale))
    assert(staleDropdown.params.items[1].params.content.kind == "TextView", "missing native metadata keeps a usable text selector")
    assert(#warnings == 1, "missing native metadata is logged")
    definitions[1].params = { copy(owned) }
    construction.getConstructionDefinitions()
    assert(#warnings == 1, "metadata warnings are not repeated")
end

do
    local implicit = copy(owned)
    implicit.numbers, implicit.images = {}, { "one.tga", "two.tga", "three.tga" }
    definitions[1].params = { copy(implicit) }
    api.res.metaConstructionRep.find = function() return 0 end
    api.res.metaConstructionRep.get = function() return { params = { implicit } } end
    local implicitPicker = construction.getConstructionDefinitions()[1].params[1]
    local implicitResult = buildSelector(uiParams(implicitPicker, { currentValue = 2 }))
    assert(implicitResult.params.items[2].params.value == 2, "empty native number arrays use default indices")
    assert(implicitResult.params.items[2].params.content.params.layout.params.children[1].params.path == "two.tga")
end

do
    definitions[1].params = { copy(owned) }
    api.res.metaConstructionRep.get = function() return { params = { owned, copy(owned) } } end
    local ok, message = pcall(construction.getConstructionDefinitions)
    assert(not ok and tostring(message):find("duplicate track selector period", 1, true), "ambiguous period metadata fails explicitly")
end

do
    local duplicateSource = copy(owned)
    duplicateSource.numbers, duplicateSource.images = { 4, 4, 30 }, { "", "two.tga", "three.tga" }
    definitions[1].params = { copy(owned) }
    api.res.metaConstructionRep.get = function() return { params = { duplicateSource } } end
    local ok, message = pcall(construction.getConstructionDefinitions)
    assert(not ok and tostring(message):find("duplicate track icon metadata value", 1, true), "duplicate metadata IDs cannot assign another track's icon")
end

for _, value in ipairs({ 0, -1, 1.5, math.huge, 0 / 0 }) do
    local invalid = copy(owned)
    invalid.numbers = { value, 12, 30 }
    definitions[1].params = { invalid }
    api.res.metaConstructionRep.get = function() return { params = sourceParams() } end
    local ok, message = pcall(construction.getConstructionDefinitions)
    assert(not ok and tostring(message):find("track selector has an invalid value", 1, true), "catalogue IDs must be finite positive integers")
end

do
    local empty = copy(owned)
    empty.values, empty.numbers = {}, {}
    definitions[1].params = { empty }
    api.res.metaConstructionRep.get = function() return { params = sourceParams() } end
    local ok, message = pcall(construction.getConstructionDefinitions)
    assert(not ok and tostring(message):find("track selector has no choices", 1, true), "empty selectors fail before producing an invalid native component")
end

do
    local malformed = copy(owned)
    malformed.numbers, malformed.images = { 4 }, { "one.tga", "two.tga", "three.tga" }
    definitions[1].params = { copy(malformed) }
    api.res.metaConstructionRep.get = function() return { params = { malformed } } end
    local ok, message = pcall(construction.getConstructionDefinitions)
    assert(not ok and tostring(message):find("track selector has no value for row 2", 1, true), "malformed metadata fails before assigning an incorrect icon")
end

print("track_icons_check: passed against the archived native renderer")
