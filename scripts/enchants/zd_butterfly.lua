-- 小月亮 附魔：紫蝶
-- 致命伤害时免疫死亡，满血复活，进入「蝶变」状态15秒（+50%伤害、+30%移速、无敌）
-- 冷却300秒（半天）。冷却期间被动+10%移速

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_ZD_BUTTERFLY", {
        name = "紫蝶",
        client_text = "紫\n蝶",
        desc = "致命伤害时免死满血复活\n进入蝶变状态15秒(+50%伤害+30%移速无敌)\n冷却300秒(半天)",
        check_desc = "紫蝶护主，破茧重生！\n冷却期间被动+10%移速",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "zd_butterfly", "Legend_ZD_BUTTERFLY", 1)

            if not owner._zd_death_hook_installed then
                owner._zd_death_hook_installed = true
                owner._zd_revive_cooldown = false
                owner._zd_had_butterfly = true -- 标记曾经拥有过紫蝶(用于冷却期移速)

                -- 冷却期间被动+10%移速
                local function applyPassiveSpeed()
                    local hh = owner.components.hh_player
                    if hh then
                        hh:AddEffectValueByKey("addSpeedPercent", 10)
                        owner._zd_speed_applied = true
                    end
                end

                local function removePassiveSpeed()
                    if owner._zd_speed_applied then
                        local hh = owner.components.hh_player
                        if hh then
                            hh:ReduceEffectValueByKey("addSpeedPercent", 10)
                        end
                        owner._zd_speed_applied = false
                    end
                end

                -- 蝶变状态
                local function applyButterflyBurst()
                    local hh = owner.components.hh_player
                    if hh then
                        hh:AddEffectValueByKey("addComDamagePercent", 50)
                        hh:AddEffectValueByKey("addSpeedPercent", 30)
                    end
                    -- 无敌
                    if owner.components.health then
                        if not owner._zd_burst_dodelta then
                            local oldDoDelta = owner.components.health.DoDelta
                            owner._zd_burst_dodelta = oldDoDelta
                            owner.components.health.DoDelta = function(self, delta, ...)
                                if owner._zd_in_burst and delta < 0 then
                                    return -- 蝶变期间免疫伤害
                                end
                                return oldDoDelta(self, delta, ...)
                            end
                        end
                    end
                    owner._zd_in_burst = true
                end

                owner._zd_removeBurst = function()
                    if not owner._zd_in_burst then return end
                    owner._zd_in_burst = false
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("addComDamagePercent", 50)
                        hh:ReduceEffectValueByKey("addSpeedPercent", 30)
                    end
                    -- 恢复 DoDelta
                    if owner._zd_burst_dodelta and owner.components.health then
                        owner.components.health.DoDelta = owner._zd_burst_dodelta
                        owner._zd_burst_dodelta = nil
                    end
                end

                -- 冷却计时器任务
                local function startCooldown()
                    owner._zd_revive_cooldown = true
                    -- 冷却期被动移速
                    if _G.Moon_HasEffect(owner, "zd_butterfly") then
                        applyPassiveSpeed()
                    end
                    if owner._zd_cooldown_task then
                        owner._zd_cooldown_task:Cancel()
                    end
                    -- 半天(300秒)冷却
                    owner._zd_cooldown_task = owner:DoTaskInTime(300, function()
                        owner._zd_revive_cooldown = false
                        removePassiveSpeed()
                    end)
                end

                -- 初始检测：如果是后来装备的，检查是否在冷却中
                -- 如果 _zd_revive_cooldown 为 true，说明之前复活过，在冷却中
                if owner._zd_revive_cooldown then
                    applyPassiveSpeed()
                end

                local oldPushEvent = owner.PushEvent
                owner.PushEvent = function(self, event, ...)
                    if _G.Moon_HasEffect(self, "zd_butterfly") and not self._zd_revive_cooldown then
                        if event == "death" then
                            local health = self.components.health
                            if health then
                                -- 满血复活
                                health:SetVal(health.maxhealth)
                                self:PushEvent("respawnfromghost")

                                -- 进入蝶变状态
                                applyButterflyBurst()

                                -- 15秒后退出蝶变
                                if self._zd_burst_task then
                                    self._zd_burst_task:Cancel()
                                end
                                self._zd_burst_task = self:DoTaskInTime(15, function()
                                    owner._zd_removeBurst()
                                end)

                                -- 开始冷却
                                startCooldown()

                                if self.components.talker then
                                    self.components.talker:Say("紫蝶护主，破茧重生！")
                                end
                                return
                            end
                        end
                        if event == "makeplayerghost" then
                            return
                        end
                    end
                    return oldPushEvent(self, event, ...)
                end
            else
                -- 重新装备：如果在冷却中，应用被动移速
                if owner._zd_revive_cooldown and _G.Moon_HasEffect(owner, "zd_butterfly") then
                    if not owner._zd_speed_applied then
                        local hh = owner.components.hh_player
                        if hh then
                            hh:AddEffectValueByKey("addSpeedPercent", 10)
                            owner._zd_speed_applied = true
                        end
                    end
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "zd_butterfly", "Legend_ZD_BUTTERFLY", 1)
            if not _G.Moon_HasEffect(owner, "zd_butterfly") then
                -- 移除蝶变状态（如果还在）
                if owner._zd_in_burst then
                    owner._zd_removeBurst()
                    if owner._zd_burst_task then
                        owner._zd_burst_task:Cancel()
                        owner._zd_burst_task = nil
                    end
                end
                -- 移除被动移速
                if owner._zd_speed_applied then
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 10)
                    end
                    owner._zd_speed_applied = false
                end
            end
        end,
    })

    -- 精英/Boss 掉落 (3%)
    _G.Moon_RegisterEnchantDrop("Legend_ZD_BUTTERFLY", 0.01)
end)
