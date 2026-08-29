-- 小月亮 附魔：灵尾印记
-- 每天灵尾+1~5 (上限5)，依赖璇儿 Mod

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end
    if not _G.Moon_IsMYXLEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_MYXL_LEVEL", {
        name = "灵尾印记",
        client_text = "灵\n尾印",
        desc = "每天灵尾+1~5(上限5)",
        check_desc = "只对璇儿生效\n仅限背包/百宝囊附魔",
        can_add = false,
        only_one = false,           -- 可叠加
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        ui_from_desc = "击败精英/Boss概率掉落",
        check_equip_can_add = function(inst)
            if inst:HasTag("backpack") then
                return true, "满足条件"
            end
            if inst.prefab and string.find(inst.prefab, "myxl_bag3x") then
                return true, "满足条件"
            end
            return false, "只允许附魔在背包或百宝囊上"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "myxl_level", "Legend_MYXL_LEVEL", 1)
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "myxl_level", "Legend_MYXL_LEVEL", 1)
        end,
    })

    -- 每日周期：灵尾+1~5
    AddPrefabPostInitAny(function(inst)
        if not GLOBAL.TheWorld.ismastersim then return end
        if not inst:HasTag("player") then return end
        inst:WatchWorldState("cycles", function(inst, cycles)
            local level = _G.Moon_GetTotalEffectValue(inst, "myxl_level")
            if level > 0 then
                local myxl_level = inst.components.myxl_level
                if myxl_level and myxl_level.LevelUp then
                    local daily_gain = math.random(1, 5)
                    myxl_level:LevelUp(false, math.min(level * daily_gain, 5))
                end
            end
        end)
    end)

    -- 精英/Boss 掉落 (3%)
    _G.Moon_RegisterEnchantDrop("Legend_MYXL_LEVEL", 0.01)
end)
