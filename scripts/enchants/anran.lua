-- 小月亮 附魔：安燃
-- 每次攻击生成 2 个火焰宝珠环绕自身（上限 8），每宝珠 +10% 攻速（HH atk_speed）
-- 火焰光环：每 2 秒对周围敌人造成 10 点/珠真伤；受击时宝珠齐射反击攻击者
-- 灵魂烈焰：被命中目标 5 秒内受到的所有伤害翻倍（包 health.DoDelta，wdsn 同款策略）
-- 贯通真伤：攻击固定造成 100 + 1% 目标最大生命值伤害（DoHHDelta 官方真伤通道，
--           无视护甲/减伤/免伤；命中才触发=天然无视闪避；格挡不减免）
-- 固定吸血：1 + 10% 自身已损失生命，走 health:SetVal 直通（绕过一切封疗/减疗钩子）
-- 免死：受致命伤害时消耗全部宝珠，锁血 50% 并无敌+不可选中 5 秒，冷却 240 秒
-- 宝珠视觉：网络化 campfirefire FX 实体（去除 heater/firefx，熄灭灯光与音效），
--           服务端驱动环绕位置，Transform 自动复制到客户端

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_ANRAN"
local EFFECT_KEY = "anran"

local ORBS_PER_ATTACK = 2      -- 每次攻击生成宝珠数
local ORB_MAX          = 8     -- 宝珠上限
local ORB_ATK_SPEED    = 10    -- 每宝珠攻速加成（%）
local ORB_RADIUS       = 1.7   -- 环绕半径
local ORB_HEIGHT       = 1.2   -- 环绕高度
local ORB_ORBIT_SPEED  = 1.6   -- 环绕角速度（弧度/秒）
local AOE_PERIOD       = 2     -- 光环自动攻击间隔（秒）
local AOE_RADIUS       = 6     -- 光环攻击范围
local ORB_AOE_DMG      = 10    -- 每宝珠每次光环伤害
local SOULFLAME_TIME   = 5     -- 灵魂烈焰持续（秒）
local TRUE_BASE        = 100   -- 贯通真伤固定值
local TRUE_MAXHP_PCT   = 0.01  -- 贯通真伤 +1% 目标最大生命
local LIFESTEAL_BASE   = 1     -- 固定吸血
local LIFESTEAL_LOST   = 0.10  -- +10% 自身已损失生命
local LOCK_PCT         = 0.5   -- 免死锁血线（50%）
local LOCK_TIME        = 5     -- 免死无敌时长（秒）
local LOCK_CD          = 240   -- 免死冷却（秒）

-- =========================================================
-- 工具
-- =========================================================

--HH atk_speed 词条增减（层数变化时差额重算，ji.lua SetHHValue 同款）
local function SetOrbAtkSpeed(owner, count)
    local hh = owner.components.hh_player
    if not hh then return end
    local newval = count * ORB_ATK_SPEED
    local old = owner._anran_applied_atkspd or 0
    if old == newval then return end
    if old > 0 then hh:ReduceEffectValueByKey("atk_speed", old) end
    if newval > 0 then hh:AddEffectValueByKey("atk_speed", newval) end
    owner._anran_applied_atkspd = newval
end

--宝珠实体（网络化 FX：campfirefire 去除 heater/firefx，熄灯）
local function CreateOrbEntity(owner)
    local orb = _G.SpawnPrefab("campfirefire")
    if orb == nil then return nil end
    if orb.components.heater then orb:RemoveComponent("heater") end
    if orb.components.firefx then orb:RemoveComponent("firefx") end
    if orb.Light then orb.Light:Enable(false) end
    orb.persists = false
    if orb.AnimState then orb.AnimState:PlayAnimation("level1", true) end
    return orb
end

--按当前层数同步宝珠实体（多退少补）
local function SyncOrbEntities(owner)
    local want = owner._anran_orb_count or 0
    local orbs = owner._anran_orbs or {}
    while #orbs > want do
        local orb = table.remove(orbs)
        if orb and orb:IsValid() then orb:Remove() end
    end
    while #orbs < want do
        local orb = CreateOrbEntity(owner)
        if orb then
            -- 初始位置放在主人环上（天环同款），避免从世界原点飞入
            local x, y, z = owner.Transform:GetWorldPosition()
            local ang = #orbs * (2 * _G.PI / math.max(want, 1))
            orb.Transform:SetPosition(
                x + ORB_RADIUS * math.cos(ang), y + ORB_HEIGHT, z + ORB_RADIUS * math.sin(ang))
            table.insert(orbs, orb)
        else
            break
        end
    end
    owner._anran_orbs = orbs
end

--宝珠环绕运动（天环同款：updatelooper 每帧驱动 + 插值平滑跟随，服务端驱动 Transform 网络复制）
local function StartOrbitTask(owner)
    if owner._anran_orbit_fn then return end
    if not owner.components.updatelooper then
        owner:AddComponent("updatelooper")
    end
    local phase = 0
    owner._anran_orbit_fn = function(inst, dt)
        if not owner:IsValid() then return end
        local orbs = owner._anran_orbs
        if orbs == nil or #orbs == 0 then return end
        phase = phase + dt * ORB_ORBIT_SPEED
        local x, y, z = owner.Transform:GetWorldPosition()
        local n = #orbs
        local smooth = math.min(1, dt * 12) -- 每帧向目标位置插值（天环 delay_factor 同思路）
        local tnow = _G.GetTime()
        for i, orb in ipairs(orbs) do
            if orb:IsValid() then
                local ang = phase + (i - 1) * (2 * _G.PI / n)
                local tx = x + ORB_RADIUS * math.cos(ang)
                local ty = y + ORB_HEIGHT + math.sin(tnow * 3 + i) * 0.15
                local tz = z + ORB_RADIUS * math.sin(ang)
                local cx, cy, cz = orb.Transform:GetWorldPosition()
                orb.Transform:SetPosition(
                    cx + (tx - cx) * smooth,
                    cy + (ty - cy) * smooth,
                    cz + (tz - cz) * smooth)
            end
        end
    end
    owner.components.updatelooper:AddOnUpdateFn(owner._anran_orbit_fn)
end

local function StopOrbitTask(owner)
    if owner._anran_orbit_fn and owner.components.updatelooper then
        owner.components.updatelooper:RemoveOnUpdateFn(owner._anran_orbit_fn)
    end
    owner._anran_orbit_fn = nil
end

--清除全部宝珠（免死消耗/卸下）
local function ClearOrbs(owner)
    owner._anran_orb_count = 0
    SyncOrbEntities(owner)
    SetOrbAtkSpeed(owner, 0)
end

-- =========================================================
-- 灵魂烈焰：目标受伤翻倍（限时标记 + health.DoDelta 包装，wdsn 同款不解包策略）
-- =========================================================
local function ApplySoulflame(target)
    if not target or not target:IsValid() then return end
    local health = target.components.health
    if not health or health:IsDead() then return end
    target._anran_soulflame_until = _G.GetTime() + SOULFLAME_TIME
    if target._anran_soul_hooked then return end
    target._anran_soul_hooked = true
    local old = health.DoDelta
    health.DoDelta = function(self, delta, overtime, cause, ...)
        if delta < 0 and target._anran_soulflame_until
                and _G.GetTime() < target._anran_soulflame_until then
            delta = delta * 2
        end
        return old(self, delta, overtime, cause, ...)
    end
end

-- =========================================================
-- 固定吸血：health:SetVal 直通（不经过任何 DoDelta 包装，不可被禁疗/减疗）
-- =========================================================
local function ForceHeal(owner, amount)
    local health = owner.components.health
    if not health or health:IsDead() or amount <= 0 then return end
    local oldval = health.currenthealth
    local newval = math.min(health:GetMaxWithPenalty(), oldval + amount)
    if newval <= oldval then return end
    health:SetVal(newval, "anran_lifesteal", owner)
    owner:PushEvent("healthdelta", {
        oldpercent = health:GetPercent(),
        newpercent = health:GetPercent(),
        amount = newval - oldval,
        cause = "anran_lifesteal",
    })
end

-- =========================================================
-- 附魔注册
-- =========================================================
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "安燃",
        client_text = "安燃",
        desc = "每次攻击生成2个火焰宝珠环绕自身（上限8）\n每宝珠+10%攻速，光环每2秒造成10点/珠真伤，受击反击\n命中目标附加灵魂烈焰：5秒内受到的所有伤害翻倍\n攻击固定造成" .. TRUE_BASE .. "+1%目标最大生命贯通真伤\n吸血" .. LIFESTEAL_BASE .. "+10%已损失生命（无视禁疗）\n致命伤消耗全部宝珠：锁血50%无敌5秒（冷却240秒）",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,

        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._anran_inited then
                owner._anran_inited = true
                owner._anran_orb_count = 0
                owner._anran_orbs = {}

                StartOrbitTask(owner)

                -- 环绕光圈自动攻击：每 2 秒对周围敌人造成 10 点/珠真伤 + 灵魂烈焰
                owner._anran_aoe_task = owner:DoPeriodicTask(AOE_PERIOD, function()
                    if not owner:IsValid() or (owner._anran_orb_count or 0) <= 0 then return end
                    if owner.components.health and owner.components.health:IsDead() then return end
                    local total = owner._anran_orb_count * ORB_AOE_DMG
                    local x, y, z = owner.Transform:GetWorldPosition()
                    for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, AOE_RADIUS, { "_combat" })) do
                        if v:IsValid() and not v:HasTag("player")
                                and v.components.health and not v.components.health:IsDead() then
                            ApplySoulflame(v)
                            if v.components.health.DoHHDelta then
                                v.components.health:DoHHDelta(-total, owner, "安燃灼烧")
                            else
                                v.components.health:DoDelta(-total, false, "anran_burn")
                            end
                        end
                    end
                end)

                -- 攻击处理：生成宝珠 + 贯通真伤 + 灵魂烈焰 + 固定吸血
                owner._anran_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    local health = target.components.health
                    if health and not health:IsDead() then
                        -- 生成宝珠（上限 8）
                        if (owner._anran_orb_count or 0) < ORB_MAX then
                            owner._anran_orb_count = math.min(ORB_MAX,
                                (owner._anran_orb_count or 0) + ORBS_PER_ATTACK)
                            SyncOrbEntities(owner)
                            SetOrbAtkSpeed(owner, owner._anran_orb_count)
                        end
                        -- 灵魂烈焰
                        ApplySoulflame(target)
                        -- 贯通真伤：100 + 1% 目标最大生命
                        local true_dmg = TRUE_BASE + (health.maxhealth or 100) * TRUE_MAXHP_PCT
                        if health.DoHHDelta then
                            health:DoHHDelta(-true_dmg, owner, "安燃贯通")
                        else
                            health:DoDelta(-true_dmg, false, "anran_true")
                        end
                    end
                    -- 固定吸血：1 + 10% 自身已损失生命（SetVal 直通，无视禁疗）
                    local myhealth = owner.components.health
                    if myhealth then
                        local lost = (myhealth.maxhealth or 0) - (myhealth.currenthealth or 0)
                        ForceHeal(owner, LIFESTEAL_BASE + math.max(0, lost) * LIFESTEAL_LOST)
                    end
                end
                owner:ListenForEvent("onattackother", owner._anran_attack_handler)

                -- 受击反击：宝珠齐射攻击者
                owner._anran_attacked_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    if (owner._anran_orb_count or 0) <= 0 then return end
                    local attacker = data and data.attacker
                    if not attacker or not attacker:IsValid() then return end
                    if attacker:HasTag("player") then return end
                    local hp = attacker.components.health
                    if not hp or hp:IsDead() then return end
                    ApplySoulflame(attacker)
                    local total = owner._anran_orb_count * ORB_AOE_DMG
                    if hp.DoHHDelta then
                        hp:DoHHDelta(-total, owner, "安燃反击")
                    else
                        hp:DoDelta(-total, false, "anran_counter")
                    end
                end
                owner:ListenForEvent("attacked", owner._anran_attacked_handler)

                -- 免死锁血：致命伤时消耗全部宝珠 → 锁血 50% + 无敌不可选中 5 秒
                if not owner._anran_lock_hooked then
                    owner._anran_lock_hooked = true
                    local old_delta = owner.components.health.DoDelta
                    owner._anran_old_health_delta = old_delta
                    owner.components.health.DoDelta = function(self, delta, overtime, cause, ...)
                        if delta < 0 and not self:IsDead()
                                and (self.currenthealth or 0) + delta <= 0
                                and _G.Moon_HasEffect(owner, EFFECT_KEY)
                                and (owner._anran_orb_count or 0) > 0
                                and _G.GetTime() >= (owner._anran_lock_cd or 0) then
                            owner._anran_lock_cd = _G.GetTime() + LOCK_CD
                            ClearOrbs(owner)
                            local lockval = math.floor((self.maxhealth or 100) * LOCK_PCT)
                            delta = -(self.currenthealth - lockval)
                            -- 无敌 + 不可选中 5 秒
                            self:SetInvincible(true)
                            owner:AddTag("notarget")
                            owner:DoTaskInTime(LOCK_TIME, function(inst)
                                if inst:IsValid() and inst.components.health then
                                    inst.components.health:SetInvincible(false)
                                    if inst:HasTag("notarget") then
                                        inst:RemoveTag("notarget")
                                    end
                                end
                            end)
                            if owner.components.talker then
                                owner.components.talker:Say("安燃不灭！血量锁定50%，无敌5秒！")
                            end
                            -- 火焰爆发特效
                            local x, y, z = owner.Transform:GetWorldPosition()
                            for i = 1, 6 do
                                local fx = _G.SpawnPrefab("campfirefire")
                                if fx then
                                    fx:RemoveComponent("heater")
                                    fx:RemoveComponent("firefx")
                                    if fx.Light then fx.Light:Enable(false) end
                                    fx.persists = false
                                    local ang = i * _G.PI / 3
                                    fx.Transform:SetPosition(
                                        x + 2 * math.cos(ang), y + 0.5, z + 2 * math.sin(ang))
                                    fx:DoTaskInTime(1, function(f) if f:IsValid() then f:Remove() end end)
                                end
                            end
                        end
                        return old_delta(self, delta, overtime, cause, ...)
                    end
                end

                -- 死亡/移除时清理宝珠
                owner:ListenForEvent("death", function(inst)
                    if inst._anran_orbs then
                        for _, orb in ipairs(inst._anran_orbs) do
                            if orb and orb:IsValid() then orb:Remove() end
                        end
                        inst._anran_orbs = {}
                        inst._anran_orb_count = 0
                    end
                end)
            end
        end,

        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                ClearOrbs(owner)
                StopOrbitTask(owner)
                if owner._anran_aoe_task then
                    owner._anran_aoe_task:Cancel()
                    owner._anran_aoe_task = nil
                end
                if owner._anran_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._anran_attack_handler)
                    owner._anran_attack_handler = nil
                end
                if owner._anran_attacked_handler then
                    owner:RemoveEventCallback("attacked", owner._anran_attacked_handler)
                    owner._anran_attacked_handler = nil
                end
                -- 免死无敌还原（若正处于无敌期）
                if owner.components.health and owner.components.health:IsInvincible()
                        and owner._anran_lock_hooked then
                    owner.components.health:SetInvincible(false)
                    if owner:HasTag("notarget") then owner:RemoveTag("notarget") end
                end
                -- 免死 DoDelta 包装保留（wdsn 同款不解包策略，靠 Moon_HasEffect 短路）
                owner._anran_inited = nil
                owner._anran_applied_atkspd = nil
            end
        end,
    })

    -- 常规掉落池（档位权重以 tier_config.lua 为准）
    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
