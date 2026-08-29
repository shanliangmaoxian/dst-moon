-- 小月亮 怪物强化 — 附魔池扩展（多样性扩展）
-- 参照开源模组 3096210166_附魔强化（HH 框架）的能力清单 + DST 原生机制批量设计
-- 全部重写为小月亮回调风格（on_apply/on_attack/on_attacked/on_kill/on_update/on_remove/on_damage），
-- 不依赖 HH 组件/工具/自定义 prefab，仅用 DST 原生组件（freezable/burnable/temperature/
-- moisture/sanity/locomotor/combat/Physics/Transform 等），缺失组件时自动跳过。
-- 由 init.lua 通过 modimport 加载后合并进 _G.MOON_MOB_ENCHANTS

local _G = GLOBAL
local SpawnPrefab = _G.SpawnPrefab
local TheSim = _G.TheSim
local math = _G.math
local GetTime = _G.GetTime

-- =====================================================================
-- 工具函数（与 enchants_pool.lua 同款）
-- =====================================================================
local function FindEnemies(inst, radius, filter)
    filter = filter or { "_combat" }
    local x, y, z = inst.Transform:GetWorldPosition()
    return TheSim:FindEntities(x, y, z, radius, filter)
end

local function IsValidTarget(inst, target)
    return target and target:IsValid()
        and target ~= inst
        and target.components.health
        and not target.components.health:IsDead()
end

-- 统一附魔伤害出口（damage_utils.lua 提供，含死亡之舞兼容限流）
local DealDamage = _G.Moon_MobEnhanceDealDamage

-- 是否免疫反伤/受击反击（HH 玄武/神龟守御 immuneBramble 等）
local function IsImmuneReflect(target)
    if not target then return false end
    local hh = target.components and target.components.hh_player
    return (hh and hh.HasSpecialEffect and hh:HasSpecialEffect("immuneBramble")) or false
end

local function FindNearestEnemy(inst, radius)
    local enemies = FindEnemies(inst, radius)
    local closest, closest_dist = nil, math.huge
    local x, y, z = inst.Transform:GetWorldPosition()
    for _, e in ipairs(enemies) do
        if IsValidTarget(inst, e) then
            local ex, ey, ez = e.Transform:GetWorldPosition()
            local dist = (x - ex)^2 + (z - ez)^2
            if dist < closest_dist then
                closest_dist = dist
                closest = e
            end
        end
    end
    return closest
end

-- SpawnFX(prefab, pos_or_x, y_or_scale, z, scale)
local function SpawnFX(prefab, pos_or_x, y_or_scale, z, scale)
    local fx = SpawnPrefab(prefab)
    if fx then
        if type(pos_or_x) == "userdata" then
            fx.Transform:SetPosition(pos_or_x)
            if y_or_scale then
                fx.Transform:SetScale(y_or_scale, y_or_scale, y_or_scale)
            end
        else
            if z ~= nil then
                fx.Transform:SetPosition(pos_or_x, y_or_scale, z)
            else
                fx.Transform:SetPosition(pos_or_x, y_or_scale, 0)
            end
            if scale then
                fx.Transform:SetScale(scale, scale, scale)
            end
        end
    end
    return fx
end

-- =====================================================================
-- 公共常量
-- =====================================================================
local REFLECT_CAP = 100  -- 反伤/弹反伤害上限

-- =====================================================================
-- 扩展附魔池
-- =====================================================================
_G.MOON_MOB_ENCHANTS_MORE = {

    -----------------------------------------------------------------
    -- 巨型 — 体型 + 血量（视觉压迫）
    -----------------------------------------------------------------
    MOB_GIANT = {
        name = "巨型", desc = "体型增大50%，生命+30%，移速-15%", weight = 2, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            inst.Transform:SetScale(1.5, 1.5, 1.5)
            local health = inst.components.health
            if health then
                local pct = health:GetPercent()
                health.maxhealth = health.maxhealth * 1.3
                health:SetPercent(math.min(pct, 1))
            end
            if inst.components.locomotor then
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, "mob_giant", 0.85)
            end
        end,
        on_remove = function(inst, state)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_giant")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 迷你 — 体型缩小 + 受击闪避（难缠的小家伙）
    -----------------------------------------------------------------
    MOB_TINY = {
        name = "迷你", desc = "体型缩小40%，移速+30%，受击30%概率闪避", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            inst.Transform:SetScale(0.6, 0.6, 0.6)
            if inst.components.locomotor then
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, "mob_tiny", 1.3)
            end
        end,
        on_damage = function(inst, damage, afflicter, tier, mult, state)
            if math.random() < 0.3 then
                -- 闪避：免伤并短暂减速攻击者
                if afflicter and afflicter:IsValid() and afflicter.components.locomotor then
                    afflicter.components.locomotor:SetExternalSpeedMultiplier(afflicter, "mob_tiny_dodge", 0.7)
                    afflicter:DoTaskInTime(2, function()
                        if afflicter:IsValid() and afflicter.components.locomotor then
                            afflicter.components.locomotor:RemoveExternalSpeedMultiplier(afflicter, "mob_tiny_dodge")
                        end
                    end)
                end
                return 0
            end
            return damage
        end,
        on_remove = function(inst, state)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_tiny")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 狂暴 — 低血量爆发（经典狂暴）
    -----------------------------------------------------------------
    MOB_BERSERK = {
        name = "狂暴", desc = "生命低于30%时攻击附加100%伤害，移速+40%", weight = 2, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._rage = false
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local health = inst.components.health
            if not health or health:GetPercent() >= 0.3 then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            DealDamage(inst, target, base * mult, "mob_berserk")
        end,
        on_update = function(inst, tier, mult, state)
            local health = inst.components.health
            if not health then return end
            local raging = health:GetPercent() < 0.3
            if raging and not state._rage then
                state._rage = true
                if inst.components.locomotor then
                    inst.components.locomotor:SetExternalSpeedMultiplier(inst, "mob_berserk", 1.4)
                end
            elseif not raging and state._rage then
                state._rage = false
                if inst.components.locomotor then
                    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_berserk")
                end
            end
        end,
        update_period = 1,
        on_remove = function(inst, state)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_berserk")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 老兵 — 自身血量越高攻击越痛
    -----------------------------------------------------------------
    MOB_VETERAN = {
        name = "老兵", desc = "自身生命越高攻击附加伤害越多（最高60%）", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local health = inst.components.health
            if not health then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            DealDamage(inst, target, base * health:GetPercent() * 0.6 * mult, "mob_veteran")
        end,
    },

    -----------------------------------------------------------------
    -- 夜行 — 夜晚强化 / 白天削弱（昼夜反差）
    -----------------------------------------------------------------
    MOB_NIGHTBORN = {
        name = "夜行", desc = "夜晚攻击附加50%伤害，白天移速-20%", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._slow = false
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local ws = _G.TheWorld and _G.TheWorld.state
            if ws and ws.isnight then
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                DealDamage(inst, target, base * 0.5 * mult, "mob_nightborn")
            end
        end,
        on_update = function(inst, tier, mult, state)
            local ws = _G.TheWorld and _G.TheWorld.state
            local is_day = ws and ws.isday
            if is_day and not state._slow then
                state._slow = true
                if inst.components.locomotor then
                    inst.components.locomotor:SetExternalSpeedMultiplier(inst, "mob_nightborn", 0.8)
                end
            elseif not is_day and state._slow then
                state._slow = false
                if inst.components.locomotor then
                    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_nightborn")
                end
            end
        end,
        update_period = 5,
        on_remove = function(inst, state)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_nightborn")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 水灵 — 雨天回血（天气联动）
    -----------------------------------------------------------------
    MOB_WET = {
        name = "水灵", desc = "下雨时每3秒回复2%生命", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            local ws = _G.TheWorld and _G.TheWorld.state
            if not (ws and ws.israining) then return end
            if inst.components.health then
                inst.components.health:DoDelta(inst.components.health.maxhealth * 0.02 * mult, false, "mob_wet")
            end
        end,
        update_period = 3,
    },

    -----------------------------------------------------------------
    -- 重甲 — 远程减伤（克制远程流派）
    -----------------------------------------------------------------
    MOB_ARMORED = {
        name = "重甲", desc = "远程攻击（7码外）伤害减免50%", weight = 2, boss_only = false,
        on_damage = function(inst, damage, afflicter, tier, mult, state)
            if not afflicter or not afflicter:IsValid() or not afflicter.Transform then
                return damage
            end
            local ax, ay, az = afflicter.Transform:GetWorldPosition()
            local mx, my, mz = inst.Transform:GetWorldPosition()
            local dx, dz = ax - mx, az - mz
            if dx * dx + dz * dz > 49 then
                return damage * 0.5
            end
            return damage
        end,
    },

    -----------------------------------------------------------------
    -- 固守 — 站桩回血（不移动时回复）
    -----------------------------------------------------------------
    MOB_FORTIFY = {
        name = "固守", desc = "站立不动时每秒回复1%生命", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            local loco = inst.components.locomotor
            if not loco then return end
            if loco.IsMoving and loco:IsMoving() then return end
            if inst.components.health then
                inst.components.health:DoDelta(inst.components.health.maxhealth * 0.01 * mult, false, "mob_fortify")
            end
        end,
        update_period = 1,
    },

    -----------------------------------------------------------------
    -- 雷击 — 高伤 + 麻痹（潮湿翻倍）
    -----------------------------------------------------------------
    MOB_ELEC = {
        name = "雷击", desc = "攻击15%概率召唤雷击（1.8倍伤害），目标潮湿时翻倍", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.15 then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            local dmg = base * 1.8 * mult
            if target:HasTag("wet") then
                dmg = dmg * 2
            end
            DealDamage(inst, target, dmg, "mob_elec")
            if target.components.locomotor then
                local gid = target.GUID
                state._elec_tasks = state._elec_tasks or {}
                if state._elec_tasks[gid] then
                    state._elec_tasks[gid]:Cancel()
                end
                target.components.locomotor:SetExternalSpeedMultiplier(target, "mob_elec", 0.6)
                state._elec_tasks[gid] = target:DoTaskInTime(1.5, function()
                    state._elec_tasks[gid] = nil
                    if target:IsValid() and target.components.locomotor then
                        target.components.locomotor:RemoveExternalSpeedMultiplier(target, "mob_elec")
                    end
                end)
            end
            SpawnFX("lightning_rod_fx", target.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 剧毒 — 持续中毒 DoT
    -----------------------------------------------------------------
    MOB_POISON = {
        name = "剧毒", desc = "攻击35%概率使目标中毒（8秒每秒5点）", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if target:HasTag("moon_poison_immune") then return end
            if math.random() > 0.35 then return end
            state._poison_id = (state._poison_id or 0) + 1
            local my_id = state._poison_id
            local dmg = 5 * mult
            local left = 8
            local function tick()
                if state._poison_id ~= my_id then return end
                if not target:IsValid() or (target.components.health and target.components.health:IsDead()) then return end
                DealDamage(inst, target, dmg, "mob_poison")
                left = left - 1
                if left > 0 then
                    target:DoTaskInTime(1, tick)
                end
            end
            tick()
        end,
    },

    -----------------------------------------------------------------
    -- 流血 — 按最大生命比例 DoT（打坦克利器）
    -----------------------------------------------------------------
    MOB_BLEED = {
        name = "流血", desc = "攻击25%概率使目标流血（5秒，每秒2%最大生命）", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.25 then return end
            state._bleed_id = (state._bleed_id or 0) + 1
            local my_id = state._bleed_id
            local left = 5
            local function tick()
                if state._bleed_id ~= my_id then return end
                if not target:IsValid() or not target.components.health or target.components.health:IsDead() then return end
                local dmg = target.components.health.maxhealth * 0.02 * mult
                DealDamage(inst, target, dmg, "mob_bleed")
                left = left - 1
                if left > 0 then
                    target:DoTaskInTime(1, tick)
                end
            end
            tick()
            SpawnFX("bloodsplash", target.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 连锁闪电 — 跳跃递减伤害（清场）
    -----------------------------------------------------------------
    MOB_CHAIN = {
        name = "连锁闪电", desc = "攻击20%概率触发闪电伤害", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.2 then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            DealDamage(inst, target, base * mult, "mob_chain")
            SpawnFX("lightning_rod_fx", target.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 虚弱诅咒 — 降低目标输出
    -----------------------------------------------------------------
    MOB_CURSE = {
        name = "虚弱诅咒", desc = "攻击40%概率使目标造成的伤害降低30%（10秒）", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.4 then return end
            if not target.components.combat then return end
            local key = "mob_curse_" .. inst.GUID
            target.components.combat.externaldamagemultipliers:SetModifier(inst, 0.7, key)
            target:DoTaskInTime(10, function()
                if target:IsValid() and target.components.combat then
                    target.components.combat.externaldamagemultipliers:RemoveModifier(inst, key)
                end
            end)
        end,
    },

    -----------------------------------------------------------------
    -- 迟滞 — 主动减速（黏住玩家）
    -----------------------------------------------------------------
    MOB_SLOW = {
        name = "迟滞", desc = "攻击50%概率使目标减速60%（4秒）", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.5 then return end
            if not target.components.locomotor then return end
            local gid = target.GUID
            state._slow_tasks = state._slow_tasks or {}
            if state._slow_tasks[gid] then
                state._slow_tasks[gid]:Cancel()
            end
            target.components.locomotor:SetExternalSpeedMultiplier(target, "mob_slow", 0.4)
            state._slow_tasks[gid] = target:DoTaskInTime(4, function()
                state._slow_tasks[gid] = nil
                if target:IsValid() and target.components.locomotor then
                    target.components.locomotor:RemoveExternalSpeedMultiplier(target, "mob_slow")
                end
            end)
        end,
    },

    -----------------------------------------------------------------
    -- 汲取 — 按目标最大生命吸血
    -----------------------------------------------------------------
    MOB_DRAIN = {
        name = "汲取", desc = "攻击30%概率吸取目标8%最大生命", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if not inst.components.health then return end
            if math.random() > 0.3 then return end
            local th = target.components.health
            if not th then return end
            local drain = th.maxhealth * 0.08 * mult
            DealDamage(inst, target, drain, "mob_drain")
            inst.components.health:DoDelta(drain, false, "mob_drain")
        end,
    },

    -----------------------------------------------------------------
    -- 霜环 — 受击冰霜新星（冰冻周围）
    -----------------------------------------------------------------
    MOB_FROSTNOVA = {
        name = "霜环", desc = "受击15%概率冰霜新星（冰冻攻击者）", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if math.random() > 0.15 then return end
            if not attacker or not attacker:IsValid() then return end
            local dmg = tier == "boss" and 150 * mult or 80 * mult
            if attacker.components.freezable then
                attacker.components.freezable:AddColdness(1)
            end
            DealDamage(inst, attacker, dmg, "mob_frostnova")
            SpawnFX("deerclops_icespike_fx", inst.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 火环 — 受击范围爆发（不点燃）
    -----------------------------------------------------------------
    MOB_FIRENOVA = {
        name = "火环", desc = "受击15%概率烈焰爆发（对攻击者造成伤害）", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if math.random() > 0.15 then return end
            if not attacker or not attacker:IsValid() then return end
            local dmg = tier == "boss" and 150 * mult or 80 * mult
            DealDamage(inst, attacker, dmg, "mob_firenova")
        end,
    },

    -----------------------------------------------------------------
    -- 招架 — 受击免伤并反击（攻防一体）
    -----------------------------------------------------------------
    MOB_PARRY = {
        name = "招架", desc = "受击20%概率完全免伤并反击1.5倍伤害", weight = 1, boss_only = false,
        on_damage = function(inst, damage, afflicter, tier, mult, state)
            if math.random() >= 0.2 then return damage end
            if afflicter and afflicter:IsValid() and afflicter.components.health
                    and not IsImmuneReflect(afflicter) then
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                local counter = math.min(base * 1.5 * mult, REFLECT_CAP)
                DealDamage(inst, afflicter, counter, "mob_parry")
            end
            return 0
        end,
    },

    -----------------------------------------------------------------
    -- 瞬移 — 受击闪到攻击者身后（戏耍玩家）
    -----------------------------------------------------------------
    -- MOB_BLINK = {
    --     name = "瞬移", desc = "受击20%概率瞬移到攻击者身后并脱战", weight = 1, boss_only = false,
    --     on_attacked = function(inst, attacker, damage, tier, mult, state)
    --         if not attacker or not attacker:IsValid() or not attacker.Transform then return end
    --         if math.random() > 0.2 then return end
    --         local ax, ay, az = attacker.Transform:GetWorldPosition()
    --         local ix, iy, iz = inst.Transform:GetWorldPosition()
    --         local dx, dz = ix - ax, iz - az
    --         local dist = math.sqrt(dx * dx + dz * dz)
    --         if dist < 0.1 then dist = 0.1 end
    --         inst.Transform:SetPosition(ix + dx / dist * 3, iy, iz + dz / dist * 3)
    --         if inst.components.combat then
    --             inst.components.combat:SetTarget(nil)
    --         end
    --         SpawnFX("collapse_small", inst.Transform:GetWorldPosition())
    --     end,
    -- },

    -----------------------------------------------------------------
    -- 隐匿 — 受击隐身并回血（丢失目标）
    -----------------------------------------------------------------
    MOB_CLOAK = {
        name = "隐匿", desc = "受击25%概率隐身5秒并回复生命", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if math.random() > 0.25 then return end
            if state._cloak then return end
            state._cloak = true
            inst:AddTag("invisible")
            inst:AddTag("notarget")
            if inst.entity then
                inst.entity:Hide()
            end
            if inst.components.combat then
                inst.components.combat:SetTarget(nil)
            end
            if inst.components.health then
                inst.components.health:DoDelta(inst.components.health.maxhealth * 0.05 * mult, false, "mob_cloak")
            end
            inst:DoTaskInTime(5, function()
                state._cloak = false
                if not inst:IsValid() then return end
                inst:RemoveTag("invisible")
                inst:RemoveTag("notarget")
                if inst.entity then
                    inst.entity:Show()
                end
            end)
        end,
    },

    -----------------------------------------------------------------
    -- 怒击 — 受击进入狂暴（短时爆发）
    -----------------------------------------------------------------
    MOB_RAGE = {
        name = "怒击", desc = "受击20%概率进入狂暴（攻击附加50%，10秒）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._rage_until = 0
        end,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if math.random() > 0.2 then return end
            state._rage_until = GetTime() + 10
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if GetTime() < state._rage_until then
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                DealDamage(inst, target, base * 0.5 * mult, "mob_rage")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 镜反 — 全额反弹伤害（与招架区分：反弹所受伤害）
    -----------------------------------------------------------------
    MOB_MIRROR = {
        name = "镜反", desc = "受击15%概率全额反弹伤害并免伤", weight = 1, boss_only = false,
        on_damage = function(inst, damage, afflicter, tier, mult, state)
            if math.random() >= 0.15 then return damage end
            local reflect_damage = math.min(damage, REFLECT_CAP)
            if afflicter and afflicter:IsValid() and afflicter.components.health
                    and not IsImmuneReflect(afflicter) then
                DealDamage(inst, afflicter, reflect_damage, "mob_mirror")
            end
            return 0
        end,
    },

    -----------------------------------------------------------------
    -- 尸爆 — 死亡爆炸（同归于尽）
    -----------------------------------------------------------------
    MOB_CORPSE = {
        name = "尸爆", desc = "死亡时对最近敌人造成伤害", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._dead = false
            inst:ListenForEvent("death", function()
                if state._dead then return end
                state._dead = true
                local dmg = tier == "boss" and 300 * mult or 150 * mult
                local nearest = FindNearestEnemy(inst, 5)
                if nearest then
                    DealDamage(inst, nearest, dmg, "mob_corpse")
                end
                SpawnFX("explode", inst.Transform:GetWorldPosition())
            end)
        end,
    },

    -----------------------------------------------------------------
    -- 临死反噬 — 死亡时反噬击杀者
    -----------------------------------------------------------------
    MOB_REVENGE = {
        name = "临死反噬", desc = "被击杀时对击杀者造成2倍攻击伤害", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            inst:ListenForEvent("death", function(_, data)
                local killer = data and data.afflicter
                if not killer and inst.components.combat and inst.components.combat.GetAttacker then
                    killer = inst.components.combat:GetAttacker()
                end
                if killer and killer:IsValid() and killer.components.health
                        and not IsImmuneReflect(killer) then
                    local dmg = (inst.components.combat and inst.components.combat.defaultdamage * 2 or 100) * mult
                    DealDamage(inst, killer, dmg, "mob_revenge")
                end
            end)
        end,
    },

    -----------------------------------------------------------------
    -- 瘟疫 — 击杀传播剧毒（尸毒扩散）
    -----------------------------------------------------------------
    MOB_PLAGUE = {
        name = "瘟疫", desc = "击杀目标时使最近敌人感染剧毒", weight = 1, boss_only = false,
        on_kill = function(inst, target, tier, mult, state)
            local nearest = FindNearestEnemy(inst, 6)
            if not nearest or nearest:HasTag("moon_poison_immune") then return end
            local left = 5
            local function tick()
                if not nearest:IsValid() or (nearest.components.health and nearest.components.health:IsDead()) then return end
                DealDamage(inst, nearest, 8 * mult, "mob_plague")
                left = left - 1
                if left > 0 then
                    nearest:DoTaskInTime(1, tick)
                end
            end
            tick()
        end,
    },

    -----------------------------------------------------------------
    -- 毒雾 — 光环持续毒伤
    -----------------------------------------------------------------
    MOB_MIASMA = {
        name = "毒雾", desc = "最近敌人每2秒受到毒伤", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            local dmg = 3 * mult
            local nearest = FindNearestEnemy(inst, 5)
            if nearest and not nearest:HasTag("moon_poison_immune") then
                DealDamage(inst, nearest, dmg, "mob_miasma")
            end
        end,
        update_period = 2,
    },

    -----------------------------------------------------------------
    -- 焦土 — 光环范围伤害（不点燃）
    -----------------------------------------------------------------
    MOB_EMBER = {
        name = "焦土", desc = "最近敌人每2秒受到伤害", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            local dmg = 15 * mult
            local nearest = FindNearestEnemy(inst, 4)
            if nearest then
                DealDamage(inst, nearest, dmg, "mob_ember")
            end
        end,
        update_period = 2,
    },

    -----------------------------------------------------------------
    -- 冰霜光环 — 范围减速玩家（控场）
    -----------------------------------------------------------------
    MOB_AURA = {
        name = "冰霜光环", desc = "周围6码的玩家与同伴减速20%", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            state._slow_tasks = state._slow_tasks or {}
            for _, v in ipairs(FindEnemies(inst, 6)) do
                if (v:HasTag("player") or v:HasTag("companion"))
                        and v.components.locomotor then
                    local gid = v.GUID
                    if state._slow_tasks[gid] then
                        state._slow_tasks[gid]:Cancel()
                    end
                    v.components.locomotor:SetExternalSpeedMultiplier(v, "mob_aura", 0.8)
                    state._slow_tasks[gid] = v:DoTaskInTime(3, function()
                        state._slow_tasks[gid] = nil
                        if v:IsValid() and v.components.locomotor then
                            v.components.locomotor:RemoveExternalSpeedMultiplier(v, "mob_aura")
                        end
                    end)
                end
            end
        end,
        update_period = 2,
    },

    -----------------------------------------------------------------
    -- 战意 — 战斗成长（越战越勇）
    -----------------------------------------------------------------
    MOB_BATTLE = {
        name = "战意", desc = "战斗中每4秒攻击附加+5%（上限25%），脱战重置", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._stacks = 0
        end,
        on_update = function(inst, tier, mult, state)
            local combat = inst.components.combat
            local in_combat = false
            if combat and combat.target and combat.target:IsValid()
                    and combat.target.components.health
                    and not combat.target.components.health:IsDead()
                    and inst:GetDistanceSqToInst(combat.target) < 400 then
                in_combat = true
            end
            if in_combat then
                state._stacks = math.min((state._stacks or 0) + 1, 5)
            else
                state._stacks = 0
            end
        end,
        update_period = 4,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if (state._stacks or 0) > 0 then
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                DealDamage(inst, target, base * 0.05 * state._stacks * mult, "mob_battle")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 饕餮 — 击杀成长（滚雪球）
    -----------------------------------------------------------------
    MOB_FEAST = {
        name = "饕餮", desc = "击杀目标回复15%生命并永久提升攻击（每层5%，上限25%）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._stacks = 0
        end,
        on_kill = function(inst, target, tier, mult, state)
            state._stacks = math.min((state._stacks or 0) + 1, 5)
            if inst.components.health then
                inst.components.health:DoDelta(inst.components.health.maxhealth * 0.15 * mult, false, "mob_feast")
            end
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if (state._stacks or 0) > 0 then
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                DealDamage(inst, target, base * 0.05 * state._stacks * mult, "mob_feast")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 王者威压 — 免疫三合一 + 恐惧（Boss 专属）
    -----------------------------------------------------------------
    MOB_SUPREME = {
        name = "王者威压", desc = "免疫冰冻/燃烧/中毒，攻击20%概率使目标精神受创", weight = 1, boss_only = true,
        on_apply = function(inst, tier, mult, state)
            if inst.components.freezable then
                inst.components.freezable.canfreeze = false
            end
            inst:AddTag("fireimmune")
            inst:AddTag("moon_poison_immune")
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.2 then return end
            if target.components.sanity then
                target.components.sanity:DoDelta(-20)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 冲击 — 击退目标（位移控制）
    -----------------------------------------------------------------
    MOB_KNOCK = {
        name = "冲击", desc = "攻击30%概率使目标短暂减速", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.3 then return end
            if target.components.locomotor then
                target.components.locomotor:SetExternalSpeedMultiplier(target, "mob_knock", 0.5)
                target:DoTaskInTime(1, function()
                    if target:IsValid() and target.components.locomotor then
                        target.components.locomotor:RemoveExternalSpeedMultiplier(target, "mob_knock")
                    end
                end)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 钩爪 — 把目标拉向自己
    -----------------------------------------------------------------
    MOB_HOOK = {
        name = "钩爪", desc = "攻击20%概率", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.2 then return end
        end,
    },

    -----------------------------------------------------------------
    -- 处决 — 对低血量目标斩杀（与老兵对称）
    -----------------------------------------------------------------
    MOB_EXECUTE = {
        name = "处决", desc = "对生命低于20%的目标攻击附加100%伤害", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local th = target.components.health
            if not th or th:GetPercent() >= 0.2 then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            DealDamage(inst, target, base * mult, "mob_execute")
        end,
    },

    -----------------------------------------------------------------
    -- 二连击 — 概率追加连击
    -----------------------------------------------------------------
    MOB_DOUBLESTRIKE = {
        name = "二连击", desc = "攻击30%概率追加一次50%伤害的连击", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.3 then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            DealDamage(inst, target, base * 0.5 * mult, "mob_doublestrike")
        end,
    },

    -----------------------------------------------------------------
    -- 呼唤 — 召唤猎犬助战
    -----------------------------------------------------------------
    MOB_SUMMON = {
        name = "呼唤", desc = "攻击10%概率召唤猎犬助战（上限2）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._minions = 0
        end,
        on_attack = function(inst, target, tier, mult, state)
            if math.random() > 0.1 then return end
            if state._minions >= 2 then return end
            local x, y, z = inst.Transform:GetWorldPosition()
            local minion = SpawnPrefab("hound")
            if minion then
                minion.Transform:SetPosition(x + math.random(-2, 2), y, z + math.random(-2, 2))
                state._minions = state._minions + 1
                if minion.components.health and inst.components.health then
                    minion.components.health:SetMaxHealth(inst.components.health.maxhealth * 0.5)
                end
                if minion.components.combat and inst.components.combat then
                    minion.components.combat.defaultdamage = (inst.components.combat.defaultdamage or 10) * 0.5
                end
                -- death + onremove 双监听，despawn 不丢计数；标记去重防死亡后重复减
                local function on_minion_gone()
                    if minion._moon_counted then return end
                    minion._moon_counted = true
                    if inst:IsValid() then
                        state._minions = math.max((state._minions or 1) - 1, 0)
                    end
                end
                minion:ListenForEvent("death", on_minion_gone)
                minion:ListenForEvent("onremove", on_minion_gone)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 孵化 — 击杀后从尸体孵化蜘蛛
    -----------------------------------------------------------------
    MOB_HATCH = {
        name = "孵化", desc = "击杀目标后从尸体孵化出蜘蛛（上限3）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._spiders = 0
        end,
        on_kill = function(inst, target, tier, mult, state)
            if state._spiders >= 3 then return end
            local tx, ty, tz = inst.Transform:GetWorldPosition()
            if target and target:IsValid() and target.Transform then
                tx, ty, tz = target.Transform:GetWorldPosition()
            end
            local spider = SpawnPrefab("spider")
            if spider then
                spider.Transform:SetPosition(tx + math.random(-1, 1), ty, tz + math.random(-1, 1))
                state._spiders = state._spiders + 1
                if spider.components.health and inst.components.health then
                    spider.components.health:SetMaxHealth(inst.components.health.maxhealth * 0.3)
                end
                if spider.components.combat and inst.components.combat then
                    spider.components.combat.defaultdamage = (inst.components.combat.defaultdamage or 10) * 0.3
                end
                -- death + onremove 双监听，despawn 不丢计数；标记去重防死亡后重复减
                local function on_spider_gone()
                    if spider._moon_counted then return end
                    spider._moon_counted = true
                    if inst:IsValid() then
                        state._spiders = math.max((state._spiders or 1) - 1, 0)
                    end
                end
                spider:ListenForEvent("death", on_spider_gone)
                spider:ListenForEvent("onremove", on_spider_gone)
                -- spider brain 白天中立，强制仇恨 20 码内最近玩家，否则孵化无威胁
                if spider.components.combat then
                    local px, py, pz = spider.Transform:GetWorldPosition()
                    local players = TheSim:FindEntities(px, py, pz, 20, { "player" })
                    if #players > 0 and players[1]:IsValid() then
                        spider.components.combat:SetTarget(players[1])
                    end
                end
            end
        end,
    },

    -----------------------------------------------------------------
    -- 浴血 — 受击叠攻（越挨打越凶）
    -----------------------------------------------------------------
    MOB_BLOODBATH = {
        name = "浴血", desc = "每次受击攻击+3%（上限30%）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._stacks = 0
        end,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            state._stacks = math.min((state._stacks or 0) + 1, 10)
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if (state._stacks or 0) > 0 then
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                DealDamage(inst, target, base * 0.03 * state._stacks * mult, "mob_bloodbath")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 地刺 — 受击在攻击者脚下生成尖刺
    -----------------------------------------------------------------
    MOB_SPIKES = {
        name = "地刺", desc = "受击25%概率在攻击者脚下生成尖刺并造成穿刺流血", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() or not attacker.Transform then return end
            if math.random() > 0.25 then return end
            local max_damage = REFLECT_CAP
            local dealt_damage = 0
            local function DoSpikeDamage(amount)
                local remain = max_damage - dealt_damage
                if remain <= 0 then return false end
                amount = math.min(amount, remain)
                DealDamage(inst, attacker, amount, "mob_spikes")
                dealt_damage = dealt_damage + amount
                return true
            end
            DoSpikeDamage(40 * mult)
            state._spike_id = (state._spike_id or 0) + 1
            local my_id = state._spike_id
            local left = 3
            local function tick()
                if state._spike_id ~= my_id then return end
                if not attacker:IsValid() or (attacker.components.health and attacker.components.health:IsDead()) then return end
                if not DoSpikeDamage(5 * mult) then return end
                left = left - 1
                if left > 0 then
                    attacker:DoTaskInTime(1, tick)
                end
            end
            tick()
            SpawnFX("collapse_small", attacker.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 酸血 — 受击溅射酸液
    -----------------------------------------------------------------
    MOB_ACIDBLOOD = {
        name = "酸血", desc = "受击30%概率溅射酸液灼伤攻击者并减速", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() then return end
            if math.random() > 0.3 then return end
            DealDamage(inst, attacker, 20 * mult, "mob_acidblood")
            if attacker.components.locomotor then
                attacker.components.locomotor:SetExternalSpeedMultiplier(attacker, "mob_acidblood", 0.7)
                attacker:DoTaskInTime(3, function()
                    if attacker:IsValid() and attacker.components.locomotor then
                        attacker.components.locomotor:RemoveExternalSpeedMultiplier(attacker, "mob_acidblood")
                    end
                end)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 恐怖气场 — 周围玩家持续掉san（光环压制）
    -----------------------------------------------------------------
    MOB_TERROR = {
        name = "恐怖气场", desc = "周围6码的玩家持续流失精神", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            for _, v in ipairs(FindEnemies(inst, 6)) do
                if v:IsValid() and v:HasTag("player") and v.components.sanity then
                    v.components.sanity:DoDelta(-2 * mult)
                end
            end
        end,
        update_period = 2,
    },

    -----------------------------------------------------------------
    -- 蓄力重击 — 周期性蓄力爆发
    -----------------------------------------------------------------
    MOB_CHARGE = {
        name = "蓄力重击", desc = "每6秒蓄力完成，下次攻击附加100%伤害", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._charged = 0
        end,
        on_update = function(inst, tier, mult, state)
            state._charged = math.min((state._charged or 0) + 1, 6)
        end,
        update_period = 1,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if (state._charged or 0) >= 6 then
                state._charged = 0
                local base = inst.components.combat and inst.components.combat.defaultdamage or 10
                DealDamage(inst, target, base * mult, "mob_charge")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 血潮 — 敌人越多回血越多
    -----------------------------------------------------------------
    MOB_LEECHING = {
        name = "血潮", desc = "攻击时附近敌人越多回复越多生命", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not inst.components.health then return end
            local count = 0
            for _, v in ipairs(FindEnemies(inst, 6)) do
                if v ~= inst and v.components.health and not v.components.health:IsDead()
                        and (v:HasTag("player") or v:HasTag("monster") or v:HasTag("hostile")) then
                    count = count + 1
                end
            end
            if count > 0 then
                inst.components.health:DoDelta(inst.components.health.maxhealth * 0.01 * count * mult, false, "mob_leeching")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 尖刺甲胄 — 近战固定反弹
    -----------------------------------------------------------------
    MOB_SPIKEDARMOR = {
        name = "尖刺甲胄", desc = "近战攻击者受到固定反弹伤害", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() or not attacker.Transform then return end
            if IsImmuneReflect(attacker) then return end
            local ax, ay, az = attacker.Transform:GetWorldPosition()
            local ix, iy, iz = inst.Transform:GetWorldPosition()
            local dx, dz = ax - ix, az - iz
            if dx * dx + dz * dz <= 9 then
                local reflect = math.min(20 * mult, REFLECT_CAP)
                DealDamage(inst, attacker, reflect, "mob_spikedarmor")
            end
        end,
    },
}

-- =====================================================================
-- 合并到主池
-- =====================================================================
if _G.MOON_MOB_ENCHANTS then
    for k, v in pairs(_G.MOON_MOB_ENCHANTS_MORE) do
        _G.MOON_MOB_ENCHANTS[k] = v
    end
end
