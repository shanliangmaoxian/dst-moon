local upgrades = require("upgrades/custom_data")
local multivalue_upgrades = upgrades.multivalue_upgrades

local CustomData = Class(function(self, inst)
    self.inst = inst

    self.data = {}
    self.donotsave = {}
end)

function CustomData:Get(key) return self.data[key].data end
function CustomData:Set(key, value)
    -- 自动版本号的设计遵循“没有改动就不需要升级”的原则
    local version = multivalue_upgrades[key] and #multivalue_upgrades[key] or 1
    self.data[key] = {data = value, version = version}
end

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
            self.data[key] = {data = instance_data.data, version = 0}
        end
    end

    --[[
        “升级程序版本”具体指的是在 multivalue_upgrades[key] 中的每个元素对应的下标位置;
        “最新版本”：因为实现了依据 multivalue_upgrades[key] 的自动版本号，可以知道最新版本就是 multivalue_upgrades[key] 这个列表的长度;
        “数据版本”是指“数据的版本号”，在存储时使用 multivalue_upgrades[key] 的长度作为版本号;

        对于数据的升级过程，我们使用“跳过开始”的处理方式，具体为:
            使用数据版本的下一个版本作为开始程序，然后依次执行到后续所有的升级程序;

        列举以下断言以帮助避免混淆:
            在任何时候，升级程序版本如果和数据版本相同，则意味着该数据不需要升级;
            最新版本如果和数据版本相同，则意味着该数据不需要升级;
            最新版本如果和数据版本相同，则意味着该版本的数据已经蕴含了对应版本的升级程序，所以不需要从对应版本开始升级;

            元升级后的数据和没有对应任何升级程序的数据含义是一致的，若未来增加对应的升级程序，它们都从 [1] 开始;

            若最新版本为 7，数据版本为 3，则该数据需要经历的升级程序依次为：[4]、[5]、[6]、[7]

        自动版本号的设计遵循“没有改动就不需要升级”的原则;
    --]]

    -- 执行多值组件升级程序
    for key, instance_data in pairs(self.data) do
        local key_upgrades = multivalue_upgrades[key]
        if key_upgrades and #key_upgrades > 0 then
            local latest_data = instance_data.data
            local current_version = instance_data.version + 1 -- 从下个版本开始执行
            local current_upgrader = key_upgrades[current_version]
            -- 从数据的下一个版本开始依次执行
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
