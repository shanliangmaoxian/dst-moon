-- 小月亮 附魔：无限星力
-- 联动魔卡少女小樱mod(workshop-3043439883)
-- 获取：小樱(ccs)消耗225点魔力炼成「无限星力附魔石」(配方 ccs_legend_stone)
-- 效果：佩戴后魔力消耗全免 = 无限魔力（走 ccs_magic 组件的 SetConsume_bf 消耗减免接口）
-- 仅小樱可用（非小樱佩戴无效果），档位 T1

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local RECIPE_NAME = "ccs_legend_stone"
local PRODUCT = "hh_effect_stone"
local EFFECT_ID = "Legend_infinite_star"

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end
    -- 检测小樱mod
    if not _G.Moon_IsModEnabled("workshop-3043439883") then return end

    _G.AddSpecialEquipEffect(EFFECT_ID, {
        name = "无限星力",
        client_text = "无限\n星力",
        desc = "无限魔力(魔力消耗全免)\n仅小樱可用",
        check_desc = "星之力，取之不尽～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(equip_inst)
            return true, "满足条件"
        end,

        on_equip_fn = function(equip_inst, owner, value)
            if owner.prefab ~= "ccs" then
                if owner.components.talker then
                    owner.components.talker:Say("星星之力只回应小樱的呼唤！")
                end
                return
            end
            _G.Moon_AddEffect(owner, "infinite_star", EFFECT_ID, 1)
            local magic = owner.components.ccs_magic
            if magic and not owner._infinite_star_hooked then
                owner._infinite_star_hooked = true
                owner._infinite_star_old_bf = magic.consume_bf
                magic:SetConsume_bf(1) -- 负向 DoDelta × (1-1) = 0，魔力消耗全免
            end
        end,

        un_equip_fn = function(equip_inst, owner, value)
            _G.Moon_ReduceEffect(owner, "infinite_star", EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, "infinite_star") then
                local magic = owner.components.ccs_magic
                if magic and owner._infinite_star_hooked then
                    magic:SetConsume_bf(owner._infinite_star_old_bf or 0)
                    owner._infinite_star_old_bf = nil
                    owner._infinite_star_hooked = nil
                end
            end
        end,
    })

    -- T1：进掉落池（权重走 tier_config 中央表）
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)

-- =========================================================
-- 炼成配方：消耗225小樱魔力 → 产物 hh_effect_stone 并注入
-- Legend_infinite_star 效果（HH 通用附魔石 prefab + hh_effect 字段）
-- =========================================================
local function SetLegendStone(item)
    if item == nil or item.prefab ~= PRODUCT then
        return false
    end
    item.hh_effect = EFFECT_ID
    if item.HH_Update_Server ~= nil then
        item:HH_Update_Server()
    end
    return true
end

local function OnBuildLegendStone(builder, data)
    local recipe = data ~= nil and data.recipe or nil
    local recipe_name = type(recipe) == "table" and recipe.name or recipe
    if recipe_name ~= RECIPE_NAME or not SetLegendStone(data.item) then
        return
    end
    local display_name = builder ~= nil and builder.GetDisplayName ~= nil
        and builder:GetDisplayName()
        or "玩家"
    _G.TheNet:Announce(string.format("恭喜 %s 炼成了「无限星力附魔石」！", tostring(display_name)))
end

STRINGS.NAMES.CCS_LEGEND_STONE = "无限星力附魔石"
STRINGS.RECIPE_DESC.CCS_LEGEND_STONE = "消耗225点小樱魔力，炼成无限星力附魔石。"

AddPlayerPostInit(function(inst)
    if _G.TheWorld.ismastersim then
        inst:ListenForEvent("builditem", OnBuildLegendStone)
    end
end)

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
                225,
                "images/inventoryimages/ccs_magic.xml"
            ),
        },
        _G.TECH.NONE,
        {
            product = PRODUCT,
            builder_tag = "ccs",
            --nounlock = true,
            no_deconstruction = true,
            atlas = "images/hh_icon/hh_items.xml",
            image = "hh_effect_stone.tex",
        },
        { "CCS_TAB1" }
    )
end)
