local CFG = GLOBAL.MOON_CFG

-- 寒月试炼附魔石配方
if CFG.ENABLE_MORE_ENCHANTS and GLOBAL.Moon_IsHHEnabled() then

    -- local enable_aria = Moon_IsModEnabled("workshop-2418617371")            -- 艾丽娅，宝石领主
    local enable_underline = Moon_IsModEnabled("workshop-3672431769")       -- 更多附魔石
                            or Moon_IsModEnabled("workshop-3253273657")     -- 下划线
    local enable_moon_enchants = true

    AddRecipe2('moon_effect_stone_hanyue_test', table.filter({
        HHEffectStoneIngredient("target_percent_damage"),           -- 撕裂
        HHEffectStoneIngredient("autumn_god"),                      -- 秋季战神

        HHEffectStoneIngredient("add_critical_hit_rate_damage"),    -- 无尽
        HHEffectStoneIngredient("atk_add_good_damage"),             -- 极品增伤

        -- enable_underline        and HHEffectStoneIngredient("Legend_jealous_stone") or nil,            -- 罪★嫉妒
        -- not enable_underline    and HHEffectStoneIngredient("add_immune_freeze") or nil,               -- 免疫冰冻
        -- not enable_underline    and HHEffectStoneIngredient("more_damage_8_500") or nil,               -- 五倍伤害

        -- enable_moon_enchants    and HHEffectStoneIngredient("Legend_EPSILON") or nil,                  -- 伊普西隆

        -- enable_aria             and HHEffectStoneIngredient("effect_aria_fantasy") or nil,             -- 终焉幻想

        Ingredient('ice', 300),
        Ingredient('bluegem', 80)
    }, truly),
    TECH.MAGIC_THREE,
    {
        atlas = 'images/hh_icon/hh_items.xml',
        image = 'hh_effect_stone.tex'
    },
    {'MAGIC'})


    -- 快速施法 配方1
    AddRecipe2('lmoon_effect_stone_quickcast1', table.filter({
        HHEffectStoneIngredient("fast_act"),           -- 快速交互
        Ingredient('opalpreciousgem', 10),
        Ingredient('purplegem', 30)
    }, truly),
    TECH.MAGIC_THREE,
    {
        product = "lmoon_effect_stone_quickcast",
        atlas = 'images/hh_icon/hh_items.xml',
        image = 'hh_effect_stone.tex'
    },
    {'MAGIC'})
    -- 快速施法 配方2
    AddRecipe2('lmoon_effect_stone_quickcast3', table.filter({
        HHEffectStoneIngredient("Legend_LIANLIAN"),    -- 无意识的恋恋
        Ingredient('opalpreciousgem', 10),
        Ingredient('purplegem', 30)
    }, truly),
    TECH.MAGIC_THREE,
    {
        product = "lmoon_effect_stone_quickcast",
        atlas = 'images/hh_icon/hh_items.xml',
        image = 'hh_effect_stone.tex'
    },
    {'MAGIC'})
    -- 快速施法 配方3
    if enable_underline then
        AddRecipe2('lmoon_effect_stone_quickcast2', table.filter({
            HHEffectStoneIngredient("Legend_diligence_stone"), -- 德★勤奋
            Ingredient('opalpreciousgem', 10),
            Ingredient('purplegem', 30)
        }, truly),
        TECH.MAGIC_THREE,
        {
            product = "lmoon_effect_stone_quickcast",
            atlas = 'images/hh_icon/hh_items.xml',
            image = 'hh_effect_stone.tex'
        },
        {'MAGIC'})
    end
end
