-- 小月亮 物品禁用 限时计时组件
-- 挂在 TheWorld 上,记录 BAN_ITEMS 限时禁用配置生效时的游戏内天数(start_cycle),
-- 通过 OnSave/OnLoad 随世界存档持久化(服务器重启天数不丢,开新档自动重记)
-- 用法: 世界 postinit 回调中 inst:AddComponent("moon_ban_timer"),
--        调用 :GetStartCycle() 首次读取时自动记录起始天数

local MoonBanTimer = Class(function(self, inst)
    self.inst = inst
    self.start_cycle = nil
end)

function MoonBanTimer:GetStartCycle()
    if not self.start_cycle then
        -- 组件由引擎 require 加载(非 modimport 沙箱),无 GLOBAL; self.inst 即 TheWorld
        self.start_cycle = self.inst.state.cycles or 0
    end
    return self.start_cycle
end

function MoonBanTimer:OnSave()
    if self.start_cycle then
        return { start_cycle = self.start_cycle }
    end
    return nil
end

function MoonBanTimer:OnLoad(data)
    if data and type(data.start_cycle) == "number" then
        self.start_cycle = data.start_cycle
    end
end

return MoonBanTimer
