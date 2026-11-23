local metadata_util = ug_require "::/scripts/metadata_util.tl" as MetadataUtil

return metadata_util.constructionInstance.register(
    "apasz_zigzag_validation_errors"
) as MetadataAccessor<ConstructionInstanceMetadata, {string}>
