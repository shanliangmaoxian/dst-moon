-- 小月亮 附魔：烷基八氮
-- 攻击20%几率冰冻目标2秒。冰冻破碎时引发冰爆(300%范围伤害)
-- 减速周围敌人50%持续3秒。对被冰冻目标伤害+50%

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_WJBD", {
        name = "烷基八氮",
        client_text = "烷基\n八氮",
        desc = "攻击20%几率冰冻目标2秒\n冰冻破碎时引发冰爆(300%范围伤害)\n对冰冻目标伤害+50%",
        check_desc = "冰冻结界，化学之力！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "wjbd", "Legend_WJBD", 1)
            if not owner._wjbd_hooked then
                owner._wjbd_hooked = true

                -- 攻击时触发
                owner._wjbd_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "wjbd") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    -- 20% 冰冻几率
                    if math.random() <= 0.2 then
                        if target.components.freezable then
                            target.components.freezable:AddColdness(2)
                            target._wjbd_frozen_by = owner

                            -- 监听解冻 → 触发冰爆
                            target:ListenForEvent("onthaw", function(t)
                                if t._wjbd_frozen_by and t._wjbd_frozen_by:IsValid() then
                                    local by = t._wjbd_frozen_by
                                    -- 冰爆AoE 300%伤害
                                    local fx_x, fx_y, fx_z = t.Transform:GetWorldPosition()
                                    if _G.SpawnPrefab then
                                        local boom = _G.SpawnPrefab("deerclops_icespike_fx")
                                        if boom then
                                            boom.Transform:SetPosition(fx_x, fx_y, fx_z)
                                            boom.Transform:SetScale(2, 2, 2)
                                        end
                                    end
                                    local nearby = _G.TheSim:FindEntities(fx_x, fx_y, fx_z, 4, { "_combat" })
                                    for _, victim in ipairs(nearby) do
                                        if victim ~= by and victim.components.health and not victim.components.health:IsDead() then
                                            if by.components.combat then
                                                local dmg = by.components.combat.defaultdamage or 34
                                                victim.components.health:DoDelta(-dmg * 3, false, nil)
                                            end
                                        end
                                    end
                                end
                                t._wjbd_frozen_by = nil
                            end)

                            -- 冰霜特效
                            if _G.SpawnPrefab then
                                local fx = _G.SpawnPrefab("deerclops_icespike_fx")
                                if fx then
                                    local x, y, z = target.Transform:GetWorldPosition()
                                    fx.Transform:SetPosition(x, y, z)
                                    fx.Transform:SetScale(1.2, 1.2, 1.2)
                                end
                            end
                        end
                    end

                    -- 对冰冻目标伤害+50%
                    if target.components.freezable and target.components.freezable:IsFrozen() then
                        if owner.components.combat then
                            -- 通过临时增加伤害实现
                            local hh = owner.components.hh_player
                            if hh then
                                hh:AddEffectValueByKey("addComDamagePercent", 50)
                                -- 下一帧移除(仅当前攻击生效)
                                owner:DoTaskInTime(0.1, function()
                                    if owner:IsValid() and owner.components.hh_player then
                                        owner.components.hh_player:ReduceEffectValueByKey("addComDamagePercent", 50)
                                    end
                                end)
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._wjbd_attack_handler)

                -- 冰爆已通过 onthaw 事件驱动，无需轮询
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "wjbd", "Legend_WJBD", 1)
            if not _G.Moon_HasEffect(owner, "wjbd") then
                if owner._wjbd_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._wjbd_attack_handler)
                    owner._wjbd_attack_handler = nil
                end
                owner._wjbd_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_WJBD", 0.01)
end)
