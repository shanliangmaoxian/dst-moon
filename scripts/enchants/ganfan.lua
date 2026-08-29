-- 小月亮 附魔：干饭人
-- 进食速度+200%。每吃一个食物叠一层「干劲」：+8%伤害+5%移速，持续30秒（最多8层）
-- 8层满后再吃食物触发「干饭冲击波」：对周围6码敌人造成250%范围伤害并消耗4层

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_GANFAN", {
        name = "干饭人",
        client_text = "干\n饭",
        desc = "进食速度+200%，吃食物叠干劲+8%伤害+5%移速(最多8层)\n满层触发冲击波250%AoE",
        check_desc = "干饭不积极，思想有问题！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "ganfan", "Legend_GANFAN", 1)
            if not owner._ganfan_hooked then
                owner._ganfan_hooked = true
                owner._ganfan_stacks = 0

                -- 进食速度+200%
                if owner.components.eater then
                    owner._ganfan_old_eatspeed = owner.components.eater.eatingspeed or 1
                    owner.components.eater.eatingspeed = owner._ganfan_old_eatspeed * 3
                end

                -- 吃食物时触发
                owner._ganfan_eat_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "ganfan") then return end
                    local food = data and data.food
                    if not food then return end

                    -- 8层满 → 触发冲击波
                    if owner._ganfan_stacks >= 8 then
                        -- 冲击波
                        local x, y, z = owner.Transform:GetWorldPosition()
                        local nearby = GLOBAL.TheSim:FindEntities(x, y, z, 6, { "_combat" })
                        for _, victim in ipairs(nearby) do
                            if victim ~= owner and victim.components.health
                                and not victim.components.health:IsDead() then
                                local dmg = (owner.components.combat and owner.components.combat.defaultdamage) or 34
                                victim.components.health:DoDelta(-dmg * 2.5, false, nil)
                            end
                        end

                        -- 特效
                        if GLOBAL.SpawnPrefab then
                            local fx = GLOBAL.SpawnPrefab("collapse_small")
                            if fx then
                                fx.Transform:SetPosition(x, y, z)
                                fx.Transform:SetScale(1.8, 1.8, 1.8)
                            end
                        end

                        if owner.components.talker then
                            owner.components.talker:Say("干饭冲击波！")
                        end

                        -- 消耗4层
                        local old_stacks = owner._ganfan_stacks
                        owner._ganfan_stacks = math.max(0, old_stacks - 4)
                        -- 移除消耗层数的buff
                        local hh = owner.components.hh_player
                        if hh then
                            hh:ReduceEffectValueByKey("addComDamagePercent", old_stacks * 8)
                            hh:ReduceEffectValueByKey("addSpeedPercent", old_stacks * 5)
                            hh:AddEffectValueByKey("addComDamagePercent", owner._ganfan_stacks * 8)
                            hh:AddEffectValueByKey("addSpeedPercent", owner._ganfan_stacks * 5)
                        end
                    else
                        -- 正常叠层
                        local old_stacks = owner._ganfan_stacks
                        owner._ganfan_stacks = math.min(8, old_stacks + 1)
                        local hh = owner.components.hh_player
                        if hh then
                            hh:ReduceEffectValueByKey("addComDamagePercent", old_stacks * 8)
                            hh:ReduceEffectValueByKey("addSpeedPercent", old_stacks * 5)
                            hh:AddEffectValueByKey("addComDamagePercent", owner._ganfan_stacks * 8)
                            hh:AddEffectValueByKey("addSpeedPercent", owner._ganfan_stacks * 5)
                        end
                        -- 飘字提示
                        if owner.components.talker then
                            if owner._ganfan_stacks >= 8 then
                                owner.components.talker:Say("干劲拉满！")
                            else
                                owner.components.talker:Say("干劲 x" .. owner._ganfan_stacks .. "!")
                            end
                        end
                    end

                    -- 重置30秒计时器（满层不清零）
                    if owner._ganfan_decay_task then
                        owner._ganfan_decay_task:Cancel()
                    end
                    owner._ganfan_decay_task = owner:DoTaskInTime(30, function()
                        if owner:IsValid() then
                            local old = owner._ganfan_stacks or 0
                            owner._ganfan_stacks = 0
                            local hh = owner.components.hh_player
                            if hh then
                                hh:ReduceEffectValueByKey("addComDamagePercent", old * 8)
                                hh:ReduceEffectValueByKey("addSpeedPercent", old * 5)
                            end
                        end
                    end)
                end
                owner:ListenForEvent("oneat", owner._ganfan_eat_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "ganfan", "Legend_GANFAN", 1)
            if not _G.Moon_HasEffect(owner, "ganfan") then
                -- 恢复进食速度
                if owner.components.eater and owner._ganfan_old_eatspeed then
                    owner.components.eater.eatingspeed = owner._ganfan_old_eatspeed
                    owner._ganfan_old_eatspeed = nil
                end
                -- 移除所有层数
                local old = owner._ganfan_stacks or 0
                owner._ganfan_stacks = 0
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addComDamagePercent", old * 8)
                    hh:ReduceEffectValueByKey("addSpeedPercent", old * 5)
                end
                -- 取消计时器
                if owner._ganfan_decay_task then
                    owner._ganfan_decay_task:Cancel()
                    owner._ganfan_decay_task = nil
                end
                if owner._ganfan_eat_handler then
                    owner:RemoveEventCallback("oneat", owner._ganfan_eat_handler)
                    owner._ganfan_eat_handler = nil
                end
                owner._ganfan_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_GANFAN", 0.01)
end)
