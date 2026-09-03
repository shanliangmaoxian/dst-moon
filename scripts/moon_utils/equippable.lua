local utils = {}

function utils.is_equipslot(target, equip_slot)
    return target.components and target.components.equippable and
               (target.components.equippable.equipslot == equip_slot)
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
