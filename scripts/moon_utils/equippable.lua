local utils = {}

function utils.is_equipslot(target, equip_slot)
    if target.components and target.components.equippable then
        return target.components.equippable.equipslot == equip_slot
    end
    if target.replica and target.replica.equippable then
        return target.replica.equippable:EquipSlot() == equip_slot
    end
    return false
end

function utils.every_lg(table1, table2)
    if #table1 ~= #table2 then return false end
    for i, value in ipairs(table1) do
        if value > table2[i] then return false end
    end
    return true
end

function utils.every_lt(table1, table2)
    if #table1 ~= #table2 then return false end
    for i, value in ipairs(table1) do
        if value < table2[i] then return false end
    end
    return true
end

return utils
