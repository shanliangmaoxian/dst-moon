-- 小月亮 附魔：负重前行
-- 移速减少90%，获得20%免伤，攻击倍率×2
-- 获取：Boss 掉落附魔石

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_FUZHONG", {
        name = "负重前行",
        client_text = "负重\n前行",
        desc = "身负千钧，步履维艰\n移速减少90%\n获得20%免伤\n攻击倍率×2",
        check_desc = "负重前行，一步一个脚印！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "fuzhong", "Legend_FUZHONG", 1)
            if not owner._fuzhong_hooked then
                owner._fuzhong_hooked = true

                -- 移速减少90%（HH 框架 addSpeedPercent 仅支持正值，用外部移速倍率实现减速）
                if owner.components.locomotor then
                    owner.components.locomotor:SetExternalSpeedMultiplier(owner, "fuzhong_slow", 0.1)
                end

                -- 20%免伤 + 攻击倍率×2（HH 框架百分比词条）
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("absorbDamage", 20)
                    hh:AddEffectValueByKey("addComDamagePercent", 100)
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "fuzhong", "Legend_FUZHONG", 1)
            if not _G.Moon_HasEffect(owner, "fuzhong") then
                if owner.components.locomotor then
                    owner.components.locomotor:RemoveExternalSpeedMultiplier(owner, "fuzhong_slow")
                end
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("absorbDamage", 20)
                    hh:ReduceEffectValueByKey("addComDamagePercent", 100)
                end
                owner._fuzhong_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_FUZHONG", 0.01)
end)
