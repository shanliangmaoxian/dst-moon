-- 小月亮 移除指定附魔石
-- 通过 HH 框架的 HH_EQUIP_BUFF_LIST 表中直接移除条目来彻底禁用附魔石
-- 支持移除当前 mod 及其他 mod 通过 HH 框架注册的附魔石

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

local remove_enchant_ids = CFG.remove_enchant

-- 配置为空表则不做任何事
if not remove_enchant_ids or type(remove_enchant_ids) ~= "table" or #remove_enchant_ids == 0 then
    return
end

-- 在 world 初始化后延迟执行，确保所有 mod 的附魔都已注册完毕
AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    -- DoTaskInTime(0) 延迟到下一帧：确保所有 mod 的 AddPrefabPostInit("world")
    -- 回调都已执行完毕，HH_EQUIP_BUFF_LIST 中已包含所有已注册的附魔石
    inst:DoTaskInTime(0, function()
        -- 安全加载 HH 框架的附魔枚举表
        local ok, hh_enchant = pcall(function() return require("enums/hh_enchant") end)
        if not ok or not hh_enchant then return end

        local HH_EQUIP_BUFF_LIST = hh_enchant["HH_EQUIP_BUFF_LIST"]
        if not HH_EQUIP_BUFF_LIST or type(HH_EQUIP_BUFF_LIST) ~= "table" then return end

        -- 构建 name -> id 的反向映射（支持按名称移除）
        local name_to_id = {}
        for id, data in pairs(HH_EQUIP_BUFF_LIST) do
            if data.name and type(data.name) == "string" then
                name_to_id[data.name] = id
            end
        end

        -- 遍历移除列表，按 ID 或名称移除
        local removed_count = 0
        for _, remove_identifier in ipairs(remove_enchant_ids) do
            if type(remove_identifier) == "string" then
                if HH_EQUIP_BUFF_LIST[remove_identifier] then
                    -- 按 ID 移除
                    HH_EQUIP_BUFF_LIST[remove_identifier] = nil
                    removed_count = removed_count + 1
                elseif name_to_id[remove_identifier] then
                    -- 按名称移除
                    local target_id = name_to_id[remove_identifier]
                    HH_EQUIP_BUFF_LIST[target_id] = nil
                    removed_count = removed_count + 1
                end
            end
        end

        if removed_count > 0 then
            print(string.format("[LittleMoon] 已移除 %d 个附魔石", removed_count))
        end
    end)
end)
