-- 小月亮 物品自动吸入
-- 客户端 RPC + 服务端周期扫描捡起可堆叠物品

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

-- ========================================
-- RPC: 客户端开关同步
-- ========================================
if CFG.ENABLE_AUTO_PICKUP then
    AddModRPCHandler("LittleMoon", "SetAutoPickup", function(player, enabled)
        if player.auto_pickup_enabled ~= nil then
            player.auto_pickup_enabled:set(enabled == true)
        end
    end)
end

-- ========================================
-- 玩家 PostInit: 自动吸入周期任务
-- ========================================
AddPlayerPostInit(function(inst)
    inst.auto_pickup_enabled = _G.net_bool(inst.GUID, "little_moon.auto_pickup_enabled", "autopickupdirty")

    if not _G.TheWorld.ismastersim or not CFG.ENABLE_AUTO_PICKUP then return end

    inst.auto_pickup_enabled:set(CFG.ENABLE_AUTO_PICKUP)

    -- 多人优化：错峰执行
    inst:DoTaskInTime(_G.math.random() * 1, function()
        inst:DoPeriodicTask(1, function()
            if inst.auto_pickup_enabled:value() and inst.components.inventory and not inst:HasTag("playerghost") then
                local x, y, z = inst.Transform:GetWorldPosition()
                local ents = _G.TheSim:FindEntities(x, y, z, CFG.AUTO_PICKUP_RANGE, {"_inventoryitem"}, {"INLIMBO", "catchable", "fire", "minespicup", "spider"})
                local backpack = inst.components.inventory:GetOverflowContainer()
                if not backpack or backpack:IsFull() then return end

                local pickup_count = 0
                local MAX_PICKUP_PER_TICK = 10

                for _, item in _G.ipairs(ents) do
                    if pickup_count >= MAX_PICKUP_PER_TICK then break end
                    if item:IsValid() and item.components.inventoryitem and not item.components.inventoryitem:IsHeld()
                       and item.components.inventoryitem.canbepickedup
                       and not (item.components.burnable and item.components.burnable:IsBurning()) then
                        -- 只有背包里已经有这个东西了，且是可堆叠物品，才吸
                        if backpack:Has(item.prefab, 1) and item.components.stackable then
                            backpack:GiveItem(item, nil, inst:GetPosition())
                            pickup_count = pickup_count + 1
                        end
                    end
                end
            end
        end)
    end)
end)
