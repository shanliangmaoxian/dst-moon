-- 小月亮 附魔：咕咕咕
-- 闪避率+42%。成功闪避后进入「鸽了！」状态：下一次攻击必定暴击且暴击伤害+400%
-- 持续6秒。闪避失败时召唤鸽子反击，造成攻击力200%伤害。内置冷却0.5秒。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_GUGUGU", {
        name = "咕咕咕",
        client_text = "咕咕\n咕",
        desc = "闪避+42%，成功闪避必暴+400%暴伤\n失败召唤鸽子反击200%，冷却0.5秒",
        check_desc = "鸽之意志！打不过就鸽！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "gugugu", "Legend_GUGUGU", 1)
            if not owner._gugugu_hooked then
                owner._gugugu_hooked = true
                owner._gugugu_dodge_cooldown = false
                owner._gugugu_dodged = false

                -- 闪避率+42%：通过 absorbDamage 实现减伤
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("absorbDamage", 42)
                end

                -- 被攻击时：42%几率闪避成功，58%几率失败反击
                owner._gugugu_attacked_handler = function(victim, data)
                    if not _G.Moon_HasEffect(owner, "gugugu") then return end

                    local attacker = data and data.attacker
                    if not attacker or not attacker:IsValid() then return end
                    if attacker == owner then return end

                    if math.random() <= 0.42 then
                        -- 闪避成功 → 「鸽了！」暴击buff
                        if not owner._gugugu_dodged then
                            owner._gugugu_dodged = true
                            local hh_player = owner.components.hh_player
                            if hh_player then
                                hh_player:AddEffectValueByKey("criticalHitRate", 100)
                                hh_player:AddEffectValueByKey("criticalHitEffect", 400)
                            end
                        end

                        -- 刷新6秒过期计时（无论是否已有buff都刷新）
                        if owner._gugugu_dodged_task then
                            owner._gugugu_dodged_task:Cancel()
                        end
                        owner._gugugu_dodged_task = owner:DoTaskInTime(6, function()
                            if owner:IsValid() then
                                owner._gugugu_dodged = false
                                if owner.components.hh_player then
                                    owner.components.hh_player:ReduceEffectValueByKey("criticalHitRate", 100)
                                    owner.components.hh_player:ReduceEffectValueByKey("criticalHitEffect", 400)
                                end
                            end
                        end)

                        if owner.components.talker then
                            owner.components.talker:Say("鸽了！")
                        end
                    else
                        -- 闪避失败 → 鸽子反击（0.5秒冷却）
                        if owner._gugugu_dodge_cooldown then return end
                        owner._gugugu_dodge_cooldown = true
                        owner:DoTaskInTime(0.5, function()
                            if owner:IsValid() then
                                owner._gugugu_dodge_cooldown = false
                            end
                        end)

                        -- 召唤3只鸽子反击
                        for i = 1, 3 do
                            owner:DoTaskInTime(i * 0.15, function()
                                if not owner:IsValid() then return end
                                if not attacker:IsValid() then return end

                                -- 造成200%攻击力伤害
                                if attacker.components.health and not attacker.components.health:IsDead() then
                                    local dmg = (owner.components.combat and owner.components.combat.defaultdamage) or 34
                                    attacker.components.health:DoDelta(-dmg * 2, false, nil)
                                end
                            end)
                        end
                    end
                end
                owner:ListenForEvent("attacked", owner._gugugu_attacked_handler)

                -- 攻击后消耗「鸽了！」buff
                owner._gugugu_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "gugugu") then return end
                    if owner._gugugu_dodged then
                        owner._gugugu_dodged = false
                        if owner._gugugu_dodged_task then
                            owner._gugugu_dodged_task:Cancel()
                            owner._gugugu_dodged_task = nil
                        end
                        if owner.components.hh_player then
                            owner.components.hh_player:ReduceEffectValueByKey("criticalHitRate", 100)
                            owner.components.hh_player:ReduceEffectValueByKey("criticalHitEffect", 400)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._gugugu_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "gugugu", "Legend_GUGUGU", 1)
            if not _G.Moon_HasEffect(owner, "gugugu") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("absorbDamage", 42)
                    if owner._gugugu_dodged then
                        hh:ReduceEffectValueByKey("criticalHitRate", 100)
                        hh:ReduceEffectValueByKey("criticalHitEffect", 400)
                    end
                end
                if owner._gugugu_attacked_handler then
                    owner:RemoveEventCallback("attacked", owner._gugugu_attacked_handler)
                    owner._gugugu_attacked_handler = nil
                end
                if owner._gugugu_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._gugugu_attack_handler)
                    owner._gugugu_attack_handler = nil
                end
                if owner._gugugu_dodged_task then
                    owner._gugugu_dodged_task:Cancel()
                    owner._gugugu_dodged_task = nil
                end
                owner._gugugu_dodged = nil
                owner._gugugu_dodge_cooldown = nil
                owner._gugugu_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_GUGUGU", 0.01)
end)
