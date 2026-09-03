local CustomData = Class(function(self, inst)
    self.inst = inst

    self.data = {}
    self.donotsave = {}
end)

function CustomData:Get(key) return self.data[key] end
function CustomData:Set(key, value) self.data[key] = value end

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
