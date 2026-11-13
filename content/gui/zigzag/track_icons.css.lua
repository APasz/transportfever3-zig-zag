local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math
























local stylesheetUtil = ug_require("::/gui/main/stylesheetutil.lua")
local constructionSizes = ug_require("::/gui/construction/construction_sizes.lua")
local ICON_SIZE = { 48, 30 }
local ROW_GAP = 8

local DROPDOWN_CHROME_WIDTH = 64
local TRACK_NAME_MAX_WIDTH = math.floor(
constructionSizes.ParamsWindowWidth - ICON_SIZE[1] - ROW_GAP - DROPDOWN_CHROME_WIDTH)


function data()
   local rules = {}
   local add = stylesheetUtil.makeAdder(rules)
   add("!apasz-zigzag-track-row", { innerSpacing = { ROW_GAP, 0 }, gravity = { -1, 0.5 } })
   add("TextView!apasz-zigzag-track-name", {
      maxSize = { TRACK_NAME_MAX_WIDTH, -1 },
      textAutoWrap = true,
      textAlignment = { 0, 0.5 },
      gravity = { -1, 0.5 },
   })
   add("!apasz-zigzag-track-icon", {
      size = ICON_SIZE,
      minSize = ICON_SIZE,
      maxSize = ICON_SIZE,
      gravity = { 0, 0.5 },
   })
   return rules
end
