local definition = ug_require(
    "apasz_zigzag::/zigzag/station_definition.lua"
) as ZigzagStationDefinition

function data(): any
    return definition.makeConstruction("MODULE_BAYS")
end
