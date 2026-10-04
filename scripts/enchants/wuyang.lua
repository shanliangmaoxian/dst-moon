-- 小月亮 附魔：无漾
-- 雨露（原版潮湿）驱动的水之庇护：
--   雨露上限 +100%（100 → 200）；每秒自然 +5 雨露，每次攻击再 +5 雨露
--   受到的任何伤害优先由雨露抵扣，雨露扣完才真正掉血
--   踏水：可走上海面（只清掉陆地↔海洋那面物理墙，树木/建筑照旧阻挡）
--   防雷：免疫闪电直击（electricdamageimmune）
--   每 3 秒回复 5 点三维（只回当前值，不动上限）
--   移速：每 1 点雨露 +1%，封顶 +40%
-- “力挽狂澜！”

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_WUYANG"
local EFFECT_KEY = "wuyang"

local MAXMOISTURE_X  = 2     -- 雨露上限倍率（+100%）
local DEW_REGEN      = 5     -- 雨露自然回复（点/秒）
local DEW_ON_ATTACK  = 5     -- 每次攻击附加雨露（点）
local DEW_SPEED_PCT  = 1     -- 每 1 点雨露 = 1% 移速
local DEW_SPEED_CAP  = 40    -- 移速加成上限（%）
local REGEN_PERIOD   = 3     -- 三维回复间隔（秒）
local REGEN_AMOUNT   = 5     -- 三维回复量

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
-- 踏水：只清掉「陆地 ↔ 海洋」这一层物理墙（COLLISION.LAND_OCEAN_LIMITS）。
-- 玩家默认碰撞掩码由 MakeCharacterPhysics 给出：
--   COLLISION.WORLD(=BOAT_LIMITS+LAND_OCEAN_LIMITS+GROUND) + OBSTACLES
--   + SMALLOBSTACLES + CHARACTERS + GIANTS
-- WORLD 这个合并位里就含着 LAND_OCEAN_LIMITS，所以按位清掉 128 就能走上水面；
-- 树/墙/建筑等障碍物（OBSTACLES / SMALLOBSTACLES）照旧阻挡——这才是「只踏水」，
-- 不能像雨纷纷那样 RemovePhysicsColliders 清掉全部碰撞（会连墙一起穿）。
-- 再配合 drownable.enabled = false，站在海上也不会被判定溺水。
-- =========================================================
local function MakeCanWater(owner)
    if owner.Physics and _G.COLLISION then
        owner.Physics:ClearCollidesWith(_G.COLLISION.LAND_OCEAN_LIMITS)
    end
end

local function RestoreWaterWall(owner)
    if owner.Physics and _G.COLLISION then
        owner.Physics:CollidesWith(_G.COLLISION.LAND_OCEAN_LIMITS)
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
        desc = "雨露上限+100%；每秒+5雨露，每次攻击再+5\n受到的伤害优先由雨露抵扣（扣完才掉血）\n踏水·防雷；每3秒回复5点三维\n每1点雨露+1%移速（封顶40%）",
        check_desc = "力挽狂澜！",
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

                -- ============ 雨露上限 +100% ============
                -- maxmoisture 是 moisture 组件的「属性」：直接赋值会触发 onmaxmoisture，
                -- 把新上限同步给 player_classified（客户端雨露表按它换算百分比）。
                -- 但 OnSave 只存当前 moisture、不存 maxmoisture，所以卸下时必须自己还原。
                local moist = owner.components.moisture
                if moist then
                    owner._wuyang_old_maxmoisture = moist.maxmoisture
                    moist.maxmoisture = moist.maxmoisture * MAXMOISTURE_X
                end

                -- ============ 防雷：免疫闪电直击 ============
                -- componentutil.IsEntityElectricImmune 查这个 tag；
                -- StrikeLightningAtPoint 与 LightningStrikeAttack 都会先过这道判定，
                -- 命中即整体跳过：不受伤、不燃烧、不进触电状态。
                if not owner:HasTag("electricdamageimmune") then
                    owner:AddTag("electricdamageimmune")
                    owner._wuyang_own_electricimmune = true
                end

                -- ============ 踏水 ============
                MakeCanWater(owner)
                if not owner.components.drownable then
                    owner:AddComponent("drownable")
                end
                if owner.components.drownable then
                    owner._wuyang_old_drownable = owner.components.drownable.enabled
                    owner.components.drownable.enabled = false
                end

                -- ============ 伤害管道：雨露优先抵扣 ============
                -- 包一层 health.DoDelta：负伤害先用雨露吃掉，扣不完的部分才继续走原管线
                -- （所以雨露足够时相当于完全免伤，护甲/无敌帧等原逻辑不受影响）。
                local health = owner.components.health
                if health and not health._wuyang_hooked then
                    health._wuyang_hooked = true
                    health._wuyang_old_delta = health.DoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and not self:IsDead()
                                and _G.Moon_HasEffect(owner, EFFECT_KEY) then
                            local m = owner.components.moisture
                            if m then
                                local dew = m:GetMoisture()
                                local absorb = math.min(dew, -delta)
                                if absorb > 0 then
                                    -- 第二个参数 true = no_announce，免得每掉一滴雨露都弹提示
                                    m:DoDelta(-absorb, true)
                                    delta = delta + absorb
                                end
                            end
                        end
                        return health._wuyang_old_delta(self, delta, overtime, cause, ...)
                    end
                end

                -- ============ 每次攻击 +5 雨露 ============
                owner._wuyang_attack_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local m = owner.components.moisture
                    if m and m:GetMoisture() < m.maxmoisture then
                        m:DoDelta(DEW_ON_ATTACK, true)
                    end
                end
                owner:ListenForEvent("onattackother", owner._wuyang_attack_handler)

                -- ============ 秒级心跳：雨露自然回复 + 移速同步 ============
                owner._wuyang_tick_task = owner:DoPeriodicTask(1, function()
                    if not owner:IsValid() then return end
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local m = owner.components.moisture
                    if not m then return end
                    if m:GetMoisture() < m.maxmoisture then
                        m:DoDelta(DEW_REGEN, true)
                    end
                    ApplyMoveSpeed(owner, m:GetMoisture())
                end, 1)

                -- ============ 每 3 秒回 5 点三维（只回当前值） ============
                -- health / sanity 传 overtime=true：这是每 3 秒一次的常驻回复，
                -- 不传会把 HUD 的 health_up / sanity_up 音效刷成噪音
                -- （statusdisplays 里 overtime 分支只做 PulseGreen、不播音效）。
                owner._wuyang_regen_task = owner:DoPeriodicTask(REGEN_PERIOD, function()
                    if not owner:IsValid() then return end
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    if owner.components.health and not owner.components.health:IsDead() then
                        owner.components.health:DoDelta(REGEN_AMOUNT, true, "wuyang_regen")
                    end
                    if owner.components.sanity then
                        owner.components.sanity:DoDelta(REGEN_AMOUNT, true)
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

                -- 雨露上限还原；当前雨露可能超过旧上限，必须夹紧
                local moist = owner.components.moisture
                if moist and owner._wuyang_old_maxmoisture then
                    moist.maxmoisture = owner._wuyang_old_maxmoisture
                    if moist.moisture > moist.maxmoisture then
                        moist:SetMoistureLevel(moist.maxmoisture)
                    end
                    owner._wuyang_old_maxmoisture = nil
                end

                -- 防雷还原（只摘自己加的那个，WX-78 自带的不管）
                if owner._wuyang_own_electricimmune and owner:HasTag("electricdamageimmune") then
                    owner:RemoveTag("electricdamageimmune")
                    owner._wuyang_own_electricimmune = nil
                end

                -- 踏水还原
                RestoreWaterWall(owner)
                if owner.components.drownable then
                    -- 记录到的 nil 等价于组件默认的 true（组件自己 DoTaskInTime(0) 会把 nil 置 true）
                    owner.components.drownable.enabled =
                        owner._wuyang_old_drownable == nil and true or owner._wuyang_old_drownable
                end
                owner._wuyang_old_drownable = nil

                -- 任务清理
                if owner._wuyang_tick_task then
                    owner._wuyang_tick_task:Cancel()
                    owner._wuyang_tick_task = nil
                end
                if owner._wuyang_regen_task then
                    owner._wuyang_regen_task:Cancel()
                    owner._wuyang_regen_task = nil
                end
                if owner._wuyang_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._wuyang_attack_handler)
                    owner._wuyang_attack_handler = nil
                end

                -- 伤害管道解包
                local health = owner.components.health
                if health and health._wuyang_hooked then
                    health.DoDelta = health._wuyang_old_delta
                    health._wuyang_old_delta = nil
                    health._wuyang_hooked = nil
                end

                owner._wuyang_inited = nil
            end
        end,
    })

    -- 常规掉落池（档位权重以 tier_config.lua 为准）
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
