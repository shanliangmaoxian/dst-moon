-- 小月亮 死亡统计
-- 使用组件 moon_death_counter 追踪每个玩家的死亡次数
-- 数据随玩家实体 OnSave/OnLoad 持久化，世界再生自动清零

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_DEATH_STATS then return end

_G._moon_death_data = nil
_G._moon_death_counts = {}

AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    inst:AddComponent("moon_death_counter")
end)

-- 注册客户端 RPC（让服务端 CLIENT_MOD_RPC 表有入口）
AddClientModRPCHandler("LittleMoon", "DeathStatsResponse", function(json_data)
    if _G.json == nil then return end
    local ok, data = _G.pcall(_G.json.decode, json_data)
    if ok and type(data) == "table" then
        _G._moon_death_data = data
    end
end)

-- 请求时动态查找 RPC ID（避免 modimport 顶层表未就绪）
AddModRPCHandler("LittleMoon", "GetDeathStats", function(player)
    if not _G.TheWorld.ismastersim then return end

    local result = {}
    for _, v in ipairs(_G.AllPlayers) do
        if v.components.moon_death_counter then
            local count = v.components.moon_death_counter:GetCount()
            if count > 0 then
                table.insert(result, { name = v.name or v.userid, count = count })
            end
        end
    end
    table.sort(result, function(a, b) return a.count > b.count end)

    local rpc = _G.CLIENT_MOD_RPC
    if rpc and rpc["LittleMoon"] and rpc["LittleMoon"]["DeathStatsResponse"] then
        _G.SendModRPCToClient(rpc["LittleMoon"]["DeathStatsResponse"], player.userid, _G.json.encode(result))
    end
end)
