-- 小月亮 附魔：孑身处处静
-- 附近 30 码内没有其他玩家时生效：
--   1) 免疫过冷过热 + 每 5 秒回复 1-5 点生命与精神
--   2) 受击自动触发 85% 高额减伤 + 霸体，持续 5 秒，60 秒冷却
--   3) 免疫沙尘暴减速
-- 套装：同时拥有「余灯照夜明」时，周围有玩家也照常生效
-- 空庭水月定，连山接无垠。孑身处处静，余灯照夜明。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- ---------------------------------------------------------------
-- 参数
-- ---------------------------------------------------------------
local SOLO_RANGE_SQ     = 900   -- 30 码（判定用平方距离，省一次开方）
local REFRESH_INTERVAL  = 2     -- 生效判定刷新间隔(秒)：玩家走动时人数变化要跟得上
local REGEN_INTERVAL    = 5     -- 回复间隔(秒)
local REGEN_MIN         = 1     -- 单次回血/回神下限
local REGEN_MAX         = 5     -- 单次回血/回神上限
local GUARD_REDUCE      = 0.85  -- 高额减伤：只吃 15% 伤害
local GUARD_DURATION    = 5     -- 护佑持续(秒)
local GUARD_CD          = 60    -- 护佑冷却(秒)

local EFFECT_ID = "Legend_JIESHEN"

-- ============================================================
-- 免疫沙尘暴减速
-- 沙尘暴本身不给玩家挂任何 debuff，只通过 locomotor 的外部速度倍率
-- "sandstorm" 生效（见原版 sandstormwatcher:UpdateSandstormWalkSpeed_Internal）。
-- 这里包一层：生效期间直接把该倍率撤掉，原版逻辑照旧跑（它自己会判
-- sandstormspeedmult < 1 才动手，撤掉后是幂等的，重复调用无副作用）。
-- 组件级 hook 只包一次，实例级判断放在闭包里，避免每个玩家重复包。
-- ============================================================
AddComponentPostInit("sandstormwatcher", function(self)
    local old_update = self.UpdateSandstormWalkSpeed_Internal
    self.UpdateSandstormWalkSpeed_Internal = function(s, level)
        local inst = s.inst
        if inst ~= nil
            and inst:IsValid()
            and inst._jieshen_active
            and _G.Moon_HasEffect(inst, "jieshen")
            and inst.components.locomotor ~= nil
        then
            inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "sandstorm")
            return
        end
        return old_update(s, level)
    end
end)

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "孑身处处静",
        client_text = "孑身\n处静",
        desc = "周围30码内无其他玩家时:\n免疫过冷过热,每5秒回复1-5生命与精神\n受击自动获得85％减伤+霸体(持续5秒/冷却60秒)\n免疫沙尘暴减速\n与「余灯照夜明」齐穿时,周围有玩家也照常生效",
        check_desc = "空庭水月定，连山接无垠。",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "jieshen", EFFECT_ID, 1)
            if not owner._jieshen_hooked then
                owner._jieshen_hooked = true
                owner._jieshen_active = false

                -- ==========================================
                -- 环境免疫：免疫过冷过热
                -- HH 层 immuneCold/immuneHot 只能挡 HH 自己的易冷/易热 buff；
                -- 原版温度 DoT（cause "cold"/"hot"）由下面的 DoDelta 钩子拦。
                -- 两层都要，缺一不可（与雨纷纷同款处理）。
                -- ==========================================
                owner._jieshen_applyEnv = function()
                    if owner._jieshen_env_applied then return end
                    owner._jieshen_env_applied = true

                    local hh = owner.components.hh_player
                    if hh then
                        hh:AddEffectValueByKey("immuneCold", 1)
                        hh:AddEffectValueByKey("immuneHot", 1)
                    end
                    -- 已经挂在身上的易冷/易热 buff 要当场清掉，否则要等它自然到期
                    local hb = owner.components.hh_buff
                    if hb and hb.HasBuff then
                        if hb:HasBuff("add_cold") then hb:RemoveBuff("add_cold") end
                        if hb:HasBuff("add_hot") then hb:RemoveBuff("add_hot") end
                    end
                end

                owner._jieshen_removeEnv = function()
                    if not owner._jieshen_env_applied then return end
                    owner._jieshen_env_applied = nil
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("immuneCold", 1)
                        hh:ReduceEffectValueByKey("immuneHot", 1)
                    end
                end

                -- ==========================================
                -- 霸体：免疫击飞(HH key) + 免疫僵直(本 mod 的 jiangzhi 标记)
                -- 与萝的守护同款组合。必须在护佑窗口结束时成对撤销，
                -- 否则 AddEffectValueByKey 只加不减会永久叠数值。
                -- ==========================================
                owner._jieshen_grantBody = function()
                    if owner._jieshen_body_applied then return end
                    owner._jieshen_body_applied = true
                    local hh = owner.components.hh_player
                    if hh then
                        hh:AddEffectValueByKey("immunityKnockBack", 1)
                    end
                    _G.Moon_AddEffect(owner, "jiangzhi", EFFECT_ID, 1)
                end

                owner._jieshen_revokeBody = function()
                    if not owner._jieshen_body_applied then return end
                    owner._jieshen_body_applied = nil
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("immunityKnockBack", 1)
                    end
                    _G.Moon_ReduceEffect(owner, "jiangzhi", EFFECT_ID, 1)
                end

                -- ==========================================
                -- 护佑：受击自动触发，持续 GUARD_DURATION 秒，之后进入 GUARD_CD
                -- 用 guard_until 做"窗口"，cd_until 做"冷却"，两者都是绝对时间戳，
                -- 不依赖任务是否存活，玩家中途换装/重连也不会错乱。
                -- ==========================================
                owner._jieshen_triggerGuard = function()
                    if not owner._jieshen_active then return end
                    local health = owner.components.health
                    if health and health:IsDead() then return end

                    local now = _G.GetTime()
                    if owner._jieshen_guard_until and now < owner._jieshen_guard_until then return end
                    if owner._jieshen_cd_until and now < owner._jieshen_cd_until then return end

                    owner._jieshen_guard_until = now + GUARD_DURATION
                    owner._jieshen_cd_until = now + GUARD_CD
                    owner._jieshen_grantBody()

                    if owner.components.talker then
                        owner.components.talker:Say("孑身处处静！")
                    end

                    if owner._jieshen_guard_end_task then
                        owner._jieshen_guard_end_task:Cancel()
                    end
                    owner._jieshen_guard_end_task = owner:DoTaskInTime(GUARD_DURATION, function()
                        owner._jieshen_guard_end_task = nil
                        if owner:IsValid() then
                            owner._jieshen_revokeBody()
                        end
                    end)
                end

                -- ==========================================
                -- 生效判定：周围 30 码无其他玩家
                -- 套装齐穿（同时有「余灯照夜明」）时直接视为生效，不再扫玩家。
                -- ==========================================
                owner._jieshen_refresh = function()
                    if not _G.Moon_HasEffect(owner, "jieshen") then return end

                    local active = _G.Moon_HasEffect(owner, "yudeng")
                    if not active then
                        local x, y, z = owner.Transform:GetWorldPosition()
                        active = true
                        for _, v in ipairs(_G.AllPlayers) do
                            if v ~= owner and v:IsValid()
                                and v:GetDistanceSqToPoint(x, y, z) < SOLO_RANGE_SQ
                            then
                                active = false
                                break
                            end
                        end
                    end

                    if active ~= owner._jieshen_active then
                        owner._jieshen_active = active
                        if active then
                            owner._jieshen_applyEnv()
                        else
                            owner._jieshen_removeEnv()
                        end
                    end
                end

                -- 每 5 秒的少量回复（只在生效状态下给）
                owner._jieshen_regen = function()
                    if not owner._jieshen_active then return end
                    local health = owner.components.health
                    if health and not health:IsDead() then
                        health:DoDelta(math.random(REGEN_MIN, REGEN_MAX), true, "jieshen_regen")
                    end
                    local sanity = owner.components.sanity
                    if sanity then
                        sanity:DoDelta(math.random(REGEN_MIN, REGEN_MAX))
                    end
                end

                -- ==========================================
                -- health:DoDelta 钩子：免疫冷热 DoT + 受击触发护佑 + 护佑期高额减伤
                -- 注意 85% 走的是自己这一层乘法，不走 HH 的 absorbDamage ——
                -- 后者在 hh_player.lua 里被 math.min(v/100, 0.8) 硬截到 80%，到不了 85%。
                -- 只拦 DoDelta，不拦 DoHHDelta：真伤是该框架明确设计来穿透减免的通道，
                -- 附魔不该把它也吃掉。
                -- ==========================================
                local health = owner.components.health
                if health and not health._jieshen_hooked then
                    local oldDoDelta = health.DoDelta
                    health._jieshen_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and owner:IsValid() and _G.Moon_HasEffect(owner, "jieshen") then
                            -- 免疫过冷过热：原版温度组件的持续伤害 cause 为 "cold"/"hot"
                            if owner._jieshen_active and (cause == "cold" or cause == "hot") then
                                return oldDoDelta(self, 0, overtime, cause, ...)
                            end
                            -- 受击自动触发护佑：只认战斗打击（overtime=false），
                            -- 持续伤害不触发，避免站在毒雾/火里白嫖护佑
                            if owner._jieshen_active and not overtime then
                                owner._jieshen_triggerGuard()
                            end
                            -- 护佑窗口内的 85% 减伤（触发的那一下也吃到，符合"受击即生效"）
                            if owner._jieshen_guard_until and _G.GetTime() < owner._jieshen_guard_until then
                                delta = delta * (1 - GUARD_REDUCE)
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._jieshen_hooked = true
                end

                -- 初始判定 + 周期任务
                owner._jieshen_refresh()
                owner._jieshen_refresh_task = owner:DoPeriodicTask(REFRESH_INTERVAL, owner._jieshen_refresh)
                owner._jieshen_regen_task = owner:DoPeriodicTask(REGEN_INTERVAL, owner._jieshen_regen)

                -- 玩家进出世界时立刻重算，不用等下一个刷新周期
                -- 注意事件源必须显式写 TheWorld：ms_playerjoined/ms_playerleft
                -- 都是由世界推的，不传第三个参数监听不会触发
                owner._jieshen_join_handler = function() owner._jieshen_refresh() end
                owner:ListenForEvent("ms_playerjoined", owner._jieshen_join_handler, _G.TheWorld)
                owner:ListenForEvent("ms_playerleft", owner._jieshen_join_handler, _G.TheWorld)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "jieshen", EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, "jieshen") then
                if owner._jieshen_refresh_task then
                    owner._jieshen_refresh_task:Cancel()
                    owner._jieshen_refresh_task = nil
                end
                if owner._jieshen_regen_task then
                    owner._jieshen_regen_task:Cancel()
                    owner._jieshen_regen_task = nil
                end
                if owner._jieshen_guard_end_task then
                    owner._jieshen_guard_end_task:Cancel()
                    owner._jieshen_guard_end_task = nil
                end
                if owner._jieshen_join_handler then
                    owner:RemoveEventCallback("ms_playerjoined", owner._jieshen_join_handler, _G.TheWorld)
                    owner:RemoveEventCallback("ms_playerleft", owner._jieshen_join_handler, _G.TheWorld)
                    owner._jieshen_join_handler = nil
                end

                -- 成对撤销：免疫冷热 + 霸体
                owner._jieshen_removeEnv()
                owner._jieshen_revokeBody()

                local health = owner.components.health
                if health and health._jieshen_old_dodelta then
                    health.DoDelta = health._jieshen_old_dodelta
                    health._jieshen_old_dodelta = nil
                    health._jieshen_hooked = nil
                end

                -- 冷却时间戳一并清掉：换装重穿相当于刷新一次护佑，
                -- 这是刻意的宽松设计（护佑只有 5 秒、CD 60 秒，不至于被刷成永动机）
                owner._jieshen_active = nil
                owner._jieshen_guard_until = nil
                owner._jieshen_cd_until = nil
                owner._jieshen_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
