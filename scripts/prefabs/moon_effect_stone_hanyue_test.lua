-- reference from aria mod https://steamcommunity.com/sharedfiles/filedetails/?id=2418617371
local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()

    inst:AddTag('CLASSIFIED')

    --[[Non-networked entity]]
    inst.persists = false

    -- Auto-remove if not spawned by builder
    inst:DoTaskInTime(0, inst.Remove)

    if not TheWorld.ismastersim then
        return inst
    end

    inst.OnBuiltFn = function(inst, builder)
        local x, y, z = builder.Transform:GetWorldPosition()

        local stone = HHSpawnStoneById("Legend_HANYUE_TEST")
        stone.Transform:SetPosition(x, y, z)
        builder.components.inventory:GiveItem(stone)

        inst:Remove()
    end

    return inst
end

return Prefab('moon_effect_stone_hanyue_test', fn)
