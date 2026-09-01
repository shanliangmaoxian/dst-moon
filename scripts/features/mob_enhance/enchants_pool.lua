-- 小月亮 怪物强化 — 附魔池
-- 所有从现有附魔适配的「怪物版」效果表
-- 由 init.lua 通过 modimport 加载后存入全局 _G.MOON_MOB_ENCHANTS

local _G = GLOBAL
local SpawnPrefab = _G.SpawnPrefab
local TheSim = _G.TheSim
local math = _G.math
local GetTime = _G.GetTime

-- =====================================================================
-- 工具函数
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

-- SpawnFX(prefab, pos_or_x, y_or_scale, z)
-- pos_or_x: Vector3 或 x 坐标；y_or_scale: y 坐标或缩放；z: z 坐标
-- 支持: SpawnFX("fx", posVector3, scale) 或 SpawnFX("fx", x, y, z, scale)
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

local function SpawnFX(prefab, pos_or_x, y_or_scale, z, scale)
    local fx = SpawnPrefab(prefab)
    if fx then
        -- 判断第一个位置参数是否是 Vector3 (userdata)
        if type(pos_or_x) == "userdata" then
            -- Vector3 模式: SpawnFX(prefab, pos, scale)
            fx.Transform:SetPosition(pos_or_x)
            if y_or_scale then
                fx.Transform:SetScale(y_or_scale, y_or_scale, y_or_scale)
            end
        else
            -- 坐标模式: SpawnFX(prefab, x, y, z, scale)
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
-- 附魔池
-- =====================================================================
_G.MOON_MOB_ENCHANTS = {

    -----------------------------------------------------------------
    -- 毛旭 — 血量提升
    -----------------------------------------------------------------
    MOB_MX_HEALTH = {
        name = "毛旭", desc = "最大生命提升（Boss +30% / 普通怪 +500，按难度倍率）", weight = 3, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            local health = inst.components.health
            if not health then return end
            local old_pct = health:GetPercent()
            if tier == "boss" then
                local bonus = health.maxhealth * 0.3 * mult
                health.maxhealth = math.min(health.maxhealth + bonus, 100000)
            else
                local bonus = 500 * mult
                health.maxhealth = health.maxhealth + bonus
            end
            health:SetPercent(old_pct)
        end,
    },

    -----------------------------------------------------------------
    -- 月半 — HP 附加伤害 + 受击 AoE
    -----------------------------------------------------------------
    MOB_YUEBAN = {
        name = "月半", desc = "攻击附带自身生命值5%伤害；受击概率反击攻击者", weight = 2, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._cooldown = 0
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local health = inst.components.health
            if not health then return end
            local hp = math.min(health.currenthealth, 20000)
            local bonus = math.min(hp * 0.05 * mult, REFLECT_CAP)
            if bonus > 0 then
                DealDamage(inst, target, bonus, "mob_yueban")
            end
        end,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() then return end
            local now = GetTime()
            if now - state._cooldown < 3 then return end
            if math.random() > 0.2 then return end
            state._cooldown = now
            local base_dmg = 100 * mult
            if tier == "boss" and inst.components.health then
                local hp = math.min(inst.components.health.maxhealth, 20000)
                base_dmg = hp * 0.05 * mult
            end
            base_dmg = math.min(base_dmg, REFLECT_CAP)
            if not IsImmuneReflect(attacker) then
                DealDamage(inst, attacker, base_dmg, "mob_yueban")
            end
            SpawnFX("collapse_small", inst.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 山竹的捏 — 护盾吸收 + 破盾 AoE
    -----------------------------------------------------------------
    MOB_SHANZHU = {
        name = "山竹的捏", desc = "护盾吸收60%伤害；破盾时反击攻击者并回血", weight = 2, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            local health = inst.components.health
            if not health then return end
            state._shield = tier == "boss" and health.maxhealth * 0.1 * mult or 200 * mult
            state._shield_max = state._shield
            state._shield_broken = false
            state._shield_task = inst:DoPeriodicTask(10, function()
                if not inst:IsValid() then return end
                if state._shield_broken then state._shield = 0; return end
                state._shield = math.min((state._shield or 0) + state._shield_max * 0.2, state._shield_max)
            end)
        end,
        on_remove = function(inst, state)
            if state._shield_task then state._shield_task:Cancel(); state._shield_task = nil end
        end,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not inst:IsValid() then return end
            if state._shield_broken then return end
            if not state._shield or state._shield <= 0 then
                state._shield_broken = true
                local heal_pct = tier == "boss" and 0.1 or 0.15
                local aoe_dmg = tier == "boss" and (inst.components.health and inst.components.health.maxhealth * 0.05 * mult or 150 * mult) or 150 * mult
                if attacker and attacker:IsValid() then
                    DealDamage(inst, attacker, aoe_dmg, "mob_shanzhu")
                end
                if inst.components.health then
                    inst.components.health:DoDelta(inst.components.health.maxhealth * heal_pct * mult, false, "mob_shanzhu_shield")
                end
            else
                state._shield = state._shield - math.min(state._shield, damage * 0.6)
                if state._shield <= 0 then state._shield = 0; state._shield_broken = true end
            end
        end,
    },

    -----------------------------------------------------------------
    -- 哎哟 — 受击回血 + 反伤 + 击杀冲击波
    -----------------------------------------------------------------
    MOB_AIYO = {
        name = "哎哟", desc = "受击60%概率回血并反伤；击杀冲击最近敌人", weight = 2, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not inst.components.health then return end
            -- 伤害计算上限 200
            local effective_damage = math.min(damage, REFLECT_CAP)
            -- 60% 概率回血
            if math.random() < 0.6 then
                local heal_ratio = tier == "boss" and 0.3 or 0.6
                inst.components.health:DoDelta(effective_damage * heal_ratio, false, "mob_aiyo_heal")
            end
            -- 反伤
            if attacker and attacker:IsValid() and attacker.components.health then
                local hh_attacker = attacker.components.hh_player
                if not (hh_attacker and hh_attacker.HasSpecialEffect
                    and hh_attacker:HasSpecialEffect("immuneBramble")) then
                    local reflect_ratio = tier == "boss" and 0.5 or 1.0
                    DealDamage(inst, attacker, effective_damage * reflect_ratio, "mob_aiyo_reflect")
                end
            end
        end,
        on_kill = function(inst, target, tier, mult, state)
            local dmg = tier == "boss" and (inst.components.combat and inst.components.combat.defaultdamage * 3 or 300) or 200
            dmg = dmg * mult
            local nearest = FindNearestEnemy(inst, 5)
            if nearest then
                DealDamage(inst, nearest, dmg, "mob_aiyo_blast")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 胖虎 — 攻击概率 AoE 音波
    -----------------------------------------------------------------
    MOB_PANGHU = {
        name = "胖虎", desc = "攻击15%概率音波单体伤害", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if math.random() > 0.15 then return end
            if not IsValidTarget(inst, target) then return end
            local dmg = tier == "boss" and (inst.components.health and inst.components.health.maxhealth * 0.05 * mult or 500) or 200 * mult
            dmg = math.min(dmg, REFLECT_CAP)
            DealDamage(inst, target, dmg, "mob_panghu")
        end,
    },

    -----------------------------------------------------------------
    -- 急冻冻 — 冰冻 + 冰爆
    -----------------------------------------------------------------
    MOB_WJBD = {
        name = "急冻冻", desc = "攻击概率冰冻目标并引发冰爆", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local chance = tier == "boss" and 0.15 or 0.2
            if math.random() > chance then return end
            -- 冰冻
            if target.components.freezable then
                target.components.freezable:AddColdness(1)
                target.components.freezable:SpawnShatterFX()
            end
            -- 冰爆单体，最终伤害上限200
            local dmg = tier == "boss" and (inst.components.health and inst.components.health.maxhealth * 0.05 * mult or 300) or 300 * mult
            dmg = math.min(dmg, REFLECT_CAP)
            DealDamage(inst, target, dmg, "mob_wjbd")
            SpawnFX("deerclops_icespike_fx", inst.Transform:GetWorldPosition())
        end,
    },

    -----------------------------------------------------------------
    -- 草莓奶昔 — 周期性回血 + 减速攻击者
    -----------------------------------------------------------------
    MOB_STRAWBERRY = {
        name = "草莓奶昔", desc = "持续回血；受击减速攻击者", weight = 3, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._heal_amount = tier == "boss" and 0.03 or 0.05
        end,
        on_update = function(inst, tier, mult, state)
            if inst.components.health then
                local heal = inst.components.health.maxhealth * state._heal_amount * mult
                inst.components.health:DoDelta(heal, false, "mob_strawberry")
            end
        end,
        update_period = 3,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if attacker and attacker:IsValid() and attacker.components.locomotor then
                attacker.components.locomotor:SetExternalSpeedMultiplier(attacker, "mob_strawberry_slow", 0.6)
                attacker:DoTaskInTime(2, function()
                    if attacker:IsValid() and attacker.components.locomotor then
                        attacker.components.locomotor:RemoveExternalSpeedMultiplier(attacker, "mob_strawberry_slow")
                    end
                end)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 萝的守护 — 免伤 + 叠层减伤
    -----------------------------------------------------------------
    MOB_LUO = {
        name = "萝的守护", desc = "常驻50%减伤，受击叠加减伤最高25%", weight = 2, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._stacks = 0
            if inst.components.combat then
                inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 0.5, "mob_luo_base")
            end
        end,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            state._stacks = math.min((state._stacks or 0) + 1, 5)
            local reduction = state._stacks * 0.05 -- up to 25%
            if inst.components.combat then
                inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 0.5 - reduction, "mob_luo_base")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 等秋零 — 攻击力 + 移速 + 受击免疫
    -----------------------------------------------------------------
    MOB_DENGQIUHING = {
        name = "等秋零", desc = "提升攻击力与移动速度", weight = 3, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            if inst.components.combat then
                local base = inst.components.combat.defaultdamage or 10
                local bonus_ratio = tier == "boss" and 0.5 or 0.25
                inst.components.combat.defaultdamage = base * (1 + bonus_ratio * mult)
            end
            if inst.components.locomotor then
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, "mob_dengqiuling_speed", 1.15)
            end
        end,
        on_remove = function(inst, state)
            if inst.components.locomotor then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mob_dengqiuling_speed")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 妖精庇护 — % 已损失生命真伤
    -----------------------------------------------------------------
    MOB_FAY = {
        name = "妖精庇护", desc = "攻击附带目标已损失生命值8%伤害", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local target_health = target.components.health
            if not target_health then return end
            local missing = target_health.maxhealth - target_health.currenthealth
            local bonus = math.min(missing * 0.08 * mult, REFLECT_CAP)
            if bonus > 0 then
                DealDamage(inst, target, bonus, "mob_fay")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 篮球 — 连击同一目标增伤
    -----------------------------------------------------------------
    MOB_LANQIU = {
        name = "篮球", desc = "连击同一目标叠层，叠满额外增伤", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._target = nil
            state._combo = 0
            state._combo_reset_task = nil
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not target or not target:IsValid() then return end
            local guid = target.GUID
            if state._target == guid then
                state._combo = math.min((state._combo or 0) + 1, 10)
            else
                state._target = guid
                state._combo = 1
            end
            -- 重置计时器
            if state._combo_reset_task then state._combo_reset_task:Cancel() end
            state._combo_reset_task = inst:DoTaskInTime(5, function()
                if not inst:IsValid() then return end
                state._target = nil; state._combo = 0
            end)
            -- 每层 +10% 伤害
            if state._combo >= 10 and inst.components.combat then
                local extra = inst.components.combat.defaultdamage * 0.5 * mult
                DealDamage(inst, target, extra, "mob_lanqiu")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 空白 — 清除目标增益
    -----------------------------------------------------------------
    MOB_KONGBAI = {
        name = "空白", desc = "概率清除目标增益并造成额外伤害", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if math.random() > 0.6 then return end
            -- 清除常见 buff 标签
            local cleared = 0
            local buffs = {"buff", "buff_player", "spider_heal", "electricity", "wet", "cold"}
            for _, tag in ipairs(buffs) do
                if target:HasTag(tag) then
                    target:RemoveTag(tag)
                    cleared = cleared + 1
                end
            end
            if cleared > 0 then
                local bonus = cleared * 0.6 * inst.components.combat.defaultdamage * mult
                DealDamage(inst, target, bonus, "mob_kongbai")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 是萌新喵 — 免死 + 高血量增伤
    -----------------------------------------------------------------
    MOB_MXM = {
        name = "是萌新喵", desc = "攻击高血量目标（>70%）附加伤害", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            if tier == "boss" then
                state._death_defiance_left = 3
            else
                state._death_defiance_left = 1
            end
        end,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local target_health = target.components.health
            if not target_health then return end
            if target_health:GetPercent() > 0.7 then
                local bonus = inst.components.combat and inst.components.combat.defaultdamage * 0.6 * mult or 30
                DealDamage(inst, target, bonus, "mob_mxm")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 酸酸草 — 酸蚀叠层减防
    -----------------------------------------------------------------
    MOB_SUANSUANCAO = {
        name = "酸酸草", desc = "攻击叠加酸蚀降低目标防御并造成真伤", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if not target.components.combat then return end
            if not target._mob_suansuan_stacks then target._mob_suansuan_stacks = 0 end
            target._mob_suansuan_stacks = math.min(target._mob_suansuan_stacks + 1, 8)
            local reduction = target._mob_suansuan_stacks * 0.05
            target.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 1 - reduction, "mob_suansuan")
            -- 真伤
            local bonus = 10 * mult
            DealDamage(inst, target, bonus, "mob_suansuan")
        end,
    },

    -----------------------------------------------------------------
    -- 七步之外 — 攻击距离增加
    -----------------------------------------------------------------
    MOB_CHANGPI = {
        name = "七步之外", desc = "攻击距离增加", weight = 3, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            if inst.components.combat then
                local range_bonus = tier == "boss" and 4 or 2
                inst.components.combat.hitrange = (inst.components.combat.hitrange or 3) + range_bonus
            end
        end,
    },

    -----------------------------------------------------------------
    -- 良弓藏 — 自动远程攻击（Boss 专用）
    -----------------------------------------------------------------
    MOB_LIANGGONGCANG = {
        name = "良弓藏", desc = "每30秒自动远程攻击附近敌人", weight = 1, boss_only = true,
        on_update = function(inst, tier, mult, state)
            -- 找最近的敌人射箭
            local nearest = nil
            local min_dist = 9999
            for _, v in ipairs(FindEnemies(inst, 20)) do
                if v:HasTag("player") or v:HasTag("companion") then
                    local dist = inst:GetDistanceSqToInst(v)
                    if dist < min_dist then
                        min_dist = dist
                        nearest = v
                    end
                end
            end
            if nearest and nearest:IsValid() and nearest.components.health and not IsImmuneReflect(nearest) then
                local dmg = math.min((inst.components.combat and inst.components.combat.defaultdamage * 3 or 100) * mult, REFLECT_CAP)
                DealDamage(inst, nearest, dmg, "mob_liang")
            end
        end,
        update_period = 30,
    },

    -----------------------------------------------------------------
    -- 蝴蝶的小阿飞 — 减伤 + 击杀回血
    -----------------------------------------------------------------
    MOB_HUFEI = {
        name = "蝴蝶的小阿飞", desc = "常驻20%减伤；击杀恢复生命", weight = 2, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            if inst.components.combat then
                inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 0.8, "mob_hufei")
            end
        end,
        on_kill = function(inst, target, tier, mult, state)
            if inst.components.health then
                local heal = inst.components.health.maxhealth * 0.1 * mult
                inst.components.health:DoDelta(heal, false, "mob_hufei_heal")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 咕咕咕 — 闪避反击
    -----------------------------------------------------------------
    MOB_GUGUGU = {
        name = "咕咕咕", desc = "受击42%概率闪避并反击", weight = 1, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() then return end
            -- 42% 概率触发：反击（攻击者免疫反伤则不反击）
            if math.random() < 0.42 and not IsImmuneReflect(attacker) then
                local counter = math.min((inst.components.combat and inst.components.combat.defaultdamage * 2 or 100) * mult, REFLECT_CAP)
                DealDamage(inst, attacker, counter, "mob_gugugu")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 云中雀 — 周期性爆发
    -----------------------------------------------------------------
    MOB_YZQ = {
        name = "云中雀", desc = "每8秒对最近敌人爆发伤害", weight = 1, boss_only = false,
        on_update = function(inst, tier, mult, state)
            -- 每8秒爆发一次，伤害上限200
            local dmg = math.min((inst.components.combat and inst.components.combat.defaultdamage * 3.5 or 100) * mult, REFLECT_CAP)
            local nearest = FindNearestEnemy(inst, 6)
            if nearest then
                DealDamage(inst, nearest, dmg, "mob_yzq")
            end
        end,
        update_period = 8,
    },

    -----------------------------------------------------------------
    -- 紫蝶分身 — 攻击召唤分身
    -----------------------------------------------------------------
    MOB_ZIDIE = {
        name = "紫蝶分身", desc = "攻击概率召唤弱化分身助战（上限2）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._clone_count = 0
        end,
        on_attack = function(inst, target, tier, mult, state)
            if math.random() > 0.05 then return end
            if state._clone_count >= 2 then return end  -- 上限 2 个分身
            local x, y, z = inst.Transform:GetWorldPosition()
            local clone = SpawnPrefab(inst.prefab)
            if clone then
                clone.Transform:SetPosition(x + math.random(-2, 2), y, z + math.random(-2, 2))
                state._clone_count = state._clone_count + 1
                -- 弱化版：50% 属性
                if clone.components.health and inst.components.health then
                    clone.components.health:SetMaxHealth(inst.components.health.maxhealth * 0.5)
                end
                if clone.components.combat and inst.components.combat then
                    clone.components.combat.defaultdamage = (inst.components.combat.defaultdamage or 10) * 0.5
                end
                -- 分身自己会死亡
                clone:ListenForEvent("death", function()
                    state._clone_count = math.max((state._clone_count or 1) - 1, 0)
                end)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 君可知 — 限伤 + 反击（与防御层互补）
    -----------------------------------------------------------------
    MOB_JUNJUN = {
        name = "君可知", desc = "受击时反击攻击者", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            state._last_roar = 0
        end,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() then return end
            -- 受击时反击
            local now = GetTime()
            if now - state._last_roar < 5 then return end
            state._last_roar = now
            local dmg = math.min((inst.components.combat and inst.components.combat.defaultdamage * 2 or 100) * mult, REFLECT_CAP)
            if not IsImmuneReflect(attacker) then
                DealDamage(inst, attacker, dmg, "mob_junjun")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 暴击 — 攻击概率造成暴击附加伤害（移植自 HH 附魔强化 addCriticalHitRate）
    -----------------------------------------------------------------
    MOB_CRIT = {
        name = "暴击", desc = "攻击概率造成暴击附加伤害（Boss 30%概率1.5倍 / 普通怪 20%概率1倍）", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local chance = tier == "boss" and 0.3 or 0.2
            if math.random() > chance then return end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            local extra = base * (tier == "boss" and 1.5 or 1.0) * mult
            DealDamage(inst, target, extra, "mob_crit")
        end,
    },

    -----------------------------------------------------------------
    -- 吸血 — 攻击按伤害百分比回血（移植自 atkBlood）
    -----------------------------------------------------------------
    MOB_LIFESTEAL = {
        name = "吸血", desc = "攻击回复伤害值10%~15%的生命", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state, data)
            if not IsValidTarget(inst, target) then return end
            if not inst.components.health then return end
            local damage = data and data.damage or 0
            if not damage or damage <= 0 then
                damage = inst.components.combat and inst.components.combat.defaultdamage or 10
            end
            local ratio = tier == "boss" and 0.15 or 0.1
            inst.components.health:DoDelta(damage * ratio * mult, false, "mob_lifesteal")
        end,
    },

    -----------------------------------------------------------------
    -- 格挡 — 受击概率完全免伤（移植自 noHitDamage/replaceDamageChance）
    -- 依赖组件 on_damage 回调（伤害拦截），与防御层共用 DoDelta hook
    -----------------------------------------------------------------
    MOB_BLOCK = {
        name = "格挡", desc = "受击概率完全格挡伤害（Boss 25% / 普通怪 20%）", weight = 2, boss_only = false,
        on_damage = function(inst, damage, afflicter, tier, mult, state)
            local chance = tier == "boss" and 0.25 or 0.2
            if math.random() < chance then
                return 0
            end
            return damage
        end,
    },

    -----------------------------------------------------------------
    -- 荆棘反伤 — 受击反弹百分比伤害（移植自 reboundDamagePercent）
    -----------------------------------------------------------------
    MOB_REFLECT = {
        name = "荆棘反伤", desc = "受击反弹所受伤害的25%~40%", weight = 2, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() then return end
            if not attacker.components.health then return end
            if IsImmuneReflect(attacker) then return end
            local ratio = tier == "boss" and 0.25 or 0.4
            local reflect = math.min(damage * ratio * mult, REFLECT_CAP)
            if reflect > 0 then
                DealDamage(inst, attacker, reflect, "mob_reflect")
            end
        end,
    },

    -----------------------------------------------------------------
    -- 时段猎手 — 白天/黄昏/夜晚差异化增伤（移植自 sunlightStrike/afterglowStrike/nightMenace）
    -----------------------------------------------------------------
    MOB_TIMED = {
        name = "时段猎手", desc = "攻击附加时段伤害:白天30%/黄昏40%/夜晚50%", weight = 2, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            local ratio = 0.4
            local ws = _G.TheWorld and _G.TheWorld.state
            if ws then
                if ws.isday then
                    ratio = 0.3
                elseif ws.isdusk then
                    ratio = 0.4
                elseif ws.isnight then
                    ratio = 0.5
                end
            end
            local base = inst.components.combat and inst.components.combat.defaultdamage or 10
            DealDamage(inst, target, base * ratio * mult, "mob_timed")
        end,
    },

    -----------------------------------------------------------------
    -- 日益强大 — 每日增加血量上限（移植自 day_add_health）
    -----------------------------------------------------------------
    MOB_DAYGROWTH = {
        name = "日益强大", desc = "每过一天增加血量上限（Boss +400/普通怪 +150，上限初始150%）", weight = 1, boss_only = false,
        on_apply = function(inst, tier, mult, state)
            local ws = _G.TheWorld and _G.TheWorld.state
            state._last_day = ws and ws.cycles or 0
            state._per_day = tier == "boss" and 400 * mult or 150 * mult
            local health = inst.components.health
            state._cap = health and health.maxhealth * 1.5 or 0
        end,
        on_update = function(inst, tier, mult, state)
            local health = inst.components.health
            if not health then return end
            -- 惰性计算上限: on_apply 时 health 可能未就绪
            if not state._cap or state._cap <= 0 then
                state._cap = health.maxhealth * 1.5
            end
            local ws = _G.TheWorld and _G.TheWorld.state
            local day = ws and ws.cycles or 0
            if day <= state._last_day then return end
            local passed = day - state._last_day
            state._last_day = day
            local old_pct = health:GetPercent()
            health.maxhealth = math.min(health.maxhealth + state._per_day * passed, state._cap)
            if health.maxhealth > 0 then
                health:SetPercent(math.min(old_pct, 1))
            end
        end,
        update_period = 5,
    },

    -----------------------------------------------------------------
    -- 冰火两重天 — 受击给攻击者挂温度/湿度 debuff（移植自 hitAddCold/hitAddHot/hitAddMoisture）
    -----------------------------------------------------------------
    MOB_CLIMATE = {
        name = "冰火两重天", desc = "受击概率使攻击者寒冷/灼热/潮湿", weight = 2, boss_only = false,
        on_attacked = function(inst, attacker, damage, tier, mult, state)
            if not attacker or not attacker:IsValid() then return end
            if attacker.components.temperature then
                if math.random() < 0.3 then
                    attacker.components.temperature:DoDelta(-20)
                end
                if math.random() < 0.3 then
                    attacker.components.temperature:DoDelta(20)
                end
            end
            if math.random() < 0.3 and attacker.components.moisture then
                attacker.components.moisture:DoDelta(20)
            end
        end,
    },

    -----------------------------------------------------------------
    -- 恐惧威压 — 攻击使目标持续掉san（移植自 addTargetDamage → monster_add_target_damage）
    -----------------------------------------------------------------
    MOB_FEAR = {
        name = "恐惧威压", desc = "攻击30%概率使目标精神持续受创（10秒）", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if not target.components.sanity then return end
            if math.random() > 0.3 then return end
            -- 去重: 重复触发覆盖旧链，避免多层叠加掉san
            state._drain_id = (state._drain_id or 0) + 1
            local my_id = state._drain_id
            local left = 10
            local function drain()
                if state._drain_id ~= my_id then return end
                if not target:IsValid() or (target.components.health and target.components.health:IsDead()) then return end
                if target.components.sanity then
                    target.components.sanity:DoDelta(-1)
                end
                left = left - 1
                if left > 0 then
                    target:DoTaskInTime(1, drain)
                end
            end
            drain()
        end,
    },

    -----------------------------------------------------------------
    -- 冰封免疫 — 免疫冰冻（移植自 immuneFreeze, Boss 专属）
    -----------------------------------------------------------------
    MOB_FREEZEIMMUNE = {
        name = "冰封免疫", desc = "免疫冰冻效果", weight = 1, boss_only = true,
        on_apply = function(inst, tier, mult, state)
            local freezable = inst.components.freezable
            if freezable then
                freezable.canfreeze = false
                if freezable.SetPercent then
                    freezable:SetPercent(0)
                end
            end
        end,
    },

    -----------------------------------------------------------------
    -- 禁疗诅咒 — 攻击使目标回血抑制（移植自 addSuppressAddHealth）
    -----------------------------------------------------------------
    MOB_SUPPRESS = {
        name = "禁疗诅咒", desc = "攻击30%概率使目标10秒内回血降为10%", weight = 1, boss_only = false,
        on_attack = function(inst, target, tier, mult, state)
            if not IsValidTarget(inst, target) then return end
            if not target.components.health then return end
            if math.random() > 0.3 then return end

            local hhealth = target.components.health
            local st = target
            -- 已挂禁疗则刷新时间
            if st._moon_suppress_task then
                st._moon_suppress_task:Cancel()
            end
            if not st._moon_suppress_hooked then
                st._moon_suppress_hooked = true
                -- 捕获当前 DoDelta 作为原函数（闭包持有，字段被清空/覆盖时兜底，防悬空调用崩溃）
                local origin = hhealth.DoDelta
                st._moon_suppress_origin = origin
                local suppress_hook = function(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
                    if st._moon_suppress_active and delta and delta > 0 then
                        delta = delta * 0.1
                    end
                    -- 兜底：原函数可能因还原失败/被其他 mod 覆盖链而丢失，字段丢失时退回闭包捕获的 origin
                    local o = st._moon_suppress_origin or origin
                    if o then
                        return o(hself, delta, overtime, cause, ignore_invincible, afflicter, ignore_absorb, ...)
                    end
                end
                st._moon_suppress_hook = suppress_hook
                hhealth.DoDelta = suppress_hook
                st:ListenForEvent("onremove", function()
                    -- 还原前校验: 当前 DoDelta 仍是自己装的 hook, 且 health 组件仍存在
                    if st.components and st.components.health
                            and st._moon_suppress_hook
                            and st.components.health.DoDelta == st._moon_suppress_hook
                            and st._moon_suppress_origin then
                        st.components.health.DoDelta = st._moon_suppress_origin
                        -- 还原成功才清空字段（还原失败说明 hook 已被其他 mod 包住，需保留 origin 供链上兜底转发）
                        st._moon_suppress_hooked = false
                        st._moon_suppress_hook = nil
                        st._moon_suppress_origin = nil
                    end
                    -- 无论能否还原都停用禁疗效果，避免被困在链中的 hook 继续压血
                    st._moon_suppress_active = false
                    if st._moon_suppress_task then
                        st._moon_suppress_task:Cancel()
                        st._moon_suppress_task = nil
                    end
                end)
            end
            st._moon_suppress_active = true
            st._moon_suppress_task = st:DoTaskInTime(10, function()
                -- 校验当前 DoDelta 仍是自己装的 hook（防目标自身 damage hook 已先还原）
                if st:IsValid() and st.components and st.components.health
                        and st._moon_suppress_hook
                        and st.components.health.DoDelta == st._moon_suppress_hook
                        and st._moon_suppress_origin then
                    st.components.health.DoDelta = st._moon_suppress_origin
                    -- 还原成功才清空字段（还原失败说明 hook 已被其他 mod 包住，保留字段供链上兜底转发）
                    st._moon_suppress_hooked = false
                    st._moon_suppress_hook = nil
                    st._moon_suppress_origin = nil
                end
                -- 10 秒到期：即使 hook 因被其他 mod 包住而无法拆下，也只原样透传不再压血
                st._moon_suppress_active = false
                st._moon_suppress_task = nil
            end)
        end,
    },
}
