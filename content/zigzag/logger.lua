local debugLoggingEnabled = ug_require(
"apasz_zigzag::/zigzag/logging_config.lua")

local logging = ug_require(
"apasz_zigzag::/zigzag/logging.lua")


return logging.new("Zigzag Station", debugLoggingEnabled)
