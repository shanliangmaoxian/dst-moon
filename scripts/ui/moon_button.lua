-- 小月亮 UI 按钮
-- 左上角可拖动图标，点击打开助手面板

local _G = GLOBAL
local Widget = _G.require("widgets/widget")
local ImageButton = _G.require("widgets/imagebutton")

local POSITION_FILE = "dst_little_moon_position"

local function ScreenYToTopOffset(y)
    local _, screen_h = _G.TheSim:GetScreenSize()
    return y - screen_h
end

local function Clamp(value, min_value, max_value)
    return _G.math.max(min_value, _G.math.min(max_value, value))
end

local function SetClampedButtonPosition(widget, x, y)
    local screen_w, screen_h = _G.TheSim:GetScreenSize()
    local size = 64 * 1.4
    widget:SetPosition(
        Clamp(x, size / 2, screen_w - size / 2),
        Clamp(y, -screen_h + size / 2, -size / 2),
        0
    )
end

AddClassPostConstruct("widgets/controls", function(self)
    self.moon_root = self:AddChild(Widget("moon_root"))
    self.moon_root:SetHAnchor(_G.ANCHOR_LEFT)
    self.moon_root:SetVAnchor(_G.ANCHOR_TOP)

    local tex = "lunar_seed.tex"
    local atlas = _G.GetInventoryItemAtlas(tex) or "images/inventoryimages.xml"
    self.moon_btn = self.moon_root:AddChild(ImageButton(atlas, tex))
    self.moon_btn:SetScale(1.4)

    -- 默认位置
    local default_x, default_y = 80, -100
    self.moon_btn:SetPosition(default_x, default_y)

    -- 拖动相关变量
    self.moon_btn.drag_move_handler = nil
    self.moon_btn.drag_button_handler = nil

    self.moon_btn.StartDragging = function(widget)
        if widget.drag_move_handler ~= nil then return end

        local mouse_pos = _G.TheInput:GetScreenPosition()
        local pos_x, pos_y = widget:GetPositionXYZ()

        widget.drag_offset_x = pos_x - mouse_pos.x
        widget.drag_offset_y = pos_y - ScreenYToTopOffset(mouse_pos.y)

        widget.drag_move_handler = _G.TheInput:AddMoveHandler(function(x, y)
            SetClampedButtonPosition(widget, x + widget.drag_offset_x, ScreenYToTopOffset(y) + widget.drag_offset_y)
        end)

        widget.drag_button_handler = _G.TheInput:AddMouseButtonHandler(function(button_id, is_down)
            if button_id == _G.MOUSEBUTTON_RIGHT and not is_down then
                widget:StopDragging()
            end
        end)
    end

    self.moon_btn.StopDragging = function(widget)
        if widget.drag_move_handler ~= nil then
            widget.drag_move_handler:Remove()
            widget.drag_move_handler = nil
        end
        if widget.drag_button_handler ~= nil then
            widget.drag_button_handler:Remove()
            widget.drag_button_handler = nil
        end

        -- 保存位置
        if _G.json ~= nil then
            local x, y = widget:GetPositionXYZ()
            _G.TheSim:SetPersistentString(POSITION_FILE, _G.json.encode({x = x, y = y}), false)
        end
    end

    self.moon_btn.LoadPosition = function(widget)
        if _G.json == nil then
            SetClampedButtonPosition(widget, default_x, default_y)
            return
        end

        _G.TheSim:GetPersistentString(POSITION_FILE, function(success, data)
            if success and data and data ~= "" then
                local ok, pos = _G.pcall(_G.json.decode, data)
                if ok and pos and pos.x and pos.y then
                    SetClampedButtonPosition(widget, pos.x, pos.y)
                else
                    SetClampedButtonPosition(widget, default_x, default_y)
                end
            else
                SetClampedButtonPosition(widget, default_x, default_y)
            end
        end)
    end

    self.moon_btn.OnRemoveEntity = function(widget)
        widget:StopDragging()
    end

    -- 右键触发拖动
    local old_OnControl = self.moon_btn.OnControl
    self.moon_btn.OnControl = function(widget, control, down)
        if control == _G.CONTROL_SECONDARY then
            if down then
                widget:StartDragging()
            end
            return true
        end
        if old_OnControl then
            return old_OnControl(widget, control, down)
        end
        return ImageButton.OnControl(widget, control, down)
    end

    -- 加载保存的位置
    self.moon_btn:LoadPosition()

    self.moon_btn:SetOnClick(function()
        if _G.ThePlayer and _G.ThePlayer.HUD and _G.ThePlayer.HUD.little_moon_panel then
            _G.ThePlayer.HUD.little_moon_panel:Toggle()
        end
    end)
    self.moon_btn:SetHoverText("小月亮助手 (右键拖动)", { offset_y = 40 })
end)
