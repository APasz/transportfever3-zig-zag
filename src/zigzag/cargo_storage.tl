local metadata_util = ug_require "::/scripts/metadata_util.tl" as MetadataUtil

-- Keep each category’s tag range independent of future capacity presets.
local STOCK_TAG_STRIDE: integer = 1000

local storage: ZigzagCargoStorage = {
    capacities = { 0, 250, 500, 1000, 2000, 5000 },
    profiles = {
        { kind = "UNIVERSAL", moduleName = "::/warehouses/wh_universal.module",
            labelKey = "apasz_zigzag_storage_universal", mixedTypes = true, loadSpeedModifier = 1 },
        { kind = "BULK", moduleName = "::/warehouses/wh_bulk.module",
            labelKey = "apasz_zigzag_storage_bulk", mixedTypes = false, loadSpeedModifier = 2 },
        { kind = "FLATBED", moduleName = "::/warehouses/wh_flatbed.module",
            labelKey = "apasz_zigzag_storage_flatbed", mixedTypes = false, loadSpeedModifier = 2 },
        { kind = "GOODS", moduleName = "::/warehouses/wh_goods.module",
            labelKey = "apasz_zigzag_storage_goods", mixedTypes = false, loadSpeedModifier = 2 },
        { kind = "LIQUID", moduleName = "::/warehouses/wh_liquid.module",
            labelKey = "apasz_zigzag_storage_liquid", mixedTypes = false, loadSpeedModifier = 2 },
    },
    bayLayouts = { "MODULE_BAYS", "SINGLE_BAY" },
    -- The vanilla universal module's capacity is defined in modules.script, not its metadata.
    moduleCapacity = 500,
    subconstructionTag = 2,
    stockTag = 1,
    metadata = metadata_util.constructionInstance.register(
        "apasz_zigzag_cargo_storage_capacity"
    ) as MetadataAccessor<ConstructionInstanceMetadata, integer>,
    baysMetadata = metadata_util.constructionInstance.register(
        "apasz_zigzag_cargo_storage_bays"
    ) as MetadataAccessor<ConstructionInstanceMetadata, {ZigzagStorageBay}>,
}

function storage.requireCapacity(value: integer | nil): integer
    local capacity: integer = 0
    if value ~= nil then
        capacity = value
    end
    for _, allowedCapacity in ipairs(storage.capacities) do
        if capacity == allowedCapacity then
            return capacity
        end
    end
    error("Zigzag Station received invalid cargo storage capacity " .. tostring(capacity))
end

function storage.requireProfile(value: integer | nil): ZigzagStorageProfile
    local index: integer = 1
    if value ~= nil then
        index = value
    end
    local profile = storage.profiles[index]
    if profile == nil then
        error("Zigzag Station received invalid cargo storage type " .. tostring(index))
    end
    return profile
end

function storage.makeBays(
    capacity: integer,
    typeIndex: integer | nil,
    layout: ZigzagStorageBayLayout
): {ZigzagStorageBay}
    capacity = storage.requireCapacity(capacity)
    if layout ~= "MODULE_BAYS" and layout ~= "SINGLE_BAY" then
        error("Zigzag Station received invalid storage bay layout " .. tostring(layout))
    end
    local profile = storage.requireProfile(typeIndex)
    local bayCapacity: integer
    if profile.mixedTypes or layout == "SINGLE_BAY" then
        bayCapacity = capacity
    else
        bayCapacity = storage.moduleCapacity
    end
    local firstTag = storage.stockTag + ((typeIndex or 1) - 1) * STOCK_TAG_STRIDE
    local bays: {ZigzagStorageBay} = {}
    local remaining = capacity
    while remaining > 0 do
        local amount = math.min(bayCapacity, remaining)
        bays[#bays + 1] = { tag = firstTag + #bays, capacity = amount }
        remaining = remaining - amount
    end
    return bays
end

function storage.makeStocks(
    bays: {ZigzagStorageBay},
    profile: ZigzagStorageProfile,
    pinnedCargo: {integer: ResName} | nil
): {ZigzagStorageStock}
    if pinnedCargo ~= nil and type(pinnedCargo) ~= "table" then
        error("Zigzag Station received an invalid pinned cargo map")
    end
    local cargoTypes: ConstructionUtilSerialized.CargoTypeSet = {
        cargoClassesIncluded = { profile.kind },
        cargoTypesExcluded = { "::/cargos/passengers/passengers.cargo" },
    }
    local stocks: {ZigzagStorageStock} = {}
    for _, bay in ipairs(bays) do
        local cargoType: ResName | nil = nil
        if not profile.mixedTypes and pinnedCargo ~= nil then
            cargoType = (pinnedCargo as {integer: ResName})[bay.tag]
            if cargoType ~= nil and (type(cargoType) ~= "string" or cargoType == "") then
                error("Zigzag Station received invalid pinned cargo for stock " .. tostring(bay.tag))
            end
        end
        stocks[#stocks + 1] = {
            tag = bay.tag,
            type = "STORAGE_STOCK",
            cargoTypes = cargoTypes,
            mixedTypes = profile.mixedTypes,
            capacity = bay.capacity,
            loadSpeedModifier = profile.loadSpeedModifier,
            cargoType = cargoType,
        }
    end
    return stocks
end

function storage.requireStockList(construction: Engine.Component.Construction): Engine.Entity
    local stockListEntity: Engine.Entity | nil = nil
    for _, entity in ipairs(construction.subconstructions) do
        local subconstruction = api.engine.getComponent(
            entity, api.type.ComponentType.SUBCONSTRUCTION
        ) as Engine.Component.Subconstruction
        if subconstruction == nil then
            error("Zigzag Station has a missing subconstruction")
        end
        if subconstruction.tag == storage.subconstructionTag then
            local warehouse = api.engine.getComponent(
                entity, api.type.ComponentType.WAREHOUSE
            ) as Engine.Component.Warehouse
            if warehouse == nil then
                error("Zigzag storage subconstruction has no warehouse")
            end
            if stockListEntity ~= nil then
                error("Zigzag Station has multiple storage warehouses")
            end
            stockListEntity = warehouse.stockList
        end
    end
    if stockListEntity == nil then
        error("Zigzag Station has storage capacity but no warehouse")
    end
    return stockListEntity
end

local function constructionBays(metadata: ConstructionInstanceMetadata): {ZigzagStorageBay}
    local bays = storage.baysMetadata.get(metadata)
    if bays ~= nil then
        return bays
    end
    -- Stations with the original shared store have a single universal stock.
    local capacity = storage.metadata.get(metadata)
    if capacity == nil or capacity == 0 then
        return {}
    end
    return { { tag = storage.stockTag, capacity = capacity } }
end

local function requireStockIndices(
    construction: Engine.Component.Construction
): Engine.Entity, {integer: integer}
    local entity = storage.requireStockList(construction)
    local stockList = api.engine.getComponent(
        entity, api.type.ComponentType.STOCK_LIST
    ) as Engine.Component.StockList
    local bays = constructionBays(construction.persistentMetadata)
    if stockList == nil or #stockList.stocks ~= #bays then
        error("Zigzag warehouse has no matching cargo stocks")
    end
    local expected: {integer: boolean} = {}
    for _, bay in ipairs(bays) do
        expected[bay.tag] = true
    end
    local stockIndices: {integer: integer} = {}
    for index, stock in ipairs(stockList.stocks) do
        if not expected[stock.tag] then
            error("Zigzag warehouse has no matching cargo stock tag")
        end
        expected[stock.tag] = nil
        stockIndices[stock.tag] = index - 1
    end
    return entity, stockIndices
end

function storage.removalErrors(
    construction: Engine.Component.Construction,
    replacement: ConstructionInstanceMetadata | nil
): {string}
    local capacities: {integer: integer} = {}
    if replacement ~= nil then
        for _, bay in ipairs(constructionBays(replacement)) do
            capacities[bay.tag] = bay.capacity
        end
    end
    local previous = constructionBays(construction.persistentMetadata)
    local errors: {string} = {}
    local reduced = false
    for _, bay in ipairs(previous) do
        if (capacities[bay.tag] or 0) < bay.capacity then
            reduced = true
            break
        end
    end
    if not reduced then
        return errors
    end
    local entity, stockIndices = requireStockIndices(construction)
    for index, bay in ipairs(previous) do
        local capacity = capacities[bay.tag] or 0
        if capacity < bay.capacity then
            local stored = api.engine.system.simEntityAtStockSystem.getStockCount(entity, stockIndices[bay.tag])
            if stored > capacity then
                if bay.tag == storage.stockTag then
                    errors[#errors + 1] = string.format(_("apasz_zigzag_cargo_storage_too_small"), stored, capacity)
                else
                    errors[#errors + 1] = string.format(_("apasz_zigzag_storage_bay_too_small"), index, stored, capacity)
                end
            end
        end
    end
    return errors
end

return storage
