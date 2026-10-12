local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local param_util = ug_require("::/scripts/construction/param_util.tl")

local LENGTHS_METRES = {
   5, 10, 20, 40, 80, 120, 160, 200, 240, 280, 320, 360, 400, 440,
}

local LEGACY_LENGTHS_METRES = { 10, 40, 80, 120, 160, 240, 320 }
local TRACK_COUNTS = { 1, 2, 3, 4, 5, 6, 7, 8 }
local TRACK_SPACINGS_METRES = {
   3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
}
local CATCHMENT_RADII_METRES = {
   50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300,
}
local PASSENGER_CAPACITY_MULTIPLIERS = {
   0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
}
local DEFAULT_LENGTH_METRES = 10
local DEFAULT_TRACK_COUNT_INDEX = 1
local DEFAULT_TRACK_SPACING_METRES = 5
local DEFAULT_CATCHMENT_RADIUS_METRES = 150
local DEFAULT_PASSENGER_CAPACITY_MULTIPLIER = 1
local DEFAULT_TRACK_TYPE_INDEX = 2
local LOADING_DISABLED_INDEX = 1
local LOADING_ENABLED_INDEX = 2
local MODULE_LENGTH_METRES = 40
local PASSENGER_LOADING_PARAM_KEY = "passengerLoadingEnabled"
local CARGO_LOADING_PARAM_KEY = "cargoLoadingEnabled"
local LOADING_VISIBILITY_SCRIPT = "zigzag.params.gui@checkLoadingVisibility"
local ICON_FILE = "zigzag.tga"
local PREVIEW_ICON_FILE = "zigzag_preview.tga"
local STATION_NAME_KEY = "apasz_zigzag_name"
local STATION_DESCRIPTION_KEY = "apasz_zigzag_description"
local STATION_NAME_PREFIX_KEY = "apasz_zigzag_name_prefix"
local LENGTH_KEY = "apasz_zigzag_length"
local TRACKS_KEY = "apasz_zigzag_tracks"
local TRACK_SPACING_KEY = "apasz_zigzag_track_spacing"
local PASSENGER_LOADING_KEY = "apasz_zigzag_passenger_loading_enabled"
local PASSENGER_CAPACITY_KEY = "apasz_zigzag_passenger_capacity"
local CARGO_LOADING_KEY = "apasz_zigzag_cargo_loading_enabled"
local CATCHMENT_RADIUS_KEY = "apasz_zigzag_catchment_radius"
local OFF_KEY = "apasz_zigzag_off"
local ON_KEY = "apasz_zigzag_on"

local function makeNumberLabels(values, suffix)
   local labels = {}
   for _, value in ipairs(values) do
      labels[#labels + 1] = tostring(value) .. suffix
   end
   return labels
end

local function makeMultiplierLabels(values)
   local labels = {}
   for _, value in ipairs(values) do
      labels[#labels + 1] = string.format("%g×", value)
   end
   return labels
end

local function requireValueIndex(values, requiredValue)
   for index, value in ipairs(values) do
      if value == requiredValue then
         return index
      end
   end
   error("Missing required parameter value " .. tostring(requiredValue))
end

local DEFAULT_LENGTH_INDEX = requireValueIndex(
LENGTHS_METRES,
DEFAULT_LENGTH_METRES)

local DEFAULT_TRACK_SPACING_INDEX = requireValueIndex(
TRACK_SPACINGS_METRES,
DEFAULT_TRACK_SPACING_METRES)

local DEFAULT_CATCHMENT_RADIUS_INDEX = requireValueIndex(
CATCHMENT_RADII_METRES,
DEFAULT_CATCHMENT_RADIUS_METRES)

local DEFAULT_PASSENGER_CAPACITY_MULTIPLIER_INDEX = requireValueIndex(
PASSENGER_CAPACITY_MULTIPLIERS,
DEFAULT_PASSENGER_CAPACITY_MULTIPLIER)


local function makeDefaultTrackTypeParam(highSpeedAvailable)
   local param
   if highSpeedAvailable then
      param = param_util.makeTrackTypeHighSpeedParam()
   else
      param = param_util.makeTrackTypeDefaultParam()
   end
   param.defaultIndex = DEFAULT_TRACK_TYPE_INDEX
   return param
end

local function makeLoadingVisibilityCheck(
   enabledParamKeys)

   return {
      fileName = LOADING_VISIBILITY_SCRIPT,
      params = {
         enabledParamKeys = enabledParamKeys,
         enabledIndex = LOADING_ENABLED_INDEX,
      },
   }
end

local function makeTemplates()
   return {
      {
         type = "DYNAMIC",
         configureLayerScript = {
            fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
            params = {
               heightmapContours = true,
            },
         },
         configureHudIconsScript = {
            fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
            params = {
               cargo = true,
               rail = true,
            },
         },
         availability = {
            yearFrom = 0,
            yearTo = 0,
         },
         description = {
            name = _(STATION_NAME_KEY),
            description = _(STATION_DESCRIPTION_KEY),
            icon = ICON_FILE,
            previewIcon = PREVIEW_ICON_FILE,
            attributes = {
               maintenanceCost = { 0, 0 },
               cost = { 0, 0 },
            },
         },
         data = {
            params = {},
         },
         menuCategory = {
            categories = {
               {
                  category = "rail_buildings",
                  order = 4500,
               },
            },
         },
      },
   }
end

function data()
   return {
      configureLayerScript = {
         fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
         params = {
            heightmapContours = true,
         },
      },
      namePrefix = _(STATION_NAME_PREFIX_KEY),
      subConstructionNamePrefix = "{constructionName}",
      description = {
         name = _(STATION_NAME_KEY),
         description = _(STATION_DESCRIPTION_KEY),
         icon = ICON_FILE,
         previewIcon = PREVIEW_ICON_FILE,
      },
      availability = {
         yearFrom = 0,
         yearTo = 0,
      },
      order = 4500,
      constructionTemplates = makeTemplates(),
      createTemplateScript = {
         fileName = "zigzag.script@createTemplateFn",
         params = {},
      },
      updateScript = {
         fileName = "zigzag.script@updateFn",
         params = {
            lengthsMetres = LENGTHS_METRES,
            legacyLengthsMetres = LEGACY_LENGTHS_METRES,
            trackCounts = TRACK_COUNTS,
            trackSpacingsMetres = TRACK_SPACINGS_METRES,
            catchmentRadiiMetres = CATCHMENT_RADII_METRES,
            passengerCapacityMultipliers = PASSENGER_CAPACITY_MULTIPLIERS,
            defaultLengthMetres = DEFAULT_LENGTH_METRES,
            defaultTrackCountIndex = DEFAULT_TRACK_COUNT_INDEX,
            defaultTrackSpacingIndex = DEFAULT_TRACK_SPACING_INDEX,
            defaultCatchmentRadiusMetres = DEFAULT_CATCHMENT_RADIUS_METRES,
            defaultPassengerCapacityMultiplier = DEFAULT_PASSENGER_CAPACITY_MULTIPLIER,
            defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
            loadingDisabledIndex = LOADING_DISABLED_INDEX,
            loadingEnabledIndex = LOADING_ENABLED_INDEX,
            moduleLengthMetres = MODULE_LENGTH_METRES,
            costMode = "MODULE_COST",
            trackCostProfiles = {},
            platformCostProfiles = {},
         },
      },
      upgradeScript = {
         fileName = "zigzag.script@upgradeFn",
         params = {
            defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
         },
      },
      isAffectedByToolScript = {
         fileName = "zigzag.script@isAffectedByToolFn",
         params = {
            defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
         },
      },
      params = {
         {
            key = "tracks",
            name = _(TRACKS_KEY),
            values = makeNumberLabels(TRACK_COUNTS, ""),
            defaultIndex = DEFAULT_TRACK_COUNT_INDEX,
            displayMode = "Horizontal",
         },
         {
            key = "trackSpacingMetres",
            name = _(TRACK_SPACING_KEY),
            values = makeNumberLabels(TRACK_SPACINGS_METRES, " m"),
            numbers = TRACK_SPACINGS_METRES,
            defaultIndex = DEFAULT_TRACK_SPACING_INDEX,
            uiType = "Slider",
         },
         {
            key = "lengthMetres",
            name = _(LENGTH_KEY),
            values = makeNumberLabels(LENGTHS_METRES, " m"),
            numbers = LENGTHS_METRES,
            defaultIndex = DEFAULT_LENGTH_INDEX,
            uiType = "Slider",
         },
         makeDefaultTrackTypeParam(false),
         makeDefaultTrackTypeParam(true),
         param_util.makeTrackCatenaryParam(),
         {
            key = PASSENGER_LOADING_PARAM_KEY,
            name = _(PASSENGER_LOADING_KEY),
            values = { _(OFF_KEY), _(ON_KEY) },
            defaultIndex = LOADING_DISABLED_INDEX,
            uiType = "CheckBox",
         },
         {
            key = "passengerCapacityMultiplier",
            name = _(PASSENGER_CAPACITY_KEY),
            values = makeMultiplierLabels(PASSENGER_CAPACITY_MULTIPLIERS),
            numbers = PASSENGER_CAPACITY_MULTIPLIERS,
            defaultIndex = DEFAULT_PASSENGER_CAPACITY_MULTIPLIER_INDEX,
            uiType = "Slider",
            checkEnabledScript = makeLoadingVisibilityCheck({
               PASSENGER_LOADING_PARAM_KEY,
            }),
         },
         {
            key = CARGO_LOADING_PARAM_KEY,
            name = _(CARGO_LOADING_KEY),
            values = { _(OFF_KEY), _(ON_KEY) },
            defaultIndex = LOADING_DISABLED_INDEX,
            uiType = "CheckBox",
         },
         {
            key = "catchmentRadiusMetres",
            name = _(CATCHMENT_RADIUS_KEY),
            values = makeNumberLabels(CATCHMENT_RADII_METRES, " m"),
            numbers = CATCHMENT_RADII_METRES,
            defaultIndex = DEFAULT_CATCHMENT_RADIUS_INDEX,
            uiType = "Slider",
            checkEnabledScript = makeLoadingVisibilityCheck({
               PASSENGER_LOADING_PARAM_KEY,
               CARGO_LOADING_PARAM_KEY,
            }),
         },
      },
   }
end
