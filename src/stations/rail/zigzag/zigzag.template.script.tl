local trackSelection = ug_require(
    "apasz_zigzag::/zigzag/track_selection.lua"
) as ZigzagTrackSelection

local record TemplateConstruction
    constructionFileName: string
    modules: {integer: string}
    params: ZigzagConstructionParams
end

local record TemplateResult
    constructions: {TemplateConstruction}
end

local function createTemplateFn(
    captureParams: ZigzagTemplateCaptureParams,
    params: ZigzagConstructionParams
): TemplateResult
    local track = trackSelection.resolve(
        captureParams.tracks,
        params.apasz_zigzag_track_variant,
        params.year or 0
    )
    local constructionParams: {string: any} = {}
    for key, value in pairs(params as {string: any}) do
        constructionParams[key] = value
    end
    -- Only the resource path is saved; picker indices belong to this load's catalogue.
    constructionParams[trackSelection.paramKey] = nil
    constructionParams.trackType = nil
    constructionParams.streetTemplate = track.resourceName
    constructionParams.catenary = trackSelection.catenaryIndex(track.electrified)
    return {
        constructions = {
            {
                constructionFileName = captureParams.constructionName,
                modules = {},
                params = constructionParams as ZigzagConstructionParams,
            },
        },
    }
end

function data(): any
    return {
        createTemplateFn = createTemplateFn,
    }
end
