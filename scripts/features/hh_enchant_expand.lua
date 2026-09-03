local Text = require("widgets/text")

local _G = GLOBAL

local hh_utils = require("moon_utils/hh_enhants")
local table_utils = require("moon_utils/table")

local ok, hh_enchant = _G.pcall(
                           function() return require("enums/hh_enchant") end)
if not ok or not hh_enchant then return end
local HH_EQUIP_BUFF_LIST = hh_enchant["HH_EQUIP_BUFF_LIST"]
local HH_SUIT_LIST = hh_enchant["HH_SUIT_LIST"]

local old_add_special_equip_effect = GLOBAL["AddSpecialEquipEffect"]
GLOBAL["AddSpecialEquipEffect"] = function(effect_id, data)
    old_add_special_equip_effect(effect_id, data)
    HH_EQUIP_BUFF_LIST[effect_id]["slots"] = data.slots or 1
    HH_EQUIP_BUFF_LIST[effect_id]["obtain_desc"] = data.obtain_desc
    HH_EQUIP_BUFF_LIST[effect_id]["desc_dync"] = data.desc_dync
    HH_EQUIP_BUFF_LIST[effect_id]["recipes"] = data.recipes

    -- 将配方的产物映射到对应附魔效果配置中去
    for _, recipe in ipairs(data.recipes or {}) do
        HH_EQUIP_BUFF_LIST["__recipe__" .. recipe] =
            HH_EQUIP_BUFF_LIST[effect_id]
    end

end

AddComponentPostInit("hh_equip", function(self, inst)
    function self:ReplaceEffect(slot_index, effect_name_newly,
                                effect_value_newly)
        self.equip_buff_list[slot_index] = {
            name = effect_name_newly,
            value = effect_value_newly
        }
    end
    -- 如果附魔配置中 desc 没有指定替换参数，千万不要指定 effect_value_newly，否则会显示出错
    function self:ReplaceEffectByName(name, effect_name_newly,
                                      effect_value_newly)
        local effect_info = self:FindEffect(name)
        if not effect_info then return end

        self:ReplaceEffect(effect_info.slot_index, effect_name_newly,
                           effect_value_newly)

        if HH_EQUIP_BUFF_LIST[name]["end_fn"] then
            HH_EQUIP_BUFF_LIST[name]["end_fn"](self.inst,
                                               effect_info.effect.value)
        end

        if HH_EQUIP_BUFF_LIST[effect_name_newly]["start_fn"] then
            HH_EQUIP_BUFF_LIST[effect_name_newly]["start_fn"](self.inst,
                                                              effect_value_newly)
        end
    end
    function self:UpdateEffectValueByName(effect_name, effect_value_newly)
        local effect_info = self:FindEffect(effect_name)
        if not effect_info then return end

        self.equip_buff_list[effect_info.slot_index].value = effect_value_newly
    end
    function self:FindEffect(effect_name)
        for slot_index, effect in ipairs(self.equip_buff_list) do
            if effect.name == effect_name then
                return {slot_index = slot_index, effect = effect}
            end
        end
    end

    function self:GetBuffDebugList(player)
        if self["equip_buff_list"] and #self["equip_buff_list"] > 0 then
            local debug_table = {}
            for i, v in ipairs(self["equip_buff_list"]) do
                if v and v["name"] and HH_EQUIP_BUFF_LIST[v["name"]] then
                    local buff_id = v["name"]
                    local buff_config = HH_EQUIP_BUFF_LIST[buff_id]
                    local buff_desc_color =
                        buff_config["desc_color"] or {1, 0, 0, 1}
                    local buff_name = buff_config["name"] or "未定义"
                    local buff_desc = buff_config["desc"] or
                                          "词条未定义描述"
                    local hh_is_suit = buff_config["is_suit"] -- 是否是套装词条

                    -- TODO: 未完全评估，其它地方对 equip_buff_list value 的假设是否都是基于非 table 的？
                    -- 支持多值
                    if hh_utils.is_hh_type(v["value"], "table") then
                        buff_desc = string["format"](buff_desc,
                                                     table.unpack(v["value"]))
                        if buff_config["value_range"] and
                            buff_config["value_range"]["max"] then
                            if table_utils.every_equals(v["value"],
                                                        buff_config["value_range"]["max"]) then
                                buff_desc = buff_desc .. "(已满)"
                            elseif table_utils.every_lt(v["value"],
                                                        buff_config["value_range"]["max"]) then
                                -- 孵蛋会有升阶词条数值-超过词条上限
                                buff_desc = buff_desc .. "(突破)"
                            end
                        end
                    elseif v["value"] then
                        buff_desc = string["format"](buff_desc, v["value"])
                        if buff_config["value_range"] and
                            buff_config["value_range"]["max"] then
                            if v["value"] == buff_config["value_range"]["max"] then
                                buff_desc = buff_desc .. "(已满)"
                            elseif v["value"] >
                                buff_config["value_range"]["max"] then
                                -- 孵蛋会有升阶词条数值-超过词条上限
                                buff_desc = buff_desc .. "(突破)"
                            end
                        end
                    end

                    if buff_config["desc_dync"] then
                        buff_desc = buff_config["desc_dync"](self.inst, v.value)
                    end

                    if hh_is_suit then
                        if hh_utils.get_component(self["inst"], "equippable") then
                            if self["inst"]["components"]["equippable"]:IsEquipped() and
                                hh_utils.is_hh_type(buff_config["suit_str"],
                                                    "string") and
                                hh_utils.is_hh_type(
                                    HH_SUIT_LIST[buff_config["suit_str"]],
                                    "table") and
                                hh_utils.is_hh_type(
                                    HH_SUIT_LIST[buff_config["suit_str"]]["effect_list"],
                                    "table") then
                                local has_num = 0
                                for ii, vv in ipairs(
                                                  HH_SUIT_LIST[buff_config["suit_str"]]["effect_list"]) do
                                    if hh_utils.get_component(player,
                                                              "hh_player") and
                                        player["components"]["hh_player"]:HasSpecialEffect(
                                            vv) then
                                        has_num = has_num + 1
                                    end
                                end
                                if has_num >= 3 then
                                    buff_desc = "套装属性已激活"
                                    if buff_config["suit_str"] and
                                        hh_utils.is_hh_type(
                                            TUNING["HH_FORMAT_CONFIG"]["SUIT_CONFIG"][buff_config["suit_str"]],
                                            "table") then
                                        buff_desc = tostring(
                                                        TUNING["HH_FORMAT_CONFIG"]["SUIT_CONFIG"][buff_config["suit_str"]]["desc"])
                                    end
                                else
                                    buff_desc = string["format"](
                                                    "部件(%s/%s)", has_num, 3)
                                end
                            else
                                buff_desc =
                                    string["format"]("部件(%s/%s)", 1, 3)
                            end
                        end
                    end
                    local rpc_color = buff_desc_color
                    -- 测试显示索引词条
                    if player and player["HHNeedShowInfo"] then
                        if self["reduce_buff_index"] == i then
                            rpc_color = {0, 1, 1, 1}
                        end
                    end
                    table["insert"](debug_table, {
                        ["name"] = v,
                        ["desc"] = string["format"]("%s:%s", buff_name,
                                                    buff_desc),
                        ["desc_color"] = rpc_color
                    })
                end
            end
            return debug_table
        end
        return {}
    end

end)

-- TODO: 是否能像 IngredientUI 一样在指定配方时传入 overlay 指定自定义控件？如果能做到那么反向映射附魔 recipes 字段则是不必要的。
AddClassPostConstruct("widgets/redux/craftingmenu_widget", function(self)
    if self.recipe_grid then
        -- 添加文字标记
        local splist = self.recipe_grid:GetListWidgets()
        if splist and #splist > 0 then
            for k, v in pairs(splist) do
                v.moon_effect_stone_label =
                    v.cell_root:AddChild(Text(BODYTEXTFONT, 40))
                -- v.moon_effect_stone_label:SetPosition(0, -45)
                v.moon_effect_stone_label:SetString("")
            end
        end

        local oldupdate_fn = self.recipe_grid.update_fn
        self.recipe_grid.update_fn = function(context, widget, data, ...)
            if oldupdate_fn then
                oldupdate_fn(context, widget, data, ...)
            end

			if not data or not data.recipe then return end

			-- 把名字显示上去
            local effect_config = HH_EQUIP_BUFF_LIST["__recipe__" ..
                                      data.recipe.product]
            if widget and widget.moon_effect_stone_label then
                if effect_config then
                    widget.moon_effect_stone_label:SetString(
                        effect_config.client_text)
                    widget.moon_effect_stone_label:Show()
                else
                    widget.moon_effect_stone_label:Hide()
                end
            end
        end
    end
end)
