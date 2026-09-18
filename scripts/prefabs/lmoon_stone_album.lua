-- 附魔收集册（lmoon_stone_album）
-- 便携容器道具：同词条附魔石自动归拢到一个槽位（存档数据合并，详见 components/moon_album.lua）
-- 依赖：HH 附魔框架（未启用时图标/动画退化为官方书本，容器不收录任何物品）

local containers = require("containers")

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
-- 9×9 = 81 格（一种词条一槽，够放下全部附魔词条）
-- 注意：album_drag.lua 的 ZONE_HALF_W / ZONE_Y_MIN 等拖动热区常量按 9×9 网格取值，须与此处保持一致
local ALBUM_COLS = 13
local ALBUM_ROWS = 9
local ALBUM_SLOT_STEP = 80
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
    type = "pack",
    openlimit = 1,
    itemtestfn = AlbumItemTest,
}
local half_w = (ALBUM_COLS - 1) * 0.5 * ALBUM_SLOT_STEP
local half_h = (ALBUM_ROWS - 1) * 0.5 * ALBUM_SLOT_STEP
-- 原版约定（宝箱/冰箱等）：y 从高到低生成，1 号槽在左上角，从上往下填充
for y = ALBUM_ROWS - 1, 0, -1 do
    for x = 0, ALBUM_COLS - 1 do
        table.insert(containers.params.lmoon_stone_album.widget.slotpos,
            Vector3(ALBUM_SLOT_STEP * x - half_w, ALBUM_SLOT_STEP * y - half_h, 0))
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

local assets = {
    Asset("ATLAS", "images/quagmire_recipebook.xml"),
}
local prefabs = {}

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
    -- 注意：atlasname 会被客户端 replica 的 SetAtlas 用 resolvefilepath 强校验，
    -- HH 不在时该图集不存在，直接设会炸掉启动/世界加载（assert）——必须随 use_hh_anim 分支
    if use_hh_anim then
        inst.components.inventoryitem.imagename = "hh_effect_tally"
        inst.components.inventoryitem.atlasname = "images/hh_icon/hh_items.xml"
    else
        inst.components.inventoryitem.imagename = "book_gardening"
        inst.components.inventoryitem.atlasname = "images/inventoryimages.xml"
    end

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

    return inst
end

return Prefab("lmoon_stone_album", fn, assets, prefabs)
