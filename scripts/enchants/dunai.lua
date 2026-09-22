-- 小月亮 附魔：毒奶
-- 攻击伤害转换为1.5倍治疗效果（吃附魔与倍率加成）：
--   1) 攻击本身不造成伤害（CalcDamage 归零，HH 百分比乘区随之失效）
--   2) 命中时按"本来应造成的伤害×1.5"治疗目标
--   3) 治疗溢出（目标已满血）时，按溢出量降低目标血上限（最低保留1点）
-- 不影响队友（不对玩家生效）；坎普斯完全除外：打它照常造成伤害，不回血不降上限。
-- "错觉吗？为什么怪的血好像变多了？！ ——by：清欢渡"

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_DUNAI"
local EFFECT_KEY = "dunai"

local HEAL_MULT = 1.5         -- 伤害转治疗倍率
local MIN_MAX_HEALTH = 1      -- 血上限下限

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "毒奶",
        client_text = "毒奶",
        desc = "攻击伤害转为1.5倍治疗（吃附魔加成），治疗溢出时降低目标血上限\n你的攻击不再造成伤害",
        check_desc = "错觉吗？为什么怪的血好像变多了？！——by：清欢渡",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._dunai_hooked then
                owner._dunai_hooked = true

                -- 1) 攻击伤害归零：包 combat.CalcDamage
                local combat = owner.components.combat
                if combat and not combat._dunai_hooked_calc then
                    combat._dunai_hooked_calc = true
                    combat._dunai_old_calc = combat.CalcDamage
                    combat.CalcDamage = function(self, target, ...)
                        if _G.Moon_HasEffect(owner, EFFECT_KEY)
                                and (target == nil
                                    or (not target:HasTag("player") and target.prefab ~= "krampus")) then
                            return 0
                        end
                        return combat._dunai_old_calc(self, target, ...)
                    end
                end

                -- 2) 命中时治疗/降上限
                owner._dunai_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target:HasTag("player") then return end
                    if target.prefab == "krampus" then return end  -- 不奶坎普斯
                    local health = target.components.health
                    if not health or health:IsDead() then return end

                    -- 本来应造成的伤害：原始 CalcDamage + HH 加成公式
                    local combat2 = owner.components.combat
                    local dmg = 0
                    if combat2 and combat2._dunai_old_calc then
                        dmg = combat2._dunai_old_calc(combat2, target) or 0
                    end
                    local hh = owner.components.hh_player
                    if hh and hh.DoAttackDamage then
                        dmg = hh:DoAttackDamage(owner, target, dmg) or dmg
                    end
                    if dmg <= 0 then return end

                    local heal = dmg * HEAL_MULT
                    local cur = health.currenthealth or health.maxhealth
                    local max = health.maxhealth or cur

                    if cur < max then
                        -- 先补血
                        local used = math.min(max - cur, heal)
                        health:DoDelta(used, false, "dunai_heal")
                        heal = heal - used
                        cur = health.currenthealth or max
                    end
                    -- 溢出部分降血上限
                    if heal > 0 then
                        local newmax = math.max(MIN_MAX_HEALTH, max - heal)
                        if newmax < max then
                            health:SetMaxHealth(newmax)  -- 原版语义：当前血同时回满
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._dunai_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                local combat = owner.components.combat
                if combat and combat._dunai_hooked_calc then
                    combat.CalcDamage = combat._dunai_old_calc
                    combat._dunai_old_calc = nil
                    combat._dunai_hooked_calc = nil
                end
                if owner._dunai_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._dunai_attack_handler)
                    owner._dunai_attack_handler = nil
                end
                owner._dunai_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
