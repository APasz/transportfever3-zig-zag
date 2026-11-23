local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local builtin = ug_require("::/gui/main/builtin.lua")
local react = ug_require("::/gui/main/react.lua")
local engineReact = ug_require("::/gui/main/engine_react_util.tl")
local contentCard = ug_require("::/gui/main/content_card.tl")
local entityWindow = ug_require("::/gui/entity_window/entity_window_util.tl")
local entityUtil = ug_require("::/scripts/entity_util.tl")
local stationWindow = ug_require(
"::/gui/entity_window/station_group/station_group_eow.script.tl")

local cargoStorage = ug_require(
"apasz_zigzag::/zigzag/cargo_storage.lua")










local function stationGroupStores(groupEntity)
   local stores = {}
   if not api.engine.entityExists(groupEntity) then
      return stores
   end
   local group = api.engine.getComponent(
   groupEntity, api.type.ComponentType.STATION_GROUP)

   if group == nil then
      return stores
   end
   local visited = {}
   for _stationIndex, stationEntity in ipairs(group.stations) do
      local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(
      stationEntity)

      if constructionEntity ~= nil and constructionEntity >= 0 and not visited[constructionEntity] then
         visited[constructionEntity] = true
         local construction = api.engine.getComponent(
         constructionEntity, api.type.ComponentType.CONSTRUCTION)

         if construction == nil then
            error("Zigzag station owner has no construction component")
         end
         local capacity = cargoStorage.metadata.get(construction.persistentMetadata)
         if capacity ~= nil and capacity > 0 then
            stores[#stores + 1] = {
               constructionEntity = constructionEntity,
               stockListEntity = cargoStorage.requireStockList(construction),
               name = api.engine.util.getEntityName(constructionEntity) or _("apasz_zigzag_name"),
               canModify = entityUtil.isOwnedByPlayerOrNotOwned(constructionEntity),
               specialised = not cargoStorage.requireProfile(
               (construction.params).cargoStorageType).
               mixedTypes,
            }
         end
      end
   end
   return stores
end

local Stocks = react.RegisterPluginRecipe(
stationWindow.StationGroupEowExtensionPoint,
"ZigzagCargoStocks",
function(params)
   local stores = engineReact.useStepState(function()
      return stationGroupStores(params.entityId)
   end):old()
   if #stores == 0 then
      return nil
   end
   local cards = {}
   for _storeIndex, store in ipairs(stores) do
      cards[#cards + 1] = contentCard.ContentCard({
         meta = { localKey = "apasz-zigzag-stocks:" .. tostring(store.constructionEntity) },
         title = _("apasz_zigzag_cargo_storage") .. " — " .. store.name,
         recipeAndParamPermanent = contentCard.makeRecipeAndParam(
         entityWindow.EntityStockCountsWidget,
         {
            entityId = store.stockListEntity,
            groupStocks = false,
            addDiscardCargoButtons = store.canModify,
            addButtonsToSetStockCargoType = store.canModify and store.specialised,
            sortByType = true,
         }),

         hasPermanentFocusables = store.canModify,
         gameCtx = params.gameCtx,
         showOnRightSide = params.showCalloutOnRightSide,
      })
   end
   return builtin.BoxLayout({
      orientation = builtin.type.Orientation.Vertical,
      children = cards,
   })
end)


function data()
   return { Stocks = Stocks }
end
