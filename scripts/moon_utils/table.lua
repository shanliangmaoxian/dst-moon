local utils = {}

function utils.every_equals(table1, table2)
    if #table1 ~= #table2 then return false end
    for i, value in ipairs(table2) do
        if value ~= table1[i] then return false end
    end
    return true
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
