-- 小月亮 UI 面板注入
-- 将 LittleMoonPanel 注入到玩家 HUD

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

AddClassPostConstruct("screens/playerhud", function(self)
    local LittleMoonPanel = _G.require("widgets/little_moon_panel")
    self.little_moon_panel = self:AddChild(LittleMoonPanel(
        self.owner,
        CFG.PROXIMITY_LIMIT,
        CFG.LITTLE_MOON_SCALE,
        CFG.ENABLE_TREASURE,
        CFG.ENABLE_QL_HELPER,
        CFG.ENABLE_AUTO_PICKUP,
        CFG.ENABLE_SUICIDE,
        CFG.DIG_TREASURE_MODE,
        CFG.ENABLE_QUICK_CHAT,
        CFG.ENABLE_DEATH_STATS,
        CFG.ENABLE_MOD_BROWSER
    ))
    self.little_moon_panel:MoveToFront()
end)
