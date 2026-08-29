-- 小月亮 附魔：小蝴蝶
-- 限伤10%、免疫反伤、脱手、免疫击飞、免疫中毒、免疫制裁
-- 小蝴蝶，飞啊飞啊飞～

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- ============================================================
-- 免疫击飞（本 mod 自实现，不依赖 HH 框架 immunityKnockBack key）：
-- hook 玩家 stategraph 的 knockback 事件，穿戴小蝴蝶时直接跳过
-- ============================================================
AddStategraphPostInit("wilson", function(sg)
    local knockback_event = sg.events and sg.events.knockback
    if knockback_event and knockback_event.fn then
        local old_knockback_fn = knockback_event.fn
        knockback_event.fn = function(inst, data)
            if inst and inst:IsValid() and _G.Moon_HasEffect(inst, "xiaohudie") then
                return
            end
            return old_knockback_fn(inst, data)
        end
    end
end)

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_XIAOHUDIE", {
        name = "小蝴蝶",
        client_text = "小蝴\n蝶",
        desc = "限伤10%+免疫反伤+脱手\n免疫击飞+免疫中毒+免疫制裁",
        check_desc = "小蝴蝶，飞啊飞啊飞～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "xiaohudie", "Legend_XIAOHUDIE", 1)
            if not owner._xiaohudie_hooked then
                owner._xiaohudie_hooked = true

                -- 免疫反伤（HH 框架 immuneBramble key 实测有效，保留 HH 方式）
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("immuneBramble", 1)
                end

                -- 脱手（免疫缴械）
                owner:AddTag("stronggrip")

                -- ==============================================
                -- 免疫中毒 + 免疫制裁（本 mod 自实现）
                -- 1) mob_enhance 怪的剧毒/毒雾/瘟疫按 moon_poison_immune tag 判断
                -- 2) HH 框架的毒("poison"/"turret_poison")与制裁
                --    ("player_healthSuppressNum") 都走 hh_buff:AddBuff，
                --    hook 掉 AddBuff 直接拦截；穿戴时清除已挂在身上的同类 buff
                -- ==============================================
                owner:AddTag("moon_poison_immune")

                local hh_buff = owner.components.hh_buff
                if hh_buff and hh_buff.AddBuff then
                    if hh_buff.HasBuff then
                        if hh_buff:HasBuff("poison") then
                            hh_buff:RemoveBuff("poison")
                        end
                        if hh_buff:HasBuff("turret_poison") then
                            hh_buff:RemoveBuff("turret_poison")
                        end
                        if hh_buff:HasBuff("player_healthSuppressNum") then
                            hh_buff:RemoveBuff("player_healthSuppressNum")
                        end
                    end
                    if not owner._xiaohudie_buff_hooked then
                        owner._xiaohudie_old_addbuff = hh_buff.AddBuff
                        hh_buff.AddBuff = function(self, buff_name, buff_time)
                            if _G.Moon_HasEffect(owner, "xiaohudie")
                                and type(buff_name) == "string"
                                and (buff_name:lower():find("poison")
                                    or buff_name == "player_healthSuppressNum")
                            then
                                return false
                            end
                            return owner._xiaohudie_old_addbuff(self, buff_name, buff_time)
                        end
                        owner._xiaohudie_buff_hooked = true
                    end
                end

                -- 限伤10% + 免疫中毒伤害兜底（cause 含 poison 的 DoT 直接免疫）
                local health = owner.components.health
                if health and not health._xiaohudie_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    health._xiaohudie_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and _G.Moon_HasEffect(owner, "xiaohudie") and owner:IsValid() then
                            -- 免疫中毒伤害（HH 毒 cause="hh_poison"、mob_enhance 毒 cause="mob_poison" 等）
                            if type(cause) == "string" and cause:lower():find("poison") then
                                return oldDoDelta(self, 0, overtime, cause, ...)
                            end
                            -- 限伤10%
                            local damage = -delta
                            local max_hp = owner.components.health.maxhealth or 150
                            local cap = max_hp * 0.10
                            if damage > cap then
                                damage = cap
                            end
                            return oldDoDelta(self, -damage, overtime, cause, ...)
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._xiaohudie_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "xiaohudie", "Legend_XIAOHUDIE", 1)
            if not _G.Moon_HasEffect(owner, "xiaohudie") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("immuneBramble", 1)
                end

                owner:RemoveTag("stronggrip")
                owner:RemoveTag("moon_poison_immune")

                -- 恢复 hh_buff:AddBuff
                local hh_buff = owner.components.hh_buff
                if hh_buff and owner._xiaohudie_old_addbuff then
                    hh_buff.AddBuff = owner._xiaohudie_old_addbuff
                    owner._xiaohudie_old_addbuff = nil
                    owner._xiaohudie_buff_hooked = nil
                end

                -- 恢复 health:DoDelta
                local health = owner.components.health
                if health and health._xiaohudie_old_dodelta then
                    health.DoDelta = health._xiaohudie_old_dodelta
                    health._xiaohudie_old_dodelta = nil
                    health._xiaohudie_hooked_dodelta = nil
                end

                owner._xiaohudie_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_XIAOHUDIE", 0.01)
end)
