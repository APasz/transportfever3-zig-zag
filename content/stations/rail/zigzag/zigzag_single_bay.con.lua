local definition = ug_require(
"apasz_zigzag::/zigzag/station_definition.lua")


function data()
   return definition.makeConstruction("SINGLE_BAY")
end
