local utils = {}

function utils.is_hh_type(data, hh_type)
    if data and type(data) == hh_type then return true end
    return false
end

function utils.get_component(inst, component_name)
    return inst.components and inst.components[component_name]
end

return utils
