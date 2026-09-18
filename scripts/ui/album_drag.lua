-- 附魔收集册容器窗口：拖动 + 放大 + 堆叠数量角标（仅客户端 UI）
--
-- 拖动：游戏 FrontEnd 不向 widget 派发 mousemove，故用全局
-- TheInput:AddMouseButtonHandler / AddMoveHandler 实现"按下-移动-松开"拖动。
-- 坐标系：鼠标坐标与 UI widget 世界坐标的相对变换存在两种口径
-- （中心原点 / 左下原点像素），位移用 delta 法天然免疫；热区命中测试对
-- 两种口径都做尝试，任一命中即可拖动。
-- 放大：ContainerWidget 构造固定 SetScale(0.6)，对收集册改为 0.8。
-- 角标：服务端把各槽总数写入 net_counts（"槽位:总数;..."），客户端监听
-- dirty 事件后直接调用原版 ItemTile:SetQuantity 画数字——与树枝等
-- 可堆叠物品的计数显示完全同款（字体/位置/999+ 截断都是原版行为）。

local _G = GLOBAL
local ALBUM_PREFAB = "lmoon_stone_album"
-- 面板背景拉伸尺寸：两页 9×9 的槽位中心横跨 1370、纵跨 640，四周各留 90 余量
-- 高度比宽度多留一截，是为了给底部的「整理」按钮腾出位置
-- （须与 prefabs/lmoon_stone_album.lua 的 ALBUM_COLS/ROWS/PAGES/PAGE_GAP 保持一致）
local ALBUM_PANEL_W = 1550
local ALBUM_PANEL_H = 880

-- 「整理」按钮纵向位置（窗口本地坐标）。网格底边在 -352、面板底边在 -440，取中放
local SORT_BTN_Y = -396

-- 当前打开的收集册窗口（客户端收到服务端 RPC 数量后据此刷新角标）
local active_albums = setmetatable({}, { __mode = "k" })

-- 拖动热区（窗口本地坐标，与缩放无关：命中测试会除以累计缩放）
-- 两页网格横向中心跨 1370（半幅 685）、纵向仍是 640（半幅 320），热区提到网格正上方
local ZONE_HALF_W = 725
local ZONE_Y_MIN = 360
local ZONE_Y_MAX = 430

local ALBUM_SCALE = 0.8 -- 默认 0.6，放大格子

---- 取容器实体：ContainerWidget 的 container 一般是 entity（playerhud:Open(container,doer) 传 self.inst），
---- 兼容万一传的是组件的情形（组件取 .inst）
local function AlbumEntity(s)
    local c = s.container
    if c == nil then
        return nil
    end
    if c.GUID ~= nil then
        return c
    end
    return c.inst
end

local function RemoveHandler(h)
    if h ~= nil then
        h:Remove()
    end
end

---- 鼠标 -> 窗口本地坐标（试两种原点口径，返回候选 dx/dy 列表）
local function MouseLocalCandidates(s, mouse)
    local scale = s:GetScale().x
    if scale == nil or scale == 0 then
        return {}
    end
    local origin = s:GetWorldPosition()
    local candidates = {
        { x = (mouse.x - origin.x) / scale, y = (mouse.y - origin.y) / scale },
    }
    -- 左下原点像素口径 -> 中心原点：减半屏
    local w, h = _G.TheSim:GetScreenSize()
    candidates[2] = {
        x = (mouse.x - w * 0.5 - origin.x) / scale,
        y = (mouse.y - h * 0.5 - origin.y) / scale,
    }
    return candidates
end

local function HitDragZone(s)
    if not s.isopen then
        return false
    end
    local mouse = _G.TheInput:GetScreenPosition()
    for _, p in ipairs(MouseLocalCandidates(s, mouse)) do
        if math.abs(p.x) <= ZONE_HALF_W and p.y >= ZONE_Y_MIN and p.y <= ZONE_Y_MAX then
            return true
        end
    end
    return false
end

---- 鼠标位移（delta 法，与原点口径无关）
local function MouseDelta(s)
    local m = _G.TheInput:GetScreenPosition()
    local d = m - (s.__album_last_mouse or m)
    s.__album_last_mouse = m
    return d
end

---- 堆叠数量角标：复用原版 ItemTile 的堆叠数字 ----
local function UpdateBadges(s)
    local drag = s.__album_drag
    if drag == nil then
        return
    end
    -- 优先用服务端 RPC 推来的数量（可靠）；没有则回退读 netvar
    local raw = drag.counts_str
    if raw == nil then
        local counts_nv = drag.album_entity ~= nil and drag.album_entity.net_counts or nil
        raw = counts_nv ~= nil and counts_nv:value() or ""
    end
    -- 解析 "slot:count;slot:count"
    local counts = {}
    for slot_str, n_str in string.gmatch(raw, "(%d+):(%d+)") do
        counts[tonumber(slot_str)] = tonumber(n_str)
    end
    -- 展示石本身不是 stackable，原版 tile 不会自带数字；
    -- 直接调用 ItemTile:SetQuantity 画上去（NUMBERFONT 42 / >999 截断均为原版行为）
    for i, slot in pairs(s.inv) do
        local tile = slot ~= nil and slot.tile or nil
        if tile ~= nil then
            local n = counts[i]
            if n ~= nil and n > 1 then
                tile:SetQuantity(n)
            elseif tile.quantity ~= nil then
                tile.quantity:SetString("") -- 数量 ≤1 不显示数字（原版单块可堆叠物品同款）
            end
        end
    end
end

local function InstallAlbumDrag(ContainerWidget)
    local OldOpen = ContainerWidget.Open
    ContainerWidget.Open = function(s, container, doer)
        OldOpen(s, container, doer)
        if container ~= nil and container.prefab == ALBUM_PREFAB then
            s:EnableAlbumDrag()
        end
    end

    local OldClose = ContainerWidget.Close
    ContainerWidget.Close = function(s, ...)
        s:DisableAlbumDrag()
        return OldClose(s, ...)
    end

    ContainerWidget.EnableAlbumDrag = function(s)
        if s.__album_drag ~= nil then
            return -- 已装好（重复 Open 防御）
        end

        -- 放大窗口（默认 0.6 太小）
        s:SetScale(ALBUM_SCALE, ALBUM_SCALE, ALBUM_SCALE)

        -- 面板边框背景：ContainerWidget 已按 params.bgatlas/bgimage 设好 s.bgimage，这里拉伸到网格大小
        if s.bgimage ~= nil and s.bgimage.texture ~= nil then
            s.bgimage:ScaleToSize(ALBUM_PANEL_W, ALBUM_PANEL_H)
            s.bgimage:MoveToBack()
        end

        -- 顶部拖动提示文字（纯提示，不拦截点击）
        local Text = _G.require("widgets/text")
        local hint = Text(_G.BUTTONFONT, 22)
        hint:SetString("· · 按住拖动 · ·")
        hint:SetColour(1, 1, 1, 0.55)
        hint:SetPosition(0, ZONE_Y_MIN + 20, 0)
        s:AddChild(hint)

        s.__album_drag = {
            hint = hint,
            dragging = false,
            counts_fn = nil,
            album_entity = nil,
            handlers = {},
        }
        active_albums[s] = true
        local drag = s.__album_drag

        -- 底部「整理」按钮：排序必须在服务端做（容器数据与存档都在服务端），
        -- 这里只发 RPC；服务端排完后会推数量同步，角标自动刷新。
        local TextButton = _G.require("widgets/textbutton")
        local sort_btn = s:AddChild(TextButton())
        sort_btn:SetFont(_G.BODYTEXTFONT)
        sort_btn:SetTextSize(26)
        sort_btn:SetTextColour({ 1, 1, 1, 0.9 })
        sort_btn:SetTextFocusColour({ 1, 0.85, 0.4, 1 })
        sort_btn:SetText("整 理")
        -- Button:SetText 不会改水平对齐，文字默认从按钮原点往右排，
        -- 直接 SetPosition(0, y) 会整体右偏半个字宽。按游戏自身写法
        -- （containerwidget.lua 的关闭按钮）把内层文字改成居中即可。
        sort_btn.text:SetHAlign(_G.ANCHOR_MIDDLE)
        sort_btn:SetTooltip("按附魔石背景色重排册内附魔石")
        sort_btn:SetPosition(0, SORT_BTN_Y, 0)
        sort_btn:MoveToFront()
        sort_btn:SetOnClick(function()
            if s.isopen then
                _G.SendModRPCToServer(_G.MOD_RPC["LittleMoon"]["AlbumSort"])
            end
        end)
        drag.sort_btn = sort_btn

        drag.handlers.mousebtn = _G.TheInput:AddMouseButtonHandler(function(button, down)
            if button ~= _G.MOUSEBUTTON_LEFT or not s.isopen then
                return
            end
            if down then
                if HitDragZone(s) then
                    drag.dragging = true
                    s.__album_last_mouse = _G.TheInput:GetScreenPosition()
                end
            else
                drag.dragging = false
            end
        end)

        drag.handlers.move = _G.TheInput:AddMoveHandler(function()
            if not drag.dragging or not s.isopen then
                return
            end
            local pos = s:GetPosition() + MouseDelta(s)
            -- 限位：让窗口整体留在屏幕内。窗口屏幕尺寸 = 面板尺寸 × 自身缩放 × 父链缩放，
            -- 据此算出中心点可偏移的余量（本地坐标 = 屏幕位移 / 父链缩放）。
            -- 窗口比屏幕还大时余量取 0（锁死居中），避免被拖出可视区后找不回来。
            local ps = (s.parent ~= nil and s.parent:GetScale().x) or 1
            local ss = s:GetScale().x
            if ps <= 0 then ps = 1 end
            if ss == nil or ss <= 0 then ss = ALBUM_SCALE end
            local w, h = _G.TheSim:GetScreenSize()
            local limit_x = _G.math.max(0, (w * 0.5 - ALBUM_PANEL_W * ss * ps * 0.5) / ps)
            local limit_y = _G.math.max(0, (h * 0.5 - ALBUM_PANEL_H * ss * ps * 0.5) / ps)
            pos.x = _G.math.max(-limit_x, _G.math.min(limit_x, pos.x))
            pos.y = _G.math.max(-limit_y, _G.math.min(limit_y, pos.y))
            s:SetPosition(pos)
        end)

        -- 数量角标：监听服务端数量同步 + 槽位变化（补货/取出会重建 tile，
        -- 数字随旧 tile 消失，需要重画）。事件顺序：OldOpen 里 ContainerWidget
        -- 已先注册 itemget/itemlose/refresh，新 tile 先建好，我们再补数字。
        drag.album_entity = AlbumEntity(s)
        if drag.album_entity ~= nil then
            drag.counts_fn = function()
                -- netvar 与 RPC 双通道，后到的为准：清掉旧 RPC 缓存，改读 netvar
                drag.counts_str = nil
                UpdateBadges(s)
            end
            if drag.album_entity.net_counts ~= nil then
                s.inst:ListenForEvent("lmoon_album_counts_dirty", drag.counts_fn, drag.album_entity)
            end
            s.inst:ListenForEvent("itemget", drag.counts_fn, drag.album_entity)
            s.inst:ListenForEvent("itemlose", drag.counts_fn, drag.album_entity)
            s.inst:ListenForEvent("refresh", drag.counts_fn, drag.album_entity)
        end
        UpdateBadges(s)
    end

    ContainerWidget.DisableAlbumDrag = function(s)
        local drag = s.__album_drag
        if drag == nil then
            return
        end
        RemoveHandler(drag.handlers.mousebtn)
        RemoveHandler(drag.handlers.move)
        if drag.counts_fn ~= nil and drag.album_entity ~= nil then
            s.inst:RemoveEventCallback("lmoon_album_counts_dirty", drag.counts_fn, drag.album_entity)
            s.inst:RemoveEventCallback("itemget", drag.counts_fn, drag.album_entity)
            s.inst:RemoveEventCallback("itemlose", drag.counts_fn, drag.album_entity)
            s.inst:RemoveEventCallback("refresh", drag.counts_fn, drag.album_entity)
        end
        if drag.hint ~= nil then
            drag.hint:Kill()
        end
        -- 按钮是窗口的子 widget，容器关闭不会自动销毁；不清掉的话下次开册会重复叠加
        if drag.sort_btn ~= nil then
            drag.sort_btn:Kill()
        end
        active_albums[s] = nil
        s.__album_drag = nil
    end
end

-- 注意：传给 AddClassPostConstruct 的是 require 模块路径，不能带 ".lua" 后缀！
-- 带 .lua 会被加载器当成子目录（containerwidget/lua.lua），导致任何环境（含客户端）都
-- require 失败、PostConstruct 永远装不上。正确写法："widgets/containerwidget"。
-- pcall 保留作保险：专用服等异常环境静默跳过，客户端正常安装。
-- 注意：AddClassPostConstruct 是 mod 环境函数（不在 _G），必须经 mod 环境调用
local ok, err = pcall(function()
    AddClassPostConstruct("widgets/containerwidget", InstallAlbumDrag)
end)
if not ok then
    print("[lmoon_stone_album] album_drag not installed (no client UI on this context):", err)
end

-- 客户端 RPC：服务端把各槽数量（"slot:count;..."）推来后刷新角标；
-- 不依赖 netvar 同步，主机/专用服都走这条通道（同 death_stats.lua 的用法）
AddClientModRPCHandler("LittleMoon", "AlbumCounts", function(str)
    for s in pairs(active_albums) do
        if s.__album_drag ~= nil then
            s.__album_drag.counts_str = str
            UpdateBadges(s)
        end
    end
end)
