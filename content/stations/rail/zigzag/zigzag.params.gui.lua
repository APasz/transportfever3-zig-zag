local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs







local function checkLoadingVisibility(
   capturedParams,
   params)

   for _, paramKey in ipairs(capturedParams.enabledParamKeys) do
      if params[paramKey] == capturedParams.enabledIndex then
         return "Enabled"
      end
   end


   return "InputActionOnly"
end

function data()
   return {
      checkLoadingVisibility = checkLoadingVisibility,
   }
end
