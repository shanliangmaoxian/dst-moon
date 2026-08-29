-- 小月亮：随身换装
-- 在物品栏上方添加"换装"按钮，所有角色均可随时打开更衣室

local _G = GLOBAL
local CFG = _G.MOON_CFG

if not CFG.ENABLE_WARDROBE_ANYWHERE then return end

-- 从沙箱环境捕获 mod API 函数
local AddModRPCHandler         = AddModRPCHandler
local AddClassPostConstruct    = AddClassPostConstruct

-- ============================================================================
-- 服务器 RPC：临时给玩家挂 wardrobe 组件，打开换装界面
-- ============================================================================
AddModRPCHandler("LittleMoon", "OpenWardrobe", function(player)
    if not player then return end

    -- 给玩家临时加上 wardrobe 组件（首次调用）
    if not player.components.wardrobe then
        player:AddComponent("wardrobe")
        player._moon_wardrobe_temp = true
    end

    -- 绑定关闭回调
    local old_closefn = player.components.wardrobe.onclosefn
    player.components.wardrobe.onclosefn = function(inst)
        inst._moon_wardrobe_justclosed = true
        if old_closefn then old_closefn(inst) end
    end

    -- 打开换装界面
    if player.components.wardrobe:CanBeginChanging(player) then
        player.components.wardrobe:BeginChanging(player)
    end
end)

-- ============================================================================
-- 客户端 UI：在物品栏上方挂载"换装"按钮
-- ============================================================================
if _G.TheNet:IsDedicated() then return end

local function add_wardrobe_button(self)
    if not self.owner then return end

    local TextButton = require("widgets/textbutton")
    local btn = self:AddChild(TextButton())
    btn:SetFont(_G.BODYTEXTFONT)
    btn:SetTextSize(36)
    btn:SetTextColour({ 254 / 255, 255 / 255, 0 / 255, 1 })
    btn:SetTextFocusColour({ 254 / 255, 255 / 255, 0 / 255, 1 })
    btn:SetText("快捷换装")
    btn:SetTooltip("随身更衣室")
    btn:SetPosition(0, 210, 0)
    btn:MoveToFront()

    btn:SetOnClick(function()
        _G.SendModRPCToServer(_G.MOD_RPC["LittleMoon"]["OpenWardrobe"])
    end)

    self._moon_wardrobe_btn = btn
end

AddClassPostConstruct("widgets/inventorybar", add_wardrobe_button)
