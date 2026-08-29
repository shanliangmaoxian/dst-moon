-- 小月亮 死亡统计 UI 注入
-- 全局变量轮询 + 转发到面板

local _G = GLOBAL

-- 声明全局变量，满足 strict 模式
_G._moon_death_data = nil

AddClassPostConstruct("screens/playerhud", function(self)
    if not _G.MOON_CFG.ENABLE_DEATH_STATS then return end

    local DeathStatsPanel = _G.require("widgets/death_stats_panel")
    local panel = self:AddChild(DeathStatsPanel())
    self.death_stats_panel = panel

    -- 轮询检测 _moon_death_data
    self.inst:DoPeriodicTask(0.1, function()
        local data = _G._moon_death_data
        if data then
            _G._moon_death_data = nil
            panel:OnReceiveData(data)
        end
    end)

	-- 面板可见时每 15 秒自动刷新
	self.inst:DoPeriodicTask(15, function()
		if panel:IsVisible() then
			panel:RequestStats()
		end
	end)
end)
