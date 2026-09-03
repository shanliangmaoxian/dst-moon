function GLOBAL.EntityScript:AddComponentDynamic(name)
    local component = self:AddComponent(name)
    local old_onsave = component.OnSave

    component.OnSave = function(self)
        local data, refs = old_onsave(self)
        if data then data.add_component_if_missing = true end

        return data, refs
    end
end

function GLOBAL.EntityScript:SetPersistData(data, newents)
	if data and data.add_component_if_missing then
		for k, v in pairs(data) do
			if self.components[k] == nil and type(v) == "table" and v.add_component_if_missing then
				self:AddComponentDynamic(k)
			end
		end
	end

    if self.OnPreLoad ~= nil then
        self:OnPreLoad(data, newents)
    end

    if data ~= nil then
        for k, v in pairs(data) do
            local cmp = self.components[k]

			--V2C: -backward compatibility for add_component_if_missing
			--     -the flag has since been added to the base data table as well so that we
			--      can add the missing components before preload
            if cmp == nil and type(v) == "table" and v.add_component_if_missing then
				self:AddComponentDynamic(k)
                cmp = self.components[k]
            end

            if cmp ~= nil and cmp.OnLoad ~= nil then
                cmp:OnLoad(v, newents)
            end
        end
    end

    if self.OnLoad ~= nil then
        self:OnLoad(data, newents)
    end
end