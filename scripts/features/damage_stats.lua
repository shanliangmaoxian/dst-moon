-- 小月亮 攻击伤害统计
-- 统计每个玩家造成的伤害，按 普伤 / 真伤 / 击杀 三个口径分类：
--   普伤：原版攻击管线 combat:GetAttacked → health:DoDelta(-damage, nil, cause, nil, 攻击者)
--         特征为 DoDelta 携带攻击者实体 afflicter，取实扣值（护甲/减伤结算后）
--   真伤：本 mod 附魔直扣 health:DoDelta(-dmg, false, "xxx_true")，无 afflicter，
--         但同步发生在玩家攻击管线内（onhitother → 附魔回调），用 GetAttacked
--         上下文（_moon_damage_ctx）归因到攻击玩家；HH 框架穿刺等 DoHHDelta
--         走 health:SetVal(cause="hh_true_damage", afflicter=攻击者)，单独识别
-- 数据随玩家实体 OnSave/OnLoad 持久化（moon_damage_stats 组件），世界再生自动清零

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_DAMAGE_STATS then return end

_G._moon_damage_counts = {}   -- userid -> {normal, true_dmg, kills}（换人恢复用）
_G._moon_damage_ctx = false   -- 当前攻击管线中的玩家实体（真伤归因上下文，false=无）

local function IsPlayer(inst)
    return inst ~= nil and inst:IsValid() and inst:HasTag("player")
end

local function GetStats(inst)
    return inst ~= nil and inst.components ~= nil and inst.components.moon_damage_stats or nil
end

-- 组件挂载 + 击杀计数
AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    inst:AddComponent("moon_damage_stats")

    inst:ListenForEvent("killed", function(inst, data)
        local victim = data and data.victim or nil
        if victim ~= nil and victim ~= inst then
            inst.components.moon_damage_stats:AddKill()
        end
    end)
end)

-- 真伤归因上下文：玩家发起攻击（GetAttacked 进入管线）期间，
-- 该玩家对目标的一切直扣（附魔真伤等）都可归因
AddComponentPostInit("combat", function(self)
    local old_GetAttacked = self.GetAttacked
    self.GetAttacked = function(self, attacker, damage, weapon, stimuli, spdamage, ...)
        if damage ~= nil and damage > 0
            and attacker ~= nil and attacker ~= self.inst
            and IsPlayer(attacker) then
            local prev = _G._moon_damage_ctx
            _G._moon_damage_ctx = attacker
            local ok, a, b, c = pcall(old_GetAttacked, self, attacker, damage, weapon, stimuli, spdamage, ...)
            _G._moon_damage_ctx = prev
            if not ok then error(a, 2) end
            return a, b, c
        end
        return old_GetAttacked(self, attacker, damage, weapon, stimuli, spdamage, ...)
    end
end)

AddComponentPostInit("health", function(self)
    -- 普伤 / 附魔真伤：DoDelta 拦截
    local old_DoDelta = self.DoDelta
    self.DoDelta = function(self, amount, overtime, cause, ignore_invincible, afflicter, ...)
        local result = old_DoDelta(self, amount, overtime, cause, ignore_invincible, afflicter, ...)

        if amount ~= nil and amount < 0 and result ~= nil and result < 0
            and overtime ~= true then    -- 排除灼烧/中毒等 overtime 持续伤害
            local victim = self.inst
            local stats = nil

            -- 普伤：afflicter 为攻击者实体（原版攻击管线特征）
            if afflicter ~= nil and afflicter ~= victim and IsPlayer(afflicter) then
                stats = GetStats(afflicter)
                if stats then stats:AddNormal(-result) end
            -- 附魔真伤：无 afflicter 的直扣，处于玩家攻击上下文中才归因
            elseif afflicter == nil then
                local ctx = _G._moon_damage_ctx
                if ctx and ctx ~= victim and ctx:IsValid() then
                    stats = GetStats(ctx)
                    if stats then stats:AddTrue(-result) end
                end
            end
        end
        return result
    end

    -- HH 框架真伤：DoHHDelta 直接走 SetVal(cause="hh_true_damage", afflicter=攻击者)
    -- 不经过 DoDelta，单独拦截；与 DoDelta 拦截的口径互不重叠
    local old_SetVal = self.SetVal
    self.SetVal = function(self, val, cause, afflicter, ...)
        local old_hp = self.currenthealth
        local r = { old_SetVal(self, val, cause, afflicter, ...) }

        if cause == "hh_true_damage" and afflicter ~= nil
            and afflicter ~= self.inst and IsPlayer(afflicter) then
            local dealt = old_hp - self.currenthealth
            if dealt > 0 then
                local stats = GetStats(afflicter)
                if stats then stats:AddTrue(dealt) end
            end
        end
        return unpack(r)
    end
end)

-- 注册客户端 RPC（让服务端 CLIENT_MOD_RPC 表有入口）
AddClientModRPCHandler("LittleMoon", "DamageStatsResponse", function(json_data)
    if _G.json == nil then return end
    local ok, data = _G.pcall(_G.json.decode, json_data)
    if ok and type(data) == "table" then
        _G._moon_damage_data = data
    end
end)

-- 请求时动态查找 RPC ID（避免 modimport 顶层表未就绪）
AddModRPCHandler("LittleMoon", "GetDamageStats", function(player)
    if not _G.TheWorld.ismastersim then return end

    local result = {}
    for _, v in ipairs(_G.AllPlayers) do
        local stats = GetStats(v)
        if stats and stats:GetTotal() > 0 then
            table.insert(result, {
                name = v.name or v.userid,
                normal = stats.normal,
                true_dmg = stats.true_dmg,
                kills = stats.kills,
                total = stats:GetTotal(),
            })
        end
    end
    table.sort(result, function(a, b) return a.total > b.total end)

    local rpc = _G.CLIENT_MOD_RPC
    if rpc and rpc["LittleMoon"] and rpc["LittleMoon"]["DamageStatsResponse"] then
        _G.SendModRPCToClient(rpc["LittleMoon"]["DamageStatsResponse"], player.userid, _G.json.encode(result))
    end
end)
