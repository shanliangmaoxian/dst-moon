local function add_string(prefab, readable_name, recipe_desc, desc)
    GLOBAL.STRINGS.NAMES[string.upper(prefab)] = readable_name
    GLOBAL.STRINGS.RECIPE_DESC[string.upper(prefab)] = recipe_desc or ""
    GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE[string.upper(prefab)] = desc or ""
end

add_string("moon_effect_stone_hanyue_test", "寒月试炼附魔石",
           "通过试炼将升级为寒月公主附魔效果",
           "通过试炼将升级为寒月公主附魔效果")
