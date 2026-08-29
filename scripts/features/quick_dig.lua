-- 小月亮 一键挖宝
-- 跳过宝藏点放置和挖掘动画，消耗卷轴直接出怪

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if CFG.DIG_TREASURE_MODE <= 0 then return end

AddModRPCHandler("LittleMoon", "QuickDig", function(player, count)
    local inv = player.components.inventory
    if not inv or not player.userid then return end

    -- 防止回调重入
    if player._quick_dig_in_progress then
        return
    end
    player._quick_dig_in_progress = true

    local count_num = _G.math.floor(_G.tonumber(count) or 0)
    if count_num < 1 then
        _G.Moon_Say(player, "请选择挖宝数量。")
        player._quick_dig_in_progress = nil
        return
    end

    local player_pos = player:GetPosition()

    -- 怪物数量检查
    local nearby_ents = _G.TheSim:FindEntities(
        player_pos.x, player_pos.y, player_pos.z, 20,
        nil, {"INLIMBO", "player", "FX", "NOCLICK", "DECOR", "INVALID"}
    )
    local monster_count = 0
    for _, ent in _G.ipairs(nearby_ents) do
        if ent.components.combat and ent.components.health and not ent:HasTag("player") then
            monster_count = monster_count + 1
        end
    end
    if monster_count > CFG.MAX_NEARBY_MONSTERS then
        _G.Moon_Say(player, _G.string.format("周边怪物太多了(%d只)，先清理一下", monster_count))
        player._quick_dig_in_progress = nil
        return
    end

    -- 卷轴检查
    local cost_prefab = "hh_treasure_tally"
    local current_scrolls = _G.Moon_CountInventoryItems(inv, cost_prefab)
    if current_scrolls <= 0 then
        _G.Moon_Say(player, "背包里没有寻宝图卷轴。")
        player._quick_dig_in_progress = nil
        return
    end

    -- 计算实际可挖数量
    local actual_count = _G.math.min(count_num, current_scrolls)

    -- 执行挖宝
    local radius = _G.math.max(3, actual_count / 4)
    local spawned = 0
    for i = 1, actual_count do
        local angle = i * (2 * _G.math.pi / actual_count)
        local offset = _G.Vector3(_G.math.cos(angle) * radius, 0, _G.math.sin(angle) * radius)
        local spawn_pos = player_pos + offset

        if _G.TheWorld.Map:IsVisualGroundAtPoint(spawn_pos.x, spawn_pos.y, spawn_pos.z)
            and #_G.TheSim:FindEntities(spawn_pos.x, spawn_pos.y, spawn_pos.z, 1.5, nil, {"INLIMBO"}, {"structure", "wall"}) == 0 then
            local treasure = _G.SpawnPrefab("hh_treasure_build")
            if treasure then
                treasure.Transform:SetPosition(spawn_pos:Get())
                treasure.moon_owner = player.userid
                treasure:AddTag("moon_owner_" .. _G.tostring(player.userid))
                _G.Moon_RegisterTreasurePoint(treasure)

                -- 立刻挖掉
                if treasure.components.workable then
                    treasure.components.workable:Destroy(player)
                    spawned = spawned + 1
                else
                    treasure:Remove()
                end
            end
        end
    end

    if spawned > 0 then
        inv:ConsumeByName(cost_prefab, spawned)
        _G.Moon_Say(player, _G.string.format("一键挖宝完成！挖了 %d 个宝藏", spawned))
    else
        _G.Moon_Say(player, "挖宝失败，请重试。")
    end
    player._quick_dig_in_progress = nil
end)
