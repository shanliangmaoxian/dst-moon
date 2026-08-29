-- 小月亮 附魔：无欲无求
-- 2秒不做动作即入禅定：每秒回复5%三维，减伤80%，免疫仇恨
-- 移动或攻击后解除，需重新站立2秒触发

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_WYWQ", {
        name = "无欲无求",
        client_text = "无欲\n无求",
        desc = "2秒不做动作即入禅定\n每秒回5%三维 减伤80% 免疫仇恨",
        check_desc = "无欲则刚，无求则安～\n站立2秒不动自动触发",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "wywq", "Legend_WYWQ", 1)
            if not owner._wywq_inited then
                owner._wywq_inited = true
                owner._wywq_meditating = false
                owner._wywq_idle_time = 0
                owner._wywq_last_pos = nil

                -- 禅定启动
                local function startMeditation()
                    if owner._wywq_meditating then return end
                    owner._wywq_meditating = true

                    -- 减伤80% 通过 combat 外部修正
                    if owner.components.combat then
                        if not owner.components.combat.externaldamagetakenmultipliers then
                            -- 确保表存在
                            owner.components.combat.externaldamagetakenmultipliers = {}
                        end
                        owner.components.combat.externaldamagetakenmultipliers:SetModifier(nil, 0.2)
                    end

                    -- 移除仇恨标签
                    if owner.components.combat then
                        owner._wywq_old_target = owner.components.combat.target
                        owner.components.combat:SetTarget(nil)
                        owner.components.combat:GiveUp()
                    end

                    -- 每1秒回复8%三维
                    if owner.components.health and owner.components.sanity and owner.components.hunger then
                        owner._wywq_regen_task = owner:DoPeriodicTask(1, function()
                            if not _G.Moon_HasEffect(owner, "wywq") then return end
                            if not owner._wywq_meditating then
                                if owner._wywq_regen_task then
                                    owner._wywq_regen_task:Cancel()
                                    owner._wywq_regen_task = nil
                                end
                                return
                            end
                            local max_hp = owner.components.health.maxhealth or 150
                            local max_san = owner.components.sanity.max or 200
                            local max_hunger = owner.components.hunger.max or 150
                            if owner.components.health:GetPercent() < 1 then
                                owner.components.health:DoDelta(max_hp * 0.05, false, nil)
                            end
                            owner.components.sanity:DoDelta(max_san * 0.05)
                            owner.components.hunger:DoDelta(max_hunger * 0.05)
                        end)
                    end

                    -- 屏幕提示
                    if owner.components.talker then
                        owner.components.talker:Say("无欲则刚～")
                    end
                end

                -- 禅定结束
                local function stopMeditation()
                    if not owner._wywq_meditating then return end
                    owner._wywq_meditating = false
                    owner._wywq_idle_time = 0

                    -- 移除减伤
                    if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                        owner.components.combat.externaldamagetakenmultipliers:RemoveModifier(nil)
                    end

                    -- 停止回血
                    if owner._wywq_regen_task then
                        owner._wywq_regen_task:Cancel()
                        owner._wywq_regen_task = nil
                    end
                end

                -- 每1秒检测是否处于空闲状态
                owner._wywq_idle_task = owner:DoPeriodicTask(1, function()
                    if not _G.Moon_HasEffect(owner, "wywq") then return end

                    local x, y, z = owner.Transform:GetWorldPosition()
                    local moving = false

                    if owner._wywq_last_pos then
                        local dx = x - owner._wywq_last_pos[1]
                        local dz = z - owner._wywq_last_pos[3]
                        if dx * dx + dz * dz > 0.01 then
                            moving = true
                        end
                    end

                    -- 检查是否在战斗/工作
                    local busy = false
                    if owner.sg then
                        -- 检查状态标签：攻击、工作、施法等
                        if owner.sg:HasStateTag("busy") or owner.sg:HasStateTag("attacking") or
                           owner.sg:HasStateTag("working") or owner.sg:HasStateTag("channeling") then
                            busy = true
                        end
                    end
                    if owner.components.combat and owner.components.combat.target then
                        busy = true
                    end

                    if moving or busy then
                        stopMeditation()
                    else
                        owner._wywq_idle_time = (owner._wywq_idle_time or 0) + 1
                        if owner._wywq_idle_time >= 2 and not owner._wywq_meditating then
                            startMeditation()
                        end
                    end

                    owner._wywq_last_pos = { x, y, z }
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "wywq", "Legend_WYWQ", 1)
            if not _G.Moon_HasEffect(owner, "wywq") then
                if owner._wywq_idle_task then
                    owner._wywq_idle_task:Cancel()
                    owner._wywq_idle_task = nil
                end
                if owner._wywq_regen_task then
                    owner._wywq_regen_task:Cancel()
                    owner._wywq_regen_task = nil
                end
                if owner._wywq_meditating then
                    if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                        owner.components.combat.externaldamagetakenmultipliers:RemoveModifier(nil)
                    end
                end
                owner._wywq_meditating = false
                owner._wywq_idle_time = 0
                owner._wywq_last_pos = nil
                owner._wywq_inited = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_WYWQ", 0.01)
end)
