-- 小月亮 宝藏点核心逻辑
-- hh_treasure_build PostInit + 召唤 RPC

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

-- ========================================
-- hh_treasure_build 预制体初始化
-- ========================================
AddPrefabPostInit("hh_treasure_build", function(inst)
    inst:AddTag("hh_treasure_build")
    _G.Moon_RegisterTreasurePoint(inst)
    inst:ListenForEvent("onremove", _G.Moon_UnregisterTreasurePoint)

    if _G.TheWorld.ismastersim then
        -- 存档保存与读取
        local old_OnSave = inst.OnSave
        inst.OnSave = function(inst, data)
            if old_OnSave then old_OnSave(inst, data) end
            data.moon_owner = inst.moon_owner
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(inst, data)
            if old_OnLoad then old_OnLoad(inst, data) end
            if data and data.moon_owner then
                inst.moon_owner = data.moon_owner
                inst:AddTag("moon_owner_" .. _G.tostring(data.moon_owner))
            end
        end

        -- 过期清理计时
        if CFG.EXPIRY_TIME > 0 then
            inst:DoTaskInTime(CFG.EXPIRY_TIME, function(i)
                if i:IsValid() then
                    local fx = _G.SpawnPrefab("small_puff")
                    if fx then fx.Transform:SetPosition(i.Transform:GetWorldPosition()) end
                    i:Remove()
                end
            end)
        end
    end
end)

-- ========================================
-- 召唤宝藏点 RPC
-- ========================================
if not CFG.ENABLE_TREASURE then return end

AddModRPCHandler("LittleMoon", "Summon", function(player, count)
    local inv = player.components.inventory
    if not inv or not player.userid then return end

    local count_num = _G.math.floor(_G.tonumber(count) or 1)
    if count_num < 1 then
        _G.Moon_Say(player, "召唤数量无效。")
        return
    end

    local player_pos = player:GetPosition()
    local cost_prefab = "hh_treasure_tally"
    local total_points, my_points_count = _G.Moon_GetTreasureCounts(player.userid)

    -- 全图总数校验
    if total_points >= CFG.GLOBAL_LIMIT then
        _G.Moon_Say(player, "全服宝藏点已达上限(" .. CFG.GLOBAL_LIMIT .. ")")
        return
    end

    -- 个人上限校验
    if my_points_count >= CFG.PLAYER_LIMIT then
        _G.Moon_Say(player, "你的宝藏点已达个人上限(" .. CFG.PLAYER_LIMIT .. ")")
        return
    end

    -- 局部密度校验
    local near_ents = _G.TheSim:FindEntities(player_pos.x, player_pos.y, player_pos.z, 20, {"hh_treasure_build"})
    local allowed_by_density = _G.math.max(0, CFG.PROXIMITY_LIMIT - #near_ents)

    if allowed_by_density <= 0 then
        _G.Moon_Say(player, "这里太挤了(局部上限" .. CFG.PROXIMITY_LIMIT .. "个)")
        return
    end

    -- 背包卷轴校验
    local current_scrolls = _G.Moon_CountInventoryItems(inv, cost_prefab)

    -- 执行召唤
    local summon_count = _G.math.min(count_num, current_scrolls)
    summon_count = _G.math.min(summon_count, allowed_by_density)
    summon_count = _G.math.min(summon_count, CFG.PLAYER_LIMIT - my_points_count)
    summon_count = _G.math.min(summon_count, CFG.GLOBAL_LIMIT - total_points)

    if summon_count > 0 then
        local radius = _G.math.max(3, summon_count / 4)
        local spawned_actual = 0

        for i = 1, summon_count do
            local angle = i * (2 * _G.math.pi / summon_count)
            local offset = _G.Vector3(_G.math.cos(angle) * radius, 0, _G.math.sin(angle) * radius)
            local spawn_pos = player_pos + offset

            -- 地皮检测
            if _G.TheWorld.Map:IsVisualGroundAtPoint(spawn_pos.x, spawn_pos.y, spawn_pos.z)
                and #_G.TheSim:FindEntities(spawn_pos.x, spawn_pos.y, spawn_pos.z, 1.5, nil, {"INLIMBO"}, {"structure", "wall"}) == 0 then
                local treasure = _G.SpawnPrefab("hh_treasure_build")
                if treasure then
                    treasure.Transform:SetPosition(spawn_pos:Get())
                    treasure.moon_owner = player.userid
                    treasure:AddTag("moon_owner_" .. _G.tostring(player.userid))
                    _G.Moon_RegisterTreasurePoint(treasure)

                    local fx = _G.SpawnPrefab("small_puff")
                    if fx then fx.Transform:SetPosition(spawn_pos:Get()) end
                    spawned_actual = spawned_actual + 1
                end
            end
        end

        if spawned_actual > 0 then
            inv:ConsumeByName(cost_prefab, spawned_actual)
            _G.Moon_Say(player, _G.string.format("成功开启 %d 个宝藏点！", spawned_actual))
        else
            _G.Moon_Say(player, "这里没有足够的陆地空间。")
        end
    else
        _G.Moon_Say(player, "无法召唤：卷轴不足或已达上限。")
    end
end)
