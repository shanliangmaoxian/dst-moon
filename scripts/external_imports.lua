local ok, hh_enchant = GLOBAL.pcall(function() return require("enums/hh_enchant") end)

HH_EQUIP_BUFF_LIST = ok and hh_enchant["HH_EQUIP_BUFF_LIST"] or {}
HH_SUIT_LIST = ok and hh_enchant["HH_SUIT_LIST"] or {}

ok, HH_LANGUAGE = GLOBAL.pcall(function() return require("enums/hh_language") end)

ok, HH_UTILS = GLOBAL.pcall(function() return require("utils/hh_utils") end)
