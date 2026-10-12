local make_entity_window = ug_require(
"::/gui/entity_window/make_entity_window.tl")








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
   _tag,
   gameCtx,
   isMapEditor,
   isSandboxMode,
   setActionFnAndProxy,
   entityRevisionCloseConditionAndProxy)

   local stationGroupEntity = requireStationGroup(constructionEntity)

   local result = make_entity_window.makeEntityWindowContent(
   stationGroupEntity,
   gameCtx,
   isMapEditor,
   isSandboxMode,
   true,
   setActionFnAndProxy,
   entityRevisionCloseConditionAndProxy,
   nil)

   result.replacedEntity = constructionEntity
   return result
end

function data()
   return {
      entityWindowFn = entityWindowFn,
   }
end
