-- 小月亮 死亡计数组件
-- 数据挂在玩家实体上，通过 OnSave/OnLoad 随世界存档自动持久化
-- 世界再生时实体重建，OnLoad 无数据，计数自动归零

local MoonDeathCounter = Class(function(self, inst)
    self.inst = inst
    self.count = 0

    -- 轮询等待 userid 就绪后从全局表恢复（换人时 userid 可能尚未设置）
    local function try_restore()
        if not self.inst:IsValid() then return end
        local uid = self.inst.userid
        if uid then
            if not MOON_CFG.DEATH_STATS_RESET_ON_SWITCH and _G._moon_death_counts[uid] then
                self.count = _G._moon_death_counts[uid]
            end
        else
            self.inst:DoTaskInTime(0, try_restore)
        end
    end
    self.inst:DoTaskInTime(0, try_restore)

    self.inst:ListenForEvent("death", function()
        -- 3 秒冷却防连续伤害多次计数
        local now = GetTime()
        if self._last_death_time and now - self._last_death_time < 3 then
            return
        end
        self._last_death_time = now
        self.count = self.count + 1

        -- 同步到全局表，换人后仍可恢复
        local uid = self.inst.userid
        if uid then
            _G._moon_death_counts[uid] = self.count
        end

        if MOON_CFG and MOON_CFG.ENABLE_DEATH_ANNOUNCE then
            TheNet:Announce("玩家 " .. (self.inst.name or self.inst.userid or "?") .. " 倒下了 (第 " .. self.count .. " 次)")
        end
    end)
end)

function MoonDeathCounter:OnSave()
    return self.count > 0 and { count = self.count } or nil
end

function MoonDeathCounter:OnLoad(data)
    if data and data.count then
        self.count = data.count
        local uid = self.inst.userid
        if uid then
            _G._moon_death_counts[uid] = self.count
        end
    end
end

function MoonDeathCounter:GetCount()
    return self.count
end

return MoonDeathCounter
