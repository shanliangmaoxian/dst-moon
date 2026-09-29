-- 小月亮 附魔：无漾
-- 雨露（原版潮湿）驱动：
--   快速回满雨露值（+3/秒）；不受潮湿影响（Wurt 同款：免扣san + 免手滑）
--   受到的所有伤害优先消耗雨露值抵扣；每 1 点雨露值 = 1% 移速（上限30）
--   每 3 秒恢复 5 点三维
--   雨露值归 0（从有到无）时生成 最大生命×10 护盾（约 20 秒快速衰减完）
--   护盾耗尽触发水爆：范围真伤+击退+灭火+溅湿（参考帝王蟹水浪风格），冷却 240 秒

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_WUYANG"
local EFFECT_KEY = "wuyang"

local DEW_REGEN       = 3     -- 雨露回复速度（点/秒，空→满约33秒）
local DEW_SPEED_PCT   = 1     -- 每 1 点雨露 = 1% 移速
local DEW_SPEED_CAP   = 30    -- 移速加成上限（%）
local REGEN_PERIOD    = 3     -- 三维回复间隔（秒）
local REGEN_AMOUNT    = 5     -- 三维回复量
local SHIELD_MAXHP_X  = 10    -- 护盾量 = 最大生命 × 10
local SHIELD_LIFETIME = 20    -- 护盾从满到空的自然衰减时间（秒）
local BURST_RADIUS    = 8     -- 水爆半径
local BURST_DMG       = 200   -- 水爆真伤
local BURST_KNOCKBACK = 10    -- 水爆击退初速
local BURST_CD        = 240   -- 水爆冷却（秒）

-- =========================================================
-- 移速：每 1 点雨露 = 1%（locomotor 外部倍率）
-- 注意：不能走 HH 的 addSpeedPercent 词条——HH 只在 equip 事件时读取一次
-- （hh_player.lua handle_equip_to_player），之后不刷新，动态变化无效。
-- 这里直接同步 locomotor 外部倍率（与 HH 内部实现同款，键名独立不冲突）。
-- =========================================================
local function ApplyMoveSpeed(owner, dew)
    local loc = owner.components.locomotor
    if not loc then return end
    local pct = math.min(math.floor(dew) * DEW_SPEED_PCT, DEW_SPEED_CAP)
    if pct > 0 then
        loc:SetExternalSpeedMultiplier(owner, "wuyang_speed", 1 + pct / 100)
    else
        loc:RemoveExternalSpeedMultiplier(owner, "wuyang_speed")
    end
end

local function ClearMoveSpeed(owner)
    if owner.components.locomotor then
        owner.components.locomotor:RemoveExternalSpeedMultiplier(owner, "wuyang_speed")
    end
end

-- =========================================================
-- 水爆：范围真伤 + 击退 + 灭火 + 溅湿
-- =========================================================
local function WaterBurst(owner)
    if not owner:IsValid() then return end
    if _G.GetTime() < (owner._wuyang_burst_cd or 0) then return end
    owner._wuyang_burst_cd = _G.GetTime() + BURST_CD

    local x, y, z = owner.Transform:GetWorldPosition()

    -- 溅花特效环
    for i = 1, 8 do
        local ang = i * _G.PI / 4
        local fx = _G.SpawnPrefab("splash_ocean")
        if fx then
            fx.Transform:SetPosition(
                x + BURST_RADIUS * 0.5 * math.cos(ang), y + 0.5, z + BURST_RADIUS * 0.5 * math.sin(ang))
        end
    end
    local big = _G.SpawnPrefab("splash_ocean")
    if big then big.Transform:SetPosition(x, y + 0.5, z) end

    for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, BURST_RADIUS, { "_combat" })) do
        if v ~= owner and v:IsValid()
                and not v:HasTag("player")
                and v.components.health
                and not v.components.health:IsDead() then
            -- 真伤
            if v.components.health.DoHHDelta then
                v.components.health:DoHHDelta(-BURST_DMG, owner, "无漾水爆")
            else
                v.components.health:DoDelta(-BURST_DMG, false, "wuyang_burst")
            end
            -- 击退
            if v.Physics then
                local vx, vy, vz = v.Transform:GetWorldPosition()
                local dx, dz = vx - x, vz - z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < 1 then dx, dz, dist = 1, 0, 1 end
                v.Physics:SetVel(dx / dist * BURST_KNOCKBACK, 5, dz / dist * BURST_KNOCKBACK)
            end
            -- 溅湿
            if v.components.moisture then
                v.components.moisture:DoDelta(100, true)
            end
        end
    end

    -- 灭火：扑灭周围燃烧/阴燃物（阴燃是 burnable 的内部状态，统一走 Extinguish）
    for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, BURST_RADIUS, { "fire" })) do
        if v ~= owner and v:IsValid() and v.components.burnable then
            v.components.burnable:Extinguish()
        end
    end
    for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, BURST_RADIUS, { "smolder" })) do
        if v ~= owner and v:IsValid() and v.components.burnable then
            v.components.burnable:Extinguish()
        end
    end

    if owner.components.talker then
        owner.components.talker:Say("无漾·水爆！")
    end
end

-- =========================================================
-- 护盾：雨露归零（从有到无的沿）时生成，自然衰减，耗尽触发水爆
-- =========================================================
local function TrySpawnShield(owner)
    if (owner._wuyang_shield or 0) > 0 then return end
    if owner._wuyang_dew_was_zero then return end  -- 雨露没回升过就不重复生成
    local health = owner.components.health
    if not health or health:IsDead() then return end
    owner._wuyang_shield = (health.maxhealth or 100) * SHIELD_MAXHP_X
    owner._wuyang_shield_decay = owner._wuyang_shield / SHIELD_LIFETIME
    if owner.components.talker then
        owner.components.talker:Say("雨露化盾，护佑此身……")
    end
end

-- =========================================================
-- 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "无漾",
        client_text = "无漾",
        desc = "快速回满雨露（+3/秒），免潮湿影响；伤害优先扣雨露\n每1点雨露+1%移速（封顶30%）；每3秒回5点三维\n雨露归零获最大生命×10护盾，耗尽触发水爆（冷却240秒）",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,

        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._wuyang_inited then
                owner._wuyang_inited = true
                owner._wuyang_shield = 0
                owner._wuyang_dew_was_zero = false

                -- ============ 不受潮湿影响（Wurt 同款，记录原值便于还原） ============
                if owner.components.sanity then
                    owner._wuyang_old_nmp = owner.components.sanity.no_moisture_penalty
                    owner.components.sanity.no_moisture_penalty = true
                end
                if not owner:HasTag("stronggrip") then
                    owner:AddTag("stronggrip")
                    owner._wuyang_own_grip = true
                end

                -- ============ 伤害管道：雨露优先抵扣 → 护盾抵扣 ============
                local health = owner.components.health
                if health and not health._wuyang_hooked then
                    health._wuyang_hooked = true
                    health._wuyang_old_delta = health.DoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and not self:IsDead()
                                and _G.Moon_HasEffect(owner, EFFECT_KEY) then
                            local moist = owner.components.moisture
                            -- 1) 雨露优先抵扣
                            if moist then
                                local dew = moist:GetMoisture()
                                local absorb = math.min(dew, -delta)
                                if absorb > 0 then
                                    moist:DoDelta(-absorb, true)
                                    delta = delta + absorb
                                end
                                -- 雨露归零沿 → 生成护盾
                                if moist:GetMoisture() <= 0 then
                                    TrySpawnShield(owner)
                                end
                            end
                            -- 2) 护盾抵扣，耗尽触发水爆
                            local shield = owner._wuyang_shield or 0
                            if shield > 0 and delta < 0 then
                                local used = math.min(shield, -delta)
                                owner._wuyang_shield = shield - used
                                delta = delta + used
                                if owner._wuyang_shield <= 0 then
                                    owner._wuyang_shield = 0
                                    WaterBurst(owner)
                                end
                            end
                        end
                        return health._wuyang_old_delta(self, delta, overtime, cause, ...)
                    end
                end

                -- ============ 秒级心跳：雨露回满 + 移速词条 + 护盾衰减 ============
                owner._wuyang_tick_task = owner:DoPeriodicTask(1, function()
                    if not owner:IsValid() then return end
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local moist = owner.components.moisture
                    if moist then
                        -- 快速回满雨露
                        if moist:GetMoisture() < moist.maxmoisture then
                            moist:DoDelta(DEW_REGEN, true)
                        end
                        -- 移速：每 1 点雨露 = 1%
                        ApplyMoveSpeed(owner, moist:GetMoisture())
                        -- 归零沿标记复位
                        if moist:GetMoisture() > 0 then
                            owner._wuyang_dew_was_zero = false
                        else
                            owner._wuyang_dew_was_zero = true
                            TrySpawnShield(owner)
                        end
                    end
                    -- 护盾自然衰减（快速衰减）
                    local shield = owner._wuyang_shield or 0
                    if shield > 0 then
                        owner._wuyang_shield = shield - (owner._wuyang_shield_decay or 0)
                        if owner._wuyang_shield <= 0 then
                            owner._wuyang_shield = 0
                            WaterBurst(owner)
                        end
                    end
                end, 1)

                -- ============ 每 3 秒回 5 点三维 ============
                owner._wuyang_regen_task = owner:DoPeriodicTask(REGEN_PERIOD, function()
                    if not owner:IsValid() then return end
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    if owner.components.health and not owner.components.health:IsDead() then
                        owner.components.health:DoDelta(REGEN_AMOUNT, false, "wuyang_regen")
                    end
                    if owner.components.sanity then
                        owner.components.sanity:DoDelta(REGEN_AMOUNT)
                    end
                    if owner.components.hunger then
                        owner.components.hunger:DoDelta(REGEN_AMOUNT)
                    end
                end, REGEN_PERIOD)
            end
        end,

        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                -- 移速倍率还原
                ClearMoveSpeed(owner)
                -- 潮湿免役还原
                if owner.components.sanity then
                    owner.components.sanity.no_moisture_penalty = owner._wuyang_old_nmp or false
                    owner._wuyang_old_nmp = nil
                end
                if owner._wuyang_own_grip and owner:HasTag("stronggrip") then
                    owner:RemoveTag("stronggrip")
                    owner._wuyang_own_grip = nil
                end
                -- 任务清理
                if owner._wuyang_tick_task then
                    owner._wuyang_tick_task:Cancel()
                    owner._wuyang_tick_task = nil
                end
                if owner._wuyang_regen_task then
                    owner._wuyang_regen_task:Cancel()
                    owner._wuyang_regen_task = nil
                end
                -- 伤害管道解包
                local health = owner.components.health
                if health and health._wuyang_hooked then
                    health.DoDelta = health._wuyang_old_delta
                    health._wuyang_old_delta = nil
                    health._wuyang_hooked = nil
                end
                owner._wuyang_shield = nil
                owner._wuyang_shield_decay = nil
                owner._wuyang_dew_was_zero = nil
                owner._wuyang_inited = nil
            end
        end,
    })

    -- 常规掉落池（档位权重以 tier_config.lua 为准）
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
