local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local param_util = ug_require("::/scripts/construction/param_util.tl")

local LENGTHS_METRES = { 10, 40, 80, 120, 160, 240, 320 }
local DEFAULT_LENGTH_INDEX = 1
local DEFAULT_TRACK_TYPE_INDEX = 2
local COST_PER_METRE = 750
local MAINTENANCE_COST_PER_METRE = 12.5
local ICON_FILE = "zigzag.tga"
local PREVIEW_ICON_FILE = "zigzag_preview.tga"
local STATION_NAME_KEY = "apasz_zigzag_name"
local STATION_DESCRIPTION_KEY = "apasz_zigzag_description"
local STATION_NAME_PREFIX_KEY = "apasz_zigzag_name_prefix"
local LENGTH_KEY = "apasz_zigzag_length"

local function makeLengthLabels(lengths)
   local labels = {}
   for _, length in ipairs(lengths) do
      labels[#labels + 1] = tostring(length) .. " m"
   end
   return labels
end

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
               cargo = false,
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
               maintenanceCost = {
                  LENGTHS_METRES[1] * MAINTENANCE_COST_PER_METRE,
                  LENGTHS_METRES[#LENGTHS_METRES] * MAINTENANCE_COST_PER_METRE,
               },
               cost = {
                  LENGTHS_METRES[1] * COST_PER_METRE,
                  LENGTHS_METRES[#LENGTHS_METRES] * COST_PER_METRE,
               },
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
            defaultLengthIndex = DEFAULT_LENGTH_INDEX,
            defaultTrackTypeIndex = DEFAULT_TRACK_TYPE_INDEX,
            costPerMetre = COST_PER_METRE,
            maintenanceCostPerMetre = MAINTENANCE_COST_PER_METRE,
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
            key = "length",
            name = _(LENGTH_KEY),
            values = makeLengthLabels(LENGTHS_METRES),
            defaultIndex = DEFAULT_LENGTH_INDEX,
            displayMode = "Sparse",
         },
         makeDefaultTrackTypeParam(false),
         makeDefaultTrackTypeParam(true),
         param_util.makeTrackCatenaryParam(),
      },
   }
end
