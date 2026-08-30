local containers = require("containers")
local HH_LANGUAGE, HH_EQUIP_BUFF_LIST

-- 小月亮 附魔：以太
-- 增强拆除法杖的功能
local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG
local Max_Transform_Times = CFG.TRANSFORM_LIMIT

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_NAME = "Legend_AETHER"

local function is_common_effect(effect)
    return HH_EQUIP_BUFF_LIST[effect] and HH_EQUIP_BUFF_LIST[effect]["can_add"]
end

local function rand_pick_on_pool(pool) return pool[math.random(1, #pool)] end

local function get_effect_name(effect)
    return HH_EQUIP_BUFF_LIST[effect] and HH_EQUIP_BUFF_LIST[effect]["name"]
end

function is_hh_type(data, hh_type)
    if data and type(data) == hh_type then return true end
    return false
end

function get_player_data_by_key(player, item_key)
    if not (player.components and player.components.hh_data) and
        is_hh_type(item_key, "string") then return 0 end
    return tonumber(player.components.hh_data:GetParamsValue(item_key)) or 0
end

function dodelta_player_data_by_key(player, item_key, value)
    if not (player.components and player.components.hh_data) and
        is_hh_type(item_key, "string") then return 0 end
    player.components.hh_data:DoDeltaParamValue(item_key, value)
end

function add_log(log_type, log_msg)
    if not (TheWorld.components and TheWorld.components.hh_world_log) then
        return
    end
    TheWorld.components.hh_world_log:AddLog(log_type, log_msg)
end

function template(template, data)
    if not data or type(data) ~= "table" then
        return "入参错误 需要table格式"
    end
    return template:gsub("{{([^{}]+)}}", function(match)
        local value = data[match]
        if value == nil or
            not (type(value) == "string" or type(value) == "number") then
            value = ""
        end
        return value
    end)
end

function get_language_by_key(type_index, item_key)
    local base_str = "未定义"
    if not (is_hh_type(type_index, "string") and is_hh_type(item_key, "string")) then
        return base_str
    end
    if not is_hh_type(HH_LANGUAGE[type_index], "table") then return base_str end
    return tostring(HH_LANGUAGE[type_index][item_key] or base_str)
end

function update_skin_item(player, target)
    if player.components and player.components.hh_skin and
        is_hh_type(target, "table") then
        player.components.hh_skin:ToolChangeSkin(target)
    end
end

-- 附魔石没有提供依据 effect 的完整更新方式，客户端的视觉状态无法有效的和它的数据状态保持一致，改用重新创建的方式来替换附魔石
local function replace_stone(stone_origin, effect, player)
    local parent = stone_origin.entity:GetParent()

    local stone = SpawnPrefab("hh_effect_stone")
    stone.hh_effect = effect
    stone:HH_Update_Server()
    update_skin_item(player, stone)

    if not parent then -- 在地上
        local x, y, z = stone_origin.Transform:GetWorldPosition()
        stone_origin:Remove()

        stone.Transform:SetPosition(x, y, z)
        return
    elseif parent.components and parent.components.inventory or
        parent.components.container then
        local container = parent.components.inventory or
                              parent.components.container -- 物品栏和容器里的
        local slot = container:GetItemSlot(stone_origin)
        stone_origin:Remove()
        container:GiveItem(stone, slot)
    end
end

-- 自动转换附魔石
local function auto_transform_stone(essence_provider, stone, player)
    if not essence_provider.components or
        not essence_provider.components.container then return end
    if not stone or stone.prefab ~= "hh_effect_stone" then return end

    local essence_container = essence_provider.components.container
    local stone_effect_origin = stone["hh_effect"]
    local player_name = player.name or
                            STRINGS.NAMES[string.upper(player.prefab)]
    local player_pos = player:GetPosition()

    local spawn_new_stone = nil
    local base_expend_essence_num = 5
    -- 已经消耗的水晶小人数量
    local current_expend_essence = get_player_data_by_key(player,
                                                          "expend_essence")

    local stone_effect_newly = stone_effect_origin

    local _, essence_count = essence_container:Has("hh_essence", 0)

    local cosume_count = 0
    local per_cosume = base_expend_essence_num
    local try_count = 0

    while is_common_effect(stone_effect_newly) and essence_count >= cosume_count +
        per_cosume and
        (Max_Transform_Times == "INF" or try_count <= Max_Transform_Times) do

        cosume_count = cosume_count + per_cosume
        try_count = try_count + 1

        local random_num = math["random"](1, 100)

        if random_num <= 1 then
            stone_effect_newly = rand_pick_on_pool(_G["HHGetRareEquipEffect"]())
            if not stone_effect_newly then return end

            local shown_effect_name = get_effect_name(stone_effect_newly) or
                                          "???"
            TheNet:Announce(string["format"](
                                "%s好运当头，合成出:超超超稀有的%s",
                                tostring(player_name),
                                tostring(shown_effect_name)))
            -- 增加世界日志
            add_log("stone",
                    template(get_language_by_key("log", "compound_stone_rare"),
                             {
                ["data_player"] = player_name,
                ["data_effect"] = shown_effect_name,
                ["data_essence"] = cosume_count + current_expend_essence
            }))
        elseif random_num <= 5 then
            stone_effect_newly = rand_pick_on_pool(_G["HHGetGoodEquipEffect"]())
            -- 增加播报
            if not stone_effect_newly then return end
            local shown_effect_name = get_effect_name(stone_effect_newly) or
                                          "???"
            TheNet:Announce(string["format"]("%s运气爆棚，合成出-%s",
                                             tostring(player_name),
                                             tostring(shown_effect_name)))
            -- 增加世界日志
            add_log("stone",
                    template(get_language_by_key("log", "compound_stone_best"),
                             {
                ["data_player"] = player_name,
                ["data_effect"] = shown_effect_name,
                ["data_essence"] = cosume_count + current_expend_essence
            }))
        else
            stone_effect_newly = rand_pick_on_pool(_G["HHGetComEquipEffect"]())
        end

    end

    if try_count <= 0 then return end

    essence_container:ConsumeByName("hh_essence", cosume_count)
    replace_stone(stone, stone_effect_newly, player)

    -- roll 到普通附魔石的次数
    local lose_count = is_common_effect(stone_effect_newly) and try_count - 1 or
                           try_count

    -- 登记一下抽奖次数-用于发送特殊蛋奖励
    if player.components and player.components.hh_data then
        -- 根据原算法，最多 100 次否则会丢失信息
        while lose_count > 0 do
            dodelta_player_data_by_key(player, "draw_lots_num_rare",
                                       math.min(lose_count, 100))
            lose_count = lose_count - 100
        end
        -- 记录一下消耗的水晶小人 后续可能会做数据统计相关
        dodelta_player_data_by_key(player, "expend_essence", cosume_count)
    end
end

-- 就地转换附魔石
local function transform_stones_inplace(inst, target, pos, caster)
    if is_hh_type(pos, "table") and pos["x"] and pos["y"] and pos["z"] then
        -- 先拆除附魔石
        local stone_entities = TheSim:FindEntities(pos["x"], pos["y"], pos["z"],
                                                   8, {"hh_add_stone"},
                                                   EQUIP_BLACK_TAG, {
            "_inventoryitem", "pickable"
        })

        if stone_entities and #stone_entities > 0 then
            local common_pool = HHGetComEquipEffect()
            for i, stone in ipairs(stone_entities) do
                if stone and stone.prefab == "hh_effect_stone" then
                    if stone.hh_effect and is_common_effect(stone.hh_effect) then
                        auto_transform_stone(inst, stone, caster)
                    end
                end
            end
        end
    end
end

local handle_map = {
    -- TODO: 月岩，把非普通附魔石转成普通附魔石
    ["moonrocknugget"] = function(inst, target, pos, doer) end,
    -- 水晶道具，自动转换
    ["hh_essence"] = function(inst, target, pos, doer)
        transform_stones_inplace(inst, target, pos, doer)
    end
}

local noop = function() end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    local ok, hh_enchant = pcall(function()
        return require("enums/hh_enchant")
    end)
    if not ok or not hh_enchant then return end
    HH_EQUIP_BUFF_LIST = hh_enchant["HH_EQUIP_BUFF_LIST"]

    local ok, hh_language = pcall(function()
        return require("enums/hh_language")
    end)
    if not ok or not hh_language then return end
    HH_LANGUAGE = hh_language

    GLOBAL.AddSpecialEquipEffect(EFFECT_NAME, {
        name = "以太",
        client_text = "以\n太",
        desc = "增强拆除法杖的功能",
        check_desc = "附魔在拆除法杖后内部放入以下道具解锁新功能：\n【月岩】: 消耗月岩进行将高级附魔石转成普通附魔石，一个月岩一次\n【水晶道具】: 自动转换，消耗里面的水晶道具对地上的附魔石进行附魔石转换，直到无法转换或水晶道具耗尽为止",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = {0.8, 0, 0.8, 1},
        check_equip_can_add = function(inst)
            if inst and inst.prefab == "hh_staff_dis" then
                return true, "满足条件"
            end
            return false, "仅能附魔在拆除法杖中"
        end,
        on_equip_fn = function(inst, owner, value) end,
        un_equip_fn = function(inst, owner, value) end,
        start_fn = function(inst, value)
            inst:AddTag("moon_hh_effect_aether")
        end,
        end_fn = function(inst, value)
            inst:RemoveTag("moon_hh_effect_aether")
        end
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_NAME, 0)

    -- 允许拆解法杖接收新的物品
    local containers_widgetsetup = containers["widgetsetup"]
    function containers.widgetsetup(container, prefab, data)
        containers_widgetsetup(container, prefab, data)

        local host_prefab = prefab or container.inst.prefab
        if host_prefab == "hh_staff_dis" then
            local old_itemtestfn = container.itemtestfn
            container.itemtestfn = function(self, item, slot)
                local activating = self.inst:HasTag("moon_hh_effect_aether")
                if activating and item and handle_map[item.prefab] then
                    return true
                end
                return old_itemtestfn and old_itemtestfn(self, item, slot)
            end
        end

    end

end)

-- 拓展拆除法杖的功能
AddPrefabPostInit("hh_staff_dis", function(inst)
    if not GLOBAL.TheWorld.ismastersim then return end

    if not inst.components or not inst.components.spellcaster then return end
    if not inst.components or not inst.components.container then return end

    local old_spell_fn = inst.components.spellcaster.spell
    inst.components.spellcaster:SetSpellFn(
        function(inst, target, pos, doer)
            if not inst.components or not inst.components.container then
                return old_spell_fn(inst, target, pos, doer)
            end

            if not inst.components.hh_equip or
                not inst.components.hh_equip:HasEffectByName(EFFECT_NAME) then
                return old_spell_fn(inst, target, pos, doer)
            end

            local first_slot_item = inst.components.container:GetItemInSlot(1)
            local transfer =
                first_slot_item and handle_map[first_slot_item.prefab] or nil

            if transfer then
                transfer(inst, target, pos, doer)
                return
            end

            old_spell_fn(inst, target, pos, doer)
        end)

end)
