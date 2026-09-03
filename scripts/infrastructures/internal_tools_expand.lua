function GLOBAL.table.map(table, fn)
    local results = {}
    for i, v in ipairs(table) do
        GLOBAL.table.insert(results, fn(v, i, table))
    end
    return results
end

function GLOBAL.table.filter(table, fn)
    local results = {}
    for i, v in ipairs(table) do 
        local result = fn(v, i, table)
        if result then
            GLOBAL.table.insert(results, result)
        end
    end
    return results
end

function GLOBAL.table.merge(...)
    local table = {}
    for _, current in pairs({...}) do
        for k, v in pairs(current) do
            if type(k) == 'number' then
                table[#table + 1] = v
            else
                table[k] = v
            end
        end
    end
    return table
end

function GLOBAL.truly(v) return v end
function GLOBAL.falsy(v) return not v end