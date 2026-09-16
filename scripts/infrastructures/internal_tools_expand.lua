
-- 改个命名空间防止和其它 Mod 混淆
GLOBAL.LMOON = {}

function GLOBAL.LMOON.map(table, fn)
    local results = {}
    for i, v in ipairs(table) do
        GLOBAL.table.insert(results, fn(v, i, table))
    end
    return results
end

function GLOBAL.LMOON.filter(table, fn)
    local results = {}
    for i = 1, #table, 1 do 
        local v = table[i]
        local result = fn(v, i, table)
        if result then
            GLOBAL.table.insert(results, v)
        end
    end
    return results
end

function GLOBAL.table.some(table, fn)
    for i, v in ipairs(table) do 
        if fn(v, i, table) then
            return true
        end
    end
    return false
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

function GLOBAL.LMOON.slice(arr, start, stop)
    local result = {}
    stop = stop or #arr

    stop = stop <= 0 and math.max(1, #arr + stop + 1) or stop
    start = start <= 0 and math.max(1, #arr + start + 1) or start

    for i = start, stop do table.insert(result, arr[i]) end

    return result
end


function GLOBAL.truly(v) return v end
function GLOBAL.falsy(v) return not v end