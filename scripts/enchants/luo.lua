-- 小月亮 附魔：萝的守护
-- 50%几率免疫伤害，不会被影怪主动攻击，免疫僵直/击退
-- 每次攻击叠1层「守护」，每层+5%免伤，最多6层+30%，持续30秒

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_LUO", {
        name = "萝的守护",
        client_text = "萝的\n守护",
        desc = "50%几率免疫伤害\n免疫僵直/击退 影怪无视\n攻击叠「守护」每层+5%免伤(6层+30%/30秒)",
        check_desc = "小萝卜头的倔强守护！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "luo", "Legend_LUO", 1)
            if not owner._luo_hooked then
                owner._luo_hooked = true
                owner._luo_shield_stacks = 0
                owner._luo_decay_task = nil

                -- 免疫僵直
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("immunityKnockBack", 1)
                end
                _G.Moon_AddEffect(owner, "jiangzhi", "Legend_LUO", 1)

                -- 影怪无视：移除玩家标签让影怪不主动攻击，但加回标记让游戏逻辑正常工作
                if not owner:HasTag("shadowcreature") then
                    owner:AddTag("notarget")
                    owner._luo_added_notarget = true
                end

                -- 更新守护层数的减伤
                local function updateShield()
                    local hh = owner.components.hh_player
                    if not hh then return end
                    -- 先清除旧值
                    hh:ReduceEffectValueByKey("absorbDamage", 30)
                    local stacks = owner._luo_shield_stacks or 0
                    if stacks > 0 then
                        hh:AddEffectValueByKey("absorbDamage", stacks * 5)
                    end
                end

                -- 重置衰减定时器
                local function resetDecay()
                    if owner._luo_decay_task then
                        owner._luo_decay_task:Cancel()
                    end
                    owner._luo_decay_task = owner:DoTaskInTime(30, function()
                        if owner:IsValid() then
                            local hh = owner.components.hh_player
                            if hh then
                                hh:ReduceEffectValueByKey("absorbDamage", (owner._luo_shield_stacks or 0) * 5)
                            end
                            owner._luo_shield_stacks = 0
                        end
                    end)
                end

                -- 攻击时叠守护层数
                owner._luo_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "luo") then return end
                    owner._luo_shield_stacks = math.min((owner._luo_shield_stacks or 0) + 1, 6)
                    updateShield()
                    resetDecay()
                end
                owner:ListenForEvent("onattackother", owner._luo_attack_handler)

                -- 50%几率免伤 + 触发守护特效：勾住 health:DoDelta
                local health = owner.components.health
                if health and not health._luo_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._luo_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 then
                            if _G.Moon_HasEffect(owner, "luo") then
                                -- 50%几率完全免伤
                                if math.random() <= 0.5 then
                                    return oldDoDelta(self, 0, overtime, cause, ...)
                                end
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._luo_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "luo", "Legend_LUO", 1)
            if not _G.Moon_HasEffect(owner, "luo") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("immunityKnockBack", 1)
                    hh:ReduceEffectValueByKey("absorbDamage", (owner._luo_shield_stacks or 0) * 5)
                end
                _G.Moon_ReduceEffect(owner, "jiangzhi", "Legend_LUO", 1)

                if owner._luo_added_notarget then
                    owner:RemoveTag("notarget")
                    owner._luo_added_notarget = nil
                end

                if owner._luo_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._luo_attack_handler)
                    owner._luo_attack_handler = nil
                end

                if owner._luo_decay_task then
                    owner._luo_decay_task:Cancel()
                    owner._luo_decay_task = nil
                end

                local health = owner.components.health
                if health and health._luo_old_dodelta then
                    health.DoDelta = health._luo_old_dodelta
                    health._luo_old_dodelta = nil
                    health._luo_hooked_dodelta = nil
                end

                owner._luo_shield_stacks = nil
                owner._luo_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_LUO", 0.005)
end)
