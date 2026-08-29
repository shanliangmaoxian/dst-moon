-- 小月亮 附魔：月半
-- 免疫击退/僵直，攻击附带自身当前生命值5%额外伤害
-- 受到伤害时20%几率「肉弹冲击」：周围3码敌人150%伤害+减速30%持续3秒

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_YUEBAN", {
        name = "月半",
        client_text = "月\n半",
        desc = "免疫击退/僵直\n攻击附带自身当前生命值5%额外伤害\n受击20%几率「肉弹冲击」:\n周围3码敌人150%伤害+减速30%持续3秒",
        check_desc = "吨位即是力量！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "yueban", "Legend_YUEBAN", 1)
            if not owner._yueban_hooked then
                owner._yueban_hooked = true

                -- 免疫击退/僵直
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("immunityKnockBack", 1)
                end
                _G.Moon_AddEffect(owner, "jiangzhi", "Legend_YUEBAN", 1)

                -- 攻击附带自身当前生命值5%额外伤害
                owner._yueban_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "yueban") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    if owner.components.health and target.components.health then
                        local bonus = owner.components.health.currenthealth * 0.05
                        target.components.health:DoDelta(-bonus, false, "yueban")
                    end
                end
                owner:ListenForEvent("onattackother", owner._yueban_attack_handler)

                -- 受击20%几率肉弹冲击
                owner._yueban_attacked_handler = function(victim, data)
                    if not _G.Moon_HasEffect(owner, "yueban") then return end
                    if math.random() > 0.2 then return end

                    local x, y, z = owner.Transform:GetWorldPosition()
                    local nearby = GLOBAL.TheSim:FindEntities(x, y, z, 3, { "_combat" })
                    for _, target in ipairs(nearby) do
                        if target ~= owner and target:IsValid()
                            and target.components.health
                            and not target.components.health:IsDead() then
                            -- 150%伤害
                            local dmg = (owner.components.combat and owner.components.combat.defaultdamage) or 34
                            target.components.health:DoDelta(-dmg * 1.5, false, "yueban")
                            -- 减速30%持续3秒
                            if target.components.locomotor then
                                target.components.locomotor:SetExternalSpeedMultiplier(target, "yueban_slow", 0.7)
                                target:DoTaskInTime(3, function()
                                    if target:IsValid() and target.components.locomotor then
                                        target.components.locomotor:RemoveExternalSpeedMultiplier(target, "yueban_slow")
                                    end
                                end)
                            end
                        end
                    end

                    -- 特效
                    if GLOBAL.SpawnPrefab then
                        local fx = GLOBAL.SpawnPrefab("collapse_small")
                        if fx then
                            fx.Transform:SetPosition(x, y, z)
                            fx.Transform:SetScale(1.2, 1.2, 1.2)
                        end
                    end

                    if owner.components.talker then
                        owner.components.talker:Say("肉弹冲击！")
                    end
                end
                owner:ListenForEvent("attacked", owner._yueban_attacked_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yueban", "Legend_YUEBAN", 1)
            if not _G.Moon_HasEffect(owner, "yueban") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("immunityKnockBack", 1)
                end
                _G.Moon_ReduceEffect(owner, "jiangzhi", "Legend_YUEBAN", 1)

                if owner._yueban_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._yueban_attack_handler)
                    owner._yueban_attack_handler = nil
                end
                if owner._yueban_attacked_handler then
                    owner:RemoveEventCallback("attacked", owner._yueban_attacked_handler)
                    owner._yueban_attacked_handler = nil
                end
                owner._yueban_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YUEBAN", 0.01)
end)
