-- reference from aria mod https://steamcommunity.com/sharedfiles/filedetails/?id=2418617371
local function make_stone_prefab(prefab_name, effect_name)
    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()

        inst:AddTag('CLASSIFIED')

        --[[Non-networked entity]]
        inst.persists = false

        -- Auto-remove if not spawned by builder
        inst:DoTaskInTime(0, inst.Remove)

        if not TheWorld.ismastersim then return inst end

        inst.OnBuiltFn = function(inst, builder)
            local x, y, z = builder.Transform:GetWorldPosition()

            local stone = HHSpawnStoneById(effect_name)
            stone.Transform:SetPosition(x, y, z)
            builder.components.inventory:GiveItem(stone)

            inst:Remove()
        end

        return inst
    end
	return Prefab(prefab_name, fn)
end

return 	make_stone_prefab('moon_effect_stone_hanyue_test', "Legend_HANYUE_TEST"),
		make_stone_prefab('lmoon_effect_stone_quickcast', "lmoon_effect_quickcast")
