-- 小月亮 怪物强化 — 公共伤害工具
-- 统一附魔伤害出口（DealDamage），含「死亡之舞」兼容限流
-- 由 init.lua 先于两个附魔池 modimport，两个附魔池共用本工具

local _G = GLOBAL
local GetTime = _G.GetTime

-- 限流状态（模块私有 upvalue，不污染全局）
local cooldowns = {}
local cooldown_ttl = 0.5    -- 同一怪物对同一死亡之舞玩家的附魔伤害冷却（秒）
local sweep_counter = 0

-- 目标是否携带「死亡之舞」效果（德·忍耐 附带，存于 HH 附魔框架效果系统）
-- HH 框架的 API 全局名是被混淆的梗字符串（Ciallo～(∠・ω< )⌒★），硬编码脆弱：
-- 框架不存在 / 改名 / 调用出错时一律视为没有 → 不限流（pcall 兜底，绝不崩溃）
-- 注意必须用 rawget 读取：该全局 key 可能不存在，裸 _G[...] 会触发 strict.lua 未声明报错
local function HasDanceOfDeath(target)
    if not target then return false end
    local hh_api = _G.rawget(_G, "Ciallo～(∠・ω< )⌒★")
    if not (hh_api and hh_api.HasEffect) then return false end
    local ok, res = pcall(hh_api.HasEffect, target, "DanceOfDeath")
    return ok and res == true
end

local function IsValidTarget(inst, target)
    return target and target:IsValid()
        and target ~= inst
        and target.components.health
        and not target.components.health:IsDead()
end

-- 定期清扫过期条目，防止长会话内存累积（key 按 GUID 唯一且不复用）
local function Sweep(now)
    for key, last in pairs(cooldowns) do
        if now - last >= cooldown_ttl then
            cooldowns[key] = nil
        end
    end
end

-- 统一附魔伤害入口（cause 沿用各附魔原 cause，默认 "mob_enchant"）
-- 仅当目标带「死亡之舞」时才限流：把同一怪物对同一玩家的多次附魔伤害
-- 压成每 0.5s 一次，防止累积触发死亡之舞的流血池（overtime 扣血绕过护甲）
_G.Moon_MobEnhanceDealDamage = function(source, target, damage, cause)
    if not IsValidTarget(source, target) then return end

    if target:HasTag("player") and HasDanceOfDeath(target)
        and source.GUID and target.GUID then
        local key = source.GUID .. "_" .. target.GUID
        local now = GetTime()
        if cooldowns[key] and now - cooldowns[key] < cooldown_ttl then
            return
        end
        cooldowns[key] = now

        -- 每 64 次调用清扫一次过期条目
        sweep_counter = sweep_counter + 1
        if sweep_counter >= 64 then
            sweep_counter = 0
            Sweep(now)
        end
    end

    target.components.health:DoDelta(-damage, false, cause or "mob_enchant")
end
