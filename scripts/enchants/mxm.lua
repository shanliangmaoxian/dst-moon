-- 小月亮 附魔：是萌新喵
-- 受到致命伤害时免疫死亡，保留1点生命并隐身3秒（冷却90秒）
-- 对生命值高于你的敌人造成+60%伤害
-- 每张地图首次攻击任意敌人时必定暴击（300%伤害）
-- 死亡不掉落任何物品

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_MXM", {
        name = "是萌新喵",
        client_text = "萌新\n喵",
        desc = "致命伤留1血+隐身3秒(冷却90秒)\n对高血量敌人+60%伤害，首击必暴300%",
        check_desc = "萌新保护条例！喵～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "mxm", "Legend_MXM", 1)
            if not owner._mxm_hooked then
                owner._mxm_hooked = true
                owner._mxm_death_cooldown = false
                owner._mxm_first_hit = {} -- 记录已首次攻击的敌人

                -- 致命伤害保护 (类似紫蝶，但保留1血+隐身)
                owner._mxm_old_push = owner.PushEvent
                owner.PushEvent = function(self, event, ...)
                    if _G.Moon_HasEffect(self, "mxm") and not self._mxm_death_cooldown then
                        if event == "death" then
                            local health = self.components.health
                            if health then
                                health:SetVal(1) -- 保留1点生命
                                self:PushEvent("respawnfromghost")
                                self._mxm_death_cooldown = true

                                -- 隐身3秒
                                self:Hide()
                                self._mxm_invisible = true
                                self:DoTaskInTime(3, function()
                                    if self:IsValid() then
                                        self:Show()
                                        self._mxm_invisible = false
                                    end
                                end)

                                -- 90秒冷却
                                if self._mxm_cooldown_task then
                                    self._mxm_cooldown_task:Cancel()
                                end
                                self._mxm_cooldown_task = self:DoTaskInTime(90, function()
                                    self._mxm_death_cooldown = false
                                end)

                                if self.components.talker then
                                    self.components.talker:Say("喵！萌新才不会死呢！")
                                end
                                return
                            end
                        end
                        if event == "makeplayerghost" then
                            return
                        end
                    end
                    return self._mxm_old_push(self, event, ...)
                end

                -- 死亡不掉落物品
                if not owner:HasTag("keepinventory") then
                    owner:AddTag("keepinventory") -- DST内置标签，死亡不掉落
                    owner._mxm_added_keeptag = true
                end

                -- 攻击时检查：首次攻击+生命值对比
                owner._mxm_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "mxm") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    local target_id = target.GUID or 0

                    -- 首次攻击必暴击 300%
                    if not owner._mxm_first_hit[target_id] then
                        owner._mxm_first_hit[target_id] = true
                        local hh = owner.components.hh_player
                        if hh then
                            hh:AddEffectValueByKey("criticalHitRate", 100)
                            hh:AddEffectValueByKey("criticalHitEffect", 200) -- 额外200% = 总共300%
                            owner:DoTaskInTime(0.2, function()
                                if owner:IsValid() and owner.components.hh_player then
                                    owner.components.hh_player:ReduceEffectValueByKey("criticalHitRate", 100)
                                    owner.components.hh_player:ReduceEffectValueByKey("criticalHitEffect", 200)
                                end
                            end)
                        end
                    end

                    -- 对高血量敌人+60%伤害
                    if target.components.health then
                        local owner_hp_pct = owner.components.health and owner.components.health:GetPercent() or 1
                        local target_hp_pct = target.components.health:GetPercent() or 0
                        if target_hp_pct > owner_hp_pct then
                            local hh = owner.components.hh_player
                            if hh then
                                hh:AddEffectValueByKey("addComDamagePercent", 60)
                                owner:DoTaskInTime(0.2, function()
                                    if owner:IsValid() and owner.components.hh_player then
                                        owner.components.hh_player:ReduceEffectValueByKey("addComDamagePercent", 60)
                                    end
                                end)
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._mxm_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "mxm", "Legend_MXM", 1)
            if not _G.Moon_HasEffect(owner, "mxm") then
                -- 恢复原始 PushEvent
                if owner._mxm_old_push then
                    owner.PushEvent = owner._mxm_old_push
                    owner._mxm_old_push = nil
                end
                if owner._mxm_death_cooldown_task then
                    owner._mxm_death_cooldown_task:Cancel()
                    owner._mxm_death_cooldown_task = nil
                end
                if owner._mxm_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._mxm_attack_handler)
                    owner._mxm_attack_handler = nil
                end
                -- 恢复隐身
                if owner._mxm_invisible then
                    owner:Show()
                    owner._mxm_invisible = false
                end
                -- 移除不掉落标签
                if owner._mxm_added_keeptag and owner:HasTag("keepinventory") then
                    owner:RemoveTag("keepinventory")
                    owner._mxm_added_keeptag = nil
                end
                owner._mxm_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_MXM", 0.01)
end)
