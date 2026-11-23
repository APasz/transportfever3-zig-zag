local nativeDirectory = assert(arg[1], "expected an extracted native warehouse directory")
local function noop() end
local function vector(x, y, z) return { x = x, y = y, z = z } end
local constructionUtil = { addModels = noop, addModelsAndGroups = noop, makeFence = noop }
-- Only geometry and emissions are stubbed; stock creation and aggregation run unchanged.
local dependencies = {
    ["/scripts/mat4.tl"] = { rotZYXTransl = noop, transl = noop, mul = noop },
    ["/scripts/vec3.tl"] = { new = vector, degToRad = vector },
    ["/scripts/vec2.tl"] = { new = vector },
    ["/scripts/construction/constructionutil.lua"] = constructionUtil,
    ["::/scripts/construction/constructionutil.lua"] = constructionUtil,
    ["/scripts/construction/modulesutil.lua"] = {
        TransformAlignmentFaces = noop,
        getModulesEmissions = function() return { noise = 0, pollution = 0 } end,
    },
    ["::/scripts/mathutil.lua"] = {},
}
for _, name in ipairs({
    "entrance/wh_entrance_sd.lua", "wh_universal/wh_universal_stocks.lua",
    "wh_flatbed/wh_flatbed_stocks.lua", "wh_goods/wh_goods_stocks.lua",
    "wh_bulk/wh_bulk_sd.lua", "wh_flatbed/wh_flatbed_sd.lua", "wh_goods/wh_goods_sd.lua",
    "wh_liquid/wh_liquid_sd.lua", "wh_universal/wh_universal_sd.lua",
}) do
    dependencies[name] = {}
end
local function loadNative(name)
    local env = setmetatable({
        require = function(path) return assert(dependencies[path], path) end,
        _ = function(text) return text end,
    }, { __index = _G })
    assert(loadfile(nativeDirectory .. "/" .. name, "t", env))()
    return env.data()
end
local nativeWarehouse = loadNative("warehouse.script.lua")
local nativeModules = loadNative("modules.script.lua")
local metadataUtil = assert(loadfile(nativeDirectory .. "/metadata_util.lua"))()
local storage = assert(loadfile("content/zigzag/cargo_storage.lua", "t", setmetatable({
    ug_require = function(path)
        assert(path == "::/scripts/metadata_util.tl", path)
        return metadataUtil
    end,
}, { __index = _G })))()

for _, profile in ipairs(storage.profiles) do
    for _, moduleCount in ipairs({ 1, 2 }) do
        local params = { seed = 0, modules = {}, tagToCargoType = {} }
        local result = nativeWarehouse.updateFn({}, params)
        for moduleIndex = 1, moduleCount do
            local slotId = result.encodeSlotId({ x = (moduleIndex - 1) * 4, y = 3 }, "warehouse_large")
            params.tagToCargoType[slotId] = "test::/pinned.cargo"
            nativeModules[profile.kind:lower()].updateFn({}, result, nil, moduleIndex, slotId, nil, params)
        end
        result.terminateConstructionHook()
        local stocks = result.subconstructions[1].stocks
        assert(#stocks == (profile.mixedTypes and 1 or moduleCount), "native bay count changed")
        for _, stock in ipairs(stocks) do
            assert(stock.type == "STORAGE_STOCK" and stock.mixedTypes == profile.mixedTypes, "native stock type changed")
            assert(stock.capacity == storage.moduleCapacity * (profile.mixedTypes and moduleCount or 1), "native capacity changed")
            assert(stock.loadSpeedModifier == profile.loadSpeedModifier, "native loading modifier changed")
            assert(#stock.cargoTypes.cargoClassesIncluded == 1
                and stock.cargoTypes.cargoClassesIncluded[1] == profile.kind, "native cargo class changed")
            assert(#stock.cargoTypes.cargoTypesExcluded == 1
                and stock.cargoTypes.cargoTypesExcluded[1] == "::/cargos/passengers/passengers.cargo", "native cargo exclusions changed")
            if not profile.mixedTypes then
                assert(stock.cargoType == params.tagToCargoType[stock.tag], "native cargo selection must use stable stock tags")
            end
        end
    end
end
print("cargo_storage_check: ok (all five native warehouse types, one and two modules)")
