local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local make_entity_window = ug_require(
"::/gui/entity_window/make_entity_window.tl")

local StationGroupWindowContent = ug_require(
"::/gui/entity_window/station_group/station_group.tl")

local logger = ug_require("apasz_zigzag::/zigzag/logger.lua")
local hasStationWindow = ug_require("apasz_zigzag::/zigzag/has_station_window.lua")

local constructionPath = ug_require("apasz_zigzag::/zigzag/construction_path.lua")
local SOURCE_CONSTRUCTION_NAME = "apasz_zigzag" .. constructionPath












































local installed = false
local tableUtil

local function isZigzagStation(stationEntity)
   local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(stationEntity)
   if constructionEntity == nil or constructionEntity < 0 then
      return false
   end
   local construction = api.engine.getComponent(
   constructionEntity, api.type.ComponentType.CONSTRUCTION)

   return construction ~= nil and hasStationWindow(construction, SOURCE_CONSTRUCTION_NAME)
end

local function configureTerminals(props)

   if props == nil then
      return nil
   end
   local originalProps = props
   if type(originalProps.props) ~= "table" then
      return originalProps
   end
   local arguments = originalProps.props
   if type(arguments[1]) ~= "table" then
      return originalProps
   end
   local params = arguments[1]
   if type(params.stateParams) ~= "table" or type(params.stateParams.station2TerminalStates) ~= "table" then
      return originalProps
   end
   local stations = nil
   for stationIndex, station in ipairs(params.stateParams.station2TerminalStates) do
      local checkedStation = false
      local ownsStation = false
      local terminals = nil
      for terminalIndex, terminal in ipairs(station[2]) do
         local stops = terminal.terminalLineStops
         if stops.isPassengerTerminal == false and stops.cargoClass == nil then
            if not checkedStation then
               ownsStation = isZigzagStation(station[1])
               checkedStation = true
            end
            if ownsStation then
               if terminals == nil then
                  terminals = tableUtil.shallowCopy(station[2])
               end
               local configuredStops = tableUtil.shallowCopy(stops)
               configuredStops.cargoClass = "UNIVERSAL"
               local configuredTerminal = tableUtil.shallowCopy(terminal)
               configuredTerminal.terminalLineStops = configuredStops;
               (terminals)[terminalIndex] = configuredTerminal
               logger.warnOnce(
               "terminal-title:missing-cargo-class",
               "Station window terminal has no cargo class; using the universal-cargo title; station=" ..
               tostring(station[1]) .. ", terminal=" .. tostring(terminal.terminalIndex))

            end
         end
      end
      if terminals ~= nil then
         if stations == nil then
            stations = tableUtil.shallowCopy(params.stateParams.station2TerminalStates)
         end
         local configuredStation = tableUtil.shallowCopy(station)
         configuredStation[2] = terminals;
         (stations)[stationIndex] = configuredStation
      end
   end
   if stations == nil then
      return originalProps
   end
   local state = tableUtil.shallowCopy(params.stateParams)
   state.station2TerminalStates = stations
   local configured = tableUtil.shallowCopy(params)
   configured.stateParams = state
   local configuredArguments = tableUtil.shallowCopy(arguments)
   configuredArguments[1] = configured
   local configuredProps = tableUtil.shallowCopy(originalProps)
   configuredProps.props = configuredArguments
   return configuredProps
end

local function install(_replacementApi)
   if installed then
      return
   end
   if not _react.recipeReplacementAllowed then
      logger.fail("station window compatibility must be installed before React execution")
   end
   tableUtil = ug_require("::/scripts/table_util.tl")


   for id, renderer in pairs(_react.recipes) do
      local original = renderer
      local isTarget = nil
      local wrapped
      wrapped = function(context, props)
         if isTarget == nil then
            isTarget = context:getCurrentRecipeName() == "TerminalsAndStops"
            if not isTarget and _react.recipes[id] == wrapped then
               _react.recipes[id] = original
            end
         end
         return original(context, isTarget and configureTerminals(props) or props)
      end
      _react.recipes[id] = wrapped
   end
   installed = true
end

local function requireStationGroup(constructionEntity)
   local constructionValue = api.engine.getComponent(
   constructionEntity,
   api.type.ComponentType.CONSTRUCTION)

   if constructionValue == nil then
      return logger.fail("station window requires a construction; entity=" .. tostring(constructionEntity))
   end
   local construction = constructionValue
   if #construction.stations ~= 1 then
      return logger.fail(
      "station window requires exactly one station; construction=" .. tostring(constructionEntity) ..
      ", stationCount=" .. tostring(#construction.stations))

   end

   local stationGroupEntity = api.engine.system.stationGroupSystem.getStationGroup(
   construction.stations[1])

   if stationGroupEntity == nil or stationGroupEntity < 0 then
      return logger.fail(
      "station has no station group; construction=" .. tostring(constructionEntity) ..
      ", station=" .. tostring(construction.stations[1]))

   end
   return stationGroupEntity
end

local function entityWindowFn(
   _captureParams,
   constructionEntity,
   tag,
   gameCtx,
   isMapEditor,
   isSandboxMode,
   setActionFnAndProxy,
   entityRevisionCloseConditionAndProxy)

   local stationGroupEntity = requireStationGroup(constructionEntity)
   local actions = make_entity_window.makeSetActionFnWithCombinedKey(
   StationGroupWindowContent,
   setActionFnAndProxy)



   return {
      recipe = StationGroupWindowContent,
      param = {
         meta = { tag = tag .. "station" },
         keyEntity = stationGroupEntity,
         gameCtx = gameCtx,
         isMapEditor = isMapEditor,
         isSandboxMode = isSandboxMode,
         setActionFn = actions.fn,
         setActionFn_compareProxy = actions.proxy,
      },
      replacedEntity = constructionEntity,
      autoCloseCondition = entityRevisionCloseConditionAndProxy[1],
      autoCloseCondition_compareProxy = entityRevisionCloseConditionAndProxy[2],
      fallbackTitle = _("Station"),
   }
end

function data()
   return {
      entityWindowFn = entityWindowFn,
      install = install,
   }
end
