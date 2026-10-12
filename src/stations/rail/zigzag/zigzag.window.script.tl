local make_entity_window = ug_require(
    "::/gui/entity_window/make_entity_window.tl"
) as ViewManager.MakeEntityWindowContentFn

local type ActionFunctionAndProxy = {
    function(actionFn?: (function(): TreeNodeId), key2?: string),
    any
}
local type CloseConditionAndProxy = {function(): boolean, any}

local function requireStationGroup(constructionEntity: Engine.Entity): Engine.Entity
    local constructionValue = api.engine.getComponent(
        constructionEntity,
        api.type.ComponentType.CONSTRUCTION
    ) as Engine.Component.Construction | nil
    if constructionValue == nil then
        error("Zigzag station window requires a construction")
    end
    local construction = constructionValue as Engine.Component.Construction
    if #construction.stations ~= 1 then
        error("Zigzag station window requires exactly one station")
    end

    local stationGroupEntity = api.engine.system.stationGroupSystem.getStationGroup(
        construction.stations[1]
    )
    if stationGroupEntity == nil or stationGroupEntity < 0 then
        error("Zigzag station has no station group")
    end
    return stationGroupEntity
end

local function entityWindowFn(
    _captureParams: table,
    constructionEntity: Engine.Entity,
    _tag: string,
    gameCtx: GameContext,
    isMapEditor: boolean,
    isSandboxMode: boolean,
    setActionFnAndProxy: ActionFunctionAndProxy,
    entityRevisionCloseConditionAndProxy: CloseConditionAndProxy
): ViewManager.MakeEntityWindowResult
    local stationGroupEntity = requireStationGroup(constructionEntity)
    -- Bypass construction dispatch so the native factory cannot re-enter this hook.
    local result = make_entity_window.makeEntityWindowContent(
        stationGroupEntity,
        gameCtx,
        isMapEditor,
        isSandboxMode,
        true,
        setActionFnAndProxy,
        entityRevisionCloseConditionAndProxy,
        nil
    )
    result.replacedEntity = constructionEntity
    return result
end

function data(): any
    return {
        entityWindowFn = entityWindowFn,
    }
end
