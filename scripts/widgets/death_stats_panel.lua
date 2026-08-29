-- 小月亮 死亡统计面板（浮动窗口）
-- 可拖动的独立窗口，展示所有玩家的死亡次数排行榜

local Widget = require("widgets/widget")
local Image = require("widgets/image")
local Text = require("widgets/text")
local TEMPLATES = require("widgets/redux/templates")

local POSITION_FILE = "dst_little_moon_death_panel_pos"
local PANEL_WIDTH = 300
local HANDLE_HEIGHT = 30
local PANEL_HEIGHT = 280
local DEFAULT_X = 450
local DEFAULT_Y = -200

local GOLD = { 0.89, 0.76, 0.47, 1 }
local WHITE = { 1, 1, 1, 1 }

local function Clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function ScreenYToTopOffset(y)
	local _, screen_h = TheSim:GetScreenSize()
	return y - screen_h
end

local DeathStatsPanel = Class(Widget, function(self)
	Widget._ctor(self, "DeathStatsPanel")

	self.drag_move_handler = nil
	self.drag_button_handler = nil
	self.drag_offset_x = 0
	self.drag_offset_y = 0

	self:SetScale(1.0)
	self:SetHAnchor(ANCHOR_LEFT)
	self:SetVAnchor(ANCHOR_TOP)
	self:SetPosition(DEFAULT_X, DEFAULT_Y, 0)

	self.background = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.background:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	self.background:SetTint(0.05, 0.05, 0.06, 0.95)
	self.background:SetClickable(false)

	local function AddBorder(w, h, x, y, tint)
		local b = self:AddChild(Image("images/ui.xml", "white.tex"))
		b:SetSize(w, h)
		b:SetTint(unpack(tint))
		b:SetPosition(x, y, 0)
		b:SetClickable(false)
		return b
	end
	AddBorder(PANEL_WIDTH, 2, 0, PANEL_HEIGHT / 2 - 1, GOLD)
	AddBorder(PANEL_WIDTH, 2, 0, -PANEL_HEIGHT / 2 + 1, {0.25, 0.20, 0.14, 0.85})
	AddBorder(2, PANEL_HEIGHT, -PANEL_WIDTH / 2 + 1, 0, {0.25, 0.20, 0.14, 0.85})
	AddBorder(2, PANEL_HEIGHT, PANEL_WIDTH / 2 - 1, 0, {0.25, 0.20, 0.14, 0.85})

	self.handle = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.handle:SetSize(PANEL_WIDTH, HANDLE_HEIGHT)
	self.handle:SetTint(0.15, 0.08, 0.05, 0.98)
	self.handle:SetPosition(0, PANEL_HEIGHT / 2 - HANDLE_HEIGHT / 2, 0)
	self.handle:SetClickable(true)
	self.handle:SetHoverText("拖动面板")
	self.handle.OnMouseButton = function(_, button, down) return self:OnHandleMouseButton(button, down) end

	self.title_text = self.handle:AddChild(Text(CHATFONT, 24, "冒险记录(每15秒刷新一次)"))
	self.title_text:SetColour(unpack(GOLD))
	self.title_text:SetPosition(0, -1, 0)

	self.close_btn = self:AddChild(TEMPLATES.StandardButton(function()
		self:Hide()
	end, "X", { 30, 30 }))
	self.close_btn:SetPosition(PANEL_WIDTH / 2 - 20, PANEL_HEIGHT / 2 - HANDLE_HEIGHT / 2, 0)
	self.close_btn:SetTextSize(18)

	self.list_root = self:AddChild(Widget("death_list_root"))
	self.list_root:SetPosition(5, PANEL_HEIGHT / 2 - HANDLE_HEIGHT - 35)

	self.hint_text = self.list_root:AddChild(Text(CHATFONT, 20, "等待数据中..."))
	self.hint_text:SetPosition(0, -10, 0)
	self.hint_text:SetColour(unpack(WHITE))

	self:LoadPosition()
	self:Hide()
end)

function DeathStatsPanel:RequestStats()
	if self.list_root == nil then return end
	if self.hint_text then self.hint_text:SetString("加载中...") end
	if self.entries then
		for _, entry in ipairs(self.entries) do entry:Kill() end
	end
	self.entries = {}

	if MOD_RPC["LittleMoon"] and MOD_RPC["LittleMoon"]["GetDeathStats"] then
		SendModRPCToServer(MOD_RPC["LittleMoon"]["GetDeathStats"])
	end
end

function DeathStatsPanel:OnReceiveData(data)
	if self.list_root == nil then return end
	if self.hint_text then self.hint_text:Kill(); self.hint_text = nil end
	if self.entries then
		for _, entry in ipairs(self.entries) do entry:Kill() end
	end
	self.entries = {}

	if not data or #data == 0 then
		self.hint_text = self.list_root:AddChild(Text(CHATFONT, 20, "大家都好好的~"))
		self.hint_text:SetPosition(0, -10, 0)
		self.hint_text:SetColour(unpack(WHITE))
		return
	end

	local display_count = math.min(#data, 10)
	for i = 1, display_count do
		local info = data[i]
		local entry_y = -(i - 1) * 20
		local rank_text = i .. ". " .. (info.name or "未知") .. ": " .. info.count .. "次"
		local entry = self.list_root:AddChild(Text(CHATFONT, 18, rank_text))
		entry:SetPosition(0, entry_y, 0)
		entry:SetRegionSize(270, 20)
		entry:SetHAlign(ANCHOR_LEFT)
		entry:SetColour(unpack(WHITE))
		table.insert(self.entries, entry)
	end
end

function DeathStatsPanel:Toggle()
	if self:IsVisible() then
		self:Hide()
	else
		self:Show()
		self:MoveToFront()
		self:RequestStats()
	end
end

function DeathStatsPanel:OnHandleMouseButton(button, down)
	if button ~= MOUSEBUTTON_LEFT then return false end
	if down then self:StartDragging() else self:StopDragging() end
	return true
end

function DeathStatsPanel:StartDragging()
	if self.drag_move_handler ~= nil then return end
	local mouse_pos = TheInput:GetScreenPosition()
	local px, py = self:GetPositionXYZ()
	self.drag_offset_x = px - mouse_pos.x
	self.drag_offset_y = py - ScreenYToTopOffset(mouse_pos.y)
	self:MoveToFront()
	self.drag_move_handler = TheInput:AddMoveHandler(function(x, y) self:UpdateDrag(x, y) end)
	self.drag_button_handler = TheInput:AddMouseButtonHandler(function(bid, down)
		if bid == MOUSEBUTTON_LEFT and not down then self:StopDragging() end
	end)
	self:UpdateDrag(mouse_pos.x, mouse_pos.y)
end

function DeathStatsPanel:UpdateDrag(mx, my)
	self:SetClampedPos(mx + self.drag_offset_x, ScreenYToTopOffset(my) + self.drag_offset_y)
end

function DeathStatsPanel:SetClampedPos(x, y)
	local sw, sh = TheSim:GetScreenSize()
	self:SetPosition(
		Clamp(x, PANEL_WIDTH / 2, sw - PANEL_WIDTH / 2),
		Clamp(y, -sh + PANEL_HEIGHT / 2, -PANEL_HEIGHT / 2),
		0
	)
end

function DeathStatsPanel:StopDragging()
	if self.drag_move_handler then self.drag_move_handler:Remove(); self.drag_move_handler = nil end
	if self.drag_button_handler then self.drag_button_handler:Remove(); self.drag_button_handler = nil end
	local x, y = self:GetPositionXYZ()
	if json ~= nil then
		TheSim:SetPersistentString(POSITION_FILE, json.encode({x = x, y = y}), false)
	end
end

function DeathStatsPanel:LoadPosition()
	if json == nil then return end
	TheSim:GetPersistentString(POSITION_FILE, function(success, data)
		if success and data and data ~= "" then
			local ok, pos = pcall(json.decode, data)
			if ok and pos and pos.x and pos.y then
				self:SetClampedPos(pos.x, pos.y)
			else
				self:SetClampedPos(DEFAULT_X, DEFAULT_Y)
			end
		else
			self:SetClampedPos(DEFAULT_X, DEFAULT_Y)
		end
	end)
end

function DeathStatsPanel:OnRemoveEntity()
	self:StopDragging()
end

return DeathStatsPanel
