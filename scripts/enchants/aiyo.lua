-- 小月亮 附魔：哎哟
-- 以牙还牙 — 受到伤害时瞬回所受伤害60%的生命值，并反弹100%伤害给攻击者
-- 「记仇」：被攻击时标记攻击者，你对标记目标的伤害+20%，持续10秒
-- 「报仇」：击杀被标记的敌人时回复最大生命15%并触发冲击波（周围5码150%范围伤害）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_AIYO", {
        name = "哎哟",
        client_text = "哎\n哟",
        desc = "受伤回血60%+反弹100%伤害\n记仇增伤20%，报仇回血15%+冲击波",
        check_desc = "哎哟，打我你也疼！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "aiyo", "Legend_AIYO", 1)
            if not owner._aiyo_hooked then
                owner._aiyo_hooked = true
                owner._aiyo_marked_target = nil

                -- 记仇：标记攻击者，对其伤害+20%持续10秒
                local function markAttacker(attacker)
                    if not attacker or not attacker:IsValid() then return end
                    if attacker == owner then return end

                    -- 清除旧标记
                    owner._aiyo_marked_target = nil

                    -- 标记新目标
                    owner._aiyo_marked_target = attacker

                    -- 10秒后自动清除标记
                    if owner._aiyo_mark_task then
                        owner._aiyo_mark_task:Cancel()
                    end
                    owner._aiyo_mark_task = owner:DoTaskInTime(10, function()
                        owner._aiyo_marked_target = nil
                    end)
                end

                -- 监听攻击，检测是否攻击标记目标（加伤20%）
                owner._aiyo_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "aiyo") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target ~= owner._aiyo_marked_target then return end

                    -- 对标记目标造成额外20%伤害
                    if target.components.health and not target.components.health:IsDead() then
                        local hh = owner.components.hh_player
                        if hh then
                            -- 用临时buff提升伤害
                            local dmg = owner.components.combat and owner.components.combat.defaultdamage or 10
                            local bonus = dmg * 0.2
                            _G.pcall(function()
                                target.components.health:DoDelta(-bonus, false, "aiyo_grudge")
                            end)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._aiyo_attack_handler)

                -- 监听击杀，检测击杀的是否是标记目标
                owner._aiyo_kill_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "aiyo") then return end
                    local victim = data and data.victim
                    if not victim or not victim:IsValid() then return end
                    if victim ~= owner._aiyo_marked_target then return end

                    -- 报仇：回复15%最大生命
                    if owner.components.health then
                        local max_hp = owner.components.health.maxhealth or 150
                        owner.components.health:DoDelta(max_hp * 0.15, false, "aiyo_revenge")
                    end

                    -- 冲击波：周围5码150%范围伤害
                    local x, y, z = victim.Transform:GetWorldPosition()
                    local nearby = _G.TheSim:FindEntities(x, y, z, 5, { "_combat" })
                    local base_dmg = owner.components.combat and owner.components.combat.defaultdamage or 10
                    local wave_dmg = base_dmg * 1.5
                    for _, enemy in ipairs(nearby) do
                        if enemy ~= owner and enemy:IsValid()
                            and enemy.components.health and not enemy.components.health:IsDead() then
                            enemy.components.health:DoDelta(-wave_dmg, false, "aiyo_revenge")
                        end
                    end

                    -- 清除标记
                    owner._aiyo_marked_target = nil
                    if owner._aiyo_mark_task then
                        owner._aiyo_mark_task:Cancel()
                        owner._aiyo_mark_task = nil
                    end
                end
                owner:ListenForEvent("onkilled", owner._aiyo_kill_handler)

                -- 勾住 health:DoDelta 实现瞬发回血 + 反弹 + 记仇
                local health = owner.components.health
                if health and not health._aiyo_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._aiyo_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and cause ~= "aiyo_heal" and cause ~= "aiyo_revenge" and cause ~= "aiyo_grudge" then
                            if _G.Moon_HasEffect(owner, "aiyo") then
                                local damage = -delta

                                -- 瞬发回血60%
                                local heal = damage * 0.6
                                if owner:IsValid() then
                                    oldDoDelta(self, -heal, false, "aiyo_heal")
                                end

                                -- 反弹100%伤害给攻击者
                                local attacker = nil
                                if owner.components.combat and owner.components.combat.lastattacker then
                                    attacker = owner.components.combat.lastattacker
                                end
                                if attacker and attacker:IsValid() and attacker.components.health
                                    and not attacker.components.health:IsDead()
                                    and attacker ~= owner then
                                    attacker.components.health:DoDelta(-damage, false, "aiyo_reflect")
                                end

                                -- 记仇：标记攻击者
                                markAttacker(attacker)

                                return oldDoDelta(self, 0, overtime, cause, ...)
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._aiyo_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "aiyo", "Legend_AIYO", 1)
            if not _G.Moon_HasEffect(owner, "aiyo") then
                if owner._aiyo_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._aiyo_attack_handler)
                    owner._aiyo_attack_handler = nil
                end
                if owner._aiyo_kill_handler then
                    owner:RemoveEventCallback("onkilled", owner._aiyo_kill_handler)
                    owner._aiyo_kill_handler = nil
                end
                if owner._aiyo_mark_task then
                    owner._aiyo_mark_task:Cancel()
                    owner._aiyo_mark_task = nil
                end

                local health = owner.components.health
                if health and health._aiyo_old_dodelta then
                    health.DoDelta = health._aiyo_old_dodelta
                    health._aiyo_old_dodelta = nil
                    health._aiyo_hooked_dodelta = nil
                end
                owner._aiyo_hooked = nil
                owner._aiyo_marked_target = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_AIYO", 0.01)
end)
