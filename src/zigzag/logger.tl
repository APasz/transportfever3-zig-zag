local debugLoggingEnabled = ug_require(
    "apasz_zigzag::/zigzag/logging_config.lua"
) as boolean
local logging = ug_require(
    "apasz_zigzag::/zigzag/logging.lua"
) as ModLogging.Module

return logging.new("Zigzag Station", debugLoggingEnabled)
