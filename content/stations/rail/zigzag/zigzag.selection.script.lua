local SELECT_EVENT = "select"





local selection = {}

function selection.update(_captureParams, state, _dt)
   if not state:hasEventSubscriptions() then
      state:subscribeToEvent(SELECT_EVENT)
   end
   return nil
end

function selection.handleEvent(
   _captureParams,
   _state,
   _src,
   _id,
   _name,
   _param)

   return nil
end

function selection.guiHandleEvent(
   captureParams,
   _state,
   _guiState,
   _src,
   id,
   name,
   param)

   if id ~= "mainView" or name ~= SELECT_EVENT then
      return nil
   end
   if type(param) ~= "number" or (param) % 1 ~= 0 then
      error("Zigzag selection requires an integer entity ID")
   end
   local entity = param
   if entity < 0 or not api.engine.entityExists(entity) then
      return nil
   end
   if api.engine.getComponent(entity, api.type.ComponentType.BASE_EDGE) == nil then
      return nil
   end

   local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForEdge(
   entity)

   if constructionEntity == nil or constructionEntity < 0 then
      return nil
   end
   local construction = api.engine.getComponent(
   constructionEntity,
   api.type.ComponentType.CONSTRUCTION)

   if construction == nil then
      error("Zigzag selected track owner has no construction component")
   end
   local params = captureParams
   local expectedWindowScript = api.res.constructionRep.findAndGet(
   params.constructionFileName).
   entityWindowScript.fileName
   if expectedWindowScript == "" then
      error("Zigzag construction has no station window script")
   end


   local actualWindowScript = api.res.constructionRep.findAndGet(
   construction.fileName).
   entityWindowScript.fileName
   if actualWindowScript ~= expectedWindowScript then
      return nil
   end



   api.gui.fireReactEvent("selectEntity", { entity = constructionEntity })
   return nil
end

function data()
   return selection
end
