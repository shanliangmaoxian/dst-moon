-- 小月亮 输出统计面板（菜谱书纸底风格，与附魔收集册同款背景）
-- 可拖动窗口，展示所有玩家的伤害输出排行榜
-- 列：玩家 | 普通伤害 | 真实伤害 | 击杀数 | 合计（按合计排序）
-- 底部：全场合计行

local Widget = require("widgets/widget")
local Image = require("widgets/image")
local Text = require("widgets/text")
local ImageButton = require("widgets/imagebutton")

local POSITION_FILE = "dst_little_moon_damage_panel_pos"
local PANEL_WIDTH = 580
local PANEL_HEIGHT = 420
local DEFAULT_X = 380
local DEFAULT_Y = -180

-- 纸底配色（菜谱书为浅色羊皮纸，文字用深色）
local INK = { 0.24, 0.16, 0.08, 1 }        -- 正文墨色
local INK_HEAD = { 0.45, 0.28, 0.08, 1 }   -- 列头深金
local INK_TOTAL = { 0.55, 0.14, 0.08, 1 }  -- 合计列深红
local INK_DIM = { 0.38, 0.30, 0.20, 1 }    -- 次要文字

-- 列布局（x 为相对面板中心）
local COL_NAME = { x = -150, w = 200 }
local COL_NORMAL = { x = -15, w = 110 }
local COL_TRUE = { x = 95, w = 110 }
local COL_KILLS = { x = 180, w = 80 }
local COL_TOTAL = { x = 250, w = 100 }

local MAX_ROWS = 8
local ROW_HEIGHT = 27

local function Clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

-- 大数字缩写：12345678 -> 1234.57万，1.2e8 -> 1.20亿
local function FmtNum(n)
	n = math.floor(n + 0.5)
	if n >= 1e8 then
		return string.format("%.2f亿", n / 1e8)
	elseif n >= 1e4 then
		return string.format("%.1f万", n / 1e4)
	end
	return tostring(n)
end

local function ScreenYToTopOffset(y)
	local _, screen_h = TheSim:GetScreenSize()
	return y - screen_h
end

local DamageStatsPanel = Class(Widget, function(self)
	Widget._ctor(self, "DamageStatsPanel")

	self.drag_move_handler = nil
	self.drag_button_handler = nil
	self.drag_offset_x = 0
	self.drag_offset_y = 0

	self:SetScale(1.0)
	self:SetHAnchor(ANCHOR_LEFT)
	self:SetVAnchor(ANCHOR_TOP)
	self:SetPosition(DEFAULT_X, DEFAULT_Y, 0)

	-- 纸底背景（同附魔收集册 / 烹饪指南），整面即可拖动
	self.background = self:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_menu_bg.tex"))
	self.background:ScaleToSize(PANEL_WIDTH, PANEL_HEIGHT)
	self.background:SetClickable(true)
	self.background:SetHoverText("拖动面板")
	self.background.OnMouseButton = function(_, button, down) return self:OnHandleMouseButton(button, down) end

	self.title_text = self:AddChild(Text(CHATFONT, 28, "输出统计"))
	self.title_text:SetColour(unpack(INK_HEAD))
	self.title_text:SetPosition(0, PANEL_HEIGHT / 2 - 42, 0)

	self.refresh_text = self:AddChild(Text(CHATFONT, 16, "(每15秒自动刷新)"))
	self.refresh_text:SetColour(unpack(INK_DIM))
	self.refresh_text:SetPosition(0, PANEL_HEIGHT / 2 - 68, 0)

	self.close_btn = self:AddChild(ImageButton("images/global_redux.xml", "close.tex"))
	self.close_btn:SetPosition(PANEL_WIDTH / 2 - 26, PANEL_HEIGHT / 2 - 26, 0)
	self.close_btn:SetScale(0.9)
	self.close_btn:SetOnClick(function() self:Hide() end)

	-- 列头（每种伤害的详细标题，与列表同样左移 30）
	self.header_root = self:AddChild(Widget("damage_header"))
	self.header_root:SetPosition(-30, PANEL_HEIGHT / 2 - 105, 0)
	local function AddHeader(col, text, colour, size)
		local t = self.header_root:AddChild(Text(CHATFONT, size or 19, text))
		t:SetPosition(col.x, 0, 0)
		t:SetRegionSize(col.w, 24)
		t:SetHAlign(ANCHOR_MIDDLE)
		t:SetColour(unpack(colour or INK_HEAD))
		return t
	end
	AddHeader(COL_NAME, "玩家")
	AddHeader(COL_NORMAL, "普通伤害")
	AddHeader(COL_TRUE, "真实伤害")
	AddHeader(COL_KILLS, "击杀数")
	AddHeader(COL_TOTAL, "合计", INK_TOTAL)

	-- 行容器（整体左移 30）
	self.list_root = self:AddChild(Widget("damage_list_root"))
	self.list_root:SetPosition(-30, PANEL_HEIGHT / 2 - 140, 0)

	self.hint_text = self.list_root:AddChild(Text(CHATFONT, 20, "等待数据中..."))
	self.hint_text:SetPosition(0, 20, 0)
	self.hint_text:SetColour(unpack(INK))

	self:LoadPosition()
	self:Hide()
end)

function DamageStatsPanel:RequestStats()
	if self.list_root == nil then return end
	if self.hint_text then self.hint_text:SetString("加载中...") end
	self:ClearEntries()
	if MOD_RPC["LittleMoon"] and MOD_RPC["LittleMoon"]["GetDamageStats"] then
		SendModRPCToServer(MOD_RPC["LittleMoon"]["GetDamageStats"])
	end
end

function DamageStatsPanel:ClearEntries()
	if self.entries then
		for _, entry in ipairs(self.entries) do entry:Kill() end
	end
	self.entries = {}
end

function DamageStatsPanel:OnReceiveData(data)
	if self.list_root == nil then return end
	if self.hint_text then self.hint_text:Kill(); self.hint_text = nil end
	self:ClearEntries()

	if not data or #data == 0 then
		self.hint_text = self.list_root:AddChild(Text(CHATFONT, 20, "还没有人打过怪~"))
		self.hint_text:SetPosition(0, 60, 0)
		self.hint_text:SetColour(unpack(INK))
		return
	end

	-- 服务端已按合计排序，这里兜底再排一次
	table.sort(data, function(a, b)
		local ta = a.total or ((a.normal or 0) + (a.true_dmg or 0))
		local tb = b.total or ((b.normal or 0) + (b.true_dmg or 0))
		return ta > tb
	end)

	local display_count = math.min(#data, MAX_ROWS)
	for i = 1, display_count do
		local info = data[i]
		local entry_y = -(i - 1) * ROW_HEIGHT
		local total = info.total or ((info.normal or 0) + (info.true_dmg or 0))

		local function AddCell(col, text, colour, size)
			local t = self.list_root:AddChild(Text(CHATFONT, size or 18, text))
			t:SetPosition(col.x, entry_y, 0)
			t:SetRegionSize(col.w, ROW_HEIGHT)
			t:SetHAlign(ANCHOR_MIDDLE)
			t:SetColour(unpack(colour))
			table.insert(self.entries, t)
			return t
		end

		local name = info.name or "未知"
		if #name > 12 then name = string.sub(name, 1, 12) .. ".." end
		AddCell(COL_NAME, string.format("%d. %s", i, name), INK)
		AddCell(COL_NORMAL, FmtNum(info.normal or 0), INK)
		AddCell(COL_TRUE, FmtNum(info.true_dmg or 0), INK)
		AddCell(COL_KILLS, tostring(info.kills or 0), INK)
		AddCell(COL_TOTAL, FmtNum(total), INK_TOTAL)
	end
end

function DamageStatsPanel:Toggle()
	if self:IsVisible() then
		self:Hide()
	else
		self:Show()
		self:MoveToFront()
		self:RequestStats()
	end
end

function DamageStatsPanel:OnHandleMouseButton(button, down)
	if button ~= MOUSEBUTTON_LEFT then return false end
	if down then self:StartDragging() else self:StopDragging() end
	return true
end

function DamageStatsPanel:StartDragging()
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

function DamageStatsPanel:UpdateDrag(mx, my)
	self:SetClampedPos(mx + self.drag_offset_x, ScreenYToTopOffset(my) + self.drag_offset_y)
end

function DamageStatsPanel:SetClampedPos(x, y)
	local sw, sh = TheSim:GetScreenSize()
	self:SetPosition(
		Clamp(x, PANEL_WIDTH / 2, sw - PANEL_WIDTH / 2),
		Clamp(y, -sh + PANEL_HEIGHT / 2, -PANEL_HEIGHT / 2),
		0
	)
end

function DamageStatsPanel:StopDragging()
	if self.drag_move_handler then self.drag_move_handler:Remove(); self.drag_move_handler = nil end
	if self.drag_button_handler then self.drag_button_handler:Remove(); self.drag_button_handler = nil end
	local x, y = self:GetPositionXYZ()
	if json ~= nil then
		TheSim:SetPersistentString(POSITION_FILE, json.encode({x = x, y = y}), false)
	end
end

function DamageStatsPanel:LoadPosition()
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

function DamageStatsPanel:OnRemoveEntity()
	self:StopDragging()
end

return DamageStatsPanel
