local function add_string(prefab, readable_name, recipe_desc, desc)
    GLOBAL.STRINGS.NAMES[string.upper(prefab)] = readable_name
    GLOBAL.STRINGS.RECIPE_DESC[string.upper(prefab)] = recipe_desc or ""
    GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE[string.upper(prefab)] = desc or ""
end

add_string("moon_effect_stone_hanyue_test", "寒月试炼附魔石",
           "通过试炼将升级为寒月公主附魔效果",
           "通过试炼将升级为寒月公主附魔效果")

add_string("lmoon_stone_album", "附魔收集册",
           "同词条附魔石自动归拢堆叠，检查可查看收录明细",
           "把多余的附魔石都装进来吧")
