local nativeDirectory = assert(arg[1], "expected extracted native UI helpers")
local sortingDirectory, sortingOrder = arg[2], arg[3]
local function noop() end
local dependencies = {
    ["/scripts/mathutil.lua"] = {},
    ["/scripts/string_util.tl"] = {},
}
ug_require = function(path) return assert(dependencies[path], path) end
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
log = { verbose = noop, warning = error, error = error }
_G._ = function(key) return key end
getOwningModId = function() return "" end
_react = {
    recipes = {}, recipeMetas = {}, extensionPoints = {}, originalRecipeFn = {},
    recipeReplace = {}, builtin = { WithComponentParams = 0 }, recipeReplacementAllowed = true,
}
local recipeNames = {}
local components = {
    [1] = { STATION_GROUP = { stations = { 2 } } },
    [3] = { CONSTRUCTION = { persistentMetadata = {}, subconstructions = { 4 }, params = {} } },
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
    ContentCard = function(params) return params end,
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
api.res.genericRep.getAllOfType = function(kind)
    assert(kind == config.type, "plugin uses the native station extension point")
    local ids = {}
    for index in ipairs(configs) do ids[index] = index end
    return ids
end
api.res.genericRep.get = function(id) return assert(configs[id]) end
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
if sortingDirectory then
    if sortingOrder == "after-plugin" then react.getPlugins(point) end
    -- Vehicle sorting is outside this station-window test; it must never be called here.
    local unrelated = setmetatable({}, { __index = function() error("station window accessed vehicle sorting") end })
    dependencies["::/scripts/table_util.tl"] = unrelated
    dependencies["sorting_modes::/sorting_modes/capacity_sort.lua"] = unrelated
    dependencies["sorting_modes::/sorting_modes/logger.lua"] = { debug = noop }
    loadResource(sortingDirectory .. "/content/sorting_modes/capacity_sort.script.lua").install({})
end
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
assert(loads == #configs, "script resources are loaded once across station window renders")

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
print("station_window_check: ok (native plugin loading and cargo pin/reset"
    .. (#configs > 1 and ", Terminal Selector" or "")
    .. (sortingDirectory and ", Sorting Modes " .. sortingOrder or "") .. ")")
