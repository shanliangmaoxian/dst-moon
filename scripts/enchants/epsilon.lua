-- 小月亮 附魔：伊普西隆 (Epsilon)
-- 数学概念「极限累积」
-- 每次攻击叠加 1 层印记（上限 5 层）
-- 每层印记：本次攻击额外造成目标当前生命值 0.5% 的真实伤害
-- 5 层满：下一次攻击造成目标最大生命值 3% 的真实伤害，随后清空印记
-- 结算时序：先叠层再结算 —— 第1击 0.5%、第2击 1.0%…第5击 2.5% 叠满，第6击爆发 3% 最大生命并清空

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_EPSILON", {
        name = "伊普西隆",
        client_text = "伊普\n西隆",
        desc = "极限累积\n每次攻击叠加1层印记(上限5层)\n每层:本次攻击额外造成目标当前生命值0.5%%的真实伤害\n5层满:下一次攻击造成目标最大生命值3%%的真实伤害,随后清空印记",
        check_desc = "极限累积，层数越高伤害越高！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "epsilon", "Legend_EPSILON", 1)
            if not owner._epsilon_hooked then
                owner._epsilon_hooked = true
                owner._epsilon_stacks = 0

                -- 攻击时结算印记层数
                owner._epsilon_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "epsilon") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if not target.components.health or target.components.health:IsDead() then return end

                    local health = target.components.health
                    local max_hp = health.maxhealth or 100
                    local cur_hp = health.currenthealth or max_hp

                    local stacks = owner._epsilon_stacks or 0
                    if stacks >= 5 then
                        -- 满层爆发：目标最大生命值 3% 真实伤害，随后清空印记
                        local burst_dmg = max_hp * 0.03
                        if health.DoHHDelta then
                            health:DoHHDelta(-burst_dmg, owner, nil)
                        else
                            health:DoDelta(-burst_dmg, false, nil)
                        end
                        owner._epsilon_stacks = 0
                    else
                        -- 先叠层再结算：本次攻击造成 层数 × 0.5% 当前生命值真实伤害
                        stacks = stacks + 1
                        owner._epsilon_stacks = stacks
                        local dmg = cur_hp * 0.005 * stacks
                        if dmg > 0 then
                            if health.DoHHDelta then
                                health:DoHHDelta(-dmg, owner, nil)
                            else
                                health:DoDelta(-dmg, false, nil)
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._epsilon_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "epsilon", "Legend_EPSILON", 1)
            if not _G.Moon_HasEffect(owner, "epsilon") then
                if owner._epsilon_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._epsilon_attack_handler)
                    owner._epsilon_attack_handler = nil
                end
                owner._epsilon_stacks = nil
                owner._epsilon_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_EPSILON", 0.01)
end)
