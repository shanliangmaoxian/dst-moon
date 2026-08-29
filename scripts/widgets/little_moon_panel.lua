local Widget = require("widgets/widget")
local Image = require("widgets/image")
local Text = require("widgets/text")
local TextEdit = require("widgets/textedit")
local Spinner = require("widgets/spinner")
local Screen = require("widgets/screen")
local TEMPLATES = require("widgets/redux/templates")

local POSITION_FILE = "dst_little_moon_merged_position"
local PANEL_WIDTH = 300
local HANDLE_HEIGHT = 30
local SECTION_TITLE_HEIGHT = 26
local DEFAULT_X = 126
local DEFAULT_Y = -150

local GOLD = { 0.89, 0.76, 0.47, 1 }
local DIM_GOLD = { 0.35, 0.28, 0.18, 0.7 }
local WHITE = { 1, 1, 1, 1 }
local DARK_BG = { 0.05, 0.05, 0.06, 0.95 }
local TITLE_BG = { 0.12, 0.10, 0.08, 0.85 }

local CHAT_MSG_SAVE_ID = "dst_little_moon_chat_msgs"
local DEFAULT_CHAT_MSGS = { "嘤嘤嘤", "#roll", "鼠标右键改消息", "鼠标右键改消息" }

local function LoadChatMsgs()
	if json == nil then return DEFAULT_CHAT_MSGS end
	local data = TheSim:GetPersistentString(CHAT_MSG_SAVE_ID)
	if data and data ~= "" then
		local ok, msgs = pcall(json.decode, data)
		if ok and type(msgs) == "table" and #msgs > 0 then
			return msgs
		end
	end
	return DEFAULT_CHAT_MSGS
end

local function SaveChatMsgs(msgs)
	if json ~= nil then
		TheSim:SetPersistentString(CHAT_MSG_SAVE_ID, json.encode(msgs), false)
	end
end

local function Clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function ScreenYToTopOffset(y)
	local _, screen_h = TheSim:GetScreenSize()
	return y - screen_h
end

-- 创建一个可折叠 section 标题条（不含内容，只返回标题条 widget 和 label 引用）
local function CreateSectionTitle(parent, text, onClick)
	local w = parent:AddChild(Widget("title_" .. text))

	local bg = w:AddChild(Image("images/ui.xml", "white.tex"))
	bg:SetSize(PANEL_WIDTH, SECTION_TITLE_HEIGHT)
	bg:SetTint(unpack(TITLE_BG))
	bg:SetClickable(false)

	local line = w:AddChild(Image("images/ui.xml", "white.tex"))
	line:SetSize(PANEL_WIDTH - 40, 1)
	line:SetTint(unpack(DIM_GOLD))
	line:SetPosition(0, -SECTION_TITLE_HEIGHT / 2 + 1, 0)
	line:SetClickable(false)

	local label = w:AddChild(Text(CHATFONT, 20, "▼ " .. text))
	label:SetPosition(-88, 0, 0)
	label:SetColour(unpack(GOLD))
	if label.EnableOutline then label:EnableOutline(true) end

	local click = w:AddChild(Image("images/ui.xml", "white.tex"))
	click:SetSize(PANEL_WIDTH, SECTION_TITLE_HEIGHT)
	click:SetTint(1, 1, 1, 0)
	click:SetClickable(true)
	click:SetHoverText("点击折叠/展开")
	click.OnMouseButton = function(_, button, down)
		if button == MOUSEBUTTON_LEFT and not down then
			onClick()
			return true
		end
		return false
	end

	return w, label
end

local LittleMoonPanel = Class(Widget, function(self, owner, max_summon, scale, enable_treasure, enable_ql_helper, enable_auto_pickup, enable_suicide, dig_treasure_mode, enable_quick_chat, enable_death_stats, enable_mod_browser)
	Widget._ctor(self, "LittleMoonPanel")

	self.owner = owner
	self.max_summon = max_summon or 50
	self.enable_treasure = enable_treasure ~= false
	self.enable_ql_helper = enable_ql_helper ~= false
	self.enable_auto_pickup = enable_auto_pickup ~= false
	self.enable_suicide = enable_suicide ~= false
	self.dig_treasure_mode = dig_treasure_mode or 0
	self.enable_quick_chat = enable_quick_chat ~= false
	self.enable_death_stats = enable_death_stats ~= false
	self.enable_mod_browser = enable_mod_browser ~= false

	self.drag_move_handler = nil
	self.drag_button_handler = nil
	self.drag_offset_x = 0
	self.drag_offset_y = 0

	self.sections = {}

	self:SetScale(scale or 1.0)
	self:SetHAnchor(ANCHOR_LEFT)
	self:SetVAnchor(ANCHOR_TOP)
	self:SetPosition(DEFAULT_X, DEFAULT_Y, 0)

	-- 背景（初始大小由 RebuildLayout 设置）
	self.background = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.background:SetTint(unpack(DARK_BG))
	self.background:SetClickable(false)

	-- 页眉
	self.header = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.header:SetTint(0.15, 0.08, 0.05, 0.98)

	-- 四周边框（由 RebuildLayout 更新位置）
	self.border_top = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.border_top:SetTint(unpack(GOLD))
	self.border_top:SetClickable(false)

	self.border_bottom = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.border_bottom:SetTint(unpack({0.25, 0.20, 0.14, 0.85}))
	self.border_bottom:SetClickable(false)

	self.border_left = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.border_left:SetTint(unpack({0.25, 0.20, 0.14, 0.85}))
	self.border_left:SetClickable(false)

	self.border_right = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.border_right:SetTint(unpack({0.25, 0.20, 0.14, 0.85}))
	self.border_right:SetClickable(false)

	-- 拖动手柄（上方）
	self.handle = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.handle:SetTint(1, 1, 1, 0)
	self.handle:SetClickable(true)
	self.handle:SetHoverText("拖动面板")
	self.handle.OnMouseButton = function(_, button, down) return self:OnHandleMouseButton(button, down) end

	self.drag_dots = self.handle:AddChild(Text(CHATFONT, 24, "::: 小月亮助手 :::"))
	self.drag_dots:SetColour(unpack(GOLD))
	self.drag_dots:SetPosition(0, -1, 0)

	-- 拖动手柄（下方）
	self.handle_bottom = self:AddChild(Image("images/ui.xml", "white.tex"))
	self.handle_bottom:SetTint(1, 1, 1, 0)
	self.handle_bottom:SetClickable(true)
	self.handle_bottom:SetHoverText("拖动面板")
	self.handle_bottom.OnMouseButton = function(_, button, down) return self:OnHandleMouseButton(button, down) end

	self.drag_dots_bottom = self.handle_bottom:AddChild(Text(CHATFONT, 24, "::: 小月亮助手 :::"))
	self.drag_dots_bottom:SetColour(unpack(GOLD))
	self.drag_dots_bottom:SetPosition(0, -1, 0)

	-------------------------------------------------------------------
	-- Mod浏览器 (模组百科, 集成自 demo/dst-mod-browser-master)
	-------------------------------------------------------------------
	if self.enable_mod_browser then
		local title_w, title_label = CreateSectionTitle(self, "模组介绍", function() self:ToggleSection("modbrowser") end)
		local container = self:AddChild(Widget("modbrowser_container"))

		self.mod_browser_btn = container:AddChild(TEMPLATES.StandardButton(function()
			local hud = ThePlayer and ThePlayer.HUD
			if not hud then return end
			if not hud.little_moon_mod_browser then
				local ModBrowserScreen = require("widgets/modbrowserscreen")
				hud.little_moon_mod_browser = hud:AddChild(ModBrowserScreen(ThePlayer))
			end
			local screen = hud.little_moon_mod_browser
			if screen:IsVisible() then
				screen:Hide()
			else
				screen:Show()
				screen:MoveToFront()
			end
		end, "打开模组介绍", { 140, 36 }))
		self.mod_browser_btn:SetPosition(0, 0, 0)
		self.mod_browser_btn:SetTextSize(20)

		table.insert(self.sections, {
			key = "modbrowser",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = 45,
			collapsed = true,
			section_name = "模组介绍",
		})
	end

	-------------------------------------------------------------------
	-- 快捷指令 (QL Helper)
	-------------------------------------------------------------------
	if self.enable_ql_helper then
		local title_w, title_label = CreateSectionTitle(self, "快捷指令", function() self:ToggleSection("ql") end)
		local container = self:AddChild(Widget("ql_container"))

		self.ql_button = container:AddChild(TEMPLATES.StandardButton(function() TheNet:Say("#ql", true) end, "清理返钱 (#ql)", { 120, 36 }))
		self.ql_button:SetPosition(-70, 0, 0)
		self.ql_button:SetTextSize(20)

		self.cleanup_button = container:AddChild(TEMPLATES.StandardButton(function() TheNet:Say("#cleanup", true) end, "清理掉落 (#cleanup)", { 120, 36 }))
		self.cleanup_button:SetPosition(70, 0, 0)
		self.cleanup_button:SetTextSize(20)

		table.insert(self.sections, {
			key = "ql",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = 50,
			collapsed = true,
			section_name = "快捷指令",
		})
	end

	-------------------------------------------------------------------
	-- 自杀
	-------------------------------------------------------------------
	if self.enable_suicide then
		local title_w, title_label = CreateSectionTitle(self, "快捷自杀", function() self:ToggleSection("suicide") end)
		local container = self:AddChild(Widget("suicide_container"))

		self.suicide_button = container:AddChild(TEMPLATES.StandardButton(function()
			if MOD_RPC["LittleMoon"] and MOD_RPC["LittleMoon"]["Suicide"] then
				SendModRPCToServer(MOD_RPC["LittleMoon"]["Suicide"])
			end
		end, "快捷自杀", { 120, 36 }))
		self.suicide_button:SetPosition(0, 0, 0)
		self.suicide_button:SetTextSize(20)

		table.insert(self.sections, {
			key = "suicide",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = 45,
			collapsed = true,
			section_name = "快捷自杀",
		})
	end

	-------------------------------------------------------------------
	-- 宝藏点召唤
	-------------------------------------------------------------------
	if self.enable_treasure then
		local title_w, title_label = CreateSectionTitle(self, "快捷挖宝", function() self:ToggleSection("treasure") end)
		local container = self:AddChild(Widget("treasure_container"))

		self.selected_count = 1
		local spinner_data = {}
		for _, count in ipairs({1, 5, 10, 20, 50}) do
			if count <= self.max_summon then
				table.insert(spinner_data, { text = tostring(count), data = count })
			end
		end
		if #spinner_data == 0 then table.insert(spinner_data, { text = "1", data = 1 }) end

		self.spinner_root = container:AddChild(Widget("spinner_root"))
		self.spinner_root:SetPosition(-75, 5)

		self.spinner_label = self.spinner_root:AddChild(Text(CHATFONT, 22, "数量:"))
		self.spinner_label:SetPosition(-50, 0)
		self.spinner_label:SetColour(unpack(WHITE))

		self.spinner = self.spinner_root:AddChild(Spinner(spinner_data, 85, 32, {font = CHATFONT, size = 22}, nil, nil, nil, true))
		self.spinner:SetTextColour(unpack(WHITE))
		self.spinner:SetOnChangedFn(function(data) self.selected_count = data end)
		self.spinner:SetPosition(20, 0)

		self.btn_summon = container:AddChild(TEMPLATES.StandardButton(function()
			if MOD_RPC["LittleMoon"] and MOD_RPC["LittleMoon"]["Summon"] then
				SendModRPCToServer(MOD_RPC["LittleMoon"]["Summon"], self.selected_count)
			end
		end, "立即召唤", { 110, 36 }))
		self.btn_summon:SetPosition(75, 5)
		self.btn_summon:SetTextSize(20)

		local treasure_height = 55

		-- 一键挖宝（dig_treasure_mode > 0 时才显示）
		if self.dig_treasure_mode > 0 then
			self.dig_count = self.dig_treasure_mode
			local dig_spinner_data = {}
			for _, dcount in ipairs({0, 1, 3, 5, 10}) do
				if dcount == 0 then
					table.insert(dig_spinner_data, { text = "关闭", data = 0 })
				elseif dcount <= self.dig_treasure_mode then
					table.insert(dig_spinner_data, { text = tostring(dcount), data = dcount })
				end
			end
			if #dig_spinner_data == 0 then
				table.insert(dig_spinner_data, { text = "关闭", data = 0 })
			end

			self.dig_spinner_root = container:AddChild(Widget("dig_spinner_root"))
			self.dig_spinner_root:SetPosition(-75, -20)

			self.dig_spinner_label = self.dig_spinner_root:AddChild(Text(CHATFONT, 22, "一键:"))
			self.dig_spinner_label:SetPosition(-50, 0)
			self.dig_spinner_label:SetColour(unpack(WHITE))

			self.dig_spinner = self.dig_spinner_root:AddChild(Spinner(dig_spinner_data, 85, 32, {font = CHATFONT, size = 22}, nil, nil, nil, true))
			self.dig_spinner:SetTextColour(unpack(WHITE))
			self.dig_spinner:SetOnChangedFn(function(data) self.dig_count = data end)
			self.dig_spinner:SetPosition(20, 0)

			for _, item in ipairs(dig_spinner_data) do
				if item.data == self.dig_treasure_mode then
					self.dig_spinner:SetSelected(item)
					break
				end
			end

			self.btn_quick_dig = container:AddChild(TEMPLATES.StandardButton(function()
				if self.dig_count > 0 and MOD_RPC["LittleMoon"] and MOD_RPC["LittleMoon"]["QuickDig"] then
					SendModRPCToServer(MOD_RPC["LittleMoon"]["QuickDig"], self.dig_count)
				end
			end, "一键挖宝", { 110, 36 }))
			self.btn_quick_dig:SetPosition(75, -20)
			self.btn_quick_dig:SetTextSize(20)

			treasure_height = 100
		end

		table.insert(self.sections, {
			key = "treasure",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = treasure_height,
			collapsed = true,
			section_name = "快捷挖宝",
		})
	end

	-------------------------------------------------------------------
	-- 自动吸入
	-------------------------------------------------------------------
	if self.enable_auto_pickup then
		local title_w, title_label = CreateSectionTitle(self, "自动吸入", function() self:ToggleSection("pickup") end)
		local container = self:AddChild(Widget("pickup_container"))
		local real_owner = self.owner or ThePlayer

		local initial_checked = false
		if real_owner and real_owner.auto_pickup_enabled then
			initial_checked = real_owner.auto_pickup_enabled:value()
		end

		self.auto_pickup_cb = container:AddChild(TEMPLATES.LabelCheckbox(function(v)
			local p = self.owner or ThePlayer
			if p and MOD_RPC["LittleMoon"] and MOD_RPC["LittleMoon"]["SetAutoPickup"] then
				SendModRPCToServer(MOD_RPC["LittleMoon"]["SetAutoPickup"], v)
			end
		end, initial_checked, "开启自动吸入物品", CHATFONT, 22, WHITE))

		self.auto_pickup_cb:SetPosition(0, 0, 0)

		if self.auto_pickup_cb.label then
			self.auto_pickup_cb.label:SetColour(unpack(WHITE))
			self.auto_pickup_cb.label:SetSize(22)
		end

		if real_owner then
			self.inst:ListenForEvent("autopickupdirty", function()
				if real_owner.auto_pickup_enabled and self.auto_pickup_cb then
					local val = real_owner.auto_pickup_enabled:value()
					if self.auto_pickup_cb.SetChecked then
						self.auto_pickup_cb:SetChecked(val)
					elseif self.auto_pickup_cb.cb and self.auto_pickup_cb.cb.SetChecked then
						self.auto_pickup_cb.cb:SetChecked(val)
					end
				end
			end, real_owner)
		end

		table.insert(self.sections, {
			key = "pickup",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = 45,
			collapsed = true,
			section_name = "自动吸入",
		})
	end

	-------------------------------------------------------------------
	-- 快捷发送
	-------------------------------------------------------------------
	if self.enable_quick_chat then
		local title_w, title_label = CreateSectionTitle(self, "快捷发送", function() self:ToggleSection("chat") end)
		local container = self:AddChild(Widget("chat_container"))

		self.chat_msgs = LoadChatMsgs()

		for i = 1, #self.chat_msgs do
			local msg_index = i
			local msg = self.chat_msgs[msg_index]
			local pos_x = msg_index % 2 == 1 and -60 or 60
			local offset_idx = math.ceil(msg_index / 2) - 1
			local btn_y = 15 - offset_idx * 40

			local btn = container:AddChild(TEMPLATES.StandardButton(function()
				TheNet:Say(self.chat_msgs[msg_index], true)
			end, msg, { 110, 30 }))
			btn:SetPosition(pos_x, btn_y, 0)
			btn:SetTextSize(16)

			btn.OnMouseButton = function(_, button, down)
				if button == MOUSEBUTTON_RIGHT and not down then
					local function OnSave(new_text)
						if new_text and new_text ~= "" then
							self.chat_msgs[msg_index] = new_text
							btn:SetText(new_text)
							SaveChatMsgs(self.chat_msgs)
						end
					end

					local edit_screen = Screen("chat_edit_screen")
					edit_screen:SetVAnchor(ANCHOR_MIDDLE)
					edit_screen:SetHAnchor(ANCHOR_MIDDLE)

					local bg = edit_screen:AddChild(Image("images/ui.xml", "white.tex"))
					bg:SetSize(320, 100)
					bg:SetTint(0.15, 0.15, 0.15, 0.95)
					bg:SetPosition(0, 0, 0)

					local editbox = edit_screen:AddChild(TextEdit(CHATFONT, 22))
					editbox:SetPosition(0, 15, 0)
					editbox:SetColour(0.9, 0.9, 0.9, 255)
					editbox:SetEditTextColour(0.9, 0.9, 0.9, 255)
					editbox:SetIdleTextColour(0.5, 0.5, 0.5, 255)
					editbox:SetRegionSize(280, 28)
					editbox:SetString(self.chat_msgs[msg_index])
					editbox:SetVAlign(ANCHOR_MIDDLE)
					editbox:SetHAlign(ANCHOR_MIDDLE)

					local confirm_btn = edit_screen:AddChild(TEMPLATES.StandardButton(function()
						OnSave(editbox:GetString())
						TheFrontEnd:PopScreen(edit_screen)
					end, "保存", { 80, 30 }))
					confirm_btn:SetPosition(80, -25, 0)
					confirm_btn:SetTextSize(18)

					local cancel_btn = edit_screen:AddChild(TEMPLATES.StandardButton(function()
						TheFrontEnd:PopScreen(edit_screen)
					end, "取消", { 80, 30 }))
					cancel_btn:SetPosition(-80, -25, 0)
					cancel_btn:SetTextSize(18)

					TheFrontEnd:PushScreen(edit_screen)
					return true
				end
				return false
			end
		end

		table.insert(self.sections, {
			key = "chat",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = math.ceil(#self.chat_msgs / 2) * 40 + 10,
			collapsed = true,
			section_name = "快捷发送",
		})
	end

	-------------------------------------------------------------------
	-- 冒险记录
	-------------------------------------------------------------------
	if self.enable_death_stats then
		local title_w, title_label = CreateSectionTitle(self, "冒险记录", function() self:ToggleSection("death") end)
		local container = self:AddChild(Widget("death_container"))

		self.death_btn = container:AddChild(TEMPLATES.StandardButton(function()
			if ThePlayer and ThePlayer.HUD and ThePlayer.HUD.death_stats_panel then
				ThePlayer.HUD.death_stats_panel:Toggle()
			end
		end, "冒险记录", { 120, 36 }))
		self.death_btn:SetPosition(0, 0, 0)
		self.death_btn:SetTextSize(20)

		table.insert(self.sections, {
			key = "death",
			enabled = true,
			title_bar = title_w,
			title_label = title_label,
			container = container,
			container_height = 45,
			collapsed = true,
			section_name = "冒险记录",
		})
	end

	-- 初始布局
	self:RebuildLayout()

	self:LoadPosition()
	self:Hide()
end)

-------------------------------------------------------------------
-- Section 折叠/展开
-------------------------------------------------------------------
function LittleMoonPanel:ToggleSection(key)
	for _, sec in ipairs(self.sections) do
		if sec.key == key then
			sec.collapsed = not sec.collapsed
			break
		end
	end
	self:RebuildLayout()
end

function LittleMoonPanel:UpdateTitleArrow(sec)
	local arrow = sec.collapsed and "▶" or "▼"
	if sec.title_label then
		sec.title_label:SetString(arrow .. " " .. sec.section_name)
	end
end

-------------------------------------------------------------------
-- 布局重建（在折叠/展开时重算所有位置）
-------------------------------------------------------------------
function LittleMoonPanel:RebuildLayout()
	-- 1. 计算面板总高度
	local total = HANDLE_HEIGHT + 5
	for _, sec in ipairs(self.sections) do
		if sec.enabled then
			total = total + SECTION_TITLE_HEIGHT + 2
			if not sec.collapsed then
				total = total + sec.container_height
			end
		end
	end
	total = total + HANDLE_HEIGHT + 5
	self.panel_height = total

	-- 2. 背景
	self.background:SetSize(PANEL_WIDTH, total)

	-- 3. 页眉
	self.header:SetSize(PANEL_WIDTH, HANDLE_HEIGHT)
	self.header:SetPosition(0, total / 2 - HANDLE_HEIGHT / 2, 0)

	-- 4. 四周边框
	self.border_top:SetSize(PANEL_WIDTH, 2)
	self.border_top:SetPosition(0, total / 2 - 1, 0)
	self.border_bottom:SetSize(PANEL_WIDTH, 2)
	self.border_bottom:SetPosition(0, -total / 2 + 1, 0)
	self.border_left:SetSize(2, total)
	self.border_left:SetPosition(-PANEL_WIDTH / 2 + 1, 0, 0)
	self.border_right:SetSize(2, total)
	self.border_right:SetPosition(PANEL_WIDTH / 2 - 1, 0, 0)

	-- 5. 拖动手柄
	self.handle:SetSize(PANEL_WIDTH, HANDLE_HEIGHT)
	self.handle:SetPosition(0, total / 2 - HANDLE_HEIGHT / 2, 0)
	self.handle_bottom:SetSize(PANEL_WIDTH, HANDLE_HEIGHT)
	self.handle_bottom:SetPosition(0, -total / 2 + HANDLE_HEIGHT / 2, 0)

	-- 6. 排列 section
	local y = total / 2 - HANDLE_HEIGHT - 5

	for _, sec in ipairs(self.sections) do
		if sec.enabled then
			local ty = y - SECTION_TITLE_HEIGHT / 2
			sec.title_bar:SetPosition(0, ty, 0)
			sec.title_bar:Show()
			y = y - SECTION_TITLE_HEIGHT

			if not sec.collapsed then
				local cy = y - sec.container_height / 2
				sec.container:SetPosition(0, cy, 0)
				sec.container:Show()
				y = y - sec.container_height
			else
				sec.container:Hide()
			end

			y = y - 2  -- gap between sections

			self:UpdateTitleArrow(sec)
		else
			sec.title_bar:Hide()
			sec.container:Hide()
		end
	end

	-- 更新夹持位置
	local x, cur_y = self:GetPositionXYZ()
	self:SetClampedPosition(x, cur_y)
end

-------------------------------------------------------------------
-- 面板开关
-------------------------------------------------------------------
function LittleMoonPanel:Toggle()
	if self:IsVisible() then self:Hide() else self:Show(); self:MoveToFront() end
end

-------------------------------------------------------------------
-- 拖拽
-------------------------------------------------------------------
function LittleMoonPanel:OnHandleMouseButton(button, down)
	if button ~= MOUSEBUTTON_LEFT then return false end
	if down then self:StartDragging() else self:StopDragging() end
	return true
end

function LittleMoonPanel:StartDragging()
	if self.drag_move_handler ~= nil then return end
	local mouse_pos = TheInput:GetScreenPosition()
	local panel_x, panel_y = self:GetPositionXYZ()
	self.drag_offset_x = panel_x - mouse_pos.x
	self.drag_offset_y = panel_y - ScreenYToTopOffset(mouse_pos.y)
	self:MoveToFront()
	self.drag_move_handler = TheInput:AddMoveHandler(function(x, y) self:UpdateDragPosition(x, y) end)
	self.drag_button_handler = TheInput:AddMouseButtonHandler(function(button_id, is_down)
		if button_id == MOUSEBUTTON_LEFT and not is_down then self:StopDragging() end
	end)
	self:UpdateDragPosition(mouse_pos.x, mouse_pos.y)
end

function LittleMoonPanel:UpdateDragPosition(mouse_x, mouse_y)
	self:SetClampedPosition(mouse_x + self.drag_offset_x, ScreenYToTopOffset(mouse_y) + self.drag_offset_y)
end

function LittleMoonPanel:SetClampedPosition(x, y)
	local screen_w, screen_h = TheSim:GetScreenSize()
	local min_x = PANEL_WIDTH / 2
	local max_x = screen_w - PANEL_WIDTH / 2
	local min_y = -screen_h + self.panel_height / 2
	local max_y = -self.panel_height / 2
	self:SetPosition(Clamp(x, min_x, max_x), Clamp(y, min_y, max_y), 0)
end

function LittleMoonPanel:StopDragging()
	if self.drag_move_handler ~= nil then self.drag_move_handler:Remove(); self.drag_move_handler = nil end
	if self.drag_button_handler ~= nil then self.drag_button_handler:Remove(); self.drag_button_handler = nil end
	local x, y = self:GetPositionXYZ()
	if json ~= nil then
		TheSim:SetPersistentString(POSITION_FILE, json.encode({x = x, y = y}), false)
	end
end

function LittleMoonPanel:LoadPosition()
	if json == nil then return end
	TheSim:GetPersistentString(POSITION_FILE, function(success, data)
		if success and data and data ~= "" then
			local ok, pos = pcall(json.decode, data)
			if ok and pos and pos.x and pos.y then
				self:SetClampedPosition(pos.x, pos.y)
			else
				self:SetClampedPosition(DEFAULT_X, DEFAULT_Y)
			end
		else
			self:SetClampedPosition(DEFAULT_X, DEFAULT_Y)
		end
	end)
end

function LittleMoonPanel:OnRemoveEntity()
	self:StopDragging()
end

return LittleMoonPanel
