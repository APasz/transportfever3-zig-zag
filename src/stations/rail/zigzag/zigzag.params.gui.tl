local record LoadingVisibilityCapturedParams
    enabledParamKeys: {string}
    enabledIndex: integer
end

local type ConstructionParams = {string: number}
local type CheckEnabledResult = ConstructionMenuParam.CheckEnabledResult

local function checkLoadingVisibility(
    capturedParams: LoadingVisibilityCapturedParams,
    params: ConstructionParams
): CheckEnabledResult
    for _, paramKey in ipairs(capturedParams.enabledParamKeys) do
        if params[paramKey] == capturedParams.enabledIndex then
            return "Enabled" as CheckEnabledResult
        end
    end

    -- InputActionOnly hides the control without dropping its selected value.
    return "InputActionOnly" as CheckEnabledResult
end

function data(): any
    return {
        checkLoadingVisibility = checkLoadingVisibility,
    }
end
