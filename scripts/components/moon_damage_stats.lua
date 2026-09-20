-- 小月亮 伤害统计组件
-- 挂在玩家实体上，通过 OnSave/OnLoad 随世界存档自动持久化
-- 统计玩家造成的伤害：普伤（攻击管线）/ 真伤（无视护甲直扣）/ 击杀数
-- 世界再生时实体重建，OnLoad 无数据，统计自动归零

local MoonDamageStats = Class(function(self, inst)
    self.inst = inst
    self.normal = 0     -- 普通伤害（走 combat:GetAttacked 管线，护甲/减伤正常生效后的实扣值）
    self.true_dmg = 0   -- 真实伤害（附魔直扣 / HH 穿刺等无视护甲伤害）
    self.kills = 0      -- 击杀数

    -- 轮询等待 userid 就绪后从全局表恢复（换人时 userid 可能尚未设置）
    local function try_restore()
        if not self.inst:IsValid() then return end
        local uid = self.inst.userid
        if uid then
            if not MOON_CFG.DAMAGE_STATS_RESET_ON_SWITCH and _G._moon_damage_counts[uid] then
                local saved = _G._moon_damage_counts[uid]
                self.normal = saved.normal or 0
                self.true_dmg = saved.true_dmg or 0
                self.kills = saved.kills or 0
            end
        else
            self.inst:DoTaskInTime(0, try_restore)
        end
    end
    self.inst:DoTaskInTime(0, try_restore)
end)

function MoonDamageStats:AddNormal(amount)
    self.normal = self.normal + amount
    self:Sync()
end

function MoonDamageStats:AddTrue(amount)
    self.true_dmg = self.true_dmg + amount
    self:Sync()
end

function MoonDamageStats:AddKill()
    self.kills = self.kills + 1
    self:Sync()
end

-- 同步到全局表，换人后仍可恢复
function MoonDamageStats:Sync()
    local uid = self.inst.userid
    if uid then
        _G._moon_damage_counts[uid] = {
            normal = self.normal,
            true_dmg = self.true_dmg,
            kills = self.kills,
        }
    end
end

function MoonDamageStats:GetTotal()
    return self.normal + self.true_dmg
end

function MoonDamageStats:OnSave()
    if self.normal > 0 or self.true_dmg > 0 or self.kills > 0 then
        return { normal = self.normal, true_dmg = self.true_dmg, kills = self.kills }
    end
    return nil
end

function MoonDamageStats:OnLoad(data)
    if data then
        self.normal = data.normal or 0
        self.true_dmg = data.true_dmg or 0
        self.kills = data.kills or 0
        self:Sync()
    end
end

return MoonDamageStats
