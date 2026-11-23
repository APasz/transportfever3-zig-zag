return function(context, fixtures)
    local dependencies = {}
    local function requireMod(reference)
        if dependencies[reference] == nil then
            local id, path = assert(reference:match("^(.-)::/(.+)$"))
            local env = setmetatable({ ug_require = requireMod, require = requireMod }, { __index = _G })
            dependencies[reference] = assert(loadfile(assert(fixtures.mods[id], id) .. "/" .. path, "t", env))()
        end
        return dependencies[reference]
    end
    local function resource(path)
        local env = setmetatable({ data = false, resolve = function(value) return value end,
            ug_require = requireMod, require = requireMod }, { __index = _G })
        assert(loadfile(path, "t", env))()
        return assert(env.data, path .. ": missing data()")()
    end

    local trackCategories = {}
    for _, path in ipairs(fixtures.categories) do
        local category = resource(path)
        if category.type == "menu_category" then
            context.menuCategories[#context.menuCategories + 1] = category
            if category.data.menu == "TRACKS" then trackCategories[category.data.category] = true end
        end
    end
    trackCategories.tracks = true
    local expected, electric, customCategories = {}, {}, {}
    for _, entry in ipairs(fixtures.templates) do
        local template = resource(entry.path)
        local train, electrified = false, false
        for _, lane in ipairs(template.laneConfigs) do
            local modes = {}
            for _, mode in ipairs(lane.transportModes) do modes[mode] = true end
            lane.transportModes = modes -- the resource binding exposes transport modes as a set
            train = train or modes.TRAIN == true
            electrified = electrified or modes.ELECTRIC_TRAIN == true
        end
        if template.roadType == "TRACK" and train then
            template.roadType = context.api.type["enum"].RoadType.TRACK
            -- Native resource records expose empty defaults for omitted menu fields.
            template.menuCategory = template.menuCategory or { categories = {} }
            template.description = template.description or { name = "", icon = "" }
            template.availability = template.availability or { yearFrom = 0, yearTo = 0 }
            context.templates[entry.name] = template
            context.templateResourceNames[#context.templateResourceNames + 1] = entry.name
            context.templateIds[entry.name] = #context.templateResourceNames - 1
            electric[entry.name] = electrified
            for _, category in ipairs(template.menuCategory.categories) do
                if trackCategories[category.category] then
                    expected[entry.name] = true
                    if category.category ~= "tracks" then customCategories[entry.name] = true end
                end
            end
        end
    end
    local configured = context.runModScript({ apasz_zigzag = { apasz_zigzag_costs_enabled = 1 } })
    local choices = context.builders[configured].createTemplateScript.params.tracks
    local found, count, customCount = {}, 0, 0
    for _, choice in ipairs(choices) do
        if electric[choice.resourceName] ~= nil then
            assert(expected[choice.resourceName], "track outside the native Tracks menu was offered: " .. choice.resourceName)
            assert(choice.electrified == electric[choice.resourceName], "wrong electric capability: " .. choice.resourceName)
            assert(not found[choice.resourceName], "duplicate track choice")
            found[choice.resourceName] = true
        end
    end
    for name in pairs(expected) do
        assert(found[name], "installed track missing from picker: " .. name)
        count = count + 1
        if customCategories[name] then customCount = customCount + 1 end
        local result = context.runUpdate(configured.updateScript.params, {
            streetTemplate = name, catenary = electric[name] and 2 or 1,
            lengthMetres = 40, tracks = 2, passengerLoadingEnabled = 2, cargoLoadingEnabled = 2,
            cargoStorageCapacity = 1000, cargoStorageType = 3,
            signedStartCurveRadiusMetres = -1000, signedEndCurveRadiusMetres = 1000,
        })
        assert(result.edgeLists[1].params.type == name, "track identity changed during construction")
        assert(#result.subconstructions[2].stocks == 2, "installed track changed warehouse bays")
    end
    assert(customCount > 0, "expected installed tracks in custom menu categories")

    local function checkModifiers(modIds)
        local modifiers, modules = {}, {}
        local loadModModule
        local util = { useFn = function(reference)
            local script, fn = assert(reference:match("^(.-)@(.+)$"))
            if script:find("apasz_zigzag::/", 1, true) == 1 then
                assert(fn == "updateFn")
                return context.runUpdate
            end
            return assert(loadModModule(script .. ".lua")[fn], reference)
        end }
        loadModModule = function(reference)
            if reference == "::/scripts/util.tl" then return util end
            if modules[reference] ~= nil then return modules[reference] end
            local id, path = assert(reference:match("^(.-)::/(.+)$"))
            local env = setmetatable({ data = false, require = loadModModule, ug_require = loadModModule,
                print = function() end, debugPrint = function() end,
                getCurrentModId = function() return id end,
                addModifier = function(kind, fn)
                    modifiers[kind] = modifiers[kind] or {}
                    table.insert(modifiers[kind], fn)
                end,
            }, { __index = _G })
            local value = assert(loadfile(assert(fixtures.mods[id], id) .. "/" .. path, "t", env))()
            if type(env.data) == "function" then value = env.data() end
            modules[reference] = assert(value, reference)
            return value
        end
        for _, id in ipairs(modIds) do loadModModule(id .. "::/mod.script.lua").runFn({}, {}, {}) end
        local selected = context.runModScript(nil, nil, nil, function(construction)
            for _, modifier in ipairs(modifiers.loadConstruction or {}) do
                modifier("apasz_zigzag::/stations/rail/zigzag/zigzag.con", construction)
            end
        end)
        local singleBay = context.api.res.constructionRep.get("apasz_zigzag::/stations/rail/zigzag/zigzag_single_bay.con")
        for _, construction in ipairs({ selected, singleBay }) do
            local wrapper = construction.updateScript
            assert(wrapper.fileName == "bobdike_catchment_control::/catchment_control/construction.script@update",
                "post-run capture must preserve the installed construction wrapper")
            local update = util.useFn(wrapper.fileName)
            local script = { updateFn = update }
            for _, modifier in ipairs(modifiers.loadScript or {}) do
                script = modifier("apasz_zigzag::/stations/rail/zigzag/zigzag.script.lua", script)
            end
            for typeIndex = 1, 5 do
                local params = { lengthMetres = 80, tracks = 2, passengerLoadingEnabled = 2, cargoLoadingEnabled = 2,
                    cargoStorageCapacity = 1000, cargoStorageType = typeIndex,
                    signedStartCurveRadiusMetres = -500, signedEndCurveRadiusMetres = 500, bobdike_cc_cargo = 8 }
                local result = script.updateFn(wrapper.params, params)
                local baseline = context.runUpdate(wrapper.params.arguments, params)
                for _, area in ipairs(result.subconstructions[1].station.catchmentAreas) do
                    assert(area.radius == 300, "installed catchment wrapper must scale Zigzag's station")
                    area.radius = area.radius / 2
                end
                context.assertSameResult(result.edgeLists, baseline.edgeLists, "installed wrappers preserve curved tracks")
                context.assertSameResult(result.metadata, baseline.metadata, "installed wrappers preserve validation and bay metadata")
                context.assertSameResult(result.subconstructions[2], baseline.subconstructions[2], "installed wrappers preserve warehouse")
                assert(result.cost == baseline.cost and result.maintenanceCost == baseline.maintenanceCost,
                    "installed wrappers preserve captured costs")
                -- Passenger Cargo Unloading deliberately enables freight at the passenger terminal.
                local terminal = result.subconstructions[1].station.terminals[1]
                assert(terminal.cargoUnload and terminal.passengers, "installed passenger freight modifier remains effective")
            end
        end
    end
    local mods = { "bobdike_catchment_control", "warehouse_stock_limits_1", "sushiflux_modularbuildahead", "pz7_pax_cargo_unload_1" }
    for _, id in ipairs(mods) do assert(fixtures.mods[id], "compatibility fixture requires " .. id) end
    checkModifiers(mods)
    local reverse = {}
    for index = #mods, 1, -1 do reverse[#reverse + 1] = mods[index] end
    checkModifiers(reverse)
    print(string.format("mod_compatibility_check: ok (%d installed track choices, %d in custom categories; %d modifiers in both orders)",
        count, customCount, #mods))
end
