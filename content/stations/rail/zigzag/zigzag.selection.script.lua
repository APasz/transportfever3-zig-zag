local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local SELECT_EVENT = "select"
local PROPOSAL_CREATE_EVENT = "builder.proposalCreate"
local PROPOSAL_PREPARE_EVENT = "builder.proposalPrepareForApply"
local validationMetadata = ug_require(
"apasz_zigzag::/zigzag/validation_metadata.lua")

local cargoStorage = ug_require(
"apasz_zigzag::/zigzag/cargo_storage.lua")














local function addValidationError(
   errors,
   message)

   local result = errors or {}
   result[message] = true
   return result
end

local function validateProposal(proposal)
   local errors = nil
   for index = 1, proposal.toAdd_native:size() do
      local added = proposal.toAdd_native:at(index)
      local messages = validationMetadata.get(added.construction.persistentMetadata)
      if messages ~= nil then
         for _, message in ipairs(messages) do
            errors = addValidationError(errors, message)
         end
      end
   end
   local checked = {}
   local function validateStorageRemoval(entity)
      if checked[entity] then
         return
      end
      checked[entity] = true
      local construction = api.engine.getComponent(
      entity, api.type.ComponentType.CONSTRUCTION)

      if construction == nil then
         return
      end
      local previousCapacity = cargoStorage.metadata.get(construction.persistentMetadata)
      if previousCapacity == nil or previousCapacity == 0 then
         return
      end
      local replacementMetadata = nil
      local replacementIndex = proposal.old2new[entity]
      if replacementIndex ~= nil then
         replacementMetadata = proposal.toAdd_native:at(replacementIndex + 1).construction.persistentMetadata
      end
      for _, message in ipairs(cargoStorage.removalErrors(construction, replacementMetadata)) do
         errors = addValidationError(errors, message)
      end
   end
   for entity in pairs(proposal.old2new) do
      validateStorageRemoval(entity)
   end
   for index = 1, proposal.toRemove_native:size() do
      validateStorageRemoval(proposal.toRemove_native:at(index))
   end
   if errors == nil then
      return nil
   end
   return { errorMessages = errors }
end

local selection = {}

function selection.update(_captureParams, state, _dt)
   local current = state:get()
   if not state:hasEventSubscriptions() or not current.builderValidationSubscribed then
      state:subscribeToEvent(SELECT_EVENT)
      state:subscribeToEvent(PROPOSAL_CREATE_EVENT)
      state:subscribeToEvent(PROPOSAL_PREPARE_EVENT)
      current.builderValidationSubscribed = true
      state:set(current)
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

   if name == PROPOSAL_CREATE_EVENT or name == PROPOSAL_PREPARE_EVENT then
      local proposalAndData = param
      return validateProposal(proposalAndData[1])
   end
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
