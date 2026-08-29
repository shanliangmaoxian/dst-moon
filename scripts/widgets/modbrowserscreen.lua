-- Mod浏览器界面 - 模仿烹饪指南样式
-- 集成自 demo/dst-mod-browser-master (九月), 接入小月亮助手面板, wiki 链接指向新站点 https://dst.9yue.dpdns.org/#<id>
local Widget = require "widgets/widget"
local ImageButton = require "widgets/imagebutton"
local Image = require "widgets/image"
local Text = require "widgets/text"
local Grid = require "widgets/grid"

local TEMPLATES = require "widgets/redux/templates"

local bigger = 1.2

local LANG = {
    MOD_LIST_TITLE = "服务器Mod列表",
    MOD_DETAILS_TITLE = "Mod详情",
    MOD_LIST = "Mod列表",
    SELECT_MOD = "选择一个Mod查看详情",
    AUTHOR = "作者",
    VERSION = "版本",
    NO_DESCRIPTION = "描述",
    UNKNOWN_AUTHOR = "未知作者",
    UNKNOWN_VERSION = "未知版本",
    UNKNOWN_MOD = "未知Mod",
    OPEN_WIKI = "打开Wiki",
    OPEN_STEAM = "打开Steam工坊",
}

local STEAM_BASE_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id="

-- 新 Wiki 站点 (wiki合集): https://dst.9yue.dpdns.org/
-- 每个 mod 的 wiki 页地址 = WIKI_URL_PREFIX .. wiki_id (docs/modwiki.md 的 id)
-- 示例: 万物书 id=80 → https://dst.9yue.dpdns.org/#80
local WIKI_BASE_URL = "https://dst.9yue.dpdns.org"
local WIKI_URL_PREFIX = WIKI_BASE_URL .. "/#"

-- 已掌握的 mod 数据库: workshop id → wiki id (docs/modwiki.md)
local KNOWN_WIKI_ID = {
-- generated from docs/modwiki.md: 90 entries; ids+workshop_ids identical to https://dst.9yue.dpdns.org/api/wikis (name text diffs: 1)
    ["workshop-3301201173"] = 1,  -- Fenrir【芬璃尔】
    ["workshop-3398290914"] = 2,  -- 小鸟游星野
    ["workshop-2526778484"] = 3,  -- 泰拉
    ["workshop-1909182187"] = 4,  -- 勋章
    ["workshop-3501103675"] = 5,  -- doro
    ["workshop-2979177306"] = 6,  -- 海洋传说
    ["workshop-2992200942"] = 7,  -- 枝江往事
    ["workshop-3152056502"] = 8,  -- 冰川镜华
    ["workshop-3349143694"] = 9,  -- 荔枝汁
    ["workshop-3283650699"] = 10,  -- 悠悠
    ["workshop-1392778117"] = 11,  -- 棱镜
    ["workshop-3245573008"] = 12,  -- 小可
    ["workshop-2736985627"] = 13,  -- 夜雨心空
    ["workshop-3043439883"] = 14,  -- 小樱
    ["workshop-1638724235"] = 15,  -- 小穹
    ["workshop-3191348907"] = 16,  -- 永恒新界
    ["workshop-3442966746"] = 17,  -- 为爽而虐重制版
    ["workshop-2886753796"] = 18,  -- 为爽而虐
    ["workshop-3355502149"] = 19,  -- 蟾宫神使 — 玉兔
    ["workshop-3394947135"] = 20,  -- 紫色三色堇
    ["workshop-3054476656"] = 21,  -- 负重前行
    ["workshop-3343873962"] = 22,  -- 香脆松子
    ["workshop-3225961625"] = 23,  -- 古树繁花
    ["workshop-3059813493"] = 24,  -- 碧蓝航线：柴郡
    ["workshop-1289779251"] = 25,  -- 樱花林
    ["workshop-3021553617"] = 26,  -- 创世纪
    ["workshop-3235319974"] = 27,  -- 登仙
    ["workshop-3288149713"] = 28,  -- 童话世界
    ["workshop-2932270367"] = 29,  -- 三国—黄巾篇
    ["workshop-3409663240"] = 30,  -- 鸽之星
    ["workshop-3401927745"] = 31,  -- 山河表里
    ["workshop-3046680574"] = 32,  -- 山海秘藏
    ["workshop-3360553731"] = 33,  -- 深埋之下
    ["workshop-3150203711"] = 34,  -- Shoetime
    ["workshop-2653288638"] = 35,  -- Albe的物品包
    ["workshop-2066838067"] = 36,  -- 太真
    ["workshop-3014738585"] = 37,  -- 神话：傲来神仙境
    ["workshop-2578692071"] = 38,  -- 魔女之旅
    ["workshop-3062833647"] = 39,  -- 武器成长
    ["workshop-3173396280"] = 40,  -- 食纪元
    ["workshop-3155177428"] = 41,  -- 道诡异仙
    ["workshop-3433379139"] = 42,  -- 琪亚娜&雷电芽衣
    ["workshop-2494336473"] = 43,  -- 悲怨之祈
    ["workshop-3491443180"] = 44,  -- 爱莉希雅
    ["workshop-3467053285"] = 45,  -- 西琳
    ["workshop-3273473826"] = 46,  -- 纸飞机
    ["workshop-3014076942"] = 47,  -- 璇儿
    ["workshop-1837053004"] = 48,  -- 晓美焰
    ["workshop-1645013096"] = 49,  -- 乃木园子
    ["workshop-2591774328"] = 50,  -- 星之卡比
    ["workshop-2941989744"] = 51,  -- 狂三
    ["workshop-2928652892"] = 52,  -- 基地投影
    ["workshop-1085586145"] = 53,  -- 额外物品包
    ["workshop-1944492666"] = 54,  -- 花样风滚草
    ["workshop-3320235585"] = 55,  -- [崩坏:星穹铁道] 流萤
    ["workshop-3412862219"] = 56,  -- [崩坏:星穹铁道]大黑塔
    ["workshop-3422055170"] = 57,  -- [崩坏:星穹铁道]符玄
    ["workshop-3396147201"] = 58,  -- [崩坏:星穹铁道]黄泉
    ["workshop-3512799457"] = 59,  -- [崩坏:星穹铁道]赛飞儿
    ["workshop-3199945184"] = 60,  -- 霆霓快雨——刻晴
    ["workshop-3358138839"] = 61,  -- 真珠之智——珊瑚宫心海
    ["workshop-3520190450"] = 62,  -- 白草净华-纳西妲
    ["workshop-2928810007"] = 63,  -- 建家档狂喜
    ["workshop-3319931009"] = 64,  -- 英雄联盟武器
    ["workshop-949808360"] = 65,  -- Carney
    ["workshop-2904374520"] = 66,  -- 卡尼猫（改）
    ["workshop-3529602474"] = 67,  -- 怪物料理
    ["workshop-3390336464"] = 68,  -- 析音
    ["workshop-3545823457"] = 69,  -- 光影交织
    ["workshop-3528397463"] = 71,  -- stella星璃
    ["workshop-3208844404"] = 73,  -- 托托莉修复加强版
    ["workshop-2418617371"] = 74,  -- Aria Crystal(艾丽娅-领主)
    ["workshop-3683369240"] = 75,  -- 华洛晨曦
    ["workshop-3449562331"] = 76,  -- 小小格温
    ["workshop-3715721500"] = 77,  -- 星露谷物语
    ["workshop-2315403479"] = 79,  -- 彩色风滚草R
    ["workshop-3544387985"] = 80,  -- 万物书
    ["workshop-2823458540"] = 81,  -- 富贵险中求
    ["workshop-2845206007"] = 82,  -- 度日如年
    ["workshop-2929911476"] = 83,  -- 真神·薇克巴顿
    ["workshop-3610049880"] = 84,  -- 星见雅miyabi
    ["workshop-3477330723"] = 85,  -- 士条怜 lian
    ["workshop-3746987944"] = 86,  -- 晴
    ["workshop-3743103449"] = 87,  -- 时间旅者:绒雪
    ["workshop-3660903728"] = 88,  -- 雪露
    ["workshop-3721602498"] = 89,  -- 水银灯
    ["workshop-3625940357"] = 90,  -- 腌笃鲜•神话书说
    ["workshop-3597024951"] = 91,  -- 景熹家居包
    ["workshop-3713562375"] = 92,  -- 小月亮
    ["workshop-3096210166"] = 93,  -- 附魔强化
    ["workshop-3522184191"] = 94,  -- 雅缇丝yatis
}

local ModBrowserScreen = Class(Widget, function(self, owner)
    Widget._ctor(self, "ModBrowserScreen")
    
    self.owner = owner
    self.mod_data = {}
    self.collected_mods = {}  -- 已收集的mod
    self.uncollected_mods = {}  -- 未收集的mod
    
    -- 设置根节点
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetVAnchor(ANCHOR_MIDDLE)
    
    -- 确保owner存在
    if not self.owner then
        print("ModBrowserScreen: owner is nil")
        return
    end
    
    -- 背景 - 使用烹饪指南样式
    self.root = self:AddChild(Widget("root"))
    self.root:SetScale(0.8*bigger)
    
    -- 主背景面板 - 使用烹饪指南的背景纹理
    self.bg = self.root:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_menu_bg.tex"))
    self.bg:ScaleToSize(850*bigger, 550*bigger)
    
    -- 本地化字符串 - 根据语言设置获取对应的语言包
    local L = LANG
    self.L = L
    
    -- 移除原有标题，因为我们只保留tab页
    
    -- 创建tab容器
    self:BuildTabs(L)
    
    -- 左侧Mod列表
    self:BuildModList(L)
    
    -- 右侧详情面板
    self:BuildDetailsPanel(L)
    
    -- 关闭按钮
    self.close_button = self.root:AddChild(ImageButton("images/global_redux.xml", "close.tex"))
    self.close_button:SetPosition(380*bigger, 260*bigger)
    self.close_button:SetScale(1.2*bigger)
    self.close_button:SetOnClick(function()
        self:Hide()
    end)
    
    -- 获取mod数据
    self:RefreshModData()
    
    self:Hide()
end)

function ModBrowserScreen:BuildTabs(L)
    -- 创建tab根容器
    local tab_root = self.root:AddChild(Widget("tab_root"))
    tab_root:SetPosition(0, 290*bigger)
    
    local base_size = 0.7
    
    -- 已收集tab
    self.collected_tab = ImageButton("images/quagmire_recipebook.xml", "quagmire_recipe_tab_inactive.tex", nil, nil, nil, "quagmire_recipe_tab_active.tex")
    self.collected_tab:SetPosition(-100*bigger, 0)
    self.collected_tab:SetFocusScale(base_size*bigger, base_size*bigger)
    self.collected_tab:SetNormalScale(base_size*bigger, base_size*bigger)
    self.collected_tab:SetText("已收集")
    self.collected_tab:SetTextSize(22)
    self.collected_tab:SetFont(HEADERFONT)
    self.collected_tab:SetTextColour(UICOLOURS.GOLD)
    self.collected_tab:SetTextFocusColour(UICOLOURS.GOLD)
    self.collected_tab:SetTextSelectedColour(UICOLOURS.GOLD)
    self.collected_tab.text:SetPosition(0, -2)
    self.collected_tab.clickoffset = Vector3(0, 5, 0)
    self.collected_tab:SetOnClick(function()
        if self.last_selected then
            self.last_selected:Unselect()
        end
        self.last_selected = self.collected_tab
        self.collected_tab:Select()
        self.collected_tab:MoveToFront()
        -- 显示已收集的mod
        self:ShowCollectedMods()
    end)
    
    -- 未收集tab
    self.uncollected_tab = ImageButton("images/quagmire_recipebook.xml", "quagmire_recipe_tab_inactive.tex", nil, nil, nil, "quagmire_recipe_tab_active.tex")
    self.uncollected_tab:SetPosition(100*bigger, 0)
    self.uncollected_tab:SetFocusScale(base_size*bigger, base_size*bigger)  -- 放大30%
    self.uncollected_tab:SetNormalScale(base_size*bigger, base_size*bigger)  -- 放大30%
    self.uncollected_tab:SetText("未收集")
    self.uncollected_tab:SetTextSize(22)
    self.uncollected_tab:SetFont(HEADERFONT)
    self.uncollected_tab:SetTextColour(UICOLOURS.GOLD)
    self.uncollected_tab:SetTextFocusColour(UICOLOURS.GOLD)
    self.uncollected_tab:SetTextSelectedColour(UICOLOURS.GOLD)
    self.uncollected_tab.text:SetPosition(0, -2)
    self.uncollected_tab.clickoffset = Vector3(0, 5, 0)
    self.uncollected_tab:SetOnClick(function()
        if self.last_selected then
            self.last_selected:Unselect()
        end
        self.last_selected = self.uncollected_tab
        self.uncollected_tab:Select()
        self.uncollected_tab:MoveToFront()
        -- 显示未收集的mod
        self:ShowUncollectedMods()
    end)
    
    tab_root:AddChild(self.collected_tab)
    tab_root:AddChild(self.uncollected_tab)
    
    -- 默认选择已收集tab
    self.last_selected = self.collected_tab
    self.collected_tab:Select()
    self.collected_tab:MoveToFront()
    
    -- 确保tab在最前面显示
    tab_root:MoveToFront()
end

function ModBrowserScreen:BuildModList(L)
    -- 左侧列表容器
    self.list_container = self.root:AddChild(Widget("list_container"))
    self.list_container:SetPosition(-220*bigger, -45*bigger)
    
    -- 创建网格布局用于显示mod列表
    self:BuildModGrid(L)
    
    -- 移除列表标题和分隔线
end

function ModBrowserScreen:BuildModGrid(L)
    local base_size = 128*bigger
    local cell_size = 73*bigger
    local row_w = cell_size
    local row_h = cell_size
    local row_spacing = 5*bigger

    local function ScrollWidgetsCtor(context, index)
        local w = Widget("mod-cell-".. index)

        -- 创建mod单元格按钮
        w.cell_root = w:AddChild(ImageButton("images/quagmire_recipebook.xml", "cookbook_unknown.tex", "cookbook_unknown_selected.tex"))
        w.cell_root:SetFocusScale(cell_size/base_size + .05, cell_size/base_size + .05)
        w.cell_root:SetNormalScale(cell_size/base_size, cell_size/base_size)
        w.focus_forward = w.cell_root

        w.cell_root.ongainfocusfn = function() self.mod_grid:OnWidgetFocus(w) end

        -- mod图标容器
        w.mod_icon_root = w.cell_root.image:AddChild(Widget("mod_icon_root"))

        w.mod_icon = w.mod_icon_root:AddChild(Image("images/quagmire_recipebook.xml", "cookbook_known.tex")) -- 这将被替换为mod图标

        -- mod名称文本
        w.mod_name = w:AddChild(Text(CHATFONT, 16*bigger, "", UICOLOURS.BROWN_DARK))
        w.mod_name:SetPosition(0, -cell_size/2 - 15*bigger)
        w.mod_name:SetRegionSize(cell_size * 2, 20*bigger)
        w.mod_name:SetHAlign(ANCHOR_MIDDLE)
        
        -- mod版本文本
        w.mod_version = w:AddChild(Text(CHATFONT, 14*bigger, "", UICOLOURS.BROWN_DARK))  -- 字体大小从14放大到18 (14*1.3=18.2≈18)
        w.mod_version:SetPosition(0, -cell_size/2 + 35*bigger)  -- 原来的35基础上放大30% (35*1.3=45.5)
        w.mod_version:SetRegionSize(cell_size * 2, 20*bigger)  -- 原来的20基础上放大30% (20*1.3=26)
        w.mod_version:SetHAlign(ANCHOR_MIDDLE)

        w.cell_root:SetOnClick(function()
            if w.data then
                self:ShowModDetails(w.data)
            end
        end)

        return w
    end

    local function ScrollWidgetSetData(context, widget, data, index)
        widget.data = data
        if data ~= nil then
            widget.cell_root:Show()
            widget.mod_icon_root:Show()
            widget.mod_name:Show()
            widget.mod_version:Show()

            -- 设置mod图标和名称
            widget.mod_name:SetString(data.name or L.UNKNOWN_MOD)
            
            -- 设置mod版本
            local version_text = data.version or L.UNKNOWN_VERSION
            widget.mod_version:SetString(version_text)
            
            -- 使用已知的纹理替换未知纹理
            widget.cell_root:SetTextures("images/quagmire_recipebook.xml", "cookbook_known.tex", "cookbook_known_selected.tex")
            
            -- 设置图标纹理（这里使用默认图标，实际项目中可能需要根据mod类型设置不同图标）
            widget.mod_icon:SetTexture("images/global.xml", "mod.tex")
            widget.mod_icon:ScaleToSize(cell_size + 20*bigger, cell_size + 20*bigger)  -- 原来的20基础上放大30% (20*1.3=26)

            widget:Enable()
        else
            widget:Disable()
            widget.cell_root:Hide()
            widget.mod_icon_root:Hide()
            widget.mod_name:Hide()
            widget.mod_version:Hide()
        end
    end

    -- 创建网格
    local grid = TEMPLATES.ScrollingGrid(
        {},
        {
            context = {},
            widget_width  = row_w+row_spacing,
            widget_height = row_h+row_spacing + 30*bigger,
            force_peek    = true,
            num_visible_rows = 4,
            num_columns      = 4,
            item_ctor_fn = ScrollWidgetsCtor,
            apply_fn     = ScrollWidgetSetData,
            scrollbar_offset = 20*bigger,
            scrollbar_height_offset = -60*bigger
        })

    grid:SetPosition(0, 70)
    self.list_container:AddChild(grid)
    self.mod_grid = grid

    -- 自定义滚动条样式
    grid.up_button:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
    grid.up_button:SetScale(0.5*bigger)  -- 原来的0.5基础上放大30% (0.5*1.3=0.65)

    grid.down_button:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
    grid.down_button:SetScale(-0.5*bigger)  -- 原来的-0.5基础上放大30% (-0.5*1.3=-0.65)

    grid.scroll_bar_line:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_bar.tex")
    grid.scroll_bar_line:SetScale(0.8*bigger)  -- 原来的0.8基础上放大30% (0.8*1.3=1.04)

    grid.position_marker:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
    grid.position_marker.image:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
    grid.position_marker:SetScale(0.6*bigger)  -- 原来的0.6基础上放大30% (0.6*1.3=0.78)
end

function ModBrowserScreen:BuildDetailsPanel(L)
    -- 右侧详情容器
    self.details_container = self.root:AddChild(Widget("details_container"))
    self.details_container:SetPosition(180*bigger, -20*bigger)  -- 原来的180, -20基础上放大30% (180*1.3=234, -20*1.3=-26)
    
    -- 详情背景 - 使用烹饪指南样式
    local details_decor = self.details_container:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_menu_block.tex"))
    details_decor:ScaleToSize(400*bigger, 480*bigger)  -- 原来的400, 480基础上放大30% (400*1.3=520, 480*1.3=624)
    
    -- 添加装饰性角落元素
    local corner_decor1 = self.details_container:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_corner_decoration.tex"))
    corner_decor1:ScaleToSize(100*bigger, 100*bigger)  -- 原来的100基础上放大30% (100*1.3=130)
    corner_decor1:SetPosition(-120*bigger, -190*bigger)  -- 原来的-120, -190基础上放大30% (-120*1.3=-156, -190*1.3=-247)
    
    local corner_decor2 = self.details_container:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_corner_decoration.tex"))
    corner_decor2:ScaleToSize(-100*bigger, 100*bigger)  -- 原来的-100, 100基础上放大30% (-100*1.3=-130, 100*1.3=130)
    corner_decor2:SetPosition(120*bigger, -190*bigger)  -- 原来的120, -190基础上放大30% (120*1.3=156, -190*1.3=-247)
    
    -- 详情面板尺寸
    self.details_panel_width = 350*bigger  -- 原来的350基础上放大30% (350*1.3=455)
    self.details_panel_height = 500*bigger  -- 原来的500基础上放大30% (500*1.3=650)
    
    -- 移除详情标题和分隔线
    -- 初始化详情内容（将在ShowModDetails中更新）
    self:ShowModDetails()
end

function ModBrowserScreen:ShowCollectedMods()
    -- 显示已收集的mod
    if self.mod_grid then
        self.mod_grid:SetItemsData(self.collected_mods)
    end
end

function ModBrowserScreen:ShowUncollectedMods()
    -- 显示未收集的mod
    if self.mod_grid then
        self.mod_grid:SetItemsData(self.uncollected_mods)
    end
end

function ModBrowserScreen:RefreshModData()
    -- 获取当前服务器开启的mod列表
    -- 这里模拟获取服务器mod数据的过程
    local server_mods = self:GetServerMods()
    
    -- 分离已收集和未收集的mod
    self.collected_mods = {}
    self.uncollected_mods = {}
    
    
    local mod = {}
    mod.id = ""
    mod.name = "总站wiki"
    mod.author = self.L.UNKNOWN_AUTHOR
    mod.version = self.L.UNKNOWN_VERSION
    mod.description = "饥荒：联机版（Don't Starve Together，简称DST）是饥荒的续作，以多人游戏模式为特色和核心，在 Steam 和 WeGame 平台上线。"
    mod.wiki_url = WIKI_BASE_URL .. "/"  -- 新 wiki 合集首页
    mod.steam_url = ""
    mod.collected = true
    table.insert(self.collected_mods, mod)

    for _, mod_id in ipairs(server_mods) do
        -- 检查mod是否在已掌握的数据库中
        local modinfo = KnownModIndex:GetModInfo(mod_id) or {}
        
        local mod = {}
        mod.id = mod_id or ""
        mod.name = modinfo.name or ""
        mod.author = modinfo.author  or ""
        mod.version = modinfo.version  or ""
        mod.description = modinfo.description or "" 
        local wiki_id = KNOWN_WIKI_ID[mod.id]
        mod.wiki_url = wiki_id and (WIKI_URL_PREFIX .. wiki_id) or ""
        mod.steam_url = STEAM_BASE_URL .. string.sub(mod.id, 10)

        if wiki_id then
            -- 如果在已掌握的数据库中，使用数据库中的信息并标记为已收集
            mod.collected = true
            table.insert(self.collected_mods, mod)
        else
            -- 如果不在已掌握的数据库中，标记为未收集
            mod.collected = false
            table.insert(self.uncollected_mods, mod)
        end
    end
    
    -- 默认显示已收集的mod
    self:ShowCollectedMods()
end

-- 获取服务器开启的mod列表
function ModBrowserScreen:GetServerMods()
    return TheNet:GetServerModNames() or {}
end

function ModBrowserScreen:UpdateModGrid()
    -- 更新网格数据
    if self.mod_grid then
        self.mod_grid:SetItemsData(self.mod_data)
    end
end

function ModBrowserScreen:ShowModDetails(mod_data)
    -- 清除之前的详情内容
    if self.details_content then
        self.details_content:Kill()
    end
    
    self.details_content = self.details_container:AddChild(Widget("details_content"))
    
    local top = self.details_panel_height/2
    local left = -self.details_panel_width / 2
    
    local y = top - 11
    
    local image_size = 110*bigger  -- 原来的110基础上放大30% (110*1.3=143)
    local name_font_size = 34*bigger  -- 原来的34基础上放大30% (34*1.3=44.2≈44)
    local title_font_size = 18*bigger  -- 原来的18基础上放大30% (18*1.3=23.4≈23)
    local body_font_size = 16*bigger  -- 原来的16基础上放大30% (16*1.3=20.8≈21)
    local value_title_font_size = 18*bigger  -- 原来的18基础上放大30% (18*1.3=23.4≈23)
    local value_body_font_size = 16*bigger  -- 原来的16基础上放大30% (16*1.3=20.8≈21)
    
    local L = self.L
    
    if not mod_data then
        -- 显示默认提示信息
        y = y - name_font_size/2
        local title = self.details_content:AddChild(Text(HEADERFONT, name_font_size, L.SELECT_MOD, UICOLOURS.BROWN_DARK))
        title:SetPosition(0, y)
        return
    end
    
    -- Mod名称
    y = y - name_font_size/2
    local mod_title = self.details_content:AddChild(Text(HEADERFONT, name_font_size, mod_data.name or L.UNKNOWN_MOD, UICOLOURS.BROWN_DARK))
    mod_title:SetPosition(0, y)
    y = y - name_font_size/2 - 4*bigger  -- 原来的4基础上放大30% (4*1.3=5.2)
    
    -- 添加分隔线
    local function MakeDetailsLine(x, y_pos, scale)
        local line = self.details_content:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line_break.tex"))
        line:SetScale(scale, scale)
        line:SetPosition(x, y_pos)
    end
    
    MakeDetailsLine(0, y-10*bigger, -0.55*bigger)  -- 原来的-10基础上放大30% (-10*1.3=-13) 和缩放(-0.55*1.3=-0.715)
    y = y - 30*bigger  -- 原来的30基础上放大30% (30*1.3=39)
    
    -- 作者信息
    local row_start_y = y
    local column_offset_x = 80*bigger  -- 原来的80基础上放大30% (80*1.3=104)
    
    -- 作者标题
    y = y - title_font_size/2
    local author_title = self.details_content:AddChild(Text(HEADERFONT, title_font_size, L.AUTHOR, UICOLOURS.BROWN_DARK))
    author_title:SetPosition(-column_offset_x, y)
    y = y - title_font_size/2
    local author_line = self.details_content:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line_veryshort.tex"))
    author_line:SetScale(0.5*bigger, 0.5*bigger)  -- 原来的0.5基础上放大30% (0.5*1.3=0.65)
    author_line:SetPosition(-column_offset_x, y - 2*bigger)  -- 原来的-2基础上放大30% (-2*1.3=-2.6)
    y = y - 8*bigger  -- 原来的8基础上放大30% (8*1.3=10.4)
    y = y - body_font_size/2
    local author_text = self.details_content:AddChild(Text(HEADERFONT, body_font_size, mod_data.author or L.UNKNOWN_AUTHOR, UICOLOURS.BROWN_DARK))
    author_text:SetPosition(-column_offset_x, y)
    y = y - body_font_size/2 - 4*bigger  -- 原来的-4基础上放大30% (-4*1.3=-5.2)
    
    y = row_start_y
    
    -- 版本标题
    y = y - title_font_size/2
    local version_title = self.details_content:AddChild(Text(HEADERFONT, title_font_size, L.VERSION, UICOLOURS.BROWN_DARK))
    version_title:SetPosition(column_offset_x, y)
    y = y - title_font_size/2
    local version_line = self.details_content:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line_veryshort.tex"))
    version_line:SetScale(0.5*bigger, 0.5*bigger)  -- 原来的0.5基础上放大30% (0.5*1.3=0.65)
    version_line:SetPosition(column_offset_x, y - 2*bigger)  -- 原来的-2基础上放大30% (-2*1.3=-2.6)
    y = y - 8*bigger  -- 原来的8基础上放大30% (8*1.3=10.4)
    y = y - body_font_size/2
    local version_text = self.details_content:AddChild(Text(HEADERFONT, body_font_size, mod_data.version or L.UNKNOWN_VERSION, UICOLOURS.BROWN_DARK))
    version_text:SetPosition(column_offset_x, y)
    y = y - body_font_size/2 - 4*bigger  -- 原来的-4基础上放大30% (-4*1.3=-5.2)
    
    y = y - 20*bigger  -- 原来的20基础上放大30% (20*1.3=26)
    
    -- 描述标题
    y = y - title_font_size/2
    local desc_title = self.details_content:AddChild(Text(HEADERFONT, title_font_size, L.NO_DESCRIPTION, UICOLOURS.BROWN_DARK))
    desc_title:SetPosition(0, y)
    y = y - title_font_size/2
    local desc_line = self.details_content:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line.tex"))
    desc_line:SetScale(0.49*bigger, 0.49*bigger)  -- 原来的0.49基础上放大30% (0.49*1.3=0.637)
    desc_line:SetPosition(0, y - 2*bigger)  -- 原来的-2基础上放大30% (-2*1.3=-2.6)
    y = y - 10*bigger  -- 原来的10基础上放大30% (10*1.3=13)
    
    -- 描述内容
    y = y - body_font_size/2
    local desc_text = self.details_content:AddChild(Text(HEADERFONT, body_font_size, "", UICOLOURS.BROWN_DARK))
    desc_text:SetString(mod_data.description or L.NO_DESCRIPTION)
    desc_text:SetRegionSize(240*bigger, 100*bigger)  -- 原来的240, 100基础上放大30% (240*1.3=312, 100*1.3=130)
    desc_text:SetHAlign(ANCHOR_LEFT)
    desc_text:SetVAlign(ANCHOR_TOP)
    desc_text:EnableWordWrap(true)
    
    local _, msg_h = desc_text:GetRegionSize()
    y = y - msg_h/2
    desc_text:SetPosition(0, y)
    
    y = y - msg_h/2 - 20


    -- 打开wiki按钮
    if mod_data.collected and mod_data.wiki_url then
        local open_wiki_button = self.details_content:AddChild(ImageButton("images/quagmire_recipebook.xml", "quagmire_recipe_tab_inactive.tex", nil, nil, nil, "quagmire_recipe_tab_active.tex"))
        open_wiki_button:SetPosition(0, y-60*bigger)  -- 原来的-60基础上放大30% (-60*1.3=-78)
        open_wiki_button:SetScale(0.6*bigger, 0.6*bigger)  -- 原来的0.6基础上放大30% (0.6*1.3=0.78)
        open_wiki_button:SetText(L.OPEN_WIKI)
        open_wiki_button:SetTextSize(28*bigger)  -- 原来的28基础上放大30% (28*1.3=36.4≈36)
        open_wiki_button:SetFont(HEADERFONT)
        open_wiki_button:SetTextColour(UICOLOURS.GOLD)
        open_wiki_button:SetTextFocusColour(UICOLOURS.GOLD)
        open_wiki_button:SetTextSelectedColour(UICOLOURS.GOLD)
        open_wiki_button.text:SetPosition(0, -2*bigger)  -- 原来的-2基础上放大30% (-2*1.3=-2.6)
        open_wiki_button:SetOnClick(function()
            VisitURL(mod_data.wiki_url, false)
        end)
    end
    
    -- 打开steam
    local open_wiki_button = self.details_content:AddChild(ImageButton("images/quagmire_recipebook.xml", "quagmire_recipe_tab_inactive.tex", nil, nil, nil, "quagmire_recipe_tab_active.tex"))
    open_wiki_button:SetPosition(0, y-120*bigger)  -- 原来的-120基础上放大30% (-120*1.3=-156)
    open_wiki_button:SetScale(0.6*bigger, 0.6*bigger)  -- 原来的0.6基础上放大30% (0.6*1.3=0.78)
    open_wiki_button:SetText(L.OPEN_STEAM)
    open_wiki_button:SetTextSize(28*bigger)  -- 原来的28基础上放大30% (28*1.3=36.4≈36)
    open_wiki_button:SetFont(HEADERFONT)
    open_wiki_button:SetTextColour(UICOLOURS.GOLD)
    open_wiki_button:SetTextFocusColour(UICOLOURS.GOLD)
    open_wiki_button:SetTextSelectedColour(UICOLOURS.GOLD)
    open_wiki_button.text:SetPosition(0, -2*bigger)  -- 原来的-2基础上放大30% (-2*1.3=-2.6)
    open_wiki_button:SetOnClick(function()
        VisitURL(mod_data.steam_url, false)
    end)
end

return ModBrowserScreen
