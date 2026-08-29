-- 小月亮 效果管理器
-- 提供通用的效果叠加/移除/查询工具函数
-- 全局函数前缀: Moon_

local _G = GLOBAL

-- 添加效果（支持数值叠加和布尔标记）
function _G.Moon_AddEffect(inst, Effect_type, source, value)
    if not inst then return end
    local Effect_table = Effect_type .. "_sources"
    if not inst[Effect_table] then
        inst[Effect_table] = {}
    end
    if value then
        local current_value = inst[Effect_table][source] or 0
        inst[Effect_table][source] = current_value + value
    else
        inst[Effect_table][source] = true
    end
end

-- 减少效果（仅对数值型生效）
function _G.Moon_ReduceEffect(inst, Effect_type, source, value)
    if not inst or not value then return end
    local Effect_table = Effect_type .. "_sources"
    if inst[Effect_table] and inst[Effect_table][source] then
        local current_value = inst[Effect_table][source]
        if type(current_value) == "number" then
            local new_value = current_value - value
            if new_value == 0 then
                inst[Effect_table][source] = nil
            else
                inst[Effect_table][source] = new_value
            end
        end
    end
end

-- 获取效果类型的总数值
function _G.Moon_GetTotalEffectValue(inst, Effect_type)
    if not inst then return 0 end
    local Effect_table = Effect_type .. "_sources"
    if not inst[Effect_table] then return 0 end
    local total = 0
    for k, v in pairs(inst[Effect_table]) do
        if type(v) == "number" then
            total = total + v
        end
    end
    return total
end

-- 检查是否有某种效果
function _G.Moon_HasEffect(inst, Effect_type)
    if not inst then return false end
    local Effect_table = Effect_type .. "_sources"
    if not inst[Effect_table] then return false end
    for k, v in pairs(inst[Effect_table]) do
        if v == true or (type(v) == "number" and v ~= 0) then
            return true
        end
    end
    return false
end
