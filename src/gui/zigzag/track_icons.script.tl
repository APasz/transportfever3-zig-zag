local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local selection = ug_require "apasz_zigzag::/zigzag/track_selection.lua" as ZigzagTrackSelection
local constructionUtil = ug_require "::/gui/construction/construction_react_util.tl" as ConstructionReactUtil
local paramUtil = ug_require "::/gui/main/script_param_util.tl" as ScriptParamUtil
local tableUtil = ug_require "::/scripts/table_util.tl" as TableUtil
local react = ug_require "::/gui/main/react.lua" as React
local logger = ug_require "apasz_zigzag::/zigzag/logger.lua" as ModLogging.Logger

local type RowRenderer = function(number): TreeNodeId
local type TrackParamsByPeriod = {integer: {integer: ScriptParam}}

local record TrackRow
    label: string
    icon: string | nil
    tooltip: string | nil
end

local record TrackPicker
    rows: {number: TrackRow}
    firstValue: number
    periodKey: string
end

local record TrackSelectorParams
    meta: Meta
    control: ScriptParamUtil.CompSimpleParam
end

local renderers: {RowRenderer: TrackPicker} = setmetatable({}, { __mode = "k" })
local installed = false

local function numericValue(numbers: {number}, index: integer): number
    if numbers == nil or #numbers == 0 then
        return index
    end
    local value = numbers[index]
    if value == nil then
        return logger.fail("track selector has no value for row " .. tostring(index))
    end
    if value < 1 or value % 1 ~= 0 then
        return logger.fail("track selector has an invalid value for row " .. tostring(index))
    end
    return value
end

local function sourceParams(resourceName: ResName): TrackParamsByPeriod
    local templateId = api.res.metaConstructionRep.find(resourceName)
    if templateId == -1 then
        logger.warnOnce(
            "track-icons:" .. resourceName,
            "Missing track icon metadata for " .. resourceName .. "; using track names"
        )
        return {}
    end
    local template = api.res.metaConstructionRep.get(templateId) as ZigzagNativeTemplateParams
    local periods: TrackParamsByPeriod = {}
    for _, param in ipairs(template.params) do
        if param.key == selection.paramKey then
            local endings = periods[param.yearFrom]
            if endings == nil then
                endings = {}
                periods[param.yearFrom] = endings
            end
            if endings[param.yearTo] ~= nil then
                return logger.fail("duplicate track selector period in " .. resourceName)
            end
            endings[param.yearTo] = param
        end
    end
    return periods
end

local function makeRenderer(param: ConstructionMenuParam, source: ScriptParam | nil): RowRenderer, TrackPicker
    if #param.values == 0 then
        return logger.fail("track selector has no choices")
    end
    local icons: {number: string} = {}
    if source ~= nil then
        local sourceParam = source as ScriptParam
        for index = 1, #sourceParam.values do
            local value = numericValue(sourceParam.numbers, index)
            if icons[value] ~= nil then
                return logger.fail("duplicate track icon metadata value " .. tostring(value))
            end
            icons[value] = sourceParam.images[index] or ""
        end
    end
    local rows: {number: TrackRow} = {}
    for index, label in ipairs(param.values) do
        local value = numericValue(param.numbers, index)
        if rows[value] ~= nil then
            return logger.fail("duplicate track selector value " .. tostring(value))
        end
        local icon = icons[value]
        rows[value] = {
            label = label,
            icon = icon,
            tooltip = param.tooltips and param.tooltips[index],
        }
    end
    local picker: TrackPicker = {
        rows = rows,
        firstValue = numericValue(param.numbers, 1),
        periodKey = tostring(param.yearFrom) .. ":" .. tostring(param.yearTo),
    }
    local render = function(value: number): TreeNodeId
        -- Native compact buttons can retain a value from a previous availability period.
        local row = rows[value] or rows[picker.firstValue]
        local label = builtin.TextView {
            meta = { class = "font-scale-body, apasz-zigzag-track-name", tooltip = row.tooltip },
            text = row.label,
            tooltipWhenClipped = row.label,
        }
        if row.icon == nil or row.icon == "" then
            return label
        end
        -- Native selector and button content must be a component, not a layout.
        return builtin.Component {
            meta = { tooltip = row.tooltip },
            layout = builtin.BoxLayout {
                meta = { class = "apasz-zigzag-track-row" },
                orientation = builtin.type.Orientation.Horizontal,
                children = {
                    builtin.ImageView {
                        meta = { class = "apasz-zigzag-track-icon" },
                        path = row.icon,
                        scaling = builtin.type.ImageViewScaling.AutoFit,
                    },
                    label,
                },
            },
        }
    end
    return render, picker
end

local function decorate(definition: ConstructionDefinition)
    local nativeParams: TrackParamsByPeriod
    for index, param in ipairs(definition.params) do
        if param.key == selection.paramKey
            and param.uiType == api.type["enum"].ScriptParamType.ComboBox
            and not renderers[param.makeCompactButtonFn]
        then
            if nativeParams == nil then
                nativeParams = sourceParams(definition.resName)
            end
            local endings = nativeParams[param.yearFrom]
            local sourceParam = endings and endings[param.yearTo]
            -- The renderer receives a reduced parameter record without its key.
            -- Function identity carries ownership through that native conversion.
            local render, picker = makeRenderer(param, sourceParam)
            local decorated = tableUtil.shallowCopy(param)
            decorated.makeCompactButtonFn = render
            renderers[render] = picker
            definition.params[index] = decorated
        end
    end
end

local function buildDropdown(param: ScriptParamUtil.CompSimpleParam, picker: TrackPicker): TreeNodeId
    local items: {TreeNodeId} = {}
    local scriptParam = param.scriptParam
    local render = scriptParam.makeCompactButtonFn
    for index = 1, #scriptParam.values do
        local value = numericValue(scriptParam.numbers, index)
        items[#items + 1] = builtin.ComboBoxItem {
            value = value,
            content = render(value),
        }
    end
    local dropdown = builtin.ComboBox {
        meta = {
            class = "right-parameters, ui-type-" .. tostring(scriptParam.uiType as integer),
            tag = "scriptParams.rightParameters." .. scriptParam.name,
            onAttention = param.onHover,
        },
        value = param.currentValue,
        onValueChange = function(value: number | string)
            if type(value) ~= "number" or picker.rows[value as number] == nil then
                error("Zigzag track selector requires an available numeric value")
            end
            param.onValueChange(value as number)
        end,
        items = items,
    }
    return dropdown
end

local function install(_replacementApi: ReactReplacementApi)
    if installed then
        return
    end
    local originalDefinitions = constructionUtil.getConstructionDefinitions
    local originalBuild = paramUtil.buildScriptParamCompSimple
    constructionUtil.getConstructionDefinitions = function(): {ConstructionDefinition}
        local definitions = originalDefinitions()
        for _, definition in ipairs(definitions) do
            decorate(definition)
        end
        return definitions
    end
    local TrackSelector = react.RegisterRecipe("ZigzagTrackSelector", function(props: TrackSelectorParams): TreeNodeId
        local param = props.control
        local picker = renderers[param.scriptParam.makeCompactButtonFn]
        if picker == nil then
            return logger.fail("track selector lost its row metadata")
        end
        local expired = picker.rows[param.currentValue] == nil
        -- Update native stored values after rendering, so later years retain the replacement.
        react.onStep(function()
            if expired then
                param.onValueChange(picker.firstValue)
            end
        end)
        if expired then
            param = tableUtil.shallowCopy(param)
            param.currentValue = picker.firstValue
        end
        local control: TreeNodeId
        if param.compact then
            control = originalBuild(param)
        else
            control = buildDropdown(param, picker)
            if param.vertical ~= nil then
                control = paramUtil.wrap(
                    param.scriptParam.name,
                    param.vertical,
                    control,
                    param.addSpacer,
                    param.onHover,
                    "script-param-wrap-combobox"
                )
            end
        end
        -- Custom recipes supply a layout; native controls are children of that layout.
        return builtin.BoxLayout { children = { control } }
    end)
    paramUtil.buildScriptParamCompSimple = function(param: ScriptParamUtil.CompSimpleParam): TreeNodeId
        local picker = renderers[param.scriptParam.makeCompactButtonFn]
        if param.scriptParam.uiType ~= api.type["enum"].ScriptParamType.ComboBox
            or picker == nil
        then
            return originalBuild(param)
        end
        return TrackSelector {
            -- Reset native compact-button state when its choices change with the year.
            meta = { localKey = picker.periodKey },
            control = param,
        }
    end
    installed = true
end

function data(): any
    return { install = install }
end
