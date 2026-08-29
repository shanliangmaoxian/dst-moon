-- 小月亮 附魔：等秋零
-- 攻击力 +25%，移动速度 +15%。受到攻击时 20% 几率完全免疫该次伤害并回复 15 点精神值。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_DENGQIULING", {
        name = "等秋零",
        client_text = "等秋\n零",
        desc = "秋意渐浓：攻击力+25%，移动速度+15%\n秋水长天：受到攻击时20%几率完全免疫伤害并回复15点精神值",
        check_desc = "浅笑依然痴若离",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "dengqiuling", "Legend_DENGQIULING", 1)
            if not owner._dengqiuling_hooked then
                owner._dengqiuling_hooked = true

                -- 基础属性加成
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("addComDamagePercent", 25)
                    hh:AddEffectValueByKey("addSpeedPercent", 15)
                end

                -- 受到伤害20%几率免疫并回复15精神
                local health = owner.components.health
                if health and not health._dengqiuling_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._dengqiuling_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and cause ~= "dengqiuling_ignore" then
                            if _G.Moon_HasEffect(owner, "dengqiuling") and math.random() <= 0.20 then
                                -- 触发免疫
                                if owner.components.sanity then
                                    owner.components.sanity:DoDelta(15)
                                end
                                if owner.components.talker then
                                    owner.components.talker:Say("浅笑依然痴若离")
                                end
                                delta = 0 -- 免疫伤害
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._dengqiuling_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "dengqiuling", "Legend_DENGQIULING", 1)
            if not _G.Moon_HasEffect(owner, "dengqiuling") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addComDamagePercent", 25)
                    hh:ReduceEffectValueByKey("addSpeedPercent", 15)
                end

                local health = owner.components.health
                if health and health._dengqiuling_old_dodelta then
                    health.DoDelta = health._dengqiuling_old_dodelta
                    health._dengqiuling_old_dodelta = nil
                    health._dengqiuling_hooked_dodelta = nil
                end
                owner._dengqiuling_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_DENGQIULING", 0.01)
end)
