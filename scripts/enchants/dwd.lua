-- 小月亮 附魔：大卫戴
-- 食用料理（preparedfood）时：
--   1) 溢出的治疗量转化为生命上限提升（save_maxhealth 持久化，累计上限 DWD_MAX_GAINED）
--   2) 同步记录溢出量到"治疗池"（血不满且不处于"制裁"时自动消耗回复）
--   3) 每以此获得 50 生命上限 → 移速 -10%（最高 -90%，即 +450 上限封顶）
--
-- 【修复说明】（参照 mx_health 毛旭的实现模式）
-- 旧问题1: 溢出转上限无上限 → 新增 DWD_MAX_GAINED 累计上限，达到后溢出只进治疗池
-- 旧问题2: un_equip_fn 用 Moon_HasEffect 判断是否清理，效果计数重复时清理被跳过，
--          摘掉附魔效果仍在 → 改为毛旭模式：每件装备 inst.GUID 独立 key + 幂等防重，
--          卸下时对比 Moon_GetTotalEffectValue 差值，仅当计数归零才清理 hook
-- 旧问题3: 治疗池只有消耗没有充值 → 溢出时同步充值
-- "味真足！ ——by：清欢渡"

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_DWD"
local EFFECT_KEY = "dwd"

local DWD_MAX_GAINED = 300     -- 溢出转生命上限的累计上限
local MAX_HEALTH_HARD_CAP = 60000 -- 血上限绝对硬顶（与毛旭一致）
local SPEED_PENALTY_PER = 50    -- 每 50 生命上限 → 移速 -10%
local SPEED_PENALTY_STEP = 10   -- 每档移速惩罚 %
local SPEED_PENALTY_CAP = 90    -- 移速惩罚上限 %
local POOL_TICK = 1             -- 治疗池结算间隔（秒）

local function get_sanctioned(owner)
    local buff = owner.components.hh_buff
    return buff ~= nil and buff.HasBuff ~= nil and buff:HasBuff("player_healthSuppressNum") or false
end

-- 重算移速惩罚
local function refresh_speed_penalty(owner)
    local gained = owner._dwd_gained or 0
    local new_penalty = math.min(SPEED_PENALTY_CAP, math.floor(gained / SPEED_PENALTY_PER) * SPEED_PENALTY_STEP)
    local old_penalty = owner._dwd_applied_penalty or 0
    if new_penalty == old_penalty then return end
    local hh = owner.components.hh_player
    if not hh then return end
    if old_penalty > 0 then
        hh:ReduceEffectValueByKey("addSpeedPercent", -old_penalty)
    end
    if new_penalty > 0 then
        hh:AddEffectValueByKey("addSpeedPercent", -new_penalty)
    end
    owner._dwd_applied_penalty = new_penalty
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "大卫戴",
        client_text = "大卫\n戴",
        desc = "食用料理时溢出的治疗量转为生命上限（累计上限+" .. DWD_MAX_GAINED ..
            "，每50上限-10%移速，最高-90%），并储存起来：血量不满时自动消耗回复（制裁中不回复）",
        check_desc = "味真足！ ——by：清欢渡",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            if not owner:IsValid() or not owner.components.health then return end
            -- 毛旭模式：每件装备独立 key + 幂等防重
            local key = "DWD_" .. inst.GUID
            owner._dwd_sources = owner._dwd_sources or {}
            if owner._dwd_sources[key] then return end
            owner._dwd_sources[key] = true
            _G.Moon_AddEffect(owner, EFFECT_KEY, key, 1)

            if not owner._dwd_hooked then
                owner._dwd_hooked = true
                owner._dwd_pool = owner._dwd_pool or 0
                owner._dwd_gained = owner._dwd_gained or 0

                -- 标记进食中：包 eater.Eat
                local eater = owner.components.eater
                if eater and not eater._dwd_hooked_eat then
                    eater._dwd_hooked_eat = true
                    eater._dwd_old_eat = eater.Eat
                    eater.Eat = function(self, food, ...)
                        if _G.Moon_HasEffect(owner, EFFECT_KEY) then
                            owner._dwd_food = food
                        end
                        local result = eater._dwd_old_eat(self, food, ...)
                        owner._dwd_food = nil
                        return result
                    end
                end

                -- 溢出捕获：包 health.DoDelta
                local health = owner.components.health
                if health and not health._dwd_hooked_delta then
                    health._dwd_hooked_delta = true
                    health._dwd_old_delta = health.DoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta > 0 and owner._dwd_food ~= nil
                                and cause == owner._dwd_food.prefab
                                and _G.Moon_HasEffect(owner, EFFECT_KEY)
                                and owner._dwd_food:HasTag("preparedfood")
                        then
                            local overflow = (self.currenthealth + delta) - self.maxhealth
                            if overflow > 0 then
                                -- 治疗池充值（无论上限是否达到都存）
                                owner._dwd_pool = (owner._dwd_pool or 0) + overflow
                                -- 溢出 → 提升生命上限（累计封顶 + 绝对硬顶）
                                local allowed = math.min(overflow,
                                    DWD_MAX_GAINED - (owner._dwd_gained or 0),
                                    MAX_HEALTH_HARD_CAP - self.maxhealth)
                                if allowed > 0 then
                                    self.maxhealth = self.maxhealth + allowed
                                    self.save_maxhealth = true
                                    self:ForceUpdateHUD()
                                    owner._dwd_gained = (owner._dwd_gained or 0) + allowed
                                    refresh_speed_penalty(owner)
                                end
                            end
                        end
                        return health._dwd_old_delta(self, delta, overtime, cause, ...)
                    end
                end

                -- 治疗池结算：血不满且不受制裁时自动消耗
                owner._dwd_pool_task = owner:DoPeriodicTask(POOL_TICK, function(inst2)
                    if not _G.Moon_HasEffect(inst2, EFFECT_KEY) then return end
                    local pool = inst2._dwd_pool or 0
                    if pool <= 0 then return end
                    local hp = inst2.components.health
                    if not hp or hp:IsDead() then return end
                    if get_sanctioned(inst2) then return end
                    local room = hp.maxhealth - hp.currenthealth
                    if room <= 0 then return end
                    local use = math.min(pool, room)
                    inst2._dwd_pool = pool - use
                    hp:DoDelta(use, false, "dwd_pool")
                end)

                -- 存档：治疗池与累计上限（记录原函数，卸下时还原）
                owner._dwd_old_onsave = owner.OnSave
                owner.OnSave = function(inst2, data)
                    if owner._dwd_old_onsave then owner._dwd_old_onsave(inst2, data) end
                    data._dwd_pool = inst2._dwd_pool or 0
                    data._dwd_gained = inst2._dwd_gained or 0
                end
                owner._dwd_old_onload = owner.OnLoad
                owner.OnLoad = function(inst2, data)
                    if owner._dwd_old_onload then owner._dwd_old_onload(inst2, data) end
                    if data then
                        inst2._dwd_pool = data._dwd_pool or inst2._dwd_pool or 0
                        inst2._dwd_gained = data._dwd_gained or inst2._dwd_gained or 0
                        if _G.Moon_HasEffect(inst2, EFFECT_KEY) then
                            refresh_speed_penalty(inst2)
                        end
                    end
                end

                -- 重装时恢复移速惩罚
                refresh_speed_penalty(owner)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            if not owner:IsValid() then return end
            -- 毛旭模式：对比 ReduceEffect 前后总量差值，计数归零才清理
            local key = "DWD_" .. inst.GUID
            local old_total = _G.Moon_GetTotalEffectValue(owner, EFFECT_KEY)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, key, 1)
            local new_total = _G.Moon_GetTotalEffectValue(owner, EFFECT_KEY)
            owner._dwd_sources = owner._dwd_sources or {}
            owner._dwd_sources[key] = nil
            if new_total > 0 then return end  -- 计数未归零（重复计数保护），不动 hook

            local eater = owner.components.eater
            if eater and eater._dwd_hooked_eat then
                eater.Eat = eater._dwd_old_eat
                eater._dwd_old_eat = nil
                eater._dwd_hooked_eat = nil
            end
            local health = owner.components.health
            if health and health._dwd_hooked_delta then
                health.DoDelta = health._dwd_old_delta
                health._dwd_old_delta = nil
                health._dwd_hooked_delta = nil
            end
            if owner._dwd_pool_task then
                owner._dwd_pool_task:Cancel()
                owner._dwd_pool_task = nil
            end
            local hh = owner.components.hh_player
            if hh then
                local old_penalty = owner._dwd_applied_penalty or 0
                if old_penalty > 0 then
                    hh:ReduceEffectValueByKey("addSpeedPercent", -old_penalty)
                end
            end
            owner._dwd_applied_penalty = 0
            owner._dwd_food = nil
            -- 还原存档钩子
            if owner._dwd_old_onsave then
                owner.OnSave = owner._dwd_old_onsave
                owner._dwd_old_onsave = nil
            end
            if owner._dwd_old_onload then
                owner.OnLoad = owner._dwd_old_onload
                owner._dwd_old_onload = nil
            end
            owner._dwd_hooked = nil
        end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
