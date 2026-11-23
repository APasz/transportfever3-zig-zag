local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local lane_util = ug_require("::/scripts/construction/laneutil.lua")
local street_util = ug_require(
"::/scripts/construction/street_util_serialized.tl")

local validationMetadata = ug_require(
"apasz_zigzag::/zigzag/validation_metadata.lua")

local cargoStorage = ug_require(
"apasz_zigzag::/zigzag/cargo_storage.lua")

local param_util = ug_require("::/scripts/construction/param_util.tl")
local trackSelection = ug_require(
"apasz_zigzag::/zigzag/track_selection.lua")

local logging = ug_require(
"apasz_zigzag::/zigzag/logging.lua")

local logger = logging.new("Zigzag Station", false)

local requireCatenaryEnabled = trackSelection.catenaryEnabled
local SNAP_ANGLE_DEGREES = 60
local MAX_SEGMENT_TURN_RADIANS = math.rad(10)
local MAX_END_TURN_RADIANS = math.pi / 2
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































































































































local function addCost(
   total,
   rate,
   quantity)

   total.construction = total.construction + rate.construction * quantity
   total.maintenance = total.maintenance + rate.maintenance * quantity
end

local function trackCostRate(
   captureParams,
   trackType)

   local profile = captureParams.trackCostProfiles[trackType]
   local rate = trackSelection.costRate(profile, captureParams.costMode)
   if rate ~= nil then
      return rate
   end
   local costType = captureParams.costMode == "TRACK_COST" and "per-metre" or "generated module"
   logger.warnOnce(
   costType .. ":" .. trackType,
   "Missing or invalid " .. costType .. " cost for track " .. trackType ..
   "; using zero track construction and maintenance costs")

   return trackSelection.zeroCostRate
end

local function requirePlatformCostProfile(
   captureParams,
   year)

   local selectedProfile = nil
   for _, profile in ipairs(captureParams.platformCostProfiles) do
      if profile.yearFrom <= year then
         if selectedProfile == nil or
            profile.yearFrom >
            (selectedProfile).yearFrom then

            selectedProfile = profile
         end
      end
   end
   if selectedProfile == nil then
      error("Zigzag Station has no platform cost profile for year " .. tostring(year))
   end
   return selectedProfile
end

local function calculateCosts(
   captureParams,
   params,
   length,
   trackCount,
   trackType,
   passengerLoadingEnabled,
   cargoLoadingEnabled,
   cargoStorageCapacity)

   local mode = captureParams.costMode
   if mode == "NO_COST" then
      return trackSelection.zeroCostRate
   end

   local total = { construction = 0, maintenance = 0 }
   if mode == "TRACK_COST" then
      local trackRate = trackCostRate(captureParams, trackType)
      addCost(total, trackRate, length * trackCount)
      return total
   end
   if mode ~= "MODULE_COST" and mode ~= "STATION_COST" then
      error("Zigzag Station received invalid cost mode " .. tostring(mode))
   end

   local trackModuleRate = trackCostRate(captureParams, trackType)
   if captureParams.moduleLengthMetres <= 0 then
      error("Zigzag Station requires a positive module length")
   end
   local moduleCountAlongLength = length / captureParams.moduleLengthMetres
   addCost(total, trackModuleRate, moduleCountAlongLength * trackCount)
   if cargoStorageCapacity > 0 then
      local profile = cargoStorage.requireProfile(params.cargoStorageType)
      local storageRate = captureParams.cargoStorageCostProfiles[profile.kind]
      if storageRate == nil then
         error("Zigzag Station has no cargo storage cost profile")
      end
      addCost(total, storageRate, cargoStorageCapacity)
   end

   if mode == "STATION_COST" and
      (passengerLoadingEnabled or cargoLoadingEnabled) then

      local platformProfile = requirePlatformCostProfile(
      captureParams,
      params.year or 0)

      local platformRows = math.floor(trackCount / 2) + 1
      local platformModuleCount = moduleCountAlongLength * platformRows
      if passengerLoadingEnabled then
         addCost(total, platformProfile.passenger, platformModuleCount)
      end
      if cargoLoadingEnabled then
         addCost(total, platformProfile.cargo, platformModuleCount)
      end
   end

   return total
end

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

local function isElectrifiedTrack(streetTemplate)
   return trackSelection.supportsTransportMode(
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

local function requireEndCurvature(
   captureParams,
   signedRadius,
   minimumRadius,
   endName,
   validationErrors)

   if signedRadius == 0 then
      return 0
   end
   local radius = requireAllowedValue(
   captureParams.curveRadiiMetres,
   signedRadius < 0 and -signedRadius or signedRadius,
   endName)

   if radius < minimumRadius then
      validationErrors[#validationErrors + 1] = endName .. ": " .. string.format(
      _("apasz_zigzag_curve_radius_too_small"),
      radius,
      math.ceil(minimumRadius))

   end
   return -1 / signedRadius
end

local function makeCurveGeometry(
   captureParams,
   params,
   length,
   trackCount,
   trackSpacingMetres,
   trackType)

   local startRadius = params.signedStartCurveRadiusMetres or 0
   local endRadius = params.signedEndCurveRadiusMetres or 0
   local minimumRadius = 0
   if startRadius ~= 0 or endRadius ~= 0 then
      local minimumTrackRadius = captureParams.trackMinimumRadiiMetres[trackType]
      if minimumTrackRadius == nil then
         error("Zigzag Station has no minimum-radius data for track " .. trackType)
      end
      local halfWidth = (trackCount - 1) * trackSpacingMetres / 2

      minimumRadius = math.max(
      minimumTrackRadius + halfWidth,
      (length / 2) / MAX_END_TURN_RADIANS,
      math.floor(halfWidth + ACCESS_EXTENSION_METRES) + 1)

   end
   local validationErrors = {}
   return {
      startCurvaturePerMetre = requireEndCurvature(
      captureParams, startRadius, minimumRadius, _("apasz_zigzag_start_curve_radius"),
      validationErrors),

      endCurvaturePerMetre = requireEndCurvature(
      captureParams, endRadius, minimumRadius, _("apasz_zigzag_end_curve_radius"),
      validationErrors),

      lengthMetres = length,
   }, validationErrors
end

local function curvatureAt(curve, longitudinalMetres)
   if longitudinalMetres < 0 then
      return curve.startCurvaturePerMetre
   end
   return curve.endCurvaturePerMetre
end

local function longitudinalScale(curvaturePerMetre, offsetMetres)
   return 1 + curvaturePerMetre * offsetMetres
end

local function curvePosition(
   curve,
   offsetMetres,
   longitudinalMetres)

   local curvature = curvatureAt(curve, longitudinalMetres)
   if curvature == 0 then
      return { offsetMetres, longitudinalMetres, 0 }
   end
   local angle = curvature * longitudinalMetres

   local lateral = -2 * math.sin(angle / 2) ^ 2 / curvature
   return {
      lateral + offsetMetres * math.cos(angle),
      math.sin(angle) / curvature + offsetMetres * math.sin(angle),
      0,
   }
end

local function addCurveNodes(
   nodes,
   curve,
   trackOffsetMetres,
   firstLongitudinalOffsetMetres,
   secondLongitudinalOffsetMetres,
   widthMetres)

   if firstLongitudinalOffsetMetres < 0 and secondLongitudinalOffsetMetres > 0 then
      addCurveNodes(nodes, curve, trackOffsetMetres, firstLongitudinalOffsetMetres, 0, widthMetres)
      addCurveNodes(nodes, curve, trackOffsetMetres, 0, secondLongitudinalOffsetMetres, widthMetres)
      return
   end
   local curvature = curvatureAt(
   curve, (firstLongitudinalOffsetMetres + secondLongitudinalOffsetMetres) / 2)

   local span = secondLongitudinalOffsetMetres - firstLongitudinalOffsetMetres
   if curvature == 0 then
      local tangent = { 0, span, 0 }
      nodes[#nodes + 1] = { { trackOffsetMetres, firstLongitudinalOffsetMetres, 0 }, tangent, widthMetres }
      nodes[#nodes + 1] = { { trackOffsetMetres, secondLongitudinalOffsetMetres, 0 }, tangent, widthMetres }
      return
   end
   local segmentCount = math.max(1, math.ceil(
   math.abs(curvature * span) / MAX_SEGMENT_TURN_RADIANS))

   for segmentIndex = 1, segmentCount do
      local first = firstLongitudinalOffsetMetres + span * (segmentIndex - 1) / segmentCount
      local last = secondLongitudinalOffsetMetres
      if segmentIndex < segmentCount then
         last = firstLongitudinalOffsetMetres + span * segmentIndex / segmentCount
      end
      local firstPosition = curvePosition(curve, trackOffsetMetres, first)
      local lastPosition = curvePosition(curve, trackOffsetMetres, last)
      local deltaX = lastPosition[1] - firstPosition[1]
      local deltaY = lastPosition[2] - firstPosition[2]
      local tangentLength = street_util.calcScale(
      math.sqrt(deltaX * deltaX + deltaY * deltaY),
      math.abs(curvature * (last - first)))

      local firstAngle = curvature * first
      local lastAngle = curvature * last
      nodes[#nodes + 1] = {
         firstPosition,
         { -math.sin(firstAngle) * tangentLength, math.cos(firstAngle) * tangentLength, 0 },
         widthMetres,
      }
      nodes[#nodes + 1] = {
         lastPosition,
         { -math.sin(lastAngle) * tangentLength, math.cos(lastAngle) * tangentLength, 0 },
         widthMetres,
      }
   end
end

local function makeTrackLayout(
   curve,
   trackType,
   trackCount,
   trackSpacingMetres)

   local halfLength = curve.lengthMetres / 2
   local edges = {}
   local snapNodes = {}
   local tracks = {}
   for trackIndex = 1, trackCount do
      local trackOffsetMetres = getTrackOffsetMetres(
      trackIndex,
      trackCount,
      trackSpacingMetres)

      local startScale = longitudinalScale(curve.startCurvaturePerMetre, trackOffsetMetres)
      local endScale = longitudinalScale(curve.endCurvaturePerMetre, trackOffsetMetres)
      local startStopOffsetMetres = -TERMINAL_NODE_SEPARATION_METRES / (2 * startScale)
      local endStopOffsetMetres = TERMINAL_NODE_SEPARATION_METRES / (2 * endScale)
      snapNodes[#snapNodes + 1] = #edges
      addCurveNodes(
      edges,
      curve,
      trackOffsetMetres,
      -halfLength,
      startStopOffsetMetres)

      local passengerNodeIndex = #edges - 1
      addCurveNodes(
      edges,
      curve,
      trackOffsetMetres,
      startStopOffsetMetres,
      0)

      local centreNodeIndex = #edges - 1
      addCurveNodes(
      edges,
      curve,
      trackOffsetMetres,
      0,
      endStopOffsetMetres)

      local cargoNodeIndex = #edges - 1
      addCurveNodes(
      edges,
      curve,
      trackOffsetMetres,
      endStopOffsetMetres,
      halfLength)

      snapNodes[#snapNodes + 1] = #edges - 1
      tracks[#tracks + 1] = {
         offsetMetres = trackOffsetMetres,
         lengthMetres = halfLength * (startScale + endScale),
         passengerNodeIndex = passengerNodeIndex,
         centreNodeIndex = centreNodeIndex,
         cargoNodeIndex = cargoNodeIndex,
      }
   end
   return {
      tracks = tracks,
      edgeList = {
         type = "TRACK",
         params = {
            type = trackType,
         },
         edges = edges,
         snapNodes = snapNodes,
         tag2nodes = {},
         alignTerrain = true,
         maxNodeSnapAngle = SNAP_ANGLE_DEGREES,
      },
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
   curve,
   laneOffsetMetres,
   transportMode)

   return lane_util.createLane(
   {
      {
         curvePosition(curve, laneOffsetMetres, -0.5),
         curvePosition(curve, laneOffsetMetres, 0.5),
      },
   },
   { transportMode },
   1,
   0,
   false)

end

local function makeServiceLane(
   curve,
   laneOffsetMetres,
   transportMode,
   widthMetres)

   local halfLength = curve.lengthMetres / 2
   local nodes = {}
   addCurveNodes(nodes, curve, laneOffsetMetres, -halfLength, 0, widthMetres)
   local centreNodeIndex = #nodes - 1
   addCurveNodes(nodes, curve, laneOffsetMetres, 0, halfLength, widthMetres)
   return {

      nodes = nodes,
      transportModes = { transportMode },
      speedLimit = LANE_SPEED_LIMIT,
      linkable = false,
   }, centreNodeIndex
end

local function makePassengerAccessLane(
   curve,
   firstTrackOffsetMetres,
   lastTrackOffsetMetres,
   passengerLaneOffsetsMetres,
   longitudinalOffsetMetres)

   local accessPoints = {
      curvePosition(curve, firstTrackOffsetMetres - ACCESS_EXTENSION_METRES, longitudinalOffsetMetres),
   }
   for _, passengerLaneOffsetMetres in ipairs(passengerLaneOffsetsMetres) do
      accessPoints[#accessPoints + 1] = curvePosition(
      curve, passengerLaneOffsetMetres, longitudinalOffsetMetres)

   end
   accessPoints[#accessPoints + 1] = curvePosition(
   curve, lastTrackOffsetMetres + ACCESS_EXTENSION_METRES, longitudinalOffsetMetres)


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
   lane,
   centreLaneNodeIndex,
   vehicleNodeIndex,
   passengers,
   cargo,
   capacity,
   cargoTransferSpeeds,
   transportModes)

   local personEdges = {}
   for edgeIndex = 0, math.floor(#lane.nodes / 2) - 1 do
      personEdges[#personEdges + 1] = { laneListIndex, edgeIndex }
   end
   return {
      tag = tag,
      personEdges = personEdges,
      personNodes = {
         { laneListIndex, centreLaneNodeIndex },
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

local function makeSubconstruction(
   tag,
   laneLists)

   return {
      tag = tag,
      models = {},
      colliders = {},
      terrainAlignmentLists = {},
      groundFaces = {},
      laneLists = laneLists,
      emissionEmitter = {},
   }
end

local function makeStorageSubconstruction(
   bays,
   profile,
   pinnedCargo)

   local result = makeSubconstruction(cargoStorage.subconstructionTag, {})

   result.models[1] = {
      id = "apasz_zigzag::/zigzag/cargo_storage.mdl",
      transf = {
         1, 0, 0, 0,
         0, 1, 0, 0,
         0, 0, 1, 0,
         0, 0, 0, 1,
      },
   }
   result.warehouse = {}
   result.stocks = cargoStorage.makeStocks(bays, profile, pinnedCargo)
   return result
end

local function makeStationSubconstruction(
   curve,
   tracks,
   passengerLoadingEnabled,
   cargoLoadingEnabled,
   passengerCapacityMultiplier,
   catchmentRadiusMetres,
   transportModes)

   local laneLists = {}
   local terminals = {}
   local passengerLaneOffsetsMetres = {}
   local loadingEnabled = passengerLoadingEnabled or cargoLoadingEnabled
   for trackIndex, track in ipairs(tracks) do
      local zeroBasedTrackIndex = trackIndex - 1
      local trackOffsetMetres = track.offsetMetres
      local passengerLaneOffsetMetres = trackOffsetMetres -
      SERVICE_LANE_OFFSET_METRES
      local cargoLaneOffsetMetres = trackOffsetMetres +
      SERVICE_LANE_OFFSET_METRES
      if loadingEnabled then


         local passengerLaneIndex = #laneLists
         if passengerLoadingEnabled then
            passengerLaneOffsetsMetres[#passengerLaneOffsetsMetres + 1] =
passengerLaneOffsetMetres
            local lane, centreLaneNodeIndex = makeServiceLane(
            curve,
            passengerLaneOffsetMetres,
            "PERSON",
            PASSENGER_LANE_WIDTH_METRES)

            laneLists[#laneLists + 1] = lane
            terminals[#terminals + 1] = makeTerminal(
            zeroBasedTrackIndex * 2,
            passengerLaneIndex,
            lane,
            centreLaneNodeIndex,
            track.passengerNodeIndex,
            true,
            false,
            passengerCapacity(track.lengthMetres, passengerCapacityMultiplier),
            { makeCargoTransferSpeed("PASSENGERS", track.lengthMetres) },
            transportModes)

         else
            laneLists[#laneLists + 1] = makeDisabledLoadingLane(
            curve,
            passengerLaneOffsetMetres,
            "PERSON")

            terminals[#terminals + 1] = makeNonLoadingTerminal(
            zeroBasedTrackIndex * 2,
            passengerLaneIndex,
            track.passengerNodeIndex,
            true,
            false,
            transportModes)

         end

         local cargoLaneIndex = #laneLists
         if cargoLoadingEnabled then
            local lane, centreLaneNodeIndex = makeServiceLane(
            curve,
            cargoLaneOffsetMetres,
            "CARGO",
            CARGO_LANE_WIDTH_METRES)

            laneLists[#laneLists + 1] = lane
            terminals[#terminals + 1] = makeTerminal(
            zeroBasedTrackIndex * 2 + 1,
            cargoLaneIndex,
            lane,
            centreLaneNodeIndex,
            track.cargoNodeIndex,
            false,
            true,
            0,
            { makeCargoTransferSpeed("UNIVERSAL", track.lengthMetres) },
            transportModes)

         else
            laneLists[#laneLists + 1] = makeDisabledLoadingLane(
            curve,
            cargoLaneOffsetMetres,
            "CARGO")

            terminals[#terminals + 1] = makeNonLoadingTerminal(
            zeroBasedTrackIndex * 2 + 1,
            cargoLaneIndex,
            track.cargoNodeIndex,
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
         track.centreNodeIndex,
         true,
         true,
         transportModes)

      end
   end

   local catchmentAreas = {}
   if loadingEnabled then
      local halfLength = curve.lengthMetres / 2
      local firstTrackOffsetMetres = tracks[1].offsetMetres
      local lastTrackOffsetMetres = tracks[#tracks].offsetMetres
      local accessLaneOffsetsMetres = { -halfLength, 0, halfLength }
      for _, longitudinalOffsetMetres in ipairs(accessLaneOffsetsMetres) do
         if passengerLoadingEnabled then
            laneLists[#laneLists + 1] = makePassengerAccessLane(
            curve,
            firstTrackOffsetMetres,
            lastTrackOffsetMetres,
            passengerLaneOffsetsMetres,
            longitudinalOffsetMetres)

         end
         catchmentAreas[#catchmentAreas + 1] = {
            position = curvePosition(curve, 0, longitudinalOffsetMetres),
            radius = catchmentRadiusMetres,
         }
      end
   end
   local result = makeSubconstruction(STATION_TAG, laneLists)
   result.station = {
      tag = STATION_TAG,
      terminals = terminals,
      pool = {
         edges = {},
         capacity = 0,
      },
      catchmentAreas = catchmentAreas,
   }
   return result
end

local function updateFn(captureParams, params)
   local length = requireLength(captureParams, params)
   local cargoStorageCapacity = cargoStorage.requireCapacity(params.cargoStorageCapacity)
   local storageProfile = cargoStorage.requireProfile(params.cargoStorageType)
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
   local curve, validationErrors = makeCurveGeometry(
   captureParams, params, length, trackCount, trackSpacingMetres, trackType)

   local layout = makeTrackLayout(curve, trackType, trackCount, trackSpacingMetres)
   local costs = calculateCosts(
   captureParams,
   params,
   length,
   trackCount,
   trackType,
   passengerLoadingEnabled,
   cargoLoadingEnabled,
   cargoStorageCapacity)

   local result = {
      edgeLists = {
         layout.edgeList,
      },
      subconstructions = {
         makeStationSubconstruction(
         curve,
         layout.tracks,
         passengerLoadingEnabled,
         cargoLoadingEnabled,
         passengerCapacityMultiplier,
         catchmentRadiusMetres,
         transportModes),

      },
      cost = costs.construction,
      maintenanceCost = costs.maintenance,
   }
   if #validationErrors > 0 then

      result.metadata = {}
      validationMetadata.set(result.metadata, validationErrors)
   end
   if cargoStorageCapacity > 0 then
      local bays = cargoStorage.makeBays(cargoStorageCapacity, params.cargoStorageType, captureParams.storageBayLayout)
      result.subconstructions[#result.subconstructions + 1] = makeStorageSubconstruction(
      bays, storageProfile, params.tagToCargoType)

      if result.metadata == nil then
         result.metadata = {}
      end
      cargoStorage.metadata.set(result.metadata, cargoStorageCapacity)
      cargoStorage.baysMetadata.set(result.metadata, bays)
   end
   return result
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
      return trackSelection.isRailwayTrack(streetTemplate)
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
      if not trackSelection.isRailwayTrack(streetTemplate) then
         error("Zigzag Station requires a train-capable railway template")
      end
      params.streetTemplate = constructionConfig.streetTemplate
      params.catenary = trackSelection.catenaryIndex(isElectrifiedTrack(streetTemplate))
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
         if not trackSelection.isRailwayTrack(upgradedStreetTemplate) or
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
