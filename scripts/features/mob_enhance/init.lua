-- 小月亮 怪物强化模块 — 入口
-- 加载附魔池 + 注册所有强化怪物
-- 与现有附魔体系完全解耦，独立运作
--
-- 加载条件: ENABLE_MOB_ENHANCE = true
-- 防御层直接影响怪物血量机制，注意不要与其他修改类模组冲突

local _G = GLOBAL
local CFG = _G.MOON_CFG

-- =====================================================================
-- 0. 配置检查
-- =====================================================================
if not CFG.ENABLE_MOB_ENHANCE then return end

local SpawnPrefab = _G.SpawnPrefab
local TheSim = _G.TheSim
local math = _G.math
local GetTime = _G.GetTime

-- 公共伤害工具（统一 DealDamage + 死亡之舞兼容限流），需先于两个附魔池加载
modimport("scripts/features/mob_enhance/damage_utils")

-- 加载附魔池定义
modimport("scripts/features/mob_enhance/enchants_pool")
modimport("scripts/features/mob_enhance/enchants_pool_more")  -- 多样性扩展池，合并进主池
local MOON_MOB_ENCHANTS = _G.MOON_MOB_ENCHANTS or {}

-- =====================================================================
-- 1. 难度配置
-- =====================================================================
local DIFFICULTY = {
    easy      = { mult = 0.6, enchant_count = 1 },
    normal    = { mult = 1.0, enchant_count = 3 },
    hard      = { mult = 3.0, enchant_count = 5 },
    nightmare = { mult = 5.0, enchant_count = 7 },
}

local diff_cfg = DIFFICULTY[CFG.MOB_ENHANCE_LEVEL] or DIFFICULTY.normal

-- =====================================================================
-- 2. 怪物分类表
-- =====================================================================

local MOON_MOB_TABLE = {}

-- Boss
local boss_list = {
    "deerclops", "bearger", "moose", "dragonfly", "antlion",
    "beequeen", "klaus", "klaus_sack", "malbatross",
    "toadstool", "toadstool_cap", "toadstool_dark",
    "crabking", "stalker", "stalker_atrium", "stalker_forest",
    "alterguardian_phase1", "alterguardian_phase2", "alterguardian_phase3",
    "alterguardian_phase1_lunarrift", "alterguardian_phase4_lunarrift",
    "minotaur", "spiderqueen", "warg",
    "eyeofterror", "twinofterror1", "twinofterror2",
    "shadow_rook", "shadow_knight", "shadow_bishop", "lordfruitfly",
    "daywalker", "daywalker2",
    "worm_boss",
    "mutateddeerclops", "mutatedbearger", "mutatedwarg",
    "vault_pillar_guard",
}
for _, name in ipairs(boss_list) do
    MOON_MOB_TABLE[name] = { tier = "boss" }
end

-- 普通战斗怪物
local normal_list = {
    "leif", "leif_sparse",
    "hound", "firehound", "icehound", "moonhound", "mutatedhound", "clayhound",
    "spider", "spider_warrior", "spider_hider", "spider_spitter", "spider_mutated", "spider_water",
    "spider_moon", "spider_healer",
    "pigman", "pigguard", "werepig", "moonpig", "bunnyman", "merm", "mermguard",
    "tentacle", "tentacle_pillar", "tentacle_pillar_arm",
    "frog", "mosquito", "bat",
    "cookiecutter", "shark", "gnarwail",
    "lavae",
    "nightmarebeak", "crawlingnightmare", "crawlinghorror", "terrorbeak",
    "slurper", "worm", "krampus",
    "walrus",
    "beefalo", "koalefant_summer", "koalefant_winter", "lightninggoat",
    "penguin", "mutated_penguin", "tallbird", "teenbird",
    "mossling", "birchnutdrake",
    "knight", "knight_nightmare", "bishop", "bishop_nightmare", "rook", "rook_nightmare",
    "eyeplant",
    "stalker_minion1", "stalker_minion2",
    "eyeofterror_mini", "eyeofterror_mini_grounded",
    "claywarg", "gingerbreadwarg", "spat",
}
for _, name in ipairs(normal_list) do
    MOON_MOB_TABLE[name] = { tier = "normal" }
end

-- =====================================================================
-- 3. 附魔池（定义在 enchants_pool.lua 中）
-- =====================================================================
-- 已通过 modimport 加载到 _G.MOON_MOB_ENCHANTS

-- =====================================================================
-- 3.5 排除列表（MOB_ENHANCE_EXCLUDE: Lua 表，如 {'pigman','月半','哎哟'}）
-- 支持两种写法:
--   1. 怪物 prefab 名（如 pigman/hound）→ 该怪物不强化
--   2. 附魔 ID 或附魔中文名（如 MOB_YUEBAN / 月半）→ 抽取时禁用该附魔
-- =====================================================================
local exclude_mobs = {}
local exclude_enchants = {}
local exclude_cfg = CFG.MOB_ENHANCE_EXCLUDE
if type(exclude_cfg) == "table" then
    for _, name in ipairs(exclude_cfg) do
        if name and name ~= "" then
            exclude_mobs[tostring(name)] = true       -- 怪物 prefab 匹配
            exclude_enchants[tostring(name)] = true   -- 附魔 ID / 中文名匹配
        end
    end
end

-- =====================================================================
-- 4. 抽取逻辑
-- =====================================================================
local function RollEnchants(tier)
    local pool = {}
    for eid, cfg in pairs(MOON_MOB_ENCHANTS) do
        if cfg.boss_only and tier ~= "boss" then
            -- skip: boss-only 不掉给普通怪
        elseif exclude_enchants[eid] or exclude_enchants[cfg.name] then
            -- skip: 用户禁用的词缀（按 ID 或中文名匹配）
        else
            table.insert(pool, { id = eid, weight = cfg.weight or 1 })
        end
    end

    -- 附魔几率（独立配置项 MOB_ENCHANT_CHANCE）: 未通过则本次不附魔
    local chance = CFG.MOB_ENCHANT_CHANCE or 1.0
    if chance < 1.0 and math.random() > chance then
        return {}
    end

    -- 确定抽取数量（Boss 与普通怪一致，由难度直接决定，不再叠加额外附魔）
    local count = diff_cfg.enchant_count  -- easy 1 / normal 3 / hard 5 / nightmare 7
    count = math.min(count, #pool)

    if count <= 0 then return {} end

    -- 加权不放回抽取
    local result = {}
    local remaining = {}
    for _, v in ipairs(pool) do
        table.insert(remaining, { id = v.id, weight = v.weight })
    end

    for _ = 1, count do
        if #remaining == 0 then break end

        local total_weight = 0
        for _, v in ipairs(remaining) do
            total_weight = total_weight + v.weight
        end

        local roll = math.random() * total_weight
        local accum = 0
        for i, v in ipairs(remaining) do
            accum = accum + v.weight
            if roll <= accum then
                table.insert(result, v.id)
                table.remove(remaining, i)
                break
            end
        end
    end

    return result
end

-- =====================================================================
-- 5. 注册到所有目标怪物
-- =====================================================================
for prefab_name, info in pairs(MOON_MOB_TABLE) do
    -- 按类型过滤
    if exclude_mobs[prefab_name] then
        -- 用户指定排除（不强化）
    elseif info.tier == "boss" and not CFG.MOB_ENHANCE_BOSS then
        -- 不强化
    elseif info.tier == "normal" and not CFG.MOB_ENHANCE_NORMAL then
        -- 不强化
    else
        AddPrefabPostInit(prefab_name, function(inst)
        -- 等待组件就绪
        inst:DoTaskInTime(0, function()
            if not inst:IsValid() then return end
            if inst.components.moon_mob_enhance then return end  -- 防重复

            local tier = info.tier or "normal"

            -- 添加组件
            local comp = inst:AddComponent("moon_mob_enhance")

            -- 抽取附魔
            local enchant_ids = RollEnchants(tier)

            -- 防御层配置（总开关关闭或检测到让我瞧瞧则全部禁用）
            -- 检测 3700206644（让我瞧瞧）是否开启
            local letmeseemod = _G.Moon_IsModEnabled and _G.Moon_IsModEnabled("workshop-3700206644") or false

            -- 防御层配置（总开关关闭或检测到让我瞧瞧则全部禁用）
            local defense_enabled = CFG.ENABLE_MOB_DEFENSE and not letmeseemod
            local defense_cfg = {}
            if defense_enabled then
                defense_cfg = {
                    mitigation = CFG.MOB_DEFENSE_MITIGATION or false,
                    dynamic    = CFG.MOB_DEFENSE_DYNAMIC or false,
                    cap        = CFG.MOB_DEFENSE_CAP or false,
                    freq       = CFG.MOB_DEFENSE_FREQ or false,
                    scope      = CFG.MOB_DEFENSE_SCOPE or "all",
                }
            end

            -- 启动
            local runtime_hh = _G.Moon_IsHHEnabled and _G.Moon_IsHHEnabled() or false
            comp:OnStart(tier, diff_cfg.mult, enchant_ids, MOON_MOB_ENCHANTS, runtime_hh, defense_cfg, letmeseemod)
        end)
    end)
    end
end
