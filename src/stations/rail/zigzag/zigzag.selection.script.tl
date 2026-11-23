local SELECT_EVENT = "select"
local PROPOSAL_CREATE_EVENT = "builder.proposalCreate"
local PROPOSAL_PREPARE_EVENT = "builder.proposalPrepareForApply"
local validationMetadata = ug_require(
    "apasz_zigzag::/zigzag/validation_metadata.lua"
) as MetadataAccessor<ConstructionInstanceMetadata, {string}>
local cargoStorage = ug_require(
    "apasz_zigzag::/zigzag/cargo_storage.lua"
) as ZigzagCargoStorage

local record SelectionParams
    constructionFileName: ResName
end

local record SelectionState
    builderValidationSubscribed: boolean | nil
end

local record ProposalValidationResult
    errorMessages: {string: boolean}
end

local function addValidationError(
    errors: {string: boolean} | nil,
    message: string
): {string: boolean}
    local result: {string: boolean} = errors or {}
    result[message] = true
    return result
end

local function validateProposal(proposal: Proposal): ProposalValidationResult | nil
    local errors: {string: boolean} | nil = nil
    for index = 1, proposal.toAdd_native:size() do
        local added = proposal.toAdd_native:at(index)
        local messages = validationMetadata.get(added.construction.persistentMetadata)
        if messages ~= nil then
            for _, message in ipairs(messages) do
                errors = addValidationError(errors, message)
            end
        end
    end
    local checked: {Engine.Entity: boolean} = {}
    local function validateStorageRemoval(entity: Engine.Entity)
        if checked[entity] then
            return
        end
        checked[entity] = true
        local construction = api.engine.getComponent(
            entity, api.type.ComponentType.CONSTRUCTION
        ) as Engine.Component.Construction
        if construction == nil then
            return
        end
        local previousCapacity = cargoStorage.metadata.get(construction.persistentMetadata)
        if previousCapacity == nil or previousCapacity == 0 then
            return
        end
        local replacementMetadata: ConstructionInstanceMetadata | nil = nil
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

local selection: GameScriptWithGui<SelectionState, table> = {}

function selection.update(_captureParams: table, state: GameScriptState<SelectionState>, _dt: number): any
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
    _captureParams: table,
    _state: GameScriptState<SelectionState>,
    _src: string,
    _id: string,
    _name: string,
    _param: any
): any
    return nil
end

function selection.guiHandleEvent(
    captureParams: table,
    _state: GameScriptStateReadOnly<SelectionState>,
    _guiState: GameScriptState<table>,
    _src: string,
    id: string,
    name: string,
    param: any
): any
    if name == PROPOSAL_CREATE_EVENT or name == PROPOSAL_PREPARE_EVENT then
        local proposalAndData = param as {Proposal, ProposalData}
        return validateProposal(proposalAndData[1])
    end
    if id ~= "mainView" or name ~= SELECT_EVENT then
        return nil
    end
    if type(param) ~= "number" or (param as number) % 1 ~= 0 then
        error("Zigzag selection requires an integer entity ID")
    end
    local entity = param as Engine.Entity
    if entity < 0 or not api.engine.entityExists(entity) then
        return nil
    end
    if api.engine.getComponent(entity, api.type.ComponentType.BASE_EDGE) == nil then
        return nil
    end

    local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForEdge(
        entity
    )
    if constructionEntity == nil or constructionEntity < 0 then
        return nil
    end
    local construction = api.engine.getComponent(
        constructionEntity,
        api.type.ComponentType.CONSTRUCTION
    ) as Engine.Component.Construction
    if construction == nil then
        error("Zigzag selected track owner has no construction component")
    end
    local params = captureParams as SelectionParams
    local expectedWindowScript = api.res.constructionRep.findAndGet(
        params.constructionFileName
    ).entityWindowScript.fileName
    if expectedWindowScript == "" then
        error("Zigzag construction has no station window script")
    end
    -- Placed dynamic constructions can have a generated resource name. Match
    -- their registered window hook rather than the source construction path.
    local actualWindowScript = api.res.constructionRep.findAndGet(
        construction.fileName
    ).entityWindowScript.fileName
    if actualWindowScript ~= expectedWindowScript then
        return nil
    end

    -- Frozen track edges are selectable, but vanilla only opens the owning
    -- construction's entity window when that construction is selected directly.
    api.gui.fireReactEvent("selectEntity", { entity = constructionEntity })
    return nil
end

function data(): any
    return selection
end
