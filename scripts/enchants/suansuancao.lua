-- 小月亮 附魔：酸酸草
-- 酸蚀叠层体系 — 对单越打越疼，吃酸味食物进入爆发期
--
-- 攻击叠「牙酸」减防（30%→35%→40%），3层满额外每秒酸性伤害
-- 食用酸味食物：回复量3倍 + 加速25% 12秒
-- 加速期间：攻击附加2%最大生命酸性伤害（每3秒一次）
-- 吃食物后下一次攻击必叠2层

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_SUANSUANCAO", {
        name = "酸酸草",
        client_text = "酸酸\n草",
        desc = "攻击叠酸蚀减防，3层额外酸性伤害\n吃酸味食物回复×3+加速25%\n攻击附带2%真伤",
        check_desc = "越打越酸，越酸越疼！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "suansuancao", "Legend_SUANSUANCAO", 1)
            if not owner._suansuancao_hooked then
                owner._suansuancao_hooked = true
                owner._suansuancao_stacks = 0           -- 酸蚀层数 0~3
                owner._suansuancao_last_target = nil     -- 上一个攻击目标
                owner._suansuancao_speed_active = false  -- 加速是否激活
                owner._suansuancao_next_double = false   -- 下次攻击是否叠2层（吃食物触发）
                owner._suansuancao_maxhp_cd = 0          -- 2%最大生命伤害CD计时

                -- 获取当前层的受伤倍率
                local function getStackMultiplier(stacks)
                    if stacks >= 3 then return 1.67 end  -- 减防40%
                    if stacks >= 2 then return 1.54 end  -- 减防35%
                    if stacks >= 1 then return 1.43 end  -- 减防30%
                    return 1.25                           -- 默认（保留fallback）
                end

                -- 应用/刷新目标身上的减防
                local function applyDefReduction(target, stacks)
                    if not target or not target:IsValid() or not target.components.combat then return end
                    if not target.components.combat.externaldamagetakenmultipliers then return end
                    if stacks > 0 then
                        local mult = getStackMultiplier(stacks)
                        target.components.combat.externaldamagetakenmultipliers:SetModifier("suansuancao", mult)
                    else
                        target.components.combat.externaldamagetakenmultipliers:RemoveModifier("suansuancao")
                    end
                end

                -- 重置酸蚀计时器
                local function resetDecayTimer()
                    if owner._suansuancao_decay_task then
                        owner._suansuancao_decay_task:Cancel()
                    end
                    owner._suansuancao_decay_task = owner:DoTaskInTime(8, function()
                        if not owner:IsValid() then return end
                        -- 层数归零
                        if owner._suansuancao_last_target and owner._suansuancao_last_target:IsValid() then
                            applyDefReduction(owner._suansuancao_last_target, 0)
                        end
                        owner._suansuancao_stacks = 0
                        owner._suansuancao_last_target = nil
                        owner._suansuancao_next_double = false
                    end)
                end

                -- 酸性伤害（持久定时器，内部判断是否3层，避免反复取消重建）
                if not owner._suansuancao_acid_task then
                    owner._suansuancao_acid_task = owner:DoPeriodicTask(1, function()
                        if not owner:IsValid() then return end
                        if not _G.Moon_HasEffect(owner, "suansuancao") then return end
                        if (owner._suansuancao_stacks or 0) < 3 then return end
                        local target = owner._suansuancao_last_target
                        if not target or not target:IsValid() or not target.components.health
                            or target.components.health:IsDead() then return end
                        local dmg = (owner.components.combat and owner.components.combat.defaultdamage) or 34
                        local acid_dmg = dmg * 0.1
                        if target.components.health.DoHHDelta then
                            target.components.health:DoHHDelta(-acid_dmg, owner, "suansuancao_acid")
                        else
                            target.components.health:DoDelta(-acid_dmg, false, "suansuancao_acid")
                        end
                    end)
                end

                -- 攻击处理
                owner._suansuancao_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "suansuancao") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() or not target.components.health then return end

                    -- 检查是否切换目标
                    if owner._suansuancao_last_target and owner._suansuancao_last_target ~= target then
                        -- 清除旧目标的减防
                        applyDefReduction(owner._suansuancao_last_target, 0)
                        owner._suansuancao_stacks = 0
                        owner._suansuancao_next_double = false
                    end

                    owner._suansuancao_last_target = target

                    -- 叠层
                    local gain = owner._suansuancao_next_double and 2 or 1
                    owner._suansuancao_next_double = false
                    owner._suansuancao_stacks = math.min(3, owner._suansuancao_stacks + gain)

                    -- 应用减防
                    applyDefReduction(target, owner._suansuancao_stacks)

                    -- 重置衰减计时
                    resetDecayTimer()

                    -- 飘字
                    if owner._suansuancao_stacks >= 3 and owner.components.talker then
                        owner.components.talker:Say("酸蚀满层！")
                    end

                    -- 加速期间：2%最大生命酸性伤害（每3秒一次）
                    if owner._suansuancao_speed_active then
                        local now = _G.GetTime and _G.GetTime() or 0
                        if now - owner._suansuancao_maxhp_cd >= 3 then
                            owner._suansuancao_maxhp_cd = now
                            local max_hp = target.components.health.maxhealth or 100
                            local bonus = max_hp * 0.02
                            if target.components.health.DoHHDelta then
                                target.components.health:DoHHDelta(-bonus, owner, "suansuancao_maxhp")
                            else
                                target.components.health:DoDelta(-bonus, false, "suansuancao_maxhp")
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._suansuancao_attack_handler)

                -- 食用酸味食物
                owner._suansuancao_eat_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "suansuancao") then return end
                    local food = data and data.food
                    if not food then return end
                    local prefab = food.prefab or ""

                    -- 判断酸味食物
                    if prefab:find("berry") or prefab:find("berries") or prefab:find("pomegranate")
                        or prefab:find("tomato") or prefab:find("citrus") or prefab:find("lemon") then

                        -- 回复量×3（额外补2倍）
                        if food.components.edible then
                            local h = food.components.edible:GetHealth(owner) or 0
                            local s = food.components.edible:GetSanity(owner) or 0
                            local hu = food.components.edible:GetHunger(owner) or 0
                            if h > 0 and owner.components.health then owner.components.health:DoDelta(h * 2, false, "suansuancao") end
                            if s > 0 and owner.components.sanity then owner.components.sanity:DoDelta(s * 2, false, "suansuancao") end
                            if hu > 0 and owner.components.hunger then owner.components.hunger:DoDelta(hu * 2, false, "suansuancao") end
                        end

                        -- 12秒加速25% + 标记下次攻击叠2层
                        local hh = owner.components.hh_player
                        if hh then
                            if not owner._suansuancao_speed_active then
                                owner._suansuancao_speed_active = true
                                hh:AddEffectValueByKey("addSpeedPercent", 25)
                            end
                            if owner._suansuancao_speed_task then
                                owner._suansuancao_speed_task:Cancel()
                            end
                            owner._suansuancao_speed_task = owner:DoTaskInTime(12, function()
                                if owner:IsValid() then
                                    owner._suansuancao_speed_active = false
                                    owner._suansuancao_speed_task = nil
                                    if owner.components.hh_player then
                                        owner.components.hh_player:ReduceEffectValueByKey("addSpeedPercent", 25)
                                    end
                                end
                            end)
                        end

                        -- 下次攻击必叠2层
                        owner._suansuancao_next_double = true

                        if owner.components.talker then
                            owner.components.talker:Say("好酸！越战越勇！")
                        end
                    end
                end
                owner:ListenForEvent("oneat", owner._suansuancao_eat_handler)

                -- 玩家死亡时清理状态
                owner:ListenForEvent("death", function()
                    if not owner:IsValid() then return end
                    if owner._suansuancao_last_target and owner._suansuancao_last_target:IsValid() then
                        applyDefReduction(owner._suansuancao_last_target, 0)
                    end
                    owner._suansuancao_stacks = 0
                    owner._suansuancao_last_target = nil
                    if owner._suansuancao_acid_task then
                        owner._suansuancao_acid_task:Cancel()
                        owner._suansuancao_acid_task = nil
                    end
                    if owner._suansuancao_decay_task then
                        owner._suansuancao_decay_task:Cancel()
                        owner._suansuancao_decay_task = nil
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "suansuancao", "Legend_SUANSUANCAO", 1)
            if not _G.Moon_HasEffect(owner, "suansuancao") then
                -- 清除目标减防
                if owner._suansuancao_last_target and owner._suansuancao_last_target:IsValid()
                    and owner._suansuancao_last_target.components.combat
                    and owner._suansuancao_last_target.components.combat.externaldamagetakenmultipliers then
                    owner._suansuancao_last_target.components.combat.externaldamagetakenmultipliers:RemoveModifier("suansuancao")
                end
                -- 移除事件回调
                if owner._suansuancao_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._suansuancao_attack_handler)
                    owner._suansuancao_attack_handler = nil
                end
                if owner._suansuancao_eat_handler then
                    owner:RemoveEventCallback("oneat", owner._suansuancao_eat_handler)
                    owner._suansuancao_eat_handler = nil
                end
                -- 取消所有定时器
                if owner._suansuancao_decay_task then
                    owner._suansuancao_decay_task:Cancel()
                    owner._suansuancao_decay_task = nil
                end
                if owner._suansuancao_acid_task then
                    owner._suansuancao_acid_task:Cancel()
                    owner._suansuancao_acid_task = nil
                end
                if owner._suansuancao_speed_task then
                    owner._suansuancao_speed_task:Cancel()
                    owner._suansuancao_speed_task = nil
                end
                -- 移除加速
                if owner._suansuancao_speed_active then
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 25)
                    end
                    owner._suansuancao_speed_active = false
                end
                owner._suansuancao_stacks = nil
                owner._suansuancao_last_target = nil
                owner._suansuancao_hooked = nil
                owner._suansuancao_next_double = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_SUANSUANCAO", 0.01)
end)
