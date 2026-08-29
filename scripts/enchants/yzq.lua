-- 小月亮 附魔：云中雀
-- 移动速度+35%，攻击有15%几率造成300%伤害
-- 每8秒获得「翱翔」buff：下一次攻击造成450%范围伤害
-- 翱翔期间免疫伤害（持续1.5秒）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_YZQ", {
        name = "云中雀",
        client_text = "云中\n雀",
        desc = "移速+35%，攻击15%几率300%伤害\n每8秒获翱翔buff:下次攻击450%范围伤害,翱翔期间免疫",
        check_desc = "云中雀，自由翱翔！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "yzq", "Legend_YZQ", 1)
            if not owner._yzq_hooked then
                owner._yzq_hooked = true
                owner._yzq_soaring = false
                owner._yzq_soar_ready = false

                local hh = owner.components.hh_player

                -- 永久移速+35%，攻击15%几率300%伤害(暴击3倍)
                if hh then
                    hh:AddEffectValueByKey("addSpeedPercent", 35)
                    hh:AddEffectValueByKey("criticalHitRate", 15)
                    hh:AddEffectValueByKey("criticalHitEffect", 100)
                end

                -- 每8秒获得翱翔充能
                owner._yzq_soar_task = owner:DoPeriodicTask(8, function()
                    if not _G.Moon_HasEffect(owner, "yzq") then return end
                    owner._yzq_soar_ready = true
                    if owner.components.talker then
                        owner.components.talker:Say("翱翔！")
                    end
                end)

                -- 翱翔buff：免疫伤害 (通过 intercept 实现)
                local function activateSoaring()
                    owner._yzq_soaring = true
                    owner._yzq_soar_ready = false
                    -- 免疫伤害（包装 DoDelta，翱翔期间负值伤害归零走原函数）
                    local health = owner.components.health
                    if health and not health._yzq_hooked_dodelta then
                        local oldDoDelta = health.DoDelta
                        local function yzq_soar_wrapper(self, delta, ...)
                            if owner._yzq_soaring and delta < 0 then
                                return oldDoDelta(self, 0, ...) -- 免疫伤害（归零，保持返回语义）
                            end
                            return oldDoDelta(self, delta, ...)
                        end
                        health._yzq_old_dodelta = oldDoDelta
                        health._yzq_wrapper = yzq_soar_wrapper
                        health.DoDelta = yzq_soar_wrapper
                        health._yzq_hooked_dodelta = true
                    end
                    -- 1.5秒后结束（存句柄，卸载时 Cancel）
                    owner._yzq_soar_timer = owner:DoTaskInTime(1.5, function()
                        if owner:IsValid() then
                            owner._yzq_soaring = false
                            owner._yzq_soar_timer = nil
                        end
                    end)
                end

                -- 攻击时检查翱翔
                owner._yzq_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "yzq") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    if owner._yzq_soar_ready then
                        activateSoaring()

                        -- 450% 范围伤害
                        local tx, ty, tz = target.Transform:GetWorldPosition()
                        local nearby = GLOBAL.TheSim:FindEntities(tx, ty, tz, 4, { "_combat" })
                        for _, victim in ipairs(nearby) do
                            if victim ~= owner and victim.components.health and not victim.components.health:IsDead() then
                                local dmg = (owner.components.combat and owner.components.combat.defaultdamage) or 34
                                victim.components.health:DoDelta(-dmg * 4.5, false, nil)
                            end
                        end

                        -- 特效
                        if GLOBAL.SpawnPrefab then
                            local fx = GLOBAL.SpawnPrefab("collapse_small")
                            if fx then
                                fx.Transform:SetPosition(tx, ty, tz)
                                fx.Transform:SetScale(1.5, 1.5, 1.5)
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._yzq_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yzq", "Legend_YZQ", 1)
            if not _G.Moon_HasEffect(owner, "yzq") then
                -- 恢复 speed / 暴击
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addSpeedPercent", 35)
                    hh:ReduceEffectValueByKey("criticalHitRate", 15)
                    hh:ReduceEffectValueByKey("criticalHitEffect", 100)
                end
                -- 恢复 DoDelta（校验归属：仅当当前包装还是自己的才还原）
                local health = owner.components.health
                if health and health._yzq_wrapper and health.DoDelta == health._yzq_wrapper then
                    health.DoDelta = health._yzq_old_dodelta
                end
                if health then
                    health._yzq_old_dodelta = nil
                    health._yzq_wrapper = nil
                    health._yzq_hooked_dodelta = nil
                end
                if owner._yzq_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._yzq_attack_handler)
                    owner._yzq_attack_handler = nil
                end
                if owner._yzq_soar_task then
                    owner._yzq_soar_task:Cancel()
                    owner._yzq_soar_task = nil
                end
                if owner._yzq_soar_timer then
                    owner._yzq_soar_timer:Cancel()
                    owner._yzq_soar_timer = nil
                end
                owner._yzq_soaring = nil
                owner._yzq_soar_ready = nil
                owner._yzq_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YZQ", 0.01)
end)
