local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pairs = _tl_compat and _tl_compat.pairs or pairs; local trackSelection = ug_require(
"apasz_zigzag::/zigzag/track_selection.lua")












local function createTemplateFn(
   captureParams,
   params)

   local track = trackSelection.resolve(
   captureParams.tracks,
   params.apasz_zigzag_track_variant,
   params.year or 0)

   local constructionParams = {}
   for key, value in pairs(params) do
      constructionParams[key] = value
   end

   constructionParams[trackSelection.paramKey] = nil
   constructionParams.trackType = nil
   constructionParams.streetTemplate = track.resourceName
   constructionParams.catenary = trackSelection.catenaryIndex(track.electrified)
   return {
      constructions = {
         {
            constructionFileName = captureParams.constructionName,
            modules = {},
            params = constructionParams,
         },
      },
   }
end

function data()
   return {
      createTemplateFn = createTemplateFn,
   }
end
