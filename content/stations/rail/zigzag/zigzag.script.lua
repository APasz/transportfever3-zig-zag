local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local lane_util = ug_require("::/scripts/construction/laneutil.lua")
local param_util = ug_require("::/scripts/construction/param_util.tl")

local CATENARY_DISABLED_INDEX = 1
local CATENARY_ENABLED_INDEX = 2
local SNAP_ANGLE_DEGREES = 60
local NODES_PER_TRACK = 8
local NEGATIVE_SNAP_NODE_OFFSET = 0
local PASSENGER_TERMINAL_NODE_OFFSET = 1
local NON_LOADING_TERMINAL_NODE_OFFSET = 3
local CARGO_TERMINAL_NODE_OFFSET = 5
local POSITIVE_SNAP_NODE_OFFSET = 7
local TERMINAL_NODE_SEPARATION_METRES = 1
local STATION_TAG = 1
local NON_LOADING_LANE_EDGE_INDEX = 0
local NON_LOADING_LANE_NODE_INDEX = 0
local LANE_SPEED_LIMIT = 30
local PASSENGER_LANE_WIDTH_METRES = 2.4
local CARGO_LANE_WIDTH_METRES = 4

local SERVICE_LANE_OFFSET_METRES = 0.5
local ACCESS_LANE_WIDTH_METRES = 1
local ACCESS_EXTENSION_METRES = 10
local PASSENGER_CAPACITY_PER_METRE = 1.7

















































































































local function requireAllowedValue(
   allowedValues,
   value,
   valueName)

   for _, allowedValue in ipairs(allowedValues) do
      if value == allowedValue then
         return value
      end
   end
   error("Zigzag Station received invalid " .. valueName .. " " .. tostring(value))
end

local function requireIndexedPositiveValue(
   values,
   index,
   valueName)

   local value = values[index]
   if value == nil or value <= 0 then
      error(
      "Zigzag Station received invalid " ..
      valueName ..
      " index " ..
      tostring(index))

   end
   return value
end

local function requireLength(captureParams, params)
   if params.lengthMetres ~= nil then
      return requireAllowedValue(
      captureParams.lengthsMetres,
      params.lengthMetres,
      "length")

   end

   local legacyLengthIndex = params.length
   if legacyLengthIndex ~= nil then
      return requireIndexedPositiveValue(
      captureParams.legacyLengthsMetres,
      legacyLengthIndex,
      "legacy length")

   end

   return requireAllowedValue(
   captureParams.lengthsMetres,
   captureParams.defaultLengthMetres,
   "default length")

end

local function requireTrackCount(
   captureParams,
   params)

   local trackCountIndex = captureParams.defaultTrackCountIndex
   if params.tracks ~= nil then
      trackCountIndex = params.tracks
   end
   return requireIndexedPositiveValue(
   captureParams.trackCounts,
   trackCountIndex,
   "track-count")

end

local function requireTrackSpacingMetres(
   captureParams,
   params)

   if params.trackSpacingMetres == nil then
      return requireIndexedPositiveValue(
      captureParams.trackSpacingsMetres,
      captureParams.defaultTrackSpacingIndex,
      "default track-spacing")

   end
   return requireAllowedValue(
   captureParams.trackSpacingsMetres,
   params.trackSpacingMetres,
   "track spacing")

end

local function requireToggleEnabled(
   captureParams,
   selectedIndex,
   defaultIndex,
   valueName)

   local loadingIndex = selectedIndex or defaultIndex
   if loadingIndex == captureParams.loadingDisabledIndex then
      return false
   end
   if loadingIndex == captureParams.loadingEnabledIndex then
      return true
   end
   error(
   "Zigzag Station received invalid " ..
   valueName ..
   " index " ..
   tostring(loadingIndex))

end

local function requireLoadingModes(
   captureParams,
   params)

   local legacyLoadingIndex = params.loadingEnabled
   local defaultLoadingIndex = captureParams.loadingDisabledIndex
   if legacyLoadingIndex ~= nil then
      requireToggleEnabled(
      captureParams,
      legacyLoadingIndex,
      captureParams.loadingDisabledIndex,
      "legacy loading")

      defaultLoadingIndex = legacyLoadingIndex
   end
   return requireToggleEnabled(
   captureParams,
   params.passengerLoadingEnabled,
   defaultLoadingIndex,
   "passenger-loading"),
   requireToggleEnabled(
   captureParams,
   params.cargoLoadingEnabled,
   defaultLoadingIndex,
   "cargo-loading")

end

local function requirePassengerCapacityMultiplier(
   captureParams,
   params)

   return requireAllowedValue(
   captureParams.passengerCapacityMultipliers,
   params.passengerCapacityMultiplier or
   captureParams.defaultPassengerCapacityMultiplier,
   "passenger capacity multiplier")

end

local function requireCatchmentRadiusMetres(
   captureParams,
   params)

   return requireAllowedValue(
   captureParams.catchmentRadiiMetres,
   params.catchmentRadiusMetres or
   captureParams.defaultCatchmentRadiusMetres,
   "catchment radius")

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

local function getTrackOffsetMetres(
   trackIndex,
   trackCount,
   trackSpacingMetres)

   return (trackIndex - (trackCount + 1) / 2) * trackSpacingMetres
end

local function addStraightTrackEdge(
   edges,
   trackOffsetMetres,
   firstLongitudinalOffsetMetres,
   secondLongitudinalOffsetMetres)

   local tangent = {
      0,
      secondLongitudinalOffsetMetres - firstLongitudinalOffsetMetres,
      0,
   }
   edges[#edges + 1] = {
      { trackOffsetMetres, firstLongitudinalOffsetMetres, 0 },
      tangent,
   }
   edges[#edges + 1] = {
      { trackOffsetMetres, secondLongitudinalOffsetMetres, 0 },
      tangent,
   }
end

local function makeTrackEdgeList(
   length,
   trackType,
   trackCount,
   trackSpacingMetres)

   local halfLength = length / 2
   local halfTerminalNodeSeparationMetres = TERMINAL_NODE_SEPARATION_METRES / 2
   local edges = {}
   local snapNodes = {}
   for trackIndex = 1, trackCount do
      local trackOffsetMetres = getTrackOffsetMetres(
      trackIndex,
      trackCount,
      trackSpacingMetres)

      local firstNodeIndex = (trackIndex - 1) * NODES_PER_TRACK
      addStraightTrackEdge(
      edges,
      trackOffsetMetres,
      -halfLength,
      -halfTerminalNodeSeparationMetres)

      addStraightTrackEdge(
      edges,
      trackOffsetMetres,
      -halfTerminalNodeSeparationMetres,
      0)

      addStraightTrackEdge(
      edges,
      trackOffsetMetres,
      0,
      halfTerminalNodeSeparationMetres)

      addStraightTrackEdge(
      edges,
      trackOffsetMetres,
      halfTerminalNodeSeparationMetres,
      halfLength)

      snapNodes[#snapNodes + 1] = firstNodeIndex + NEGATIVE_SNAP_NODE_OFFSET
      snapNodes[#snapNodes + 1] = firstNodeIndex + POSITIVE_SNAP_NODE_OFFSET
   end
   return {
      type = "TRACK",
      params = {
         type = trackType,
      },
      edges = edges,
      snapNodes = snapNodes,
      tag2nodes = {},
      alignTerrain = true,
      maxNodeSnapAngle = SNAP_ANGLE_DEGREES,
   }
end

local function makeCombinedNonLoadingLane(
   trackOffsetMetres,
   transportMode)

   return lane_util.createLane(
   {
      {
         { trackOffsetMetres - 0.5, 0, 0 },
         { trackOffsetMetres + 0.5, 0, 0 },
      },
   },
   { transportMode },
   1,
   0,
   false)

end

local function makeDisabledLoadingLane(
   laneOffsetMetres,
   transportMode)

   return lane_util.createLane(
   {
      {
         { laneOffsetMetres, -0.5, 0 },
         { laneOffsetMetres, 0.5, 0 },
      },
   },
   { transportMode },
   1,
   0,
   false)

end

local function makeServiceLane(
   laneOffsetMetres,
   length,
   transportMode,
   widthMetres)

   local halfLength = length / 2
   return lane_util.createLane(
   {
      {
         { laneOffsetMetres, -halfLength, 0 },
         { laneOffsetMetres, 0, 0 },
      },
      {
         { laneOffsetMetres, 0, 0 },
         { laneOffsetMetres, halfLength, 0 },
      },
   },
   { transportMode },
   LANE_SPEED_LIMIT,
   widthMetres,
   false)

end

local function makePassengerAccessLane(
   firstTrackOffsetMetres,
   lastTrackOffsetMetres,
   passengerLaneOffsetsMetres,
   longitudinalOffsetMetres)

   local accessPoints = {
      {
         firstTrackOffsetMetres - ACCESS_EXTENSION_METRES,
         longitudinalOffsetMetres,
         0,
      },
   }
   for _, passengerLaneOffsetMetres in ipairs(passengerLaneOffsetsMetres) do
      accessPoints[#accessPoints + 1] = {
         passengerLaneOffsetMetres,
         longitudinalOffsetMetres,
         0,
      }
   end
   accessPoints[#accessPoints + 1] = {
      lastTrackOffsetMetres + ACCESS_EXTENSION_METRES,
      longitudinalOffsetMetres,
      0,
   }

   local accessSegments = {}
   for pointIndex = 1, #accessPoints - 1 do
      accessSegments[#accessSegments + 1] = {
         accessPoints[pointIndex],
         accessPoints[pointIndex + 1],
      }
   end
   return lane_util.createLane(
   accessSegments,
   { "PERSON" },
   LANE_SPEED_LIMIT,
   ACCESS_LANE_WIDTH_METRES,
   true)

end

local function makeCargoTransferSpeed(
   cargoClass,
   length)

   return {
      cargoTypeSet = {
         cargoClassesIncluded = { cargoClass },
         cargoClassesExcluded = {},
         cargoTypesIncluded = {},
         cargoTypesExcluded = {},
      },
      loadSpeedModifier = 1,
      length = length,
   }
end

local function makeTerminal(
   tag,
   laneListIndex,
   vehicleNodeIndex,
   passengers,
   cargo,
   capacity,
   cargoTransferSpeeds,
   transportModes)

   return {
      tag = tag,
      personEdges = {
         { laneListIndex, 0 },
         { laneListIndex, 1 },
      },
      personNodes = {
         { laneListIndex, 1 },
      },
      vehicleNode = { -1, vehicleNodeIndex },
      passengers = passengers,
      cargo = cargo,
      capacity = capacity,
      comfortFactor = 1,
      cargoTransferSpeeds = cargoTransferSpeeds,
      transportModes = transportModes,
   }
end

local function makeNonLoadingTerminal(
   tag,
   laneListIndex,
   vehicleNodeIndex,
   passengers,
   cargo,
   transportModes)

   return {
      tag = tag,
      personEdges = {
         { laneListIndex, NON_LOADING_LANE_EDGE_INDEX },
      },
      personNodes = {
         { laneListIndex, NON_LOADING_LANE_NODE_INDEX },
      },
      vehicleNode = { -1, vehicleNodeIndex },
      passengers = passengers,
      cargo = cargo,
      capacity = 0,
      comfortFactor = 1,
      cargoTransferSpeeds = {},
      transportModes = transportModes,
   }
end

local function passengerCapacity(length, multiplier)
   local baseCapacity = math.max(
   math.floor(length * PASSENGER_CAPACITY_PER_METRE + 0.5),
   1)

   return math.max(math.floor(baseCapacity * multiplier + 0.5), 1)
end

local function makeStationSubconstruction(
   length,
   trackCount,
   trackSpacingMetres,
   passengerLoadingEnabled,
   cargoLoadingEnabled,
   passengerCapacityMultiplier,
   catchmentRadiusMetres,
   transportModes)

   local laneLists = {}
   local terminals = {}
   local passengerLaneOffsetsMetres = {}
   local loadingEnabled = passengerLoadingEnabled or cargoLoadingEnabled
   for trackIndex = 1, trackCount do
      local zeroBasedTrackIndex = trackIndex - 1
      local trackOffsetMetres = getTrackOffsetMetres(
      trackIndex,
      trackCount,
      trackSpacingMetres)

      local firstTrackNodeIndex = zeroBasedTrackIndex * NODES_PER_TRACK
      local passengerVehicleNodeIndex = firstTrackNodeIndex +
      PASSENGER_TERMINAL_NODE_OFFSET
      local nonLoadingVehicleNodeIndex = firstTrackNodeIndex +
      NON_LOADING_TERMINAL_NODE_OFFSET
      local cargoVehicleNodeIndex = firstTrackNodeIndex +
      CARGO_TERMINAL_NODE_OFFSET
      local passengerLaneOffsetMetres = trackOffsetMetres -
      SERVICE_LANE_OFFSET_METRES
      local cargoLaneOffsetMetres = trackOffsetMetres +
      SERVICE_LANE_OFFSET_METRES
      if loadingEnabled then


         local passengerLaneIndex = #laneLists
         if passengerLoadingEnabled then
            passengerLaneOffsetsMetres[#passengerLaneOffsetsMetres + 1] =
passengerLaneOffsetMetres
            laneLists[#laneLists + 1] = makeServiceLane(
            passengerLaneOffsetMetres,
            length,
            "PERSON",
            PASSENGER_LANE_WIDTH_METRES)

            terminals[#terminals + 1] = makeTerminal(
            zeroBasedTrackIndex * 2,
            passengerLaneIndex,
            passengerVehicleNodeIndex,
            true,
            false,
            passengerCapacity(length, passengerCapacityMultiplier),
            { makeCargoTransferSpeed("PASSENGERS", length) },
            transportModes)

         else
            laneLists[#laneLists + 1] = makeDisabledLoadingLane(
            passengerLaneOffsetMetres,
            "PERSON")

            terminals[#terminals + 1] = makeNonLoadingTerminal(
            zeroBasedTrackIndex * 2,
            passengerLaneIndex,
            passengerVehicleNodeIndex,
            true,
            false,
            transportModes)

         end

         local cargoLaneIndex = #laneLists
         if cargoLoadingEnabled then
            laneLists[#laneLists + 1] = makeServiceLane(
            cargoLaneOffsetMetres,
            length,
            "CARGO",
            CARGO_LANE_WIDTH_METRES)

            terminals[#terminals + 1] = makeTerminal(
            zeroBasedTrackIndex * 2 + 1,
            cargoLaneIndex,
            cargoVehicleNodeIndex,
            false,
            true,
            0,
            { makeCargoTransferSpeed("UNIVERSAL", length) },
            transportModes)

         else
            laneLists[#laneLists + 1] = makeDisabledLoadingLane(
            cargoLaneOffsetMetres,
            "CARGO")

            terminals[#terminals + 1] = makeNonLoadingTerminal(
            zeroBasedTrackIndex * 2 + 1,
            cargoLaneIndex,
            cargoVehicleNodeIndex,
            false,
            true,
            transportModes)

         end
      else
         local laneListIndex = #laneLists
         laneLists[#laneLists + 1] = makeCombinedNonLoadingLane(
         trackOffsetMetres,
         "PERSON")

         terminals[#terminals + 1] = makeNonLoadingTerminal(
         zeroBasedTrackIndex,
         laneListIndex,
         nonLoadingVehicleNodeIndex,
         true,
         true,
         transportModes)

      end
   end

   local catchmentAreas = {}
   if loadingEnabled then
      local halfLength = length / 2
      local firstTrackOffsetMetres = getTrackOffsetMetres(
      1,
      trackCount,
      trackSpacingMetres)

      local lastTrackOffsetMetres = getTrackOffsetMetres(
      trackCount,
      trackCount,
      trackSpacingMetres)

      local accessLaneOffsetsMetres = { -halfLength, 0, halfLength }
      for _, longitudinalOffsetMetres in ipairs(accessLaneOffsetsMetres) do
         if passengerLoadingEnabled then
            laneLists[#laneLists + 1] = makePassengerAccessLane(
            firstTrackOffsetMetres,
            lastTrackOffsetMetres,
            passengerLaneOffsetsMetres,
            longitudinalOffsetMetres)

         end
         catchmentAreas[#catchmentAreas + 1] = {
            position = { 0.0, longitudinalOffsetMetres, 0.0 },
            radius = catchmentRadiusMetres,
         }
      end
   end
   return {
      tag = STATION_TAG,
      models = {},
      colliders = {},
      terrainAlignmentLists = {},
      groundFaces = {},


      laneLists = laneLists,
      emissionEmitter = {},
      station = {
         tag = STATION_TAG,
         terminals = terminals,
         pool = {
            edges = {},
            capacity = 0,
         },
         catchmentAreas = catchmentAreas,
      },
   }
end

local function updateFn(captureParams, params)
   local length = requireLength(captureParams, params)
   local trackCount = requireTrackCount(captureParams, params)
   local trackSpacingMetres = requireTrackSpacingMetres(captureParams, params)
   local passengerLoadingEnabled, cargoLoadingEnabled = requireLoadingModes(
   captureParams,
   params)

   local passengerCapacityMultiplier = requirePassengerCapacityMultiplier(
   captureParams,
   params)

   local catchmentRadiusMetres = requireCatchmentRadiusMetres(captureParams, params)
   local catenaryEnabled = requireCatenaryEnabled(params.catenary)
   local trackType = requireTrackType(
   params,
   captureParams.defaultTrackTypeIndex,
   catenaryEnabled)

   local transportModes = makeTrackTransportModes(catenaryEnabled)
   return {
      edgeLists = {
         makeTrackEdgeList(
         length,
         trackType,
         trackCount,
         trackSpacingMetres),

      },
      subconstructions = {
         makeStationSubconstruction(
         length,
         trackCount,
         trackSpacingMetres,
         passengerLoadingEnabled,
         cargoLoadingEnabled,
         passengerCapacityMultiplier,
         catchmentRadiusMetres,
         transportModes),

      },
      cost = length * trackCount * captureParams.costPerMetre,
      maintenanceCost = length * trackCount * captureParams.maintenanceCostPerMetre,
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
