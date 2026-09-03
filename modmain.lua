-- ================================================================================
-- 小月亮 (Little Moon) — 主入口
-- 功能模块拆分到 scripts/ 目录，此处仅做串联导入
-- ================================================================================

local _G = GLOBAL

-- 全局贴图资产（配方图标等独立于 prefab 的贴图）
Assets = {
    Asset("IMAGE", "images/inventoryimages/stalker_atrium.tex"),
    Asset("ATLAS", "images/inventoryimages/stalker_atrium.xml"),
    Asset("IMAGE", "images/inventoryimages/alterguardian_phase4_lunarrift.tex"),
    Asset("ATLAS", "images/inventoryimages/alterguardian_phase4_lunarrift.xml"),
    Asset("IMAGE", "images/inventoryimages/alterguardian_phase1.tex"),
    Asset("ATLAS", "images/inventoryimages/alterguardian_phase1.xml"),
    Asset("IMAGE", "images/inventoryimages/crabking.tex"),
    Asset("ATLAS", "images/inventoryimages/crabking.xml"),
    Asset("IMAGE", "images/inventoryimages/emojitan.tex"),
    Asset("ATLAS", "images/inventoryimages/emojitan.xml"),
    Asset("IMAGE", "images/inventoryimages/shijizhihua_bulb.tex"),
    Asset("ATLAS", "images/inventoryimages/shijizhihua_bulb.xml"),
    Asset("IMAGE", "images/inventoryimages/pig_man.tex"),
    Asset("ATLAS", "images/inventoryimages/pig_man.xml"),
    Asset("IMAGE", "images/inventoryimages/star_brooch.tex"),
    Asset("ATLAS", "images/inventoryimages/star_brooch.xml"),
}

PrefabFiles = {
    "moon_effect_stone_hanyue_test"
}
-- 骰子 RPC 在最顶部注册（确保客户端 MOD_RPC 表正确填充）
AddModRPCHandler("LittleMoon", "RollDice", function(player)
    if _G.Moon_DoDiceRoll then _G.Moon_DoDiceRoll(player) end
end)

modimport("scripts/strings")

-- ------------------------------------------------------------------
-- 0. 基础设施 (无依赖，工程环境)
-- ------------------------------------------------------------------
modimport("scripts/infrastructures/internal_tools_expand") -- 拓展内置函数
modimport("scripts/infrastructures/dynamic_component_presist_support") -- 支持动态组件的自动持久化
modimport("scripts/infrastructures/recipe_expand") -- 配方相关新 API 拓展

-- ------------------------------------------------------------------
-- 1. 核心工具层 (无依赖)
-- ------------------------------------------------------------------
modimport("scripts/core/config")
modimport("scripts/core/effect_manager")
modimport("scripts/core/mod_utils")
modimport("scripts/core/treasure_utils")

-- ------------------------------------------------------------------
-- 2. 功能模块 (各文件内部根据配置决定是否启用)
-- ------------------------------------------------------------------
modimport("scripts/features/hh_enchant_expand") -- 通用附魔机制拓展
modimport("scripts/features/anti_packing")
modimport("scripts/features/loot_limiter")
modimport("scripts/features/treasure")
modimport("scripts/features/quick_dig")
modimport("scripts/features/auto_pickup")
modimport("scripts/features/suicide")
modimport("scripts/features/lock_speed")
modimport("scripts/features/disable_reselect")
modimport("scripts/features/enchant_remover")
-- modimport("scripts/features/skin_ownership")
modimport("scripts/features/wardrobe_anywhere")
modimport("scripts/features/death_stats")
modimport("scripts/features/ban_items")
modimport("scripts/features/moon_shop")
modimport("scripts/features/moon_qunyou")     -- 小月亮商店：召唤群友（瞬发 prefab + 召唤逻辑）
modimport("scripts/features/mob_enhance/init")
modimport("scripts/features/start_gift")        -- 开局礼包（服务端逻辑，内部按配置启用）
modimport("scripts/features/start_gift_client") -- 开局礼包（客户端弹窗 UI，内部按配置启用）

-- ------------------------------------------------------------------
-- 3. 附魔模块
-- ------------------------------------------------------------------
modimport("scripts/enchants/drop_utils")
modimport("scripts/enchants/mx_health")
-- modimport("scripts/enchants/zd_butterfly") 紫蝶去掉
modimport("scripts/enchants/fqcd_sanity")
modimport("scripts/enchants/myxl_level")
modimport("scripts/enchants/yzdx")
modimport("scripts/enchants/wywq")
-- modimport("scripts/enchants/wjbd")   烷基八氮去掉
modimport("scripts/enchants/lanqiu")
modimport("scripts/enchants/aiyo")
modimport("scripts/enchants/fay")
modimport("scripts/enchants/yzq")
modimport("scripts/enchants/mgcy")
modimport("scripts/enchants/kongbai")
modimport("scripts/enchants/strawberry")
-- modimport("scripts/enchants/mxm")  -- 萌新已注释
modimport("scripts/enchants/gugugu")
modimport("scripts/enchants/ganfan")
modimport("scripts/enchants/hufei")
modimport("scripts/enchants/qianyue") 
modimport("scripts/enchants/xping")
-- modimport("scripts/enchants/jiuyue") -- 九月已注释，后续可能重做
modimport("scripts/enchants/genzhe")
modimport("scripts/enchants/suansuancao")
modimport("scripts/enchants/panghu")
modimport("scripts/enchants/yueban")
modimport("scripts/enchants/tutushengcai")
modimport("scripts/enchants/dagongren")
modimport("scripts/enchants/dengqiuling")
modimport("scripts/enchants/junjun")
modimport("scripts/enchants/luo")
modimport("scripts/enchants/lianggongcang")
modimport("scripts/enchants/huaimin")
modimport("scripts/enchants/laodong")
modimport("scripts/enchants/changpi")
modimport("scripts/enchants/xiaoguai")
modimport("scripts/enchants/shanzhu")
modimport("scripts/enchants/xingyunchengzhi")
modimport("scripts/enchants/zidie")
modimport("scripts/enchants/ccs_blessing")
modimport("scripts/enchants/malatutou")
modimport("scripts/enchants/yangmaoke")
modimport("scripts/enchants/youjishucai")
modimport("scripts/enchants/qiangwei")
modimport("scripts/enchants/dengdengqiuling")
modimport("scripts/enchants/epsilon")
modimport("scripts/enchants/fuzhong")
modimport("scripts/enchants/laoshi")
modimport("scripts/enchants/xiaohudie")
modimport("scripts/enchants/hanyue")      -- 寒月公主
modimport("scripts/enchants/yufenfen")    -- 雨纷纷
modimport("scripts/enchants/lianlian")    -- 无意识的恋恋
-- modimport("scripts/enchants/lihuaxue")
-- modimport("scripts/enchants/xinshidi")

modimport("scripts/enchants/aether") -- 拆除法杖功能性增强

-- ------------------------------------------------------------------
-- 配方
-- ------------------------------------------------------------------
modimport("scripts/recipes/recipe_stone") -- 附魔石配方



-- ------------------------------------------------------------------
-- 4. UI 界面 (仅当任一相关功能启用时加载)
-- ------------------------------------------------------------------
local CFG = GLOBAL.MOON_CFG
if CFG.ENABLE_TREASURE or CFG.ENABLE_QL_HELPER or CFG.ENABLE_AUTO_PICKUP or CFG.ENABLE_SUICIDE or CFG.ENABLE_MORE_ENCHANTS or CFG.ENABLE_DEATH_STATS or CFG.ENABLE_QUICK_CHAT or CFG.ENABLE_MOD_BROWSER then
    modimport("scripts/ui/moon_button")
    modimport("scripts/ui/moon_panel")
end

-- 死亡统计独立面板 (需要自己的UI注入)
if CFG.ENABLE_DEATH_STATS then
    modimport("scripts/ui/death_stats_inject")
end

-- ------------------------------------------------------------------
-- 5. 安全补丁 (始终加载)
-- ------------------------------------------------------------------
modimport("scripts/features/security_patch")

-- ------------------------------------------------------------------
-- 6. 蓝图本地化兜底 (始终加载)
--    小月亮商店配方 name 形如 "MoonShop_cutstone"（非产物 prefab 名），
--    STRINGS.NAMES 无对应条目；掉落任意蓝图随机抽到这些配方时，
--    原版 blueprint.lua 会用 string.upper(recipe.name) 查 STRINGS.NAMES，
--    拼接 nil 直接报错。这里为所有缺本地化名字的配方补上兜底名字。
-- ------------------------------------------------------------------
AddPrefabPostInit("world", function(inst)
    if not _G.AllRecipes or not _G.STRINGS or not _G.STRINGS.NAMES then return end
    for name, _ in pairs(_G.AllRecipes) do
        if type(name) == "string" then
            local key = string.upper(name)
            if _G.STRINGS.NAMES[key] == nil then
                if name:sub(1, 9) == "MoonShop_" then
                    _G.STRINGS.NAMES[key] = "小月亮商店兑换"
                else
                    _G.STRINGS.NAMES[key] = name
                end
            end
        end
    end
end)


-- -- WARNING: 上线前请注释，仅在开发时使用
-- -- WARNING: 上线前请注释，仅在开发时使用
-- -- WARNING: 上线前请注释，仅在开发时使用
-- GLOBAL.c_reload = function()
--     GLOBAL.StartNextInstance({
--         reset_action = GLOBAL.RESET_ACTION.LOAD_SLOT,
--         save_slot = GLOBAL.SaveGameIndex:GetCurrentSaveSlot()
--     })
-- end