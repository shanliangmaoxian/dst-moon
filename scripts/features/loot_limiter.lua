-- 小月亮 掉落物限流
-- SpawnPrefab 全局拦截 + lootdropper 组件精确限流
-- 防止高频垃圾掉落导致服务器卡顿

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_LOOT_LIMITER then return end

local MAX_NON_STACKABLE = CFG.MAX_NON_STACKABLE

-- 判定是否为"高频垃圾掉落物"
local function IsJunkLoot(prefab)
    if not prefab then return false end
    local name = _G.tostring(prefab):lower()
    if name == "minimap" then return false end
    return name:find("blueprint")
        or name:find("recipe")
        or name:find("schematic")
        or name:find("tally")
        or name:find("scroll")
        or name:find("treasure_map")
end

-- ========================================
-- 全局 SpawnPrefab 拦截 (第一时间拦截)
-- ========================================
local _SpawnPrefab = _G.SpawnPrefab
local last_tick = -1
local tick_counts = {}

_G.SpawnPrefab = function(name, ...)
    if _G.TheWorld and _G.TheWorld.ismastersim then
        local tick = _G.TheSim:GetTick()
        if tick ~= last_tick then
            last_tick = tick
            tick_counts = {}
        end

        -- 针对不可堆叠物或垃圾物品进行瞬时限流
        if IsJunkLoot(name) then
            local count = (tick_counts[name] or 0) + 1
            tick_counts[name] = count
            if count > (MAX_NON_STACKABLE * 2) then
                return nil
            end
        end
    end

    local inst = _SpawnPrefab(name, ...)

    -- 辅助限流：针对所有非堆叠物品的空间密度检查 (双重保险)
    if inst and _G.TheWorld and _G.TheWorld.ismastersim then
        inst:DoTaskInTime(0, function(i)
            if not i:IsValid() or not i.Transform then return end
            if (i.components.inventoryitem and not i.components.stackable) or IsJunkLoot(i.prefab) then
                local x, y, z = i.Transform:GetWorldPosition()
                local ents = _G.TheSim:FindEntities(x, y, z, 6)
                local count = 0
                for _, ent in _G.ipairs(ents) do
                    if ent.prefab == i.prefab then count = count + 1 end
                end
                if count > MAX_NON_STACKABLE then i:Remove() end
            end
        end)
    end
    return inst
end

-- ========================================
-- lootdropper 组件精确限流
-- ========================================
AddComponentPostInit("lootdropper", function(self)
    local old_DropLoot = self.DropLoot
    self.DropLoot = function(self, pt, attacker)
        local prefabs = self:GenerateLoot()
        if not prefabs or #prefabs == 0 then
            return old_DropLoot(self, pt, attacker)
        end

        local counts = {}
        for _, v in _G.ipairs(prefabs) do
            counts[v] = (counts[v] or 0) + 1
        end

        if _G.TheWorld.components.lootreplicator ~= nil then
            _G.TheWorld.components.lootreplicator:OnDropLoot(self.inst, prefabs, pt)
        end

        for prefab, total_count in _G.pairs(counts) do
            if total_count > 0 then
                local test_loot = self:SpawnLootPrefab(prefab, pt)
                if test_loot then
                    local is_stackable_test = test_loot.components.stackable ~= nil
                    self.inst:PushEvent("onlootdropped", { loot = test_loot, attacker = attacker })

                    if is_stackable_test then
                        -- 可堆叠：合并
                        local max_size = test_loot.components.stackable.maxsize or 40
                        local current_count = _G.math.min(total_count, max_size)
                        test_loot.components.stackable:SetStackSize(current_count)
                        local remaining = total_count - current_count
                        while remaining > 0 do
                            local next_loot = self:SpawnLootPrefab(prefab, pt)
                            if next_loot then
                                self.inst:PushEvent("onlootdropped", { loot = next_loot, attacker = attacker })
                                local drop_count = _G.math.min(remaining, max_size)
                                next_loot.components.stackable:SetStackSize(drop_count)
                                remaining = remaining - drop_count
                            else break end
                        end
                    else
                        -- 不可堆叠
                        if IsJunkLoot(prefab) then
                            -- 垃圾物品：强制截断
                            local actual_to_drop = _G.math.min(total_count, MAX_NON_STACKABLE)
                            for i = 1, actual_to_drop - 1 do
                                local extra_loot = self:SpawnLootPrefab(prefab, pt)
                                if extra_loot then
                                    self.inst:PushEvent("onlootdropped", { loot = extra_loot, attacker = attacker })
                                else break end
                            end
                        else
                            -- 非垃圾物品：全部生成，不做截断
                            for i = 2, total_count do
                                local extra_loot = self:SpawnLootPrefab(prefab, pt)
                                if extra_loot then
                                    self.inst:PushEvent("onlootdropped", { loot = extra_loot, attacker = attacker })
                                else break end
                            end
                        end
                    end
                else
                    -- SpawnLootPrefab 返回 nil：被其他 Mod 拦截
                    for i = 2, total_count do
                        self:SpawnLootPrefab(prefab, pt)
                    end
                end
            end
        end
    end
end)
