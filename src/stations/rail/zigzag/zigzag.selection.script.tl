local SELECT_EVENT = "select"

local record SelectionParams
    constructionFileName: ResName
end

local selection: GameScriptWithGui<table, table> = {}

function selection.update(_captureParams: table, state: GameScriptState<table>, _dt: number): any
    if not state:hasEventSubscriptions() then
        state:subscribeToEvent(SELECT_EVENT)
    end
    return nil
end

function selection.handleEvent(
    _captureParams: table,
    _state: GameScriptState<table>,
    _src: string,
    _id: string,
    _name: string,
    _param: any
): any
    return nil
end

function selection.guiHandleEvent(
    captureParams: table,
    _state: GameScriptStateReadOnly<table>,
    _guiState: GameScriptState<table>,
    _src: string,
    id: string,
    name: string,
    param: any
): any
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
