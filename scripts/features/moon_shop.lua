-- 小月亮商店 — 原版精炼材料 x10 批量兑换 + Boss 兑换

GLOBAL.setmetatable(env, { __index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end })

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MOON_SHOP then return end

-- 商店标签文字
if STRINGS and STRINGS.UI and STRINGS.UI.CRAFTING_FILTERS then
    STRINGS.UI.CRAFTING_FILTERS.MOON_SHOP = "小月亮商店"
end

-- 注册商店标签
local has_filter = false
if AddRecipeFilter ~= nil then
    local tex = "lunar_seed.tex"
    local atlas = GetInventoryItemAtlas(tex) or "images/inventoryimages.xml"
    AddRecipeFilter({
        name = "MOON_SHOP",
        atlas = atlas,
        image = tex,
    })
    has_filter = true
    print("[小月亮商店] 独立标签注册成功")
end

local filter_list = has_filter and { "MOON_SHOP" } or nil

local hh_enabled = _G.Moon_IsModEnabled("workshop-3096210166")
local soul_exchange_enabled = _G.Moon_IsModEnabled("workshop-2526778484")
local hoshino_enabled = _G.Moon_IsModEnabled("workshop-3398290914")
local legend_enabled = _G.Moon_IsModEnabled("workshop-2578692071")

-- 织影者地上防自毁（模块加载时注册，确保在第一个实例出生前生效）
if hh_enabled then
    AddPrefabPostInit("stalker_atrium", function(inst)
        local _IsNearAtrium = inst.IsNearAtrium
        inst.IsNearAtrium = function() return true end
        local _OnEntitySleep = inst.OnEntitySleep
        inst.OnEntitySleep = function() return true end
    end)
    print("[小月亮商店] 织影者防自毁补丁已注册")
end

-- 精炼材料批量兑换: { product, { {原料, 数量}, ... } }
local shop_items = {
    { "cutstone",       { { "rocks",      30 } } },  -- 3x10
    { "boards",         { { "log",        40 } } },  -- 4x10
    { "rope",           { { "cutgrass",   30 } } },  -- 3x10
    { "papyrus",        { { "cutreeds",   40 } } },  -- 4x10
}

-- ------------------------------------------------------------------
-- 商店配方本地化：标题 + 专属描述
-- 标题：DST 制作栏按 STRINGS.NAMES[string.upper(recipe.name)] 查（craftingmenu_details.lua:253），
--       缺失时 modmain 蓝图兜底会统一填「小月亮商店兑换」，故为每个 MoonShop_ 配方显式补名；
--       numtogive > 1 时 UI 会自动在标题后拼 "(xN)"（NUMTOGIVEFMT），标题只写产品名。
-- 描述：UI 按 recipe.description（优先）或 STRINGS.RECIPE_DESC[string.upper(recipe.product)]
--       显示（craftingmenu_details.lua:362）。专属描述写进 recipe.description，
--       避免覆盖原版/他 mod 的 RECIPE_DESC[product]（如 cutstone 会显示原版配方描述）。
--       召唤群友（moon_qunyou_summon）由 scripts/features/moon_qunyou.lua 自行处理，不在此表。
-- ------------------------------------------------------------------
local shop_localization = {
    ["MoonShop_cutstone"]                     = { name = "石砖",       desc = "30 个石头兑换 10 块石砖" },
    ["MoonShop_boards"]                       = { name = "木板",       desc = "40 个木头兑换 10 块木板" },
    ["MoonShop_rope"]                         = { name = "绳子",       desc = "30 个干草兑换 10 根绳子" },
    ["MoonShop_papyrus"]                      = { name = "莎草纸",     desc = "40 个芦苇兑换 10 张莎草纸" },
    ["MoonShop_opalpreciousgem_10"]           = { name = "彩虹宝石",   desc = "6 色宝石各 10 个，兑换 10 颗彩虹宝石" },
    ["MoonShop_opalpreciousgem_100"]          = { name = "彩虹宝石",   desc = "6 色宝石各 100 个，兑换 100 颗彩虹宝石" },
    ["MoonShop_alterguardian_phase4_lunarrift"] = { name = "天体后裔", desc = "100 水晶小人兑换天体后裔掉落物（需 HH 附魔模组）" },
    ["MoonShop_stalker_atrium"]               = { name = "织影者",     desc = "100 水晶小人兑换织影者掉落物（需 HH 附魔模组）" },
    ["MoonShop_alterguardian_phase1"]         = { name = "天体英雄",   desc = "100 水晶小人兑换天体英雄掉落物（需 HH 附魔模组）" },
    ["MoonShop_crabking"]                     = { name = "帝王蟹",     desc = "100 水晶小人兑换帝王蟹掉落物（需 HH 附魔模组）" },
    ["MoonShop_hoshino_item_travel_traces"]   = { name = "遍历之迹",   desc = "500 水晶小人兑换遍历之迹（需 HH 附魔模组 + 小鸟模组）" },
    ["MoonShop_treasure_hh_treasure_tally_x1"]  = { name = "寻宝卷轴", desc = "50 金子兑换 1 张寻宝卷轴" },
    ["MoonShop_treasure_hh_treasure_tally_x10"] = { name = "寻宝卷轴", desc = "500 金子兑换 10 张寻宝卷轴" },
    ["MoonShop_white_soul_from_black_soul"]   = { name = "光明之魂",   desc = "3 个暗影之魂兑换 1 个光明之魂" },
    ["MoonShop_black_soul_from_white_soul"]   = { name = "暗影之魂",   desc = "3 个光明之魂兑换 1 个暗影之魂" },
    ["MoonShop_emojitan"]                     = { name = "恶魔祭坛",   desc = "虚空异界的远古祭坛" },
    ["MoonShop_moonstorm_spark"]              = { name = "月熠",       desc = "5 个月亮碎片兑换 1 个月熠" },
    ["MoonShop_shijizhihua_bulb"]             = { name = "世纪之花球茎", desc = "原地放置，召唤世纪之花" },
    ["MoonShop_star_brooch"]                  = { name = "星辰胸针",   desc = "1 个老师怜悯附魔石 + 60 个锻体碎片 + 666 魔法值兑换\n只能是老师怜悯这个附魔兑换，其他附魔无效" },
}

-- 标题/描述兜底 key（recipe.name 大写）在两端 mod 加载时写入（modmain 蓝图兜底只填缺失项，不会覆盖）
if _G.STRINGS and _G.STRINGS.NAMES and _G.STRINGS.RECIPE_DESC then
    for recipe_id, entry in pairs(shop_localization) do
        local key = string.upper(recipe_id)
        if _G.STRINGS.NAMES[key] == nil then
            _G.STRINGS.NAMES[key] = entry.name
        end
        if entry.desc and _G.STRINGS.RECIPE_DESC[key] == nil then
            _G.STRINGS.RECIPE_DESC[key] = entry.desc
        end
    end
end

local function InitMoonShop()

    -- 批量材料兑换: 精炼材料 x10 + 彩虹宝石
    if CFG.ENABLE_MOON_SHOP_BATCH then
        local count = 0
        for _, item in ipairs(shop_items) do
            local recipe_id = "MoonShop_" .. item[1]
            if not (AllRecipes and AllRecipes[recipe_id]) then
                local ingredients = {}
                for _, ing in ipairs(item[2]) do
                    table.insert(ingredients, Ingredient(ing[1], ing[2]))
                end
                AddRecipe2(
                    recipe_id,
                    ingredients,
                    TECH.SCIENCE_ONE,
                    { product = item[1], nounlock = false, numtogive = 10 },
                    filter_list
                )
                count = count + 1
            end
        end
        print("[小月亮商店] 批量精炼配方注册完成，共 " .. count .. " 件")

        -- 彩虹宝石批量兑换: 各色宝石 xN → 彩虹宝石 xN
        local gem_count = 0
        local gem_colors = { "redgem", "bluegem", "purplegem", "orangegem", "yellowgem", "greengem" }
        for _, batch in ipairs({ 10, 100 }) do
            local recipe_id = "MoonShop_opalpreciousgem_" .. batch
            if not (AllRecipes and AllRecipes[recipe_id]) then
                local ingredients = {}
                for _, gem in ipairs(gem_colors) do
                    table.insert(ingredients, Ingredient(gem, batch))
                end
                AddRecipe2(
                    recipe_id,
                    ingredients,
                    TECH.NONE,
                    { product = "opalpreciousgem", nounlock = true, numtogive = batch },
                    filter_list
                )
                gem_count = gem_count + 1
            end
        end
        print("[小月亮商店] 彩虹宝石兑换注册完成，共 " .. gem_count .. " 件")
    end

    -- HH附魔强化 Boss 兑换 (100 水晶小人)
    if hh_enabled then
        local boss_items = {}
        if CFG.ENABLE_MOON_SHOP_BOSS_CELESTIAL then
            table.insert(boss_items, { "alterguardian_phase4_lunarrift", "天体后裔" })
        end
        if CFG.ENABLE_MOON_SHOP_BOSS_STALKER then
            table.insert(boss_items, { "stalker_atrium", "织影者" })
        end
        if CFG.ENABLE_MOON_SHOP_BOSS_ALTERGUARDIAN then
            table.insert(boss_items, { "alterguardian_phase1", "天体英雄" })
        end
        if CFG.ENABLE_MOON_SHOP_BOSS_CRABKING then
            table.insert(boss_items, { "crabking", "帝王蟹" })
        end
        local boss_count = 0
        for _, item in ipairs(boss_items) do
            local recipe_id = "MoonShop_" .. item[1]
            local prefab = item[1]
            if not (AllRecipes and AllRecipes[recipe_id]) then
                AddRecipe2(
                    recipe_id,
                    { Ingredient("hh_essence", 100) },
                    TECH.NONE,
                    {
                        product = prefab,
                        nounlock = true,
                        numtogive = 1,
                        atlas = "images/inventoryimages/" .. prefab .. ".xml",
                        image = prefab .. ".tex",
                    },
                    filter_list
                )
                boss_count = boss_count + 1
            end
        end
        if boss_count > 0 then
            print("[小月亮商店] Boss兑换注册完成，共 " .. boss_count .. " 件")
        end
    end

    -- 召唤群友 (20 个大肉)：制作后原地召唤 1 只猪人群友（周边最多 3 只）
    -- 产物是瞬发实体 moon_qunyou_summon（scripts/features/moon_qunyou.lua），图标用 mod 自带猪人图
    -- 兑换材料是原版大肉，不依赖 HH 附魔模组
    if CFG.ENABLE_MOON_SHOP_BOSS_QUNYOU then
        local qunyou_recipe_id = "MoonShop_moon_qunyou_summon"
        if not (AllRecipes and AllRecipes[qunyou_recipe_id]) then
            AddRecipe2(
                qunyou_recipe_id,
                { Ingredient("meat", 20) },
                TECH.NONE,
                {
                    product = "moon_qunyou_summon",
                    nounlock = true,
                    numtogive = 1,
                    atlas = "images/inventoryimages/pig_man.xml",
                    image = "pig_man.tex",
                },
                filter_list
            )
            print("[小月亮商店] 召唤群友配方注册成功")
        end
    end

    -- 遍历之迹兑换 (需要 HH 附魔 3096210166 + 小鸟 3398290914)
    if CFG.ENABLE_MOON_SHOP_TRAVEL_TRACES and hh_enabled and hoshino_enabled then
        local travel_traces_id = "MoonShop_hoshino_item_travel_traces"
        if not (AllRecipes and AllRecipes[travel_traces_id]) then
            AddRecipe2(
                travel_traces_id,
                { Ingredient("hh_essence", 500) },
                TECH.NONE,
                { product = "hoshino_item_travel_traces", nounlock = true, numtogive = 1 },
                filter_list
            )
            print("[小月亮商店] 遍历之迹兑换注册成功")
        end
    end

    -- 寻宝卷轴兑换: 金子 → 寻宝卷轴 (需要 HH 附魔 3096210166)
    if CFG.ENABLE_MOON_SHOP_TREASURE_TALLY and hh_enabled then
        local tally_recipes = {
            { "hh_treasure_tally", 1,  50 },
            { "hh_treasure_tally", 10, 500 },
        }
        local tally_count = 0
        for _, r in ipairs(tally_recipes) do
            local recipe_id = "MoonShop_treasure_" .. r[1] .. "_x" .. r[2]
            if not (AllRecipes and AllRecipes[recipe_id]) then
                AddRecipe2(
                    recipe_id,
                    { Ingredient("goldnugget", r[3]) },
                    TECH.NONE,
                    { product = r[1], nounlock = true, numtogive = r[2] },
                    filter_list
                )
                tally_count = tally_count + 1
            end
        end
        print("[小月亮商店] 寻宝卷轴兑换注册完成，共 " .. tally_count .. " 件")
    end

    -- 灵魂兑换 (需要模组 2526778484)
    if CFG.ENABLE_MOON_SHOP_SOUL and soul_exchange_enabled then
        local soul_atlas = {
            white_soul = { atlas = "images/inventoryimages/white_soul.xml", image = "white_soul.tex" },
            black_soul = { atlas = "images/inventoryimages/black_soul.xml", image = "black_soul.tex" },
        }
        local soul_exchanges = {
            { "white_soul", "black_soul" },
            { "black_soul", "white_soul" },
        }
        local soul_count = 0
        for _, ex in ipairs(soul_exchanges) do
            local recipe_id = "MoonShop_" .. ex[1] .. "_from_" .. ex[2]
            if not (AllRecipes and AllRecipes[recipe_id]) then
                local ing = soul_atlas[ex[2]]
                local prod = soul_atlas[ex[1]]
                local recipe = AddRecipe2(
                    recipe_id,
                    { Ingredient(ex[2], 3, ing.atlas, ing.image) },
                    TECH.NONE,
                    { product = ex[1], nounlock = true, numtogive = 1 },
                    filter_list
                )
                if recipe then
                    recipe.atlas = prod.atlas
                    recipe.image = prod.image
                end
                soul_count = soul_count + 1
            end
        end
        print("[小月亮商店] 灵魂兑换注册完成，共 " .. soul_count .. " 件")
    end

    -- 恶魔祭坛 (需要泰拉模组 2526778484)
    if CFG.ENABLE_DEMON_ALTAR and soul_exchange_enabled then
        if not _G.STRINGS.NAMES.EMOJITAN then _G.STRINGS.NAMES.EMOJITAN = "恶魔祭坛" end
        if not _G.STRINGS.RECIPE_DESC.EMOJITAN then _G.STRINGS.RECIPE_DESC.EMOJITAN = "虚空异界的远古祭坛" end
        if not _G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.EMOJITAN then _G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.EMOJITAN = "散发着不详的气息。" end

        local altar_recipe_id = "MoonShop_emojitan"
        if not (AllRecipes and AllRecipes[altar_recipe_id]) then
            AddRecipe2(
                altar_recipe_id,
                {
                    Ingredient("thulecite", 6),
                    Ingredient("purplegem", 4),
                    Ingredient("livinglog", 6),
                    Ingredient("goldnugget", 10),
                    Ingredient("nightmarefuel", 20),
                },
                TECH.NONE,
                { product = "emojitan", nounlock = true, placer = "emojitan_placer", min_spacing = 2, numtogive = 1, atlas = "images/inventoryimages/emojitan.xml", image = "emojitan.tex" },
                filter_list
            )
            print("[小月亮商店] emojitan 配方注册成功")
        end
    end

    -- 月熠兑换: 5 个月亮碎片 → 1 个月熠
    if CFG.ENABLE_MOON_SHOP_SPARK then
        local spark_recipe_id = "MoonShop_moonstorm_spark"
        if not (AllRecipes and AllRecipes[spark_recipe_id]) then
            AddRecipe2(
                spark_recipe_id,
                { Ingredient("moonglass", 5) },
                TECH.NONE,
                { product = "moonstorm_spark", nounlock = true, numtogive = 1 },
                filter_list
            )
            print("[小月亮商店] 月熠兑换注册成功")
        end
    end

    -- 星辰胸针兑换: 1 个 Legend_LAOSHI 附魔石 + 60 个锻体碎片 + 666 魔法值 → 1 个星辰胸针 (需要 Legend 模组 2578692071)
    if CFG.ENABLE_MOON_SHOP_STAR_BROOCH and legend_enabled then
        local star_brooch_recipe_id = "MoonShop_star_brooch"
        if not (AllRecipes and AllRecipes[star_brooch_recipe_id]) then
            -- 检查是否有 CHARACTER_INGREDIENT.ELAINA_MAGIC
            local has_elaina_magic = _G.CHARACTER_INGREDIENT and _G.CHARACTER_INGREDIENT.ELAINA_MAGIC
            local ingredients = {
                Ingredient("hh_effect_stone", 1),
                Ingredient("elaina_dtsp", 60),
            }
            -- 如果有魔法值系统，添加魔法值消耗
            if has_elaina_magic then
                table.insert(ingredients, Ingredient(_G.CHARACTER_INGREDIENT.ELAINA_MAGIC, 666, "images/inventoryimages/elaina_magic.xml"))
            end
            local recipe = AddRecipe2(
                star_brooch_recipe_id,
                ingredients,
                TECH.NONE,
                { 
                    product = "star_brooch", 
                    nounlock = true, 
                    numtogive = 1,
                    atlas = "images/inventoryimages/star_brooch.xml",
                    image = "star_brooch.tex",
                },
                filter_list
            )
            -- 添加自定义检查：只接受 Legend_LAOSHI 附魔石
            if recipe then
                recipe.canbuild = function(recipe, inst, pt, rotation, prototyper)
                    if not inst or not inst.components or not inst.components.inventory then
                        return false, "NOITEM"
                    end
                    -- 检查背包中是否有 Legend_LAOSHI 附魔石
                    local has_legend_stone = false
                    for k, v in pairs(inst.components.inventory.itemslots) do
                        if v and v.prefab == "hh_effect_stone" and v.hh_effect == "Legend_LAOSHI" then
                            has_legend_stone = true
                            break
                        end
                    end
                    -- 检查手持物品
                    if not has_legend_stone and inst.components.inventory.activeitem then
                        local item = inst.components.inventory.activeitem
                        if item and item.prefab == "hh_effect_stone" and item.hh_effect == "Legend_LAOSHI" then
                            has_legend_stone = true
                        end
                    end
                    -- 检查打开的容器
                    if not has_legend_stone and inst.components.inventory.opencontainers then
                        for container_inst in pairs(inst.components.inventory.opencontainers) do
                            local container = container_inst.components.container
                            if container then
                                for i = 1, container.numslots do
                                    local v = container.slots[i]
                                    if v and v.prefab == "hh_effect_stone" and v.hh_effect == "Legend_LAOSHI" then
                                        has_legend_stone = true
                                        break
                                    end
                                end
                            end
                            if has_legend_stone then break end
                        end
                    end
                    if not has_legend_stone then
                        return false, "NOITEM"
                    end
                    -- 检查魔法值是否足够
                    if has_elaina_magic and inst.components.elaina_magic then
                        if inst.components.elaina_magic:GetMagic() < 666 then
                            return false, "NOITEM"
                        end
                    end
                    return true
                end
            end
            print("[小月亮商店] 星辰胸针兑换注册成功")
        end
    end

    -- 世纪之花球茎 (需要泰拉模组 2526778484)
    if CFG.ENABLE_SHIJIZHIHUA_BULB and soul_exchange_enabled then
        if not _G.STRINGS.NAMES.SHIJIZHIHUA_BULB then _G.STRINGS.NAMES.SHIJIZHIHUA_BULB = "世纪之花球茎" end
        if not _G.STRINGS.RECIPE_DESC.SHIJIZHIHUA_BULB then _G.STRINGS.RECIPE_DESC.SHIJIZHIHUA_BULB = "原地放置，召唤世纪之花" end
        if not _G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.SHIJIZHIHUA_BULB then _G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.SHIJIZHIHUA_BULB = "一颗散发着自然与机械气息的球茎。" end

        local bulb_recipe_id = "MoonShop_shijizhihua_bulb"
        if not (AllRecipes and AllRecipes[bulb_recipe_id]) then
            AddRecipe2(
                bulb_recipe_id,
                {
                    Ingredient("jixiemoyan", 3),
                    Ingredient("jixiexinbiao", 3),
                    Ingredient("laohuaxinhaofasheqi", 3),
                },
                TECH.NONE,
                { product = "shijizhihua_bulb", nounlock = true, numtogive = 1, atlas = "images/inventoryimages/shijizhihua_bulb.xml", image = "shijizhihua_bulb.tex" },
                filter_list
            )
            print("[小月亮商店] shijizhihua_bulb 配方注册成功")
        end
    end

    -- 商店配方专属描述写入 recipe.description
    -- （craftingmenu_details.lua:348 优先读 recipe.description 作为 STRINGS.RECIPE_DESC 的 key，否则回落到 recipe.product）
    -- 我们已经在模块加载时设置了 STRINGS.RECIPE_DESC[recipe_id]，所以需要设置 recipe.description = recipe_id
    -- 这样 UI 就会使用正确的 key 来查找描述
    if _G.AllRecipes then
        for recipe_id, entry in pairs(shop_localization) do
            local recipe = _G.AllRecipes[recipe_id]
            if recipe and entry.desc then
                recipe.description = recipe_id
            end
        end
    end
end

AddPrefabPostInit("world", function(inst)
    InitMoonShop()
end)

-- 星辰胸针兑换：修改 inventory 组件的 GetCraftingIngredient 函数，确保只返回 Legend_LAOSHI 附魔石
if CFG.ENABLE_MOON_SHOP_STAR_BROOCH and legend_enabled then
    AddComponentPostInit("inventory", function(self)
        local original_GetCraftingIngredient = self.GetCraftingIngredient
        self.GetCraftingIngredient = function(self, item, amount, ...)
            if item == "hh_effect_stone" then
                -- 当请求 hh_effect_stone 时，只返回 Legend_LAOSHI 附魔石
                local crafting_items = {}
                local total_num_found = 0
                
                -- 检查背包中的物品
                for i = 1, self.maxslots do
                    local v = self.itemslots[i]
                    if v ~= nil and v.prefab == "hh_effect_stone" and v.hh_effect == "Legend_LAOSHI" and not v:HasTag("nocrafting") then
                        local stacksize = v.components.stackable and v.components.stackable:StackSize() or 1
                        crafting_items[v] = stacksize
                        total_num_found = total_num_found + stacksize
                        if total_num_found >= amount then
                            return crafting_items
                        end
                    end
                end
                
                -- 检查手持物品
                if self.activeitem ~= nil and self.activeitem.prefab == "hh_effect_stone" and self.activeitem.hh_effect == "Legend_LAOSHI" and not self.activeitem:HasTag("nocrafting") then
                    local stacksize = self.activeitem.components.stackable and self.activeitem.components.stackable:StackSize() or 1
                    crafting_items[self.activeitem] = math.min(stacksize, amount - total_num_found)
                end
                
                return crafting_items
            end
            -- 对于其他物品，使用原始函数
            return original_GetCraftingIngredient(self, item, amount, ...)
        end
    end)
end
