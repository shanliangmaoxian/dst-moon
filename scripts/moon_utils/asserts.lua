local utils = {}

function utils.is_equipslot(target, equip_slot)
    if target.components and target.components.equippable then
        return target.components.equippable.equipslot == equip_slot
    end
    if target.replica and target.replica.equippable then
        return target.replica.equippable:EquipSlot() == equip_slot
    end
    return false
end

function utils.get_component(target, component_name)
    return target.components and target.components[component_name]
end
function utils.get_replica(target, component_name)
    return target.replica and target.replica[component_name]
end

function utils.is_spellcaster(target)
    if not target then return false end
    local spellcaster_component_names = {'spellcaster', 'aoespell'}
    for _, component_name in pairs(spellcaster_component_names) do
        if utils.get_component(target, component_name) or utils.get_replica(target, component_name) then
            return true
        end
    end
    return false
end

return utils
