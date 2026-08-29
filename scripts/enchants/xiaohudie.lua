-- 小月亮 附魔：小蝴蝶
-- 限伤10%、免疫反伤、脱手、免疫击飞、免疫中毒、免疫制裁
-- 小蝴蝶，飞啊飞啊飞～

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_XIAOHUDIE", {
        name = "小蝴蝶",
        client_text = "小蝴\n蝶",
        desc = "限伤10%+免疫反伤+脱手\n免疫击飞+免疫中毒+免疫制裁",
        check_desc = "小蝴蝶，飞啊飞啊飞～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0.5, 1, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "xiaohudie", "Legend_XIAOHUDIE", 1)
            if not owner._xiaohudie_hooked then
                owner._xiaohudie_hooked = true

                -- HH框架效果
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("immuneBramble", 1)
                    hh:AddEffectValueByKey("immunePoison", 1)
                    hh:AddEffectValueByKey("immunityKnockBack", 1)
                    hh:AddEffectValueByKey("immuneSuppressNum", 1)
                end

                -- 脱手（免疫缴械）
                owner:AddTag("stronggrip")

                -- 限伤10%
                local health = owner.components.health
                if health and not health._xiaohudie_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._xiaohudie_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and _G.Moon_HasEffect(owner, "xiaohudie") and owner:IsValid() then
                            local damage = -delta
                            local max_hp = owner.components.health.maxhealth or 150
                            local cap = max_hp * 0.10
                            if damage > cap then
                                damage = cap
                            end
                            return oldDoDelta(self, -damage, overtime, cause, ...)
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._xiaohudie_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "xiaohudie", "Legend_XIAOHUDIE", 1)
            if not _G.Moon_HasEffect(owner, "xiaohudie") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("immuneBramble", 1)
                    hh:ReduceEffectValueByKey("immunePoison", 1)
                    hh:ReduceEffectValueByKey("immunityKnockBack", 1)
                    hh:ReduceEffectValueByKey("immuneSuppressNum", 1)
                end
                owner:RemoveTag("stronggrip")

                local health = owner.components.health
                if health and health._xiaohudie_old_dodelta then
                    health.DoDelta = health._xiaohudie_old_dodelta
                    health._xiaohudie_old_dodelta = nil
                    health._xiaohudie_hooked_dodelta = nil
                end

                owner._xiaohudie_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_XIAOHUDIE", 0.01)
end)
