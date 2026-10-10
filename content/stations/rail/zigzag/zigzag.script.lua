local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local lane_util = ug_require("::/scripts/construction/laneutil.lua")
local param_util = ug_require("::/scripts/construction/param_util.tl")

local CATENARY_DISABLED_INDEX = 1
local CATENARY_ENABLED_INDEX = 2
local SNAP_ANGLE_DEGREES = 60
local NEGATIVE_TRACK_SNAP_NODE_INDEX = 0
local TERMINAL_TRACK_NODE_INDEX = 1
local POSITIVE_TRACK_SNAP_NODE_INDEX = 3
local STATION_TAG = 1
local NON_LOADING_LANE_INDEX = 0
local NON_LOADING_LANE_EDGE_INDEX = 0
local NON_LOADING_LANE_NODE_INDEX = 0






















































































local function requireLength(captureParams, params)
   local lengthIndex = captureParams.defaultLengthIndex
   if params.length ~= nil then
      lengthIndex = params.length
   end
   local length = captureParams.lengthsMetres[lengthIndex]
   if length == nil or length <= 0 then
      error("Zigzag Station received invalid length index " .. tostring(lengthIndex))
   end
   return length
end

local function requireStreetTemplate(resourceName)
   return api.res.streetTemplateRep.findAndGet(resourceName)
end

local function supportsTransportMode(
   streetTemplate,
   transportMode)

   for _, laneConfig in ipairs(streetTemplate.laneConfigs) do
      if laneConfig.transportModes[transportMode] then
         return true
      end
   end
   return false
end

local function isElectrifiedTrack(streetTemplate)
   return supportsTransportMode(
   streetTemplate,
   api.type["enum"].TransportMode.ELECTRIC_TRAIN)

end

local function makeTrackTransportModes(
   catenaryEnabled)

   local transportModes = { "TRAIN" }
   if catenaryEnabled then
      transportModes[#transportModes + 1] = "ELECTRIC_TRAIN"
   end
   return transportModes
end

local function requireCatenaryEnabled(catenaryIndex)
   local catenary = catenaryIndex or CATENARY_DISABLED_INDEX
   if catenary ~= CATENARY_DISABLED_INDEX and catenary ~= CATENARY_ENABLED_INDEX then
      error("Zigzag Station received invalid catenary index " .. tostring(catenary))
   end
   return catenary == CATENARY_ENABLED_INDEX
end

local function requireTrackType(
   params,
   defaultTrackTypeIndex,
   catenaryEnabled)

   if params.streetTemplate ~= nil then
      return params.streetTemplate
   end

   local trackTypes = param_util.getRailTrackTypes(catenaryEnabled)
   local trackTypeIndex = defaultTrackTypeIndex
   if params.trackType ~= nil then
      trackTypeIndex = params.trackType
   end
   local trackType = trackTypes[trackTypeIndex]
   if trackType == nil then
      error("Zigzag Station received invalid track type index " .. tostring(trackTypeIndex))
   end
   return trackType
end

local function getCatenaryReplacement(
   streetTemplate,
   catenaryEnabled)

   local replacement
   if catenaryEnabled then
      replacement = streetTemplate.catenaryAdd
   else
      replacement = streetTemplate.catenaryRemove
   end
   if replacement == nil or replacement == "" then
      return nil
   end
   return replacement
end

local function supportsCatenaryConfig(
   streetTemplate,
   constructionConfig)

   if constructionConfig.catenary == nil then
      return false
   end
   local catenaryEnabled = requireCatenaryEnabled(constructionConfig.catenary)
   return getCatenaryReplacement(streetTemplate, catenaryEnabled) ~= nil
end

local function makeTrackEdgeList(length, trackType)
   local halfLength = length / 2
   local tangent = { 0, halfLength, 0 }
   return {
      type = "TRACK",
      params = {
         type = trackType,
      },
      edges = {
         { { 0, -halfLength, 0 }, tangent },
         { { 0, 0, 0 }, tangent },
         { { 0, 0, 0 }, tangent },
         { { 0, halfLength, 0 }, tangent },
      },
      snapNodes = {
         NEGATIVE_TRACK_SNAP_NODE_INDEX,
         POSITIVE_TRACK_SNAP_NODE_INDEX,
      },
      tag2nodes = {},
      alignTerrain = true,
      maxNodeSnapAngle = SNAP_ANGLE_DEGREES,
   }
end

local function makeNonLoadingPersonLane()
   return lane_util.createLane(
   {
      {
         { -0.5, 0, 0 },
         { 0.5, 0, 0 },
      },
   },
   { "PERSON" },
   1,
   0,
   false)

end

local function makeStationSubconstruction(
   transportModes)

   return {
      tag = STATION_TAG,
      models = {},
      colliders = {},
      terrainAlignmentLists = {},
      groundFaces = {},


      laneLists = {
         makeNonLoadingPersonLane(),
      },
      emissionEmitter = {},
      station = {
         tag = STATION_TAG,
         terminals = {
            {
               tag = 0,
               personEdges = {
                  { NON_LOADING_LANE_INDEX, NON_LOADING_LANE_EDGE_INDEX },
               },
               personNodes = {
                  { NON_LOADING_LANE_INDEX, NON_LOADING_LANE_NODE_INDEX },
               },
               vehicleNode = { -1, TERMINAL_TRACK_NODE_INDEX },


               passengers = true,
               cargo = true,
               capacity = 0,
               comfortFactor = 1,
               cargoTransferSpeeds = {},
               transportModes = transportModes,
            },
         },
         pool = {
            edges = {},
            capacity = 0,
         },
         catchmentAreas = {},
      },
   }
end

local function updateFn(captureParams, params)
   local length = requireLength(captureParams, params)
   local catenaryEnabled = requireCatenaryEnabled(params.catenary)
   local trackType = requireTrackType(
   params,
   captureParams.defaultTrackTypeIndex,
   catenaryEnabled)

   local transportModes = makeTrackTransportModes(catenaryEnabled)
   return {
      edgeLists = {
         makeTrackEdgeList(length, trackType),
      },
      subconstructions = {
         makeStationSubconstruction(transportModes),
      },
      cost = length * captureParams.costPerMetre,
      maintenanceCost = length * captureParams.maintenanceCostPerMetre,
   }
end

local function createTemplateFn(_captureParams, _params)
   return {}
end

local function isAffectedByToolFn(
   captureParams,
   params,
   conConfigAdd,
   conConfigRemove)

   if conConfigAdd.streetTemplate ~= nil then
      local streetTemplate = requireStreetTemplate(conConfigAdd.streetTemplate)
      return streetTemplate.roadType == api.type["enum"].RoadType.TRACK
   end

   if conConfigAdd.catenary == nil and conConfigRemove.catenary == nil then
      return false
   end

   local catenaryEnabled = requireCatenaryEnabled(params.catenary)
   local trackType = requireTrackType(
   params,
   captureParams.defaultTrackTypeIndex,
   catenaryEnabled)

   local streetTemplate = requireStreetTemplate(trackType)
   return supportsCatenaryConfig(streetTemplate, conConfigAdd) or
   supportsCatenaryConfig(streetTemplate, conConfigRemove)
end

local function upgradeFn(
   captureParams,
   params,
   _slotId,
   constructionConfig)

   if constructionConfig.streetTemplate ~= nil then
      if constructionConfig.catenary ~= nil then
         requireCatenaryEnabled(constructionConfig.catenary)
      end
      local streetTemplate = requireStreetTemplate(constructionConfig.streetTemplate)
      if streetTemplate.roadType ~= api.type["enum"].RoadType.TRACK then
         error("Zigzag Station cannot use a non-track street template")
      end
      params.streetTemplate = constructionConfig.streetTemplate
      params.catenary = isElectrifiedTrack(streetTemplate) and
      CATENARY_ENABLED_INDEX or
      CATENARY_DISABLED_INDEX
   elseif constructionConfig.catenary ~= nil then
      local catenaryEnabled = requireCatenaryEnabled(constructionConfig.catenary)
      local currentCatenaryEnabled = requireCatenaryEnabled(params.catenary)
      local trackType = requireTrackType(
      params,
      captureParams.defaultTrackTypeIndex,
      currentCatenaryEnabled)

      local streetTemplate = requireStreetTemplate(trackType)
      if isElectrifiedTrack(streetTemplate) == catenaryEnabled then
         params.catenary = constructionConfig.catenary
         return params
      end

      local upgradedTrackType = getCatenaryReplacement(streetTemplate, catenaryEnabled)
      if upgradedTrackType ~= nil then
         local upgradedStreetTemplate = requireStreetTemplate(upgradedTrackType)
         if upgradedStreetTemplate.roadType ~= api.type["enum"].RoadType.TRACK or
            isElectrifiedTrack(upgradedStreetTemplate) ~= catenaryEnabled then
            error("Track template " .. trackType .. " has an invalid catenary replacement")
         end
         params.streetTemplate = upgradedTrackType
         params.catenary = constructionConfig.catenary
      end
   end
   return params
end

function data()
   return {
      createTemplateFn = createTemplateFn,
      updateFn = updateFn,
      isAffectedByToolFn = isAffectedByToolFn,
      upgradeFn = upgradeFn,
   }
end
