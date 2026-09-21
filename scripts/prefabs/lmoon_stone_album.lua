-- 附魔收集册（lmoon_stone_album）
-- 便携容器道具：同词条附魔石自动归拢到一个槽位（存档数据合并，详见 components/moon_album.lua）
-- 依赖：HH 附魔框架（未启用时图标/动画退化为官方书本，容器不收录任何物品）

local containers = require("containers")

-- 执行环境提醒（踩过坑，改本文件前先看）：
--   本文件由 PrefabFiles 经 loadfile 加载（mainfunctions.lua:150），跑在**游戏全局环境**
--   里，而不是 modimport 的沙箱环境。两者差别很关键：
--     · 沙箱里 GLOBAL 是 _G 的别名；这里没有 GLOBAL，写 GLOBAL.xxx 会直接报
--       "variable 'GLOBAL' is not declared"（strict.lua 拦截未声明全局的读取）。
--     · 但这里能用裸全局名（TheWorld / TUNING / Moon_Say ...），也能用 _G 本身。
--       本 mod 用 `function _G.Moon_xxx()` 挂在真实 _G 上的跨文件函数，在这个环境里
--       可以直接按裸名字读到（modimport 沙箱里写的是 _G 真表，不是沙箱表）。
--   所以：绝对不要写 `local _G = GLOBAL`；需要新增全局时用 rawset(_G, ...) 绕过 strict。

-- HH 附魔石注册表（跨 mod require，未启用时为 nil）
local ok_hh, hh_enchant = pcall(require, "enums/hh_enchant")
local HH_EQUIP_BUFF_LIST = ok_hh and hh_enchant ~= nil
    and hh_enchant["HH_EQUIP_BUFF_LIST"] or nil

local use_hh_anim = HH_EQUIP_BUFF_LIST ~= nil
    and type(Moon_IsHHEnabled) == "function"
    and Moon_IsHHEnabled()

---- 统一取词条 id：服务端读 hh_effect；客户端近似读 netvar hh_client_effect
local function GetItemEffect(item)
    if item == nil then
        return nil
    end
    if item.hh_effect ~= nil then
        return item.hh_effect
    end
    local ne = item.hh_client_effect
    if ne ~= nil then
        local v = ne:value()
        if v ~= nil and v ~= "" then
            return v
        end
    end
    return nil
end

---- 容器物品过滤：只收含有效词条的附魔石；且已占用的槽位只接受同词条石头
---- （一个槽位只归拢一种词条，禁止不同词条挤进同一槽，否则取出时词条错位）
---- 服务端按 HH 注册表校验；客户端用 netvar（hh_client_effect）近似校验
local function AlbumItemTest(container, item, slot)
    if item == nil or item.prefab ~= "hh_effect_stone" then
        return false
    end
    local effect = GetItemEffect(item)
    if effect == nil then
        return false
    end
    if TheWorld.ismastersim then
        if HH_EQUIP_BUFF_LIST == nil or HH_EQUIP_BUFF_LIST[effect] == nil then
            return false
        end
    end
    -- 槽位类型守卫：目标槽已有石头且词条不同 → 拒绝（防止展示石与后台存货词条错位）
    if slot ~= nil and container ~= nil then
        local existing = container:GetItemInSlot(slot)
        if existing ~= nil and existing.prefab == "hh_effect_stone" then
            local ex_effect = GetItemEffect(existing)
            if ex_effect ~= nil and ex_effect ~= effect then
                return false
            end
        end
    end
    return true
end

-- 注入容器 UI 参数（服务端 + 客户端各执行一次本文件，注册表按 prefab 名共享）
-- 布局：左右两页各 9×9，共 162 格（一种词条一槽，够放下全部附魔词条）
-- 槽位编号：左页 = 1~81，与原单页 9×9 的生成顺序完全一致（旧存档槽位语义不变，只是整体左移）；
--          右页 = 82~162，左页填满后接着用。
-- 注意：album_drag.lua 的 ZONE_HALF_W / ALBUM_PANEL_W 等常量按此布局取值，须与此处保持一致
local ALBUM_COLS = 9
local ALBUM_ROWS = 9
local ALBUM_PAGES = 2
local ALBUM_SLOT_STEP = 80
local ALBUM_PAGE_GAP = 90 -- 两页之间的装订缝（纯留白，不占槽位）
-- 下限约束：槽位贴图 inv_slot 本身宽 64，缝宽 ≤64 时两页最边上的槽会视觉重叠。
-- 取 90 让跨页缝隙（26）略大于页内间隙（16）：看得出分页，又不至于把两页拉开。
containers.params.lmoon_stone_album = {
    widget = {
        slotpos = {},
        -- 面板边框：借用菜谱书纸张背景（原版无 9×9 箱贴图），Open 后由 album_drag 拉伸到网格大小
        bgatlas = "images/quagmire_recipebook.xml",
        bgimage = "quagmire_recipe_menu_bg.tex",
        -- pos：容器锚点 containerroot 在屏幕中心，设 (0,0,0) 让窗口居中
        pos = Vector3(0, 0, 0),
        side_align_tip = 160,
    },
    -- 非侧边容器：挂在屏幕中央锚点（containerroot），issidewidget=true 会挂到右侧锚点
    issidewidget = false,
    -- type 必须与背包区分开：原版 Container:Open 会按「同 prefab 或同 type」自动关闭
    -- 已打开的同类型容器（components/container.lua）。背包 type 是 "pack"，
    -- 若这里也写 "pack"，开收集册会强制关掉背包、开背包也会关掉收集册，两者无法并存。
    -- 取独立 type 后互不干扰；该值未命中 playerhud 的特殊分支，仍落在 containerroot，位置不变。
    type = "lmoon_album",
    -- 不设 openlimit：与宝箱一致，扔在地上后允许多人同时打开（RUMMAGE.fn 里有
    -- CanOpen() 校验，若设 openlimit=1 则一人开着时其他玩家会打不开）。
    itemtestfn = AlbumItemTest,
}
local page_w = (ALBUM_COLS - 1) * ALBUM_SLOT_STEP
local total_w = page_w * ALBUM_PAGES + ALBUM_PAGE_GAP * (ALBUM_PAGES - 1)
local half_h = (ALBUM_ROWS - 1) * 0.5 * ALBUM_SLOT_STEP
-- 两页各自的起始 x：整幅左右对称居中（左页整体偏左、右页整体偏右，装订缝落在正中）
local page_x0 = {
    -total_w * 0.5,
    -total_w * 0.5 + page_w + ALBUM_PAGE_GAP,
}
-- 原版约定（宝箱/冰箱等）：y 从高到低生成，1 号槽在左上角，从上往下填充
-- 逐页生成：左页 1~81，右页 82~162
for page = 1, ALBUM_PAGES do
    local x0 = page_x0[page]
    for y = ALBUM_ROWS - 1, 0, -1 do
        for x = 0, ALBUM_COLS - 1 do
            table.insert(containers.params.lmoon_stone_album.widget.slotpos,
                Vector3(x0 + ALBUM_SLOT_STEP * x, ALBUM_SLOT_STEP * y - half_h, 0))
        end
    end
end
containers.MAXITEMSLOTS = math.max(containers.MAXITEMSLOTS or 0,
    #containers.params.lmoon_stone_album.widget.slotpos)

---- 词条展示名
local function EffectDisplayName(effect_id)
    if effect_id ~= nil and HH_EQUIP_BUFF_LIST ~= nil
        and HH_EQUIP_BUFF_LIST[effect_id] ~= nil then
        return HH_EQUIP_BUFF_LIST[effect_id]["name"] or tostring(effect_id)
    end
    return tostring(effect_id or "???")
end

local function GetAlbumDescription(inst)
    local album = inst.components ~= nil and inst.components.moon_album or nil
    if album == nil then
        return "一本装订好的附魔收集册"
    end
    return album:GetSummary(EffectDisplayName)
end

-- ============================================================
-- 「整理」功能支撑
-- ============================================================
-- 全局实例表：整理 RPC 要定位「玩家正打开的那一本收集册」。
-- 服务端只能从容器反查 openers，而玩家对象上没有「当前打开容器」的记录，
-- 因此维护一份弱引用集合（实体销毁后自动回收，另加 onremove 显式清理）。
-- 挂在 _G 上：mod 热重载时表得以保留，不会丢失已登记的实例。
-- 用 rawget/rawset 读写：本文件跑在游戏全局环境里，strict.lua 会拦未声明全局的读取，
-- 而 rawget/rawset 直接操作原表、绕过元表，既能安全地取「可能还不存在」的表，
-- 也避免第一次读取时被 strict 当成未声明变量报错。
local MOON_ALBUMS = rawget(_G, "MOON_ALBUMS")
if MOON_ALBUMS == nil then
    MOON_ALBUMS = setmetatable({}, { __mode = "k" })
    rawset(_G, "MOON_ALBUMS", MOON_ALBUMS)
end

-- ============================================================
-- 整理排序依据：附魔石背景色（"整理"按钮唯一的排序键）
-- ============================================================
-- 「整理」只认一样东西——附魔石图标的背景色。同色的石头在册子里连成一片，
-- 颜色组之间的先后由下面的 COLOR_ORDER 决定（行的顺序 = 整理后的顺序）。
--
-- 背景色取自 HH 词条配置的 client_color 字段（HH 就是拿它染附魔石飘字的，
-- 见 hh_prefabs.lua）。小月亮 / 附魔强化 / 更多附魔石 三个来源用的是同一个
-- 字段，所以这里不需要区分来源，也不需要星级或档位，一张颜色表通吃。
-- ⚠️ 例外：HH 自带的大多数词条（小攻速 / 加血 / 吸血等）压根没写
--    client_color，运行时按 HH 自己的兜底显示（can_add == false → 橙，
--    其余 → 白）。排序在 AlbumColorRank 里复刻了同一套兜底，见下方注释。
--
-- ⚠️ 小月亮自己的附魔目前被 tier_display.lua 统一染成紫色（T0~T4 同色），
--    所以它们在册子里会连成一大片、彼此不分先后。想让它们按档位分开，
--    改 tier_display.lua 的 TIER_COLORS 即可，本文件不用动。
--
-- ★ 想调整顺序：直接移动 COLOR_ORDER 里的整行；想加新颜色，照格式加一行。
--   表里没列的颜色会自动排到已列颜色之后（同色仍然相邻）。
-- ============================================================

-- 颜色表：{ 颜色名（仅供阅读/调试）, R, G, B }
-- 顺序 = 整理后的先后，按「暖色（稀有） → 冷色 → 黑白灰（基础）」排，
-- 即稀有的颜色组排前面、基础的排后面。
-- 里面有几个色（黑/白/浅灰/蓝/青/绿/深青）是「更多附魔石」调色板里定义、
-- 但当前还没有词条在用的，先占好位置——将来有石头用上就不用再回来改表。
local COLOR_ORDER = {
    { "猩红", 255, 0, 0 },         -- 稀★系列 / 终幕 / 天外天环 / 超级稀有宝石
    { "HH橙", 255, 97, 0 },        -- HH 未写颜色且不可卷轴附魔的词条（HH 显示兜底橙）
    { "橙色", 255, 128, 0 },       -- 元素系列 + 各 mod 专属
    { "暗金", 142, 91, 0 },        -- 附魔强化指定色
    { "金黄", 255, 255, 0 },       -- 高级（斩杀 / 暴击伤害 / 免疫卸甲 / 大幸运 / 大增伤）
    { "HH默认", 101, 255, 0 },     -- 外部接口注册但未指定颜色的词条（AddSpecialEquipEffect 的默认色）
    { "绿色", 0, 255, 0 },
    { "粉色", 255, 192, 203 },     -- 枝江系列（蜜意甜心）
    { "紫色", 204, 0, 204 },       -- 小月亮（T0~T4 统一色）
    { "青色", 0, 255, 255 },
    { "苍穹蓝", 154, 200, 226 },   -- 精英（破命 / 死亡之舞 / 阴烛侵蚀 / 玲珑圣印）
    { "蓝色", 0, 0, 255 },
    { "深蓝绿", 0, 40, 80 },       -- 诡秘系列
    { "深青", 0, 40, 40 },
    { "白色", 255, 255, 255 },     -- HH 自带基础词条（未写颜色时的显示默认色）
    { "象牙白", 250, 250, 245 },   -- 德★ 七美德系列
    { "浅灰", 204, 204, 204 },
    { "灰色", 128, 128, 128 },     -- 基础（小幸运 / 小增伤 / 元素核心 / 耐久 / 采集）
    { "深灰", 51, 51, 51 },
    { "深炭灰", 20, 20, 20 },      -- 罪★ 七原罪系列
    { "黑色", 0, 0, 0 },
}

-- 表里没列的颜色：排在所有已列颜色之后，用 RGB 整数键当次序
-- （保证「同色仍然相邻」且每次结果一致；键最大约 1.7e7，仍远小于下面的兜底值）
local COLOR_UNKNOWN_BASE = 1000
-- 完全没有颜色信息的（注册表里查不到该词条——正常只有混进非附魔石物品才会出现）：
-- 排到最后。注意 HH 自带词条虽然大多没写 client_color，但它们走上面的显示兜底，
-- 不会落进这一档。
local COLOR_NO_COLOR = 999999999

-- ------------------------------------------------------------
-- client_color（{r,g,b,a} 浮点 0~1）→ 量化后的 RGB 整数键
-- ------------------------------------------------------------
-- 量化：每通道先换算成 0~255 整数，再按 QUANT 归并，最后才拼成 key。
-- 为什么要归并：同一个颜色在不同 mod 里可能写成 0.75 和 0.753 这种肉眼无差的
-- 近似值（实测粉色同时存在 (255,191,204) 与 (255,192,203) 两种写法），不归并
-- 会被拆成两组、分到册子两头。归并到 16 级（每级约 6%）足以吸收这类误差，
-- 又不会把本来不同的颜色混到一起。
local QUANT = 16

-- 单通道量化：0~255 的整数 → 归并到 QUANT 的整数倍
local function QuantCh(v)
    local q = math.floor(v / QUANT + 0.5) * QUANT
    if q < 0 then return 0 end
    if q > 255 then return 255 end
    return q
end

-- 颜色表与词条颜色走同一个量化函数，保证两边的 key 一定能对上
local function ColorKey(color)
    if type(color) ~= "table" then return nil end
    local r, g, b = color[1], color[2], color[3]
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    local qr = QuantCh(math.floor(r * 255 + 0.5))
    local qg = QuantCh(math.floor(g * 255 + 0.5))
    local qb = QuantCh(math.floor(b * 255 + 0.5))
    return qr * 65536 + qg * 256 + qb
end

-- HH 自带词条的显示兜底色（必须与 hh_prefabs.lua updateChildText 的染色逻辑一致）：
-- HH 注册表里一大批词条（小攻速 / 加血 / 吸血等）的 client_color 是被注释掉的，
-- 运行时 HH 对它们不染色——Label 默认白；只有 can_add == false（不可卷轴附魔）
-- 的词条被染成 (255,97,0) 的橙。排序必须复刻同一套兜底，否则这批词条会全部
-- 落进「无颜色」档、被甩到册子最末尾（上一版整理乱序的主因）。
-- 两个 key 都用 ColorKey 现算，与颜色表行（"白色"/"HH橙"）走同一量化路径。
local COLOR_FALLBACK_ORANGE = ColorKey({ 255 / 255, 97 / 255, 0, 1 })
local COLOR_FALLBACK_WHITE = ColorKey({ 1, 1, 1, 1 })

-- 量化后的 RGB 键 → 颜色组序号（1 起，越小越靠前）
local COLOR_RANK = {}
for i, c in ipairs(COLOR_ORDER) do
    COLOR_RANK[QuantCh(c[2]) * 65536 + QuantCh(c[3]) * 256 + QuantCh(c[4])] = i
end

---- 取某个词条的整理权重（越小越靠前）
---- 只看附魔石背景色：同色相邻，颜色组之间的次序由 COLOR_ORDER 决定；
---- 组内的先后交给 SortByRank 用 effect_id 兜底（effect_id 唯一 → 全序，
---- 规避 table.sort 不稳定导致同组内每次顺序不同）。
---- 注：这里的 HH_EQUIP_BUFF_LIST 是本文件第 18~20 行 pcall(require, "enums/hh_enchant")
----     拿到的**局部表**（与 HH 是同一张活表，tier_display.lua 改的颜色也在这里生效），
----     不是 modimport 沙箱里那个同名全局——那个全局在本文件所在的环境里根本读不到。
local function AlbumColorRank(effect_id)
    local cfg = HH_EQUIP_BUFF_LIST ~= nil and HH_EQUIP_BUFF_LIST[effect_id] or nil
    if cfg == nil then
        return COLOR_NO_COLOR
    end
    local key = ColorKey(cfg.client_color)
    if key == nil then
        -- 复刻 HH 的显示兜底：排序键与玩家看到的飘字颜色保持一致
        key = (cfg.can_add == false) and COLOR_FALLBACK_ORANGE or COLOR_FALLBACK_WHITE
    end
    local rank = COLOR_RANK[key]
    if rank ~= nil then
        return rank
    end
    return COLOR_UNKNOWN_BASE + key
end

local assets = {
    Asset("IMAGE", "images/inventoryimages/lmoon_stone_album.tex"),
    Asset("ATLAS", "images/inventoryimages/lmoon_stone_album.xml"),
    Asset("ATLAS", "images/quagmire_recipebook.xml"),
}
local prefabs = {}

-- ============================================================
-- 地面贴图（Image 图标，血条同款方案）
-- ============================================================
-- 物品躺在地上时的外观：用引擎 Image 实体直接渲染物品栏图集贴图，
-- 不再依赖 bank/build 动画。要点：
--   · Image 组件不随网络复制，贴图由各端本地设置——创建逻辑放在 fn()
--     的公共分支（服务端/客户端都会执行），非网络子实体 SetParent 挂本体
--     （参照 components/healthbar.lua 的做法）。
--   · Image 是「跟随实体、始终朝向屏幕」的覆盖层，躺在背包/容器里时
--     若不关闭会飘在玩家/箱子头上——用 IsHeld 区分：躺地上才 Enable。
--   · 本体 AnimState（HH 印章/书本兜底）保留为兜底外观，躺地上时
--     整体透明（alpha 0）避免"印章+悬浮图标"两个外观叠加。
local ALBUM_ICON_ATLAS = "images/inventoryimages/lmoon_stone_album.xml"
local ALBUM_ICON_TEX = "lmoon_stone_album.tex"
-- 尺寸/贴地参考：血条 bar 100x10、world_offset y=3（那是刻意悬在怪头顶）。
-- 原版物品落地没有偏移：物理落定后实体原点=贴地点、动画底部画在原点
-- （inventoryitem.lua DoDropPhysics）。Image 以"原点+offset"为中心渲染，
-- 因此 offset 取图标半高让底边贴地，而不是悬空。
local GROUND_ICON_SIZE = 80
local GROUND_ICON_OFFSET_Y = 0.4

local function CreateGroundIcon(inst)
    local img = CreateEntity("lmoon_album_groundicon")
    img.entity:AddTransform()
    img.entity:AddImage()
    img:AddTag("NOCLICK")
    img.persists = false
    img.Image:SetTexture(resolvefilepath(ALBUM_ICON_ATLAS), ALBUM_ICON_TEX)
    img.Image:SetSize(GROUND_ICON_SIZE, GROUND_ICON_SIZE)
    img.Image:SetWorldOffset(0, GROUND_ICON_OFFSET_Y, 0)
    img.entity:SetParent(inst.entity)
    img.Image:Enable(false)
    return img
end

-- 躺地上（不在任何 holder 里）→ Enable 图标、隐藏本体动画；被持有 → 反之。
-- 服务端查 inventoryitem 组件，客户端查 replica；事件只在服务端可靠触发，
-- 客户端靠低频轮询兜底（每册 0.5s 一次，开销可忽略）。
local function UpdateGroundVisual(inst)
    local img = inst.MOON_GROUND_IMG
    if img == nil or img.Image == nil then return end
    local held
    if TheWorld.ismastersim then
        held = inst.components ~= nil and inst.components.inventoryitem ~= nil
            and inst.components.inventoryitem:IsHeld()
    else
        held = inst.replica ~= nil and inst.replica.inventoryitem ~= nil
            and inst.replica.inventoryitem:IsHeld()
    end
    img.Image:Enable(not held)
    inst.AnimState:SetMultColour(1, 1, 1, held and 1 or 0)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    -- 槽位计数同步（"槽位:总数;..."，客户端角标用；净变量须在 SetPristine 前创建）
    inst.net_counts = net_string(inst.GUID, "lmoon_album_counts", "lmoon_album_counts_dirty")

    inst:AddTag("lmoon_stone_album")

    MakeInventoryPhysics(inst)

    if use_hh_anim then
        -- 借用 HH 的物品动画，外观为附魔印章
        inst.AnimState:SetBank("hh_items")
        inst.AnimState:SetBuild("hh_items")
        inst.AnimState:PlayAnimation("idle", true)
        inst.AnimState:OverrideSymbol("hh_remove_stone", "hh_items", "hh_effect_tally")
    else
        -- HH 未启用时的兜底外观（官方书本动画）
        inst.AnimState:SetBank("book")
        inst.AnimState:SetBuild("book_gardening")
        inst.AnimState:PlayAnimation("idle", true)
    end

    -- 地面贴图：公共分支创建（服务端/客户端各一份本地子实体）
    inst.MOON_GROUND_IMG = CreateGroundIcon(inst)
    inst:DoTaskInTime(0, UpdateGroundVisual)
    inst:ListenForEvent("onputininventory", UpdateGroundVisual)
    inst:ListenForEvent("ondropped", UpdateGroundVisual)
    inst:DoPeriodicTask(0.25, UpdateGroundVisual)

    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        inst.OnEntityReplicated = function(inst)
            if inst.replica.container ~= nil then
                inst.replica.container:WidgetSetup("lmoon_stone_album")
            end
        end
        return inst
    end

    inst:AddComponent("inspectable")
    inst.components.inspectable.getspecialdescription = GetAlbumDescription

    inst:AddComponent("inventoryitem")
    -- 物品栏图标：用自己的 lmoon_stone_album 图集（xml 元素名 lmoon_stone_album.tex，
    -- imagename 按 DST 约定不带 .tex，replica SetImage 会自动补）。
    -- 该图集在本 mod 内、且已在上方 assets 注册（resolvefilepath 可解析），
    -- 与 HH 是否启用无关，两种分支下图标都一致。
    inst.components.inventoryitem.imagename = "lmoon_stone_album"
    inst.components.inventoryitem.atlasname = "images/inventoryimages/lmoon_stone_album.xml"

    inst:AddComponent("container")
    inst.components.container:WidgetSetup("lmoon_stone_album")
    inst.components.container.onopenfn = function(inst, doer)
        local album = inst.components.moon_album
        if album ~= nil then
            album:RestockAll()
            -- 开册 0 帧后再推一次数量（此时打开者已加入 openlist）
            inst:DoTaskInTime(0, function()
                if inst:IsValid() and inst.components.moon_album ~= nil then
                    inst.components.moon_album:UpdateCounts()
                end
            end)
        end
    end

    inst:AddComponent("moon_album")
    inst.components.moon_album:SetupContainer()

    -- 登记到全局实例表，供整理 RPC 反查（客户端不需要，只在服务端分支执行）
    MOON_ALBUMS[inst] = true
    inst:ListenForEvent("onremove", function()
        MOON_ALBUMS[inst] = nil
    end)

    return inst
end

-- ============================================================
-- 整理 RPC（服务端）：把发起者正打开的收集册按附魔石背景色重排。
-- 客户端只发请求——排序必须走服务端，容器数据与存档都在服务端。
-- ============================================================
AddModRPCHandler("LittleMoon", "AlbumSort", function(player)
    if player == nil or not TheWorld.ismastersim then return end
    for inst in pairs(MOON_ALBUMS) do
        if inst:IsValid()
            and inst.components.container ~= nil
            and inst.components.container:IsOpenedBy(player)
            and inst.components.moon_album ~= nil then
            local n = inst.components.moon_album:SortByRank(AlbumColorRank)
            if n > 0 then
                Moon_Say(player, string.format("已按附魔石颜色整理 %d 种附魔石", n))
            else
                Moon_Say(player, "册子里没有需要整理的附魔石")
            end
            return
        end
    end
end)

return Prefab("lmoon_stone_album", fn, assets, prefabs)
