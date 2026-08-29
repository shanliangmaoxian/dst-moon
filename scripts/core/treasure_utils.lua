-- 小月亮 宝藏点共享工具
-- 全局数据: _G.MOON_TREASURE_POINTS
-- 全局函数前缀: Moon_

local _G = GLOBAL

-- 宝藏点注册表
_G.MOON_TREASURE_POINTS = {}

function _G.Moon_Say(player, message)
    if player.components.talker then
        player.components.talker:Say(message)
    end
end

function _G.Moon_RegisterTreasurePoint(inst)
    _G.MOON_TREASURE_POINTS[inst] = true
end

function _G.Moon_UnregisterTreasurePoint(inst)
    _G.MOON_TREASURE_POINTS[inst] = nil
end

function _G.Moon_GetTreasureCounts(userid)
    local total_count = 0
    local player_count = 0

    for inst in pairs(_G.MOON_TREASURE_POINTS) do
        if inst:IsValid() then
            total_count = total_count + 1
            if userid ~= nil and inst.moon_owner == userid then
                player_count = player_count + 1
            end
        else
            _G.MOON_TREASURE_POINTS[inst] = nil
        end
    end

    return total_count, player_count
end

function _G.Moon_CountInventoryItems(inv, prefab)
    local count = 0

    local function CountItem(item)
        if item and item.prefab == prefab then
            count = count + (item.components.stackable and item.components.stackable:StackSize() or 1)
        end
    end

    if inv.itemslots then
        for _, item in pairs(inv.itemslots) do
            CountItem(item)
        end
    end

    if inv.equipslots then
        for _, item in pairs(inv.equipslots) do
            CountItem(item)
        end
    end

    CountItem(inv.activeitem)

    local overflow = inv:GetOverflowContainer()
    if overflow and overflow.slots then
        for _, item in pairs(overflow.slots) do
            CountItem(item)
        end
    end

    return count
end
