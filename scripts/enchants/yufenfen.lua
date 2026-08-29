-- 小月亮 附魔：雨纷纷
-- 锁定满雨露，无视雨露值带来的影响（扣san、手滑），限伤1%，无视地形，
-- 攻击结算时伤害减少1000%，不会吸引生物仇恨（如果攻击倍率≥3，改为嘲讽并失去限伤），
-- 受到即死效果时，消耗99%耐久免疫（不足99%或者无耐久则不生效）
-- 只能附魔在伞上（雨伞，暗影伞，花伞等）
-- “饥荒最忧郁之人”

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local TAUNT_MULT = 3      -- 攻击倍率≥3 时切换嘲讽模式（HH addComDamagePercent≥200）
local INSTA_NEED = 0.99   -- 即死免疫需要伞耐久≥99%
local INSTA_LEFT = 0.01   -- 消耗99%耐久后剩余1%

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_YUFENFEN", {
        name = "雨纷纷",
        client_text = "雨纷\n纷",
        desc = "满雨露+无视雨露影响(扣san/手滑)\n限伤1%+无视地形+攻击伤害-1000%\n不吸引仇恨(攻击倍率≥3嘲讽且失去限伤)\n受即死伤害消耗99%伞耐久免疫",
        check_desc = "饥荒最忧郁之人",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            local prefab = inst.prefab or ""
            if inst:HasTag("umbrella")
                or prefab:find("brella")
                or prefab:find("umbrella")
                or prefab:find("flower_hat")
                or prefab:find("flowerhat")
            then
                return true, "满足条件"
            end
            return false, "只能附魔在伞上(雨伞/草伞/眼球伞/暗影伞/花伞等)"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "yufenfen", "Legend_YUFENFEN", 1)
            if not owner._yufenfen_inited then
                owner._yufenfen_inited = true
                owner._yufenfen_taunt = false

                -- ============ 锁定满雨露 ============
                if owner.components.moisture then
                    owner.components.moisture:SetPercent(1)
                end
                owner._yufenfen_moisture_task = owner:DoPeriodicTask(1, function()
                    if owner.components.moisture then
                        owner.components.moisture:SetPercent(1)
                    end
                end)

                -- ============ 无视雨露影响：扣san / 手滑 ============
                -- 扣san：原版 sanity 潮湿惩罚开关（与 Wurt 同款）
                if owner.components.sanity then
                    owner._yufenfen_old_nmp = owner.components.sanity.no_moisture_penalty
                    owner.components.sanity.no_moisture_penalty = true
                end
                -- 手滑：原版湿滑脱手免疫 tag（与 Wurt 同款 stronggrip）
                if not owner:HasTag("stronggrip") then
                    owner:AddTag("stronggrip")
                    owner._yufenfen_own_stronggrip = true
                end

                -- ============ 无视地形（地形减速免疫 + 不触发陷阱） ============
                local loco = owner.components.locomotor
                if loco then
                    owner._yufenfen_old_groundmult = loco.groundspeedmultiplier
                    owner._yufenfen_old_groundenabled = loco.enablegroundspeedmultiplier
                    loco.groundspeedmultiplier = 1
                    loco.enablegroundspeedmultiplier = false
                end
                if not owner:HasTag("notraptrigger") then
                    owner:AddTag("notraptrigger")
                    owner._yufenfen_own_notrap = true
                end

                -- ============ 攻击伤害减少1000%（结算归零） ============
                local combat = owner.components.combat
                if combat and combat.CalcDamage then
                    owner._yufenfen_old_calcdamage = combat.CalcDamage
                    combat.CalcDamage = function(self, ...)
                        return 0
                    end
                end

                -- ============ 不吸引生物仇恨（默认模式） ============
                -- 原版：ShouldAggro 检查目标 stealth tag + 目标 combat.shouldavoidaggrofn
                if not owner:HasTag("stealth") then
                    owner:AddTag("stealth")
                    owner._yufenfen_own_stealth = true
                end
                if combat then
                    owner._yufenfen_old_avoidaggro = combat.shouldavoidaggrofn
                    combat.shouldavoidaggrofn = function() return true end
                end

                -- ============ 即死免疫：找伞耐久并消耗 ============
                local function findUmbrellaDurability()
                    local inv = owner.components.inventory
                    if not inv then return nil end
                    local item = inv:GetEquippedItem(EQUIPSLOTS.HEAD)
                    if not item then return nil end
                    local com
                    local get_pct, set_pct
                    if item.components.armor
                        and item.components.armor.maxcondition
                        and item.components.armor.maxcondition > 0
                        and item.components.armor.maxcondition < 99999999
                    then
                        com = item.components.armor
                        get_pct = function() return com.condition / com.maxcondition end
                        set_pct = function(p) com:SetCondition(com.maxcondition * p) end
                    elseif item.components.finiteuses and item.components.finiteuses.total and item.components.finiteuses.total > 0 then
                        com = item.components.finiteuses
                        get_pct = function() return com:GetUses() / com.total end
                        set_pct = function(p) com:SetUses(math.max(1, com.total * p)) end
                    elseif item.components.fueled and item.components.fueled.maximum then
                        com = item.components.fueled
                        get_pct = function() return com:GetPercent() end
                        set_pct = function(p) com:SetPercent(p) end
                    elseif item.components.perishable and item.components.perishable.perishtime then
                        com = item.components.perishable
                        get_pct = function() return com:GetPercent() end
                        set_pct = function(p) com:SetPercent(p) end
                    end
                    if not get_pct then return nil end
                    return get_pct, set_pct
                end

                local function tryImmuneInstantDeath()
                    local get_pct, set_pct = findUmbrellaDurability()
                    if not get_pct then return false end
                    if get_pct() < INSTA_NEED then return false end
                    set_pct(INSTA_LEFT)
                    return true
                end

                -- ============ 限伤1% + 即死免疫（health.DoDelta / DoHHDelta） ============
                local health = owner.components.health
                if health and not health._yufenfen_hooked then
                    local oldDoDelta = health.DoDelta
                    local oldDoHHDelta = health.DoHHDelta
                    health._yufenfen_old_dodelta = oldDoDelta
                    health._yufenfen_old_dohhdelta = oldDoHHDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and _G.Moon_HasEffect(owner, "yufenfen") and owner:IsValid() then
                            -- 限伤1%（嘲讽模式下失去限伤）
                            if not owner._yufenfen_taunt then
                                local damage = -delta
                                local max_hp = self.maxhealth or 100
                                local cap = max_hp * 0.01
                                if damage > cap then
                                    damage = cap
                                end
                                delta = -damage
                            end
                            -- 即死免疫：限伤后仍会致死 → 消耗99%伞耐久保命
                            if self.currenthealth + delta <= 0 then
                                if tryImmuneInstantDeath() then
                                    delta = -self.currenthealth + 1
                                end
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    if oldDoHHDelta then
                        health.DoHHDelta = function(self, amount, attacker, cause)
                            if amount < 0 and _G.Moon_HasEffect(owner, "yufenfen") and owner:IsValid() then
                                -- 真伤致死 → 即死免疫
                                if self.currenthealth + amount <= 0 then
                                    if tryImmuneInstantDeath() then
                                        amount = -self.currenthealth + 1
                                    end
                                end
                            end
                            return oldDoHHDelta(self, amount, attacker, cause)
                        end
                    end
                    health._yufenfen_hooked = true
                end

                -- ============ 嘲讽模式切换（攻击倍率≥3） ============
                owner._yufenfen_switchMode = function()
                    local hh = owner.components.hh_player
                    local pct = hh and hh.GetEffectValueByKey and hh:GetEffectValueByKey("addComDamagePercent") or 0
                    local mult = 1 + (pct or 0) / 100
                    local should_taunt = mult >= TAUNT_MULT
                    if should_taunt ~= owner._yufenfen_taunt then
                        owner._yufenfen_taunt = should_taunt
                        if should_taunt then
                            -- 嘲讽模式：移除隐身，恢复可被选为目标
                            if owner._yufenfen_own_stealth then
                                owner:RemoveTag("stealth")
                            end
                            if owner.components.combat then
                                owner.components.combat.shouldavoidaggrofn = nil
                            end
                        else
                            -- 咸鱼模式：不吸引仇恨
                            if owner._yufenfen_own_stealth and not owner:HasTag("stealth") then
                                owner:AddTag("stealth")
                            end
                            if owner.components.combat then
                                owner.components.combat.shouldavoidaggrofn = function() return true end
                            end
                        end
                    end
                end

                -- ============ 攻击：嘲讽模式下范围嘲讽 ============
                owner._yufenfen_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "yufenfen") then return end
                    if not owner._yufenfen_taunt then return end
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local ents = _G.TheSim:FindEntities(x, y, z, 8, { "_combat" })
                    for _, e in ipairs(ents) do
                        if e ~= owner and e:IsValid() and e.components.combat then
                            e.components.combat:SetTarget(owner)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._yufenfen_attack_handler)

                -- ============ 周期：模式切换 ============
                owner._yufenfen_mode_task = owner:DoPeriodicTask(1, owner._yufenfen_switchMode)
                owner._yufenfen_switchMode()
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yufenfen", "Legend_YUFENFEN", 1)
            if not _G.Moon_HasEffect(owner, "yufenfen") then
                -- 满雨露任务
                if owner._yufenfen_moisture_task then
                    owner._yufenfen_moisture_task:Cancel()
                    owner._yufenfen_moisture_task = nil
                end

                -- 扣san免疫
                if owner.components.sanity and owner._yufenfen_old_nmp ~= nil then
                    owner.components.sanity.no_moisture_penalty = owner._yufenfen_old_nmp
                    owner._yufenfen_old_nmp = nil
                end

                -- 手滑免疫
                if owner._yufenfen_own_stronggrip then
                    owner:RemoveTag("stronggrip")
                    owner._yufenfen_own_stronggrip = nil
                end

                -- 无视地形
                local loco = owner.components.locomotor
                if loco then
                    if owner._yufenfen_old_groundmult ~= nil then
                        loco.groundspeedmultiplier = owner._yufenfen_old_groundmult
                    end
                    if owner._yufenfen_old_groundenabled ~= nil then
                        loco.enablegroundspeedmultiplier = owner._yufenfen_old_groundenabled
                    end
                    owner._yufenfen_old_groundmult = nil
                    owner._yufenfen_old_groundenabled = nil
                end
                if owner._yufenfen_own_notrap then
                    owner:RemoveTag("notraptrigger")
                    owner._yufenfen_own_notrap = nil
                end

                -- 伤害归零
                local combat = owner.components.combat
                if combat and owner._yufenfen_old_calcdamage then
                    combat.CalcDamage = owner._yufenfen_old_calcdamage
                    owner._yufenfen_old_calcdamage = nil
                end

                -- 仇恨
                if combat then
                    if owner._yufenfen_old_avoidaggro ~= nil then
                        combat.shouldavoidaggrofn = owner._yufenfen_old_avoidaggro
                    else
                        combat.shouldavoidaggrofn = nil
                    end
                    owner._yufenfen_old_avoidaggro = nil
                end
                if owner._yufenfen_own_stealth then
                    owner:RemoveTag("stealth")
                    owner._yufenfen_own_stealth = nil
                end

                -- 攻击/模式任务
                if owner._yufenfen_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._yufenfen_attack_handler)
                    owner._yufenfen_attack_handler = nil
                end
                if owner._yufenfen_mode_task then
                    owner._yufenfen_mode_task:Cancel()
                    owner._yufenfen_mode_task = nil
                end

                -- health hooks
                local health = owner.components.health
                if health and health._yufenfen_hooked then
                    if health._yufenfen_old_dodelta then
                        health.DoDelta = health._yufenfen_old_dodelta
                        health._yufenfen_old_dodelta = nil
                    end
                    if health._yufenfen_old_dohhdelta then
                        health.DoHHDelta = health._yufenfen_old_dohhdelta
                        health._yufenfen_old_dohhdelta = nil
                    end
                    health._yufenfen_hooked = nil
                end

                owner._yufenfen_taunt = nil
                owner._yufenfen_inited = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YUFENFEN", 0.01)
end)
