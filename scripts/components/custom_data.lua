local upgrades = require("upgrades/custom_data")
local multivalue_upgrades = upgrades.multivalue_upgrades

local CustomData = Class(function(self, inst)
    self.inst = inst

    self.data = {}
    self.donotsave = {}
end)

function CustomData:Get(key) return self.data[key] end
-- version 需要大于 0
function CustomData:Set(key, value, version) self.data[key] = {data = value, version = version} end

function CustomData:Clear(key) self.data[key] = nil end

function CustomData:DoNotSave(key) self.donotsave[key] = true end

function CustomData:OnSave()
    if next(self.data) == nil then return end

    local data = {}
    for k, v in pairs(self.data) do
        if not self.donotsave[k] then data[k] = v end
    end

    return {data = data}
end

function CustomData:OnLoad(data)
    if not data then return end

    self.data = data.data or self.data
    for key, instance_data in pairs(self.data) do
        -- 元升级（等到现存旧组件数据都消失时，可以安全删除
        -- 在元升级前，实例数据中不存在 version 和 data 键，所以这是安全的
        if instance_data and not instance_data.version and not instance_data.data then
            instance_data = {data = instance_data.data, version = 0}
        end
    end

    -- 执行多值组件升级程序
    for key, instance_data in pairs(self.data) do
        local key_upgrades = multivalue_upgrades[key]
        if key_upgrades and #key_upgrades > 0 then
            local current_version = instance_data.version + 1 -- 从下个版本开始执行
            local latest_data = instance_data.data
            local current_upgrader = key_upgrades[current_version]
            -- 从数据的版本开始依次执行
            while current_upgrader do
                latest_data = current_upgrader(latest_data)
                current_version = current_version + 1
                current_upgrader = key_upgrades[current_version]
            end
            self.data[key] = {data = latest_data, version = current_version - 1}
        end
    end
end

function CustomData:GetDebugString()
    if next(self.data) == nil then return nil end

    local values = {}
    for key, value in pairs(self.data) do
        table.insert(values, {key = key, value = value})
    end
    table.sort(values, function(a, b) return a.key < b.key end)

    for i, v in ipairs(values) do
        values[i] = string.format("%s : %g", v.key, v.value)
    end

    return
        string.format("%d total\n  %s", #values, table.concat(values, "\n  "))
end

return CustomData
