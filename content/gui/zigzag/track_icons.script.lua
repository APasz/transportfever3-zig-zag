local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local builtin = ug_require("::/gui/main/builtin.lua")
local selection = ug_require("apasz_zigzag::/zigzag/track_selection.lua")
local constructionUtil = ug_require("::/gui/construction/construction_react_util.tl")
local paramUtil = ug_require("::/gui/main/script_param_util.tl")
local tableUtil = ug_require("::/scripts/table_util.tl")
local react = ug_require("::/gui/main/react.lua")
local logging = ug_require("apasz_zigzag::/zigzag/logging.lua")
local logger = logging.new("Zigzag Station", false)





















local renderers = setmetatable({}, { __mode = "k" })
local installed = false

local function numericValue(numbers, index)
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

local function sourceParams(resourceName)
   local templateId = api.res.metaConstructionRep.find(resourceName)
   if templateId == -1 then
      logger.warnOnce(
      "track-icons:" .. resourceName,
      "Missing track icon metadata for " .. resourceName .. "; using track names")

      return {}
   end
   local template = api.res.metaConstructionRep.get(templateId)
   local periods = {}
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

local function makeRenderer(param, source)
   if #param.values == 0 then
      return logger.fail("track selector has no choices")
   end
   local icons = {}
   if source ~= nil then
      local sourceParam = source
      for index = 1, #sourceParam.values do
         local value = numericValue(sourceParam.numbers, index)
         if icons[value] ~= nil then
            return logger.fail("duplicate track icon metadata value " .. tostring(value))
         end
         icons[value] = sourceParam.images[index] or ""
      end
   end
   local rows = {}
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
   local picker = {
      rows = rows,
      firstValue = numericValue(param.numbers, 1),
      periodKey = tostring(param.yearFrom) .. ":" .. tostring(param.yearTo),
   }
   local render = function(value)

      local row = rows[value] or rows[picker.firstValue]
      local label = builtin.TextView({
         meta = { class = "font-scale-body, apasz-zigzag-track-name", tooltip = row.tooltip },
         text = row.label,
         tooltipWhenClipped = row.label,
      })
      if row.icon == nil or row.icon == "" then
         return label
      end

      return builtin.Component({
         meta = { tooltip = row.tooltip },
         layout = builtin.BoxLayout({
            meta = { class = "apasz-zigzag-track-row" },
            orientation = builtin.type.Orientation.Horizontal,
            children = {
               builtin.ImageView({
                  meta = { class = "apasz-zigzag-track-icon" },
                  path = row.icon,
                  scaling = builtin.type.ImageViewScaling.AutoFit,
               }),
               label,
            },
         }),
      })
   end
   return render, picker
end

local function decorate(definition)
   local nativeParams
   for index, param in ipairs(definition.params) do
      if param.key == selection.paramKey and
         param.uiType == api.type["enum"].ScriptParamType.ComboBox and
         not renderers[param.makeCompactButtonFn] then

         if nativeParams == nil then
            nativeParams = sourceParams(definition.resName)
         end
         local endings = nativeParams[param.yearFrom]
         local sourceParam = endings and endings[param.yearTo]


         local render, picker = makeRenderer(param, sourceParam)
         local decorated = tableUtil.shallowCopy(param)
         decorated.makeCompactButtonFn = render
         renderers[render] = picker
         definition.params[index] = decorated
      end
   end
end

local function buildDropdown(param, picker)
   local items = {}
   local scriptParam = param.scriptParam
   local render = scriptParam.makeCompactButtonFn
   for index = 1, #scriptParam.values do
      local value = numericValue(scriptParam.numbers, index)
      items[#items + 1] = builtin.ComboBoxItem({
         value = value,
         content = render(value),
      })
   end
   local dropdown = builtin.ComboBox({
      meta = {
         class = "right-parameters, ui-type-" .. tostring(scriptParam.uiType),
         tag = "scriptParams.rightParameters." .. scriptParam.name,
         onAttention = param.onHover,
      },
      value = param.currentValue,
      onValueChange = function(value)
         if type(value) ~= "number" or picker.rows[value] == nil then
            error("Zigzag track selector requires an available numeric value")
         end
         param.onValueChange(value)
      end,
      items = items,
   })
   return dropdown
end

local function install(_replacementApi)
   if installed then
      return
   end
   local originalDefinitions = constructionUtil.getConstructionDefinitions
   local originalBuild = paramUtil.buildScriptParamCompSimple
   constructionUtil.getConstructionDefinitions = function()
      local definitions = originalDefinitions()
      for _, definition in ipairs(definitions) do
         decorate(definition)
      end
      return definitions
   end
   local TrackSelector = react.RegisterRecipe("ZigzagTrackSelector", function(props)
      local param = props.control
      local picker = renderers[param.scriptParam.makeCompactButtonFn]
      if picker == nil then
         return logger.fail("track selector lost its row metadata")
      end
      local expired = picker.rows[param.currentValue] == nil

      react.onStep(function()
         if expired then
            param.onValueChange(picker.firstValue)
         end
      end)
      if expired then
         param = tableUtil.shallowCopy(param)
         param.currentValue = picker.firstValue
      end
      local control
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
            "script-param-wrap-combobox")

         end
      end

      return builtin.BoxLayout({ children = { control } })
   end)
   paramUtil.buildScriptParamCompSimple = function(param)
      local picker = renderers[param.scriptParam.makeCompactButtonFn]
      if param.scriptParam.uiType ~= api.type["enum"].ScriptParamType.ComboBox or
         picker == nil then

         return originalBuild(param)
      end
      return TrackSelector({

         meta = { localKey = picker.periodKey },
         control = param,
      })
   end
   installed = true
end

function data()
   return { install = install }
end
