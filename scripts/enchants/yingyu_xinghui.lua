-- 樱语星辉：小樱专属制作，星之杖专用。
local G = GLOBAL
if not G.MOON_CFG.ENABLE_MORE_ENCHANTS then return end

local adapter = require("moon_utils/yingyu_starstaff")
local EFFECT_ID = adapter.EFFECT_ID
local PRODUCT = "lmoon_effect_stone_yingyu_xinghui"
local registered = false

local function RegisterEnchant()
    local register = G.rawget(G, "AddSpecialEquipEffect")
    local ingredients = G.rawget(G, "CHARACTER_INGREDIENT")
    if registered or not G.Moon_IsHHEnabled() or type(register) ~= "function"
        or not ingredients or not ingredients.CCS_MAGIC then return end

    register(EFFECT_ID, {
        name = "樱语星辉",
        client_text = "樱语\n星辉",
        desc = "库洛魔法使的力量",
        check_desc = "仅限星之杖；彩虹宝石提供的真实伤害转为小樱本体的樱花伤害",
        ui_from_desc = "小樱消耗225魔力制作；成功封印有0.05%概率获得，1500次保底",
        obtain_desc = "小樱消耗225魔力制作；每次成功封印0.05%概率获得，1500次保底（掉落后重置）",
        obtains = {},
        -- 不声明 recipes：不写 __recipe__ 别名键，与其他附魔一致。
        -- 代价是制作栏配方格不再叠加 client_text 花字（物品名仍正常显示）。
        can_add = false,
        only_one = true,
        only_compound = true,
        is_special = true,
        client_color = { 1, 0.45, 0.75, 1 },
        check_equip_can_add = function(inst)
            return inst ~= nil and inst.prefab == "ccs_starstaff",
                "樱语星辉只能附魔在星之杖上"
        end,
        start_fn = function(inst)
            if inst._lmoon_yingyu then inst._lmoon_yingyu:set(true) end
        end,
        end_fn = function(inst)
            if inst._lmoon_yingyu then inst._lmoon_yingyu:set(false) end
        end,
    })
    registered = true
end

-- 世界创建时双方都注册词条；此时其它模组的 modmain 已加载完毕。
AddPrefabPostInit("world", RegisterEnchant)
AddSimPostInit(function()
    RegisterEnchant()
    if registered and G.TheWorld.ismastersim then
        -- 等其它模组的AddSimPostInit完成，兼容额外的物品封印动作。
        G.TheWorld:DoTaskInTime(0, function()
            require("moon_utils/yingyu_seal").Install()
        end)
    end
    if not registered or G.AllRecipes[PRODUCT] then return end
    AddRecipe2(PRODUCT, {
        Ingredient(G.CHARACTER_INGREDIENT.CCS_MAGIC, 225,
            "images/inventoryimages/ccs_magic.xml"),
    }, TECH.NONE, {
        builder_tag = "ccs",
        nounlock = true,
        no_deconstruction = true,
        atlas = "images/hh_icon/hh_items.xml",
        image = "hh_effect_stone.tex",
        canbuild = function(recipe, builder)
            local magic = builder.components.ccs_magic
            -- 本体的材料检查会向上取整，此处避免224.x魔力也能制作。
            return builder.prefab == "ccs" and magic ~= nil and magic.current >= 225
        end,
    }, { "CCS_TAB1" })
end)

AddPrefabPostInit("ccs", function(inst)
    if G.TheWorld.ismastersim and registered then
        inst:AddComponent("lmoon_yingyu_pity")
    end
end)

AddPrefabPostInit("ccs_starstaff", function(inst)
    local hh_available = G.Moon_IsHHEnabled()
        and type(G.rawget(G, "AddSpecialEquipEffect")) == "function"
    if hh_available then inst:AddTag("hh_equip") end
    inst._lmoon_yingyu = G.net_bool(inst.GUID, "lmoon.yingyu_xinghui")
    local old_name = inst.displaynamefn
    if old_name then
        inst.displaynamefn = function(item, ...)
            local name = old_name(item, ...)
            if item._lmoon_yingyu:value() and type(name) == "string" then
                name = name:gsub("真实伤害强化:", "樱花伤害强化:")
            end
            return name
        end
    end
    if not G.TheWorld.ismastersim then return end
    -- HH默认只开放原版装备；单独开放星之杖，不要求打开所有mod装备强化。
    if hh_available and not inst.components.hh_equip then
        inst:AddComponent("hh_equip")
        inst.components.hh_equip:SetMaxGemLimit(3)
        inst.components.hh_equip:SetEquipBuffLimit(5)
    end
    adapter.Install(inst)
    -- 在全部组件读档结束后，按实际词条列表校准客户端显示。
    inst:DoTaskInTime(0, function(item)
        item._lmoon_yingyu:set(adapter.HasEffect(item))
    end)
end)

STRINGS.NAMES.LMOON_EFFECT_STONE_YINGYU_XINGHUI = "樱语星辉"
STRINGS.RECIPE_DESC.LMOON_EFFECT_STONE_YINGYU_XINGHUI = "库洛魔法使的力量"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.LMOON_EFFECT_STONE_YINGYU_XINGHUI = "库洛魔法使的力量"
