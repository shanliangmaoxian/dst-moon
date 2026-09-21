-- 小月亮 附魔：无限星力
-- 联动魔卡少女小樱mod(workshop-3043439883)
-- 获取：小樱(ccs)消耗225点魔力炼成「无限星力附魔石」(配方 ccs_legend_stone)
-- 效果：佩戴后魔力消耗全免 = 无限魔力（仅小樱有效），档位 T1

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local RECIPE_NAME = "ccs_legend_stone"
local PRODUCT = "lmoon_effect_stone_infinite_star"
local EFFECT_ID = "Legend_infinite_star"
local EFFECT_NAME = "infinite_star"
local CRAFT_MAGIC_COST = 225

-- =========================================================
-- 无限魔力：消耗入口拦截
-- =========================================================
-- 该玩家是否有"无限星力"效果
local function HasInfiniteStar(inst)
    return inst ~= nil and _G.Moon_HasEffect(inst, EFFECT_NAME)
end

-- 需要"真实付费"的配方：产物是小月亮自己的附魔石（炼石不能被无限魔力免单，
-- 否则可以无限刷石）。小樱本体那些消耗魔力的配方（物品/卡牌）不受影响。
local function NeedsRealMagicCost(recname)
    if recname == RECIPE_NAME then return true end
    local recipe = _G.AllRecipes ~= nil and _G.AllRecipes[recname] or nil
    local product = recipe ~= nil and recipe.product or nil
    if type(product) ~= "string" then return false end
    return product:find("^lmoon_effect_stone_") ~= nil
        or product:find("^moon_effect_stone_") ~= nil
end

AddComponentPostInit("ccs_magic", function(self)
    local old_DoDelta = self.DoDelta
    function self:DoDelta(amount, ...)
        local inst = self.inst
        -- 与原 consume_bf = 1 语义一致：消耗归零但仍走完 DoDelta（保留事件推送）；
        -- 制作炼石付款期间（_moon_crafting_magic_pay）不抵消，保证真实扣费
        if type(amount) == "number" and amount < 0
            and not (inst ~= nil and inst._moon_crafting_magic_pay)
            and HasInfiniteStar(inst)
        then
            amount = 0
        end
        return old_DoDelta(self, amount, ...)
    end
end)

-- 制作付费放行：本体已在 prefab 构造函数里包过一层 RemoveIngredients（扣魔力），
-- AddPrefabPostInit 晚于构造函数，这里包到的是本体那层 → 我们位于更外层。
AddPrefabPostInit("ccs", function(inst)
    if not _G.TheWorld.ismastersim then return end
    local builder = inst.components.builder
    if builder == nil then return end
    local old_RemoveIngredients = builder.RemoveIngredients
    builder.RemoveIngredients = function(self, ingredients, recname, ...)
        if not NeedsRealMagicCost(recname) then
            return old_RemoveIngredients(self, ingredients, recname, ...)
        end
        inst._moon_crafting_magic_pay = true
        local results = { _G.pcall(old_RemoveIngredients, self, ingredients, recname, ...) }
        inst._moon_crafting_magic_pay = nil
        if not results[1] then _G.error(results[2]) end
        return _G.unpack(results, 2)
    end
end)

-- =========================================================
-- 词条注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end
    -- 检测小樱mod
    if not _G.Moon_IsModEnabled("workshop-3043439883") then return end

    _G.AddSpecialEquipEffect(EFFECT_ID, {
        name = "无限星力",
        client_text = "无限\n星力",
        desc = "无限魔力(魔力消耗全免)\n仅小樱可用",
        check_desc = "星之力，取之不尽～",
        recipes = { PRODUCT },
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(equip_inst)
            return true, "满足条件"
        end,

        on_equip_fn = function(equip_inst, owner, value)
            if owner ~= nil and owner.prefab ~= "ccs" then
                if owner.components.talker then
                    owner.components.talker:Say("星星之力只回应小樱的呼唤！")
                end
                return
            end
            _G.Moon_AddEffect(owner, EFFECT_NAME, EFFECT_ID, 1)
        end,

        un_equip_fn = function(equip_inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_NAME, EFFECT_ID, 1)
        end,
    })

    -- T1：进掉落池（权重走 tier_config 中央表）
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)

-- =========================================================
-- 炼成配方：消耗225小樱魔力 → 产物 lmoon_effect_stone_infinite_star
-- （dummy prefab，由 lmoon_effect_stones.lua 的 OnBuiltFn 生成真正的
--   HH 附魔石并注入 Legend_infinite_star 效果）
-- =========================================================
STRINGS.NAMES.CCS_LEGEND_STONE = "无限星力附魔石"
STRINGS.RECIPE_DESC.CCS_LEGEND_STONE = "消耗225点小樱魔力，炼成无限星力附魔石。"
STRINGS.NAMES.LMOON_EFFECT_STONE_INFINITE_STAR = "无限星力附魔石"

AddSimPostInit(function()
    if not _G.Moon_IsHHEnabled() then return end
    if not _G.Moon_IsModEnabled("workshop-3043439883") then return end
    if _G.AllRecipes[RECIPE_NAME] ~= nil then return end
    -- 注意：AddRecipe2 是 mod 环境注入的 modutil 函数，不在 GLOBAL 里，
    -- 必须裸写（GLOBAL.AddRecipe2 会触发 strict.lua "not declared"）
    AddRecipe2(
        RECIPE_NAME,
        {
            _G.Ingredient(
                _G.CHARACTER_INGREDIENT.CCS_MAGIC,
                CRAFT_MAGIC_COST,
                "images/inventoryimages/ccs_magic.xml"
            ),
        },
        _G.TECH.NONE,
        {
            product = PRODUCT,
            builder_tag = "ccs",
            no_deconstruction = true,
            atlas = "images/hh_icon/hh_items.xml",
            image = "hh_effect_stone.tex",
            -- 本体的材料检查用 math.ceil(current)，224.x 魔力也会判定通过，
            -- 这里按实际值卡住，避免"魔力不够也能炼"
            canbuild = function(recipe, builder)
                local magic = builder.components.ccs_magic
                if builder.prefab ~= "ccs" or magic == nil then
                    return false, "仅小樱可以炼成"
                end
                if magic.current < CRAFT_MAGIC_COST then
                    return false, "魔力不足"
                end
                return true
            end,
        },
        { "CCS_TAB1" }
    )
end)
