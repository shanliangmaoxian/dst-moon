local containers = require("containers")
local Widget = require("widgets/widget")

local HH_EQUIP_BUFF_LIST

local ok, hh_enchant = pcall(function() return require("enums/hh_enchant") end)
if not ok or not hh_enchant then return end
HH_EQUIP_BUFF_LIST = hh_enchant["HH_EQUIP_BUFF_LIST"]

local ok, HH_LANGUAGE =
    pcall(function() return require("enums/hh_language") end)
if not ok or not HH_LANGUAGE then return end

local ok, HH_UTILS = pcall(function() return require("utils/hh_utils") end)
if not ok or not HH_UTILS then return end

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
local GEM_TYPES = {
    "redgem", "bluegem", "purplegem", "greengem", "orangegem", "yellowgem",
    "opalpreciousgem"
}

-- 核心函数：检查并删除指定点周围地上每种宝石各一个
function RemoveOneOfEachGem(x, y, z, radius, gem_types)
    -- 找出所有地上的宝石（排除背包/容器中的）
    local all_gems = TheSim:FindEntities(x, y, z, radius, {"gem"}, {"INLIMBO"})

    -- 每个 prefab 
    local gems = {}
    for _, ent in ipairs(all_gems) do
        local prefab = ent.prefab
        if prefab and not gems[prefab] then gems[prefab] = ent end
    end

    -- 检查是否每种宝石都有
    local all_present = true
    for _, gem_type in pairs(gem_types) do
        if not gems[gem_type] then return end
    end

    -- 删除
    for _, gem_prefab in ipairs(gem_types) do gems[gem_prefab]:Remove() end

    return true
end

local ActionLookAt_old = ACTIONS.LOOKAT.fn
ACTIONS.LOOKAT.fn = function(act, ...)
    local target = act.target or act.invobject

    if target and target.prefab then
        if target.prefab == "hh_staff_dis" then
            local x, y, z = target.Transform:GetWorldPosition()
            local hh_equip = target.components and target.components.hh_equip
            if hh_equip and not target:HasTag("moon_hh_effect_aether") and
                RemoveOneOfEachGem(x, y, z, 5, GEM_TYPES) then
                TheWorld:PushEvent("ms_sendlightningstrike", Vector3(x, y, z))
                hh_equip:AddEquipBuff(EFFECT_NAME)
            end
        end
    end

    return ActionLookAt_old(act, ...)
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
            break
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
            break
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

-- 自动转换附魔石
local function transform_to_common_stone(currency_provider, stone, player,
                                         currency_type, cosume_amount)
    if not currency_provider.components or
        not currency_provider.components.container then return end
    if not stone or stone.prefab ~= "hh_effect_stone" then return end
    if is_common_effect(stone.hh_effect) then return end

    local currency_container = currency_provider.components.container
    local enough = currency_container:Has(currency_type, cosume_amount)
    local stone_effect_newly = rand_pick_on_pool(_G["HHGetComEquipEffect"]())

    currency_container:ConsumeByName(currency_type, cosume_amount)
    replace_stone(stone, stone_effect_newly, player)
end

local EQUIP_BLACK_TAG = {
    "INLIMBO", "NOCLICK", "irreplaceable", "knockbackdelayinteraction",
    "event_trigger", "minesprung", "mineactive", "catchable", "fire", "light",
    "spider", "cursed", "paired", "bundle", "heatrock", "deploykititem",
    "boatbuilder", "singingshell", "archive_lockbox", "simplebook",
    "furnituredecor", "flower", "gemsocket", "structure", "donotautopick"
}

-- 就地转换附魔石
local function transform_stones_inplace(inst, target, pos, caster, transformer)
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
                    if stone.hh_effect then
                        transformer(inst, stone, caster)
                    end
                end
            end
        end
    end
end

local handle_map = {
    ["moonrocknugget"] = function(inst, target, pos, doer)
        transform_stones_inplace(inst, target, pos, doer, function (inst, stone, caster)
            transform_to_common_stone(inst, stone, caster, "moonrocknugget", 1)
        end)
    end,
    -- 水晶道具，自动转换
    ["hh_essence"] = function(inst, target, pos, doer)
        transform_stones_inplace(inst, target, pos, doer, auto_transform_stone)
    end
}

local noop = function() end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_NAME, {
        name = "以太",
        client_text = "以\n太",
        desc = "增强拆除法杖的功能：\n【月岩】: 消耗月岩将高级附魔石转成普通附魔石，每次1月岩\n【水晶道具】: 消耗水晶道具对周围附魔石进行自动转换",
        check_desc = "仅能附魔在拆解法杖上",
        can_add = false,
        obtain_desc = "若拆解法杖周围地上存在 7 色宝石各一个，检查它即可附魔上去",
        only_one = true,
        is_special = false,
        slots = 0,
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

AddComponentPostInit("hh_equip", function(self, inst)
    local old_set_equip_buff_limit = self.SetEquipBuffLimit;
    self.SetEquipBuffLimit = function(self, buff_num, force)
        old_set_equip_buff_limit(self, buff_num)
        if force then self.equip_buff_limit = buff_num end
    end

    -- 计算占用槽位
    function self:GetUsedSlots()
        local effect_list = self.equip_buff_list

        local used_slots = 0

        for i, effect in pairs(effect_list) do
            local effect_name = effect.name
            local effect_config = HH_EQUIP_BUFF_LIST[effect_name] or {}
            local used_slot = effect_config.slots or 1

            used_slots = used_slots + used_slot
        end

        return used_slots
    end

    local old_add_equip_buff = self.CanAddEquipBuff
    function self:CanAddEquipBuff(buff_name, buff_value)
        if not self.equip_buff_limit or
            not is_hh_type(self.equip_buff_list, "table") then
            return false
        end

        local effect_config = HH_EQUIP_BUFF_LIST[buff_name] or {}
        local advanced_slots = effect_config.slots or 1

        -- 计算占用槽位
        local effect_list = self.equip_buff_list

        local used_slots = self:GetUsedSlots()

        return used_slots + advanced_slots <= self.equip_buff_limit
    end

    function self:GetBuffDebugString()
        local debug_format = "%s/%s"
        return string.format(debug_format, self:GetUsedSlots(),
                             self.equip_buff_limit)
    end

    -- 无法通过增量的方式来更改原函数的行为，将原来的逻辑复制了一份。CanAddEquipBuff 需
    -- 要传递添加进来的附魔效果，才能完整判断是否能继续添加，例如词条已经满了，但仍能添加
    -- slots 为 0 的附魔。
    function self:AddEquipBuff(buff_name, buff_value)
        local add_buff_name = nil
        local can_add_buff = self:CanAddEquipBuff(buff_name, buff_value)
        if not can_add_buff then
            return false, "词条已满,无法增加词条!!!"
        end
        -- 校验词条是否可以新增
        if buff_name then
            add_buff_name = buff_name
            if not HH_EQUIP_BUFF_LIST[buff_name] then
                return false, "无法识别的词条 附魔失败!!!"
            end

            if HH_EQUIP_BUFF_LIST[buff_name]["check_equip_can_add"] then
                local check_equip_can_add, check_result =
                    HH_EQUIP_BUFF_LIST[buff_name]["check_equip_can_add"](
                        self["inst"])
                if not check_equip_can_add then
                    return false, check_result or
                               "该词条不允许附魔在当前装备上 附魔失败！！！"
                end
            end
            -- 校验词条唯一性
            if HH_EQUIP_BUFF_LIST[buff_name]["only_one"] then
                for key, value in ipairs(self["equip_buff_list"]) do
                    if value and value["name"] == buff_name then
                        return false,
                               "此词条只允许存在一条 附魔失败！！！"
                    end
                end
            end
        else
            -- 查询可新增的词条
            local all_can_add_buffs = self:GetAllBuffByEquip()
            if not all_can_add_buffs or #all_can_add_buffs < 1 then
                return false, "没有可以新增的词条!!!"
            end
            local all_buff_length = #all_can_add_buffs
            local hh_random_num = math["random"](1, all_buff_length)
            add_buff_name = all_can_add_buffs[hh_random_num]
        end
        local buff_config = HH_EQUIP_BUFF_LIST[add_buff_name]
        -- 套装词条增加校验
        if buff_config["is_suit"] and self:HasSuitEffect() then
            return false, "已经存在套装词条,无法附魔"
        end
        local random_buff_value = nil
        if buff_value then
            random_buff_value = buff_value
        else
            if buff_config["value_range"] and buff_config["value_range"]["max"] and
                buff_config["value_range"]["min"] then
                random_buff_value = math["random"](
                                        buff_config["value_range"]["min"],
                                        buff_config["value_range"]["max"])
            end
        end
        table["insert"](self["equip_buff_list"], {
            ["name"] = add_buff_name,
            ["value"] = random_buff_value
        })
        if HH_EQUIP_BUFF_LIST[add_buff_name]["start_fn"] then
            HH_EQUIP_BUFF_LIST[add_buff_name]["start_fn"](self["inst"],
                                                          random_buff_value)
        end
        -- 防止清除词条回档刷词条
        local last_reduce_index = math["random"](1, #self["equip_buff_list"])
        self:UpdateReduceBuffIndex(last_reduce_index)
        return true, "附魔成功!!!"
    end
end)

-- 排序函数 根据id倒序 新词条在前面
local function sortById(a, b)
    local aValue = a["value"]
    local bValue = b["value"]
    -- 检查两个元素是否都有id
    if aValue["id"] and bValue["id"] then
        return aValue["id"] > bValue["id"]
        -- 只有a有id
    elseif aValue["id"] then
        return true
        -- 只有b有id
    elseif bValue["id"] then
        return false
        -- 两个元素都没有id
    else
        return false
    end
end
local effect_rare_str = "只能从合成台较低概率合成出来"

local function GetAllEquipBuff()
    local hh_copy = HH_UTILS:HHCopyTable(HH_EQUIP_BUFF_LIST)
    local hh_table = {}
    -- 将键值对转换为数组格式
    local itemList = {}
    for key, value in pairs(hh_copy) do
        table["insert"](itemList, {["key"] = key, ["value"] = value})
    end
    -- 使用table.sort进行排序
    table["sort"](itemList, sortById)
    for i, v in ipairs(itemList) do
        if HH_UTILS:IsHHType(v, "table") and
            HH_UTILS:IsHHType(v["value"], "table") then
            local buff_config = v["value"]
            -- 套装属性不展示
            if not buff_config["is_suit"] then
                local buff_name = buff_config["name"] or "词条未定义"
                local buff_small_name = buff_config["client_text"] or "空"
                local buff_desc_format =
                    buff_config["desc"] or "描述未定义"
                local buff_color = {128 / 255, 138 / 255, 135 / 255, 1}
                if buff_config["client_color"] then
                    buff_color = buff_config["client_color"]
                elseif not buff_config["can_add"] then
                    buff_color = {255 / 255, 97 / 255, 0 / 255, 1}
                end
                local range_value = buff_config["value_range"] and
                                        HH_UTILS:Template("{{min}}~{{max}}",
                                                          buff_config["value_range"]) or
                                        "无取值范围"
                local buff_desc = buff_desc_format
                if range_value ~= "无取值范围" then
                    buff_desc = string["format"](buff_desc_format, range_value)
                end
                local buff_is_one = buff_config["only_one"] and
                                        "只允许存在一条" or
                                        "可重复附魔"
                local buff_can_get = buff_config["can_add"] and
                                         "可以通过普通附魔获取" or
                                         "精英/boss掉落的专属附魔石/武器包裹"
                if buff_config["only_compound"] then
                    buff_can_get = effect_rare_str
                end
                if buff_config["ui_from_desc"] then
                    buff_can_get = tostring(buff_config["ui_from_desc"])
                end
                local buff_check_desc = "无"
                if buff_config["check_desc"] then
                    buff_check_desc = tostring(buff_config["check_desc"])
                end
                table["insert"](hh_table, {
                    ["id"] = v.key,
                    ["name"] = buff_name,
                    ["small_name"] = buff_small_name,
                    ["desc"] = buff_desc,
                    ["color"] = buff_color,
                    ["range_value"] = range_value,
                    ["is_one"] = buff_is_one,
                    ["can_add"] = buff_can_get,
                    ["check_desc"] = buff_check_desc
                })
            end
        end
    end
    return hh_table
end

local hh_offset = 20
local main_size_x, main_size_y = 800, 500

AddClassPostConstruct("widgets/hh_help_ui", function(self)
    function self:CreateEffectUi()
        self:CreateTitle("词条属性")
        local father_ui = self["hh_main"]["main_ui"]
        local all_effect = GetAllEquipBuff()
        ----------------------------------------------------------------------------------------------
        local sub_root = Widget()
        local start_x, start_y = 0, 0
        local sub_ui_y = 0, 0
        -- x轴分两段
        local sub_ui_x_left, sub_ui_x_right = 0, 0
        local image_size = 40
        for i, v in ipairs(all_effect) do
            local child_x, child_y = image_size / 2, start_y - image_size / 2
            local start_left = true
            if i % 2 ~= 0 then
                start_left = false
                child_x = image_size / 2 + main_size_x / 2 - 30
            end
            sub_root["hh_image_" .. i] =
                HH_UTILS:HHCreateImageUi(sub_root,
                                         "images/hh_icon/hh_status.xml",
                                         "hh_status.tex", Vector3(0, 0, 1),
                                         image_size, image_size, v["color"])
            sub_root["hh_image_" .. i]:SetPosition(child_x, child_y, 1)
            sub_root["hh_image_" .. i]["stone_image"] =
                HH_UTILS:HHCreateImageUi(
                    sub_root["hh_image_" .. i], "images/hh_icon/hh_items.xml",
                    "hh_effect_stone.tex", Vector3(0, 0, 1), image_size * 0.8,
                    image_size * 0.8)
            sub_root["hh_image_" .. i]["hh_client_text"] =
                HH_UTILS:HHCreateTextUi(sub_root["hh_image_" .. i],
                                        Vector3(0, 0, 1),
                                        tostring(v["small_name"]), nil,
                                        image_size / 2, true)

            -- 来源
            local from_str = HH_EQUIP_BUFF_LIST[v.id] and
                                 HH_EQUIP_BUFF_LIST[v.id].obtain_desc or
                                 v["can_add"]
            local can_add_color = {1, 1, 1, 1}
            if from_str == effect_rare_str then
                can_add_color = {1, 0, 0, 1}
            end
            sub_root["hh_image_" .. i]["hh_str_ui"] =
                HH_UTILS:CreateMoreTextUi(
                    sub_root["hh_image_" .. i], {
                        {
                            ["str"] = v["name"],
                            ["color"] = {255 / 255, 102 / 255, 0 / 255, 1},
                            ["scale"] = 25
                        },
                        {
                            ["str"] = "描述:" .. v["desc"],
                            ["color"] = nil,
                            ["scale"] = 20
                        },
                        {
                            ["str"] = "唯一性:" .. v["is_one"],
                            ["color"] = nil,
                            ["scale"] = 20
                        },
                        {
                            ["str"] = "来源:" .. from_str,
                            ["color"] = can_add_color,
                            ["scale"] = 20
                        },
                        {
                            ["str"] = "前置条件:" .. v["check_desc"],
                            ["color"] = nil,
                            ["scale"] = 20
                        }, {["str"] = " ", ["color"] = nil, ["scale"] = 20}
                    }, 3)
            local hh_str_ui_x, hh_str_ui_y =
                sub_root["hh_image_" .. i]["hh_str_ui"]["max_x"],
                sub_root["hh_image_" .. i]["hh_str_ui"]["max_y"]
            sub_root["hh_image_" .. i]["hh_str_ui"]:SetPosition(
                image_size / 2 + 2, image_size / 2, 1)
            if start_left then
                sub_ui_x_left = math["max"](image_size + hh_str_ui_x + 2,
                                            sub_ui_x_left)
                start_y = start_y - math["max"](hh_str_ui_y, image_size)
                sub_ui_y = sub_ui_y + math["max"](hh_str_ui_y, image_size)
            else
                sub_ui_x_right = math["max"](image_size + hh_str_ui_x + 2,
                                             sub_ui_x_right)
            end
        end
        local sub_w, sub_h = sub_ui_x_left + sub_ui_x_right + 70, 380
        father_ui["hh_info_ui"] = HH_UTILS:CreateTrueScrollArea(father_ui,
                                                                sub_root, sub_w,
                                                                sub_h, sub_ui_y,
                                                                65, 3)
        father_ui["hh_info_ui"]:SetPosition(-main_size_x / 2 + hh_offset + 40,
                                            -sub_h / 2, 1)
        father_ui["hh_info_ui"]["up_button"]:SetTextures(
            "images/quagmire_recipebook.xml",
            "quagmire_recipe_scroll_arrow_hover.tex")
        father_ui["hh_info_ui"]["up_button"]:SetScale(0.35)
        father_ui["hh_info_ui"]["down_button"]:SetTextures(
            "images/quagmire_recipebook.xml",
            "quagmire_recipe_scroll_arrow_hover.tex")
        father_ui["hh_info_ui"]["down_button"]:SetScale(-0.35)
        father_ui["hh_info_ui"]["scroll_bar_line"]:SetTexture(
            "images/quagmire_recipebook.xml", "quagmire_recipe_scroll_bar.tex")
        father_ui["hh_info_ui"]["scroll_bar_line"]:SetScale(0.75)
        father_ui["hh_info_ui"]["position_marker"]:SetTextures(
            "images/quagmire_recipebook.xml",
            "quagmire_recipe_scroll_handle.tex")
        father_ui["hh_info_ui"]["position_marker"]["image"]:SetTexture(
            "images/quagmire_recipebook.xml",
            "quagmire_recipe_scroll_handle.tex")
        father_ui["hh_info_ui"]["position_marker"]:SetScale(0.3)
        ---------------------------------------------------------------------------------------
        HH_UTILS:HookFocusCamera(father_ui["hh_info_ui"])
        -- local all_suit = GetAllSuitBuff(self["owner"])
        -- local sub_suit_root = Widget()
        -- sub_suit_root["hh_ui"] = HH_UTILS:CreateMoreTextUi(sub_suit_root, all_suit, 3)
        -- local sub_suit_ui_x, sub_suit_ui_y = sub_suit_root["hh_ui"]["max_x"], sub_suit_root["hh_ui"]["max_y"]
        -- local sub_suit_w, sub_suit_h = sub_suit_ui_x + 3, 380
        -- father_ui["hh_suit_ui"] = HH_UTILS:CreateTrueScrollArea(father_ui, sub_suit_root, sub_suit_w, sub_suit_h, sub_suit_ui_y, 25, 3)
        -- father_ui["hh_suit_ui"]:SetPosition(main_size_x / 2 - sub_suit_w - hh_offset * 3, -sub_suit_h / 2, 1)
        -- father_ui["hh_suit_ui"]["up_button"]:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
        -- father_ui["hh_suit_ui"]["up_button"]:SetScale(0.35)
        -- father_ui["hh_suit_ui"]["down_button"]:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
        -- father_ui["hh_suit_ui"]["down_button"]:SetScale(-0.35)
        -- father_ui["hh_suit_ui"]["scroll_bar_line"]:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_bar.tex")
        -- father_ui["hh_suit_ui"]["scroll_bar_line"]:SetScale(0.75)
        -- father_ui["hh_suit_ui"]["position_marker"]:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
        -- father_ui["hh_suit_ui"]["position_marker"]["image"]:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
        -- father_ui["hh_suit_ui"]["position_marker"]:SetScale(0.3)
    end
end)
