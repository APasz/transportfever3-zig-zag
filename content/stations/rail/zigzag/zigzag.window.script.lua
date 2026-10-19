local make_entity_window = ug_require(
"::/gui/entity_window/make_entity_window.tl")

local StationGroupWindowContent = ug_require(
"::/gui/entity_window/station_group/station_group.tl")








local function requireStationGroup(constructionEntity)
   local constructionValue = api.engine.getComponent(
   constructionEntity,
   api.type.ComponentType.CONSTRUCTION)

   if constructionValue == nil then
      error("Zigzag station window requires a construction")
   end
   local construction = constructionValue
   if #construction.stations ~= 1 then
      error("Zigzag station window requires exactly one station")
   end

   local stationGroupEntity = api.engine.system.stationGroupSystem.getStationGroup(
   construction.stations[1])

   if stationGroupEntity == nil or stationGroupEntity < 0 then
      error("Zigzag station has no station group")
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
   }
end
