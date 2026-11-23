local nativeDirectory = assert(arg[1], "expected extracted native UI helpers")
local sortingDirectory, sortingOrder = arg[2], arg[3]
local function noop() end
local dependencies = {
    ["/scripts/mathutil.lua"] = {},
    ["/scripts/string_util.tl"] = {},
    ["apasz_zigzag::/zigzag/logging.lua"] = assert(loadfile("content/zigzag/logging.lua"))(),
    ["apasz_zigzag::/zigzag/logging_config.lua"] = assert(loadfile("content/zigzag/logging_config.lua"))(),
}
ug_require = function(path)
    local dependency = dependencies[path]
    assert(dependency ~= nil, path)
    return dependency
end
local function loadModule(path)
    return assert(loadfile(path, "t", setmetatable({ require = ug_require }, { __index = _G })))()
end
local function loadResource(path)
    local env = setmetatable({ data = false }, { __index = _G })
    -- Script resources ignore the chunk's return value and call data().
    assert(loadfile(path, "t", env))()
    assert(type(env.data) == "function", path .. ": function data() not defined")
    return env.data()
end
local loggedWarnings = {}
log = { verbose = noop, warning = function(message) loggedWarnings[#loggedWarnings + 1] = message end, error = error }
dependencies["apasz_zigzag::/zigzag/logger.lua"] = loadModule("content/zigzag/logger.lua")
dependencies["apasz_zigzag::/zigzag/has_station_window.lua"] = loadModule("content/zigzag/has_station_window.lua")
dependencies["apasz_zigzag::/zigzag/construction_path.lua"] = loadModule("content/zigzag/construction_path.lua")
_G._ = function(key) return key end
getOwningModId = function() return "" end
_react = {
    recipes = {}, recipeMetas = {}, extensionPoints = {}, originalRecipeFn = {},
    recipeReplace = {}, builtin = { WithComponentParams = 0 }, recipeReplacementAllowed = true,
}
local recipeNames = {}
local components = {
    [1] = { STATION_GROUP = { stations = { 2 } } },
    [3] = { CONSTRUCTION = { fileName = "generated-zigzag", persistentMetadata = {}, subconstructions = { 4 }, params = {} } },
    [4] = { SUBCONSTRUCTION = { tag = 2 }, WAREHOUSE = { stockList = 5 } },
}
api = {
    type = { ComponentType = { STATION_GROUP = "STATION_GROUP", CONSTRUCTION = "CONSTRUCTION",
        SUBCONSTRUCTION = "SUBCONSTRUCTION", WAREHOUSE = "WAREHOUSE" } },
    engine = {
        entityExists = function(entity) return components[entity] ~= nil end,
        getComponent = function(entity, kind) return components[entity] and components[entity][kind] end,
        util = { getEntityName = function() return "Zigzag" end },
        system = { streetConnectorSystem = { getConstructionEntityForStation = function() return 3 end } },
    },
    gui = { react = { detail = { makeRecipeId = function(name)
        recipeNames[#recipeNames + 1] = name
        return #recipeNames
    end } } },
    res = { genericRep = {} },
}
dependencies["/scripts/util.tl"] = loadModule(nativeDirectory .. "/util.lua")
local react = loadModule(nativeDirectory .. "/react.lua")
local builtin = { type = { Orientation = { Vertical = "Vertical" } }, BoxLayout = function(params) return params end }
dependencies["::/gui/main/react.lua"] = react
dependencies["/gui/main/react.lua"] = react
dependencies["::/gui/main/builtin.lua"] = builtin
dependencies["/gui/main/builtin.lua"] = builtin
dependencies["::/gui/main/engine_react_util.tl"] = {
    useStepState = function(makeState) return { old = makeState } end,
}
dependencies["::/gui/main/content_card.tl"] = {
    ContentCard = function(first, params) return params or first end,
    makeRecipeAndParam = function(recipe, params) return { recipe = recipe, params = params } end,
}
dependencies["::/gui/entity_window/entity_window_util.tl"] = { EntityStockCountsWidget = noop }
dependencies["/gui/entity_window/entity_window_util.tl"] = dependencies["::/gui/entity_window/entity_window_util.tl"]
dependencies["::/scripts/entity_util.tl"] = { isOwnedByPlayerOrNotOwned = function() return true end }
dependencies["::/scripts/metadata_util.tl"] = loadModule(nativeDirectory .. "/metadata_util.lua")
local storage = loadModule("content/zigzag/cargo_storage.lua")
dependencies["apasz_zigzag::/zigzag/cargo_storage.lua"] = storage
local stationWindow = loadModule(nativeDirectory .. "/station_group_eow.script.lua")
dependencies["::/gui/entity_window/station_group/station_group_eow.script.tl"] = stationWindow
local point = stationWindow.StationGroupEowExtensionPoint
local config = loadResource("content/gui/zigzag/cargo_storage.res.lua")
local configs = { config }
local terminalFile = io.open(nativeDirectory .. "/station_terminals_plugin.script.lua", "r")
if terminalFile then
    terminalFile:close()
    for _, path in ipairs({
        "::/gui/main/gui_react_util.tl", "::/gui/main/styleutil.tl", "::/scripts/lang_util.tl",
        "::/gui/line_vehicle_mgmt/line_react_util.tl", "::/gui/main/popover_react_util.tl",
    }) do dependencies[path] = {} end
    api.engine.system.lineSystem = { getLineStops = function() return {} end }
    configs[#configs + 1] = loadResource(nativeDirectory .. "/station_terminals_plugin.res.lua")
end
local windowConfig = loadResource("content/gui/zigzag/station_window.res.lua")
api.res.genericRep.getAllOfType = function(kind)
    if kind == windowConfig.type then return { -1 } end
    assert(kind == config.type, "plugin uses the native station extension point")
    local ids = {}
    for index in ipairs(configs) do ids[index] = index end
    return ids
end
api.res.genericRep.get = function(id) return id == -1 and windowConfig or assert(configs[id]) end
game = {}
local loads = 0
loaderHelper = { useFn = function(_self, reference)
    local script = assert(reference:match("^(.-)@"))
    if game[script] == nil then
        if script == "gameburrow_terminalselector::/station_terminals_plugin.script" then
            game[script] = loadModule(nativeDirectory .. "/station_terminals_plugin.script.lua")
        else
            local path = assert(script:match("^apasz_zigzag::/(.+)$"))
            game[script] = loadResource("content/" .. path .. ".lua")
        end
        loads = loads + 1
    end
end }
local windowRecipe = react.RegisterRecipe("StationGroupWindowContent", function()
    return react.getPlugins(point)
end)
local windowId = react.GetRecipeId(windowRecipe)
local tableUtil = { shallowCopy = function(value)
    local copy = {}
    for key, item in pairs(value) do copy[key] = item end
    return copy
end }
dependencies["::/scripts/table_util.tl"] = tableUtil
dependencies["/gui/main/engine_react_util.tl"] = dependencies["::/gui/main/engine_react_util.tl"]
dependencies["/gui/entity_window/station_group/station_group_eow.script.tl"] = stationWindow
dependencies["/gui/main/gui_react_util.tl"] = { makeHorizontalSpacer = function() return {} end }
dependencies["/gui/main/styleutil.tl"] = { makeStyle = function(params) return params end }
dependencies["/gui/line_vehicle_mgmt/line_react_util.tl"] = {
    makeTerminalIndicator = function(number) return { number = number } end,
}
for _, path in ipairs({
    "/gui/main/cargo_util.tl", "/gui/main/color_util.tl", "/gui/entity_window/entity_window_hud.tl",
    "/gui/entity_window/eow_extension_util.tl", "/gui/hud/hud_react_util.tl", "/scripts/lang_util.tl",
    "/gui/line_vehicle_mgmt/line_util.tl", "/gui/main/selector_react_util.tl",
}) do dependencies[path] = {} end
builtin.type.Orientation.Horizontal = "Horizontal"
builtin.type.ImageViewScaling = { AutoFit = "AutoFit" }
for _, name in ipairs({ "ImageView", "TextView" }) do builtin[name] = function(params) return params end end
dependencies["::/gui/entity_window/station_group/station_group.tl"] = loadModule(nativeDirectory .. "/station_group.lua")
dependencies["::/gui/entity_window/make_entity_window.tl"] = {}
local recipeIds = {}
for id, name in ipairs(recipeNames) do recipeIds[name] = id end
local titleId, terminalsId = assert(recipeIds.TerminalTitle), assert(recipeIds.TerminalsAndStops)
local titleContext = {
    getCurrentRecipeName = function(self) return self.name end,
    setResult = function(self, result) self.result = result end,
    makeNodeWithProps = function(_self, id, _key, props) return { id = id, props = props } end,
}
local function renderNative(id, props)
    titleContext.name = recipeNames[id]
    _react.recipes[id](titleContext, props)
    return titleContext.result
end
local observedProps
local originalTerminals = _react.recipes[terminalsId]
_react.recipes[terminalsId] = function(context, props)
    observedProps = props
    return originalTerminals(context, props)
end
local unrelatedId, collisionId = -100, -101
local releasedId = -102
local passthroughResult, passthroughProps = {}, nil
local function foreignRenderer(_context, props)
    passthroughProps = props
    return passthroughResult
end
_react.recipes[unrelatedId], _react.recipes[collisionId] = foreignRenderer, foreignRenderer
_react.recipes[releasedId] = foreignRenderer
local classLookups = 0
api.res.cargoClassRep = {
    getCargoClassId = function(class)
        assert(type(class) == "string", "cargo class must be a string")
        classLookups = classLookups + 1
        return class == "GOODS" and 7 or -1
    end,
    get = function(id)
        assert(id == 7)
        return { name = "Goods", color = { x = 0.7, y = 0.8, z = 0.9 } }
    end,
}
api.util = { formatLength = function(length) return length .. " m" end }
local missingClass = { terminalIndex = 1, displayNumber = 2, isPassengerTerminal = false, isCargoTerminal = true }
local ok, message = pcall(renderNative, titleId, { props = { missingClass } })
assert(not ok and tostring(message):find("cargo class must be a string", 1, true),
    "native non-loading cargo terminal reproduces the reported crash")
assert(windowConfig.type == "react-replacement-config", "title fix uses the GUI bootstrap")
dependencies["/gui/main/game.tl"] = { defaultElem = {} }
local bootstrapEnv = setmetatable({ require = ug_require }, { __index = _G })
assert(loadfile(nativeDirectory .. "/bootstrap_game.lua", "t", bootstrapEnv))()
if sortingOrder ~= "after-plugin" then bootstrapEnv._reactDoReplaceRecipes() end
if sortingDirectory then
    if sortingOrder == "after-plugin" then react.getPlugins(point) end
    -- Vehicle sorting is outside this station-window test; it must never be called here.
    local unrelated = setmetatable({}, { __index = function() error("station window accessed vehicle sorting") end })
    dependencies["sorting_modes::/sorting_modes/capacity_sort.lua"] = unrelated
    dependencies["sorting_modes::/sorting_modes/logger.lua"] = { debug = noop }
    loadResource(sortingDirectory .. "/content/sorting_modes/capacity_sort.script.lua").install({})
end
if sortingOrder == "after-plugin" then bootstrapEnv._reactDoReplaceRecipes() end
assert(not _react.recipeReplacementAllowed, "native bootstrap completes replacement installation")
local installWindow = assert(game[windowConfig.data.filePath][windowConfig.data.doReplaceFn])
local terminalsRenderer = _react.recipes[terminalsId]
installWindow({})
assert(_react.recipes[terminalsId] == terminalsRenderer, "title fix installs once")
local scriptPath = assert(windowConfig.data.filePath:match("^apasz_zigzag::/(.+)$"))
local lateInstaller = loadResource("content/" .. scriptPath .. ".lua")[windowConfig.data.doReplaceFn]
ok, message = pcall(lateInstaller, {})
assert(not ok and tostring(message):find("must be installed before React execution", 1, true)
    and _react.recipes[terminalsId] == terminalsRenderer, "late installation fails before changing the registry")
local outerCalls = 0
local earlierWrapper = _react.recipes[unrelatedId]
local outerWrapper = function(context, props)
    outerCalls = outerCalls + 1
    return earlierWrapper(context, props)
end
_react.recipes[unrelatedId] = outerWrapper
titleContext.name = "OtherModRecipe"
local foreignProps = { props = { { arbitrary = true } }, style = {} }
local function renderForeign(id, props)
    local result = _react.recipes[id](titleContext, props)
    assert(passthroughProps == props, "foreign recipe parameters retain their identity")
    -- Sorting Modes follows the native void renderer contract and discards returns.
    if not sortingDirectory then
        assert(result == passthroughResult, "Zigzag preserves renderer return values")
    end
end
for _index = 1, 2 do
    renderForeign(unrelatedId, foreignProps)
end
assert(outerCalls == 2 and _react.recipes[unrelatedId] == outerWrapper, "discovery preserves wrappers installed afterwards")
if not sortingDirectory then
    renderForeign(releasedId, foreignProps)
    assert(_react.recipes[releasedId] == foreignRenderer, "unrelated renderers release the discovery wrapper")
end
titleContext.name = "TerminalsAndStops"
for _, arguments in ipairs({ {}, { props = false }, { props = {} }, { props = { false } }, { props = { {} } } }) do
    renderForeign(collisionId, arguments)
end
renderForeign(collisionId, nil)
local owners = { [2] = 3, [6] = 7 }
components[7] = { CONSTRUCTION = { fileName = "other_mod::/station.con" } }
api.engine.system.streetConnectorSystem.getConstructionEntityForStation = function(entity) return owners[entity] end
local descriptions = {
    ["apasz_zigzag" .. dependencies["apasz_zigzag::/zigzag/construction_path.lua"]] = "zigzag-window",
    ["generated-zigzag"] = "zigzag-window",
    ["other_mod::/station.con"] = "other-window",
}
local resourceReads = 0
api.res.constructionRep = { findAndGet = function(name)
    resourceReads = resourceReads + 1
    return { entityWindowScript = { fileName = assert(descriptions[name], name) } }
end }
local function terminalState(params)
    return { terminalIndex = params.terminalIndex, displayNumber = params.displayNumber,
        terminalLineStops = params, terminalLineStopsCount = 0 }
end
local function renderTerminals(stations)
    local props = { props = { { stateParams = { station2TerminalStates = stations }, key = "test", lastInScrollAreaRef = {} }, {} },
        style = { class = "test-title" }, metadata = {} }
    local result = renderNative(terminalsId, props)
    assert(observedProps.style == props.style and observedProps.metadata == props.metadata
        and observedProps.props[2] == props.props[2], "native renderer metadata and extra arguments are preserved")
    return result.children, props
end
local function renderTitle(bar)
    return renderNative(titleId, renderNative(recipeIds.TerminalBar, bar.props).children[1].props)
end
local function checkTitle(params, expectedText, expectedLookups)
    local before = classLookups
    local original = tableUtil.shallowCopy(params)
    local result
    if params.terminalIndex == nil then
        result = renderNative(titleId, { props = { params } })
    else
        local terminal = terminalState(params)
        local stations = { { 2, { terminal } } }
        local cards, props = renderTerminals(stations)
        assert(props.props[1].stateParams.station2TerminalStates == stations
            and stations[1][2][1] == terminal and terminal.terminalLineStops == params,
            "the shared native state is not mutated")
        if params.cargoClass ~= nil or params.isPassengerTerminal then
            assert(observedProps == props, "unaffected terminal states are passed through without copying")
        end
        result = renderTitle(cards[1].extraChildrenPermanent[1])
    end
    assert(result.children[2].text == expectedText, "native terminal title text")
    assert(classLookups - before == expectedLookups, "only specialised titles look up cargo classes")
    for key, value in pairs(params) do assert(original[key] == value, "title fix does not mutate saved parameters") end
    return result
end
checkTitle({ terminalIndex = 0, displayNumber = 1, isPassengerTerminal = true, isCargoTerminal = false }, "Passenger", 0)
checkTitle({ terminalIndex = 0, displayNumber = 1, isPassengerTerminal = true, isCargoTerminal = true }, "Passenger and Cargo", 0)
checkTitle({}, "Waiting Hall", 0)
assert(#loggedWarnings == 0, "ordinary titles do not log warnings")
assert(resourceReads == 0, "ordinary terminal titles do not query construction resources")
checkTitle(missingClass, "All Cargo Types", 0)
assert(#loggedWarnings == 1 and loggedWarnings[1] == "[Zigzag Station] Station window terminal has no cargo class; using the universal-cargo title; station=2, terminal=1",
    "the compatibility workaround is logged through the shared logger")
checkTitle(missingClass, "All Cargo Types", 0)
checkTitle({ terminalIndex = 3, displayNumber = 4, isPassengerTerminal = false, isCargoTerminal = false }, "All Cargo Types", 0)
assert(#loggedWarnings == 1, "redraws and additional non-loading terminals do not repeat the warning")
for _, class in ipairs({ "UNIVERSAL", "GOODS", "MODDED" }) do
    local params = { terminalIndex = 1, displayNumber = 2, isPassengerTerminal = false,
        isCargoTerminal = true, cargoClass = class, terminalLength = 40 }
    local result = checkTitle(params, class == "GOODS" and "Goods" or "All Cargo Types", class == "UNIVERSAL" and 0 or 1)
    assert(result.children[4].text == "40 m", "native terminal length is preserved")
end
assert(#loggedWarnings == 1, "specialised titles do not emit compatibility warnings")
ok, message = pcall(checkTitle, {
    terminalIndex = 1, isPassengerTerminal = false, cargoClass = false,
}, "unused", 0)
assert(not ok and tostring(message):find("cargo class must be a string", 1, true),
    "invalid cargo class types still fail explicitly")
local foreignTerminal = terminalState(tableUtil.shallowCopy(missingClass))
local orphanTerminal = terminalState(tableUtil.shallowCopy(missingClass))
local stations = { { 6, { foreignTerminal } }, { 2, { terminalState(missingClass), terminalState(missingClass) } },
    { 8, { orphanTerminal } } }
stations[2].extension = { fromAnotherMod = true }
local readsBefore = resourceReads
local cards = renderTerminals(stations)
local configuredStations = observedProps.props[1].stateParams.station2TerminalStates
assert(configuredStations[1] == stations[1] and configuredStations[3] == stations[3],
    "mixed station groups preserve foreign and unowned station states")
assert(configuredStations[2] ~= stations[2] and foreignTerminal.terminalLineStops.cargoClass == nil,
    "only Zigzag terminals receive the compatibility value")
assert(configuredStations[2].extension == stations[2].extension, "station extensions supplied by other mods are preserved")
assert(resourceReads - readsBefore == 4, "construction identity is checked once per affected station")
assert(renderTitle(cards[2].extraChildrenPermanent[1]).children[2].text == "All Cargo Types",
    "Zigzag terminals in mixed groups render normally")
ok, message = pcall(renderTitle, cards[1].extraChildrenPermanent[1])
assert(not ok and tostring(message):find("cargo class must be a string", 1, true),
    "another mod's terminal behaviour is left to its own renderer")
assert(#loggedWarnings == 1, "compatibility diagnostics are not repeated for grouped stations")
local groupedCards = renderTerminals({
    { 6, { terminalState({ terminalIndex = 0, displayNumber = 1, isPassengerTerminal = false,
        isCargoTerminal = true, cargoClass = "GOODS" }) } },
    { 2, { terminalState(missingClass) } },
})
assert(renderTitle(groupedCards[1].extraChildrenPermanent[1]).children[2].text == "Goods"
    and renderTitle(groupedCards[2].extraChildrenPermanent[1]).children[2].text == "All Cargo Types",
    "mixed groups retain specialised foreign labels alongside Zigzag reversing terminals")
local context = {
    getCurrentRecipeName = function(self) return self.name end,
    setResult = function(self, result) self.result = result end,
}
for typeIndex in ipairs(storage.profiles) do
    components[3].CONSTRUCTION.params.cargoStorageType = typeIndex
    for _, capacity in ipairs({ 0, 500 }) do
        storage.metadata.set(components[3].CONSTRUCTION.persistentMetadata, capacity)
        context.name = "StationGroupWindowContent"
        _react.recipes[windowId](context, { props = { { entityId = 1 } } })
        assert(#context.result == #configs, "native loader preserves all station plugins")
        local plugin = context.result[#configs].recipe
        if #configs > 1 then
            local terminalPlugin = context.result[1].recipe
            context.name = "gameburrow_ts_LineTerminalsPlugin"
            _react.recipes[react.GetRecipeId(terminalPlugin)](context, { props = { { entityId = 1, gameCtx = {} } } })
            assert(context.result == nil, "Terminal Selector handles a station without stopping lines")
        end
        context.name = "ZigzagCargoStocks"
        _react.recipes[react.GetRecipeId(plugin)](context, { props = { { entityId = 1, gameCtx = {} } } })
        if capacity == 0 then
            assert(context.result == nil, "existing stations without storage still open")
        else
            assert(#context.result.children == 1, "enabled storage supplies its stock card")
        end
    end
end
assert(loads == #configs + 1, "plugin and replacement scripts are loaded once across station window renders")

-- Exercise the native stock icon callbacks, including their construction rebuild command.
local stockRecipes, buttons, commands = {}, {}, {}
dependencies["/gui/main/react.lua"] = { RegisterRecipe = function(name, body)
    stockRecipes[name] = body
    return body
end }
dependencies["/gui/main/engine_react_util.tl"] = dependencies["::/gui/main/engine_react_util.tl"]
dependencies["/gui/main/cargo_react_util.tl"] = { makeCargoIcon = function(id) return { cargoId = id } end }
dependencies["/scripts/lang_util.tl"] = { formatInt = tostring, format = function(value) return value end }
dependencies["/gui/main/styleutil.tl"] = { makeStyle = function(value) return value end }
for _, path in ipairs({
    "/gui/main/button_react_util.tl", "/gui/main/cargo_util.tl", "/gui/main/free_cam_options.tl",
    "/gui/main/gui_react_util.tl", "/industries/industry_productivity_util.tl",
    "/gui/line_vehicle_mgmt/line_react_util.tl", "/game_mechanics/notifications/types/notification_react_util.tl",
    "/game_mechanics/notifications/notification_util.tl",
    "/game_mechanics/towns/town_util.tl", "/gui/line_vehicle_mgmt/vehicle_react_util.tl",
    "/gui/line_vehicle_mgmt/vehicle_util.tl",
}) do dependencies[path] = {} end
builtin.type.Orientation.Horizontal = "Horizontal"
for _, name in ipairs({ "Component", "WithComponentParams", "TextView", "FloatingLayout", "FloatingLayoutChild", "ImageView" }) do
    builtin[name] = function(params) return params end
end
builtin.Button = function(params)
    buttons[#buttons + 1] = params
    return params
end
local nativeStockWidgets = loadModule(nativeDirectory .. "/entity_window_util.lua")
nativeStockWidgets.ProgressDisplay = function(params) return params end
api.type.ComponentType.STOCK_LIST = "STOCK_LIST"
api.engine.util.stock = { isCargoTypeCurrentlyProduced = function() return true end }
api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction = function(entity)
    assert(entity == 5, "native cargo selector resolves the stock list's parent construction")
    return 3
end
api.engine.util.proposal = { createProposalReplaceConstruction = function(entity, params)
    assert(entity == 3, "native cargo selector rebuilds the owning station")
    return { params = params }
end }
api.res.cargoTypeRep = { getName = function(id)
    assert(id == 7, "selected cargo uses its native ID")
    return "test::/chosen.cargo"
end }
api.cmd = {
    makeWorldBuildProposalCmd = function(proposal, context, ignoreErrors, keepSimEntities)
        assert(context == nil and ignoreErrors == false and keepSimEntities == true,
            "native cargo selector uses the construction replacement command")
        return proposal
    end,
    sendCommand = function(command) commands[#commands + 1] = command end,
}
for typeIndex, profile in ipairs(storage.profiles) do
    if not profile.mixedTypes then
        for _, layout in ipairs(storage.bayLayouts) do
            local bays = storage.makeBays(1000, typeIndex, layout)
            local params = { cargoStorageType = typeIndex, cargoStorageCapacity = 1000 }
            components[3].CONSTRUCTION.params = params
            components[5] = { STOCK_LIST = { stocks = storage.makeStocks(bays, profile, nil) } }
            local stockId = #bays - 1
            local selectedTag = bays[stockId + 1].tag
            local config = { ids = { stockId }, cargoTypesSorted = { 7 }, stored = 0, capacity = bays[#bays].capacity,
                numSpoiled = 0, pinnedCargoType = false }
            local entry = { entity = 5, config = config, maxIcons = 5, addButtonsToSetStockCargoType = true }
            for _, pinned in ipairs({ false, true }) do
                config.pinnedCargoType = pinned
                buttons, commands = {}, {}
                stockRecipes.StockCountsEntry(entry)
                assert(#buttons == 1, "native stock row offers a cargo selector")
                buttons[1].onClick()
                assert(#commands == 1, "cargo selection issues exactly one replacement command")
                local saved = commands[1].params
                assert(saved.cargoStorageType == typeIndex and saved.cargoStorageCapacity == 1000,
                    "native cargo selection preserves warehouse settings")
                local stocks = storage.makeStocks(bays, profile, saved.tagToCargoType)
                local expectedCargo
                if not pinned then expectedCargo = "test::/chosen.cargo" end
                assert(saved.tagToCargoType[selectedTag] == expectedCargo
                    and stocks[stockId + 1].cargoType == expectedCargo,
                    "native pin and reset use the bay's stable tag, independent of its stock ID")
            end
        end
    end
end
print("station_window_check: ok (native terminal titles, plugin loading and cargo pin/reset"
    .. (#configs > 1 and ", Terminal Selector" or "")
    .. (sortingDirectory and ", Sorting Modes " .. sortingOrder or "") .. ")")
