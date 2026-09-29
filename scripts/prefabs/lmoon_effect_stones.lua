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
            local inventory = builder ~= nil and builder.components ~= nil and builder.components.inventory or nil
            if inventory == nil then
                inst:Remove()
                return
            end

            local x, y, z = builder.Transform:GetWorldPosition()

            -- HH API 未就绪时不要报错中断制作栏/建造流程，直接移除占位物。
            local spawn_stone = rawget(_G, "HHSpawnStoneById")
            local ok, stone = false, nil
            if type(spawn_stone) == "function" then
                ok, stone = pcall(spawn_stone, effect_name)
            end
            if not ok then stone = nil end
            if stone == nil then
                inst:Remove()
                return
            end
            stone.Transform:SetPosition(x, y, z)
            inventory:GiveItem(stone)

            inst:Remove()
        end

        return inst
    end
	return Prefab(prefab_name, fn)
end

return 	make_stone_prefab('moon_effect_stone_hanyue_test', "Legend_HANYUE_TEST"),
		make_stone_prefab('lmoon_effect_stone_quickcast', "lmoon_effect_quickcast"),
		make_stone_prefab('lmoon_effect_stone_infinite_star', "Legend_infinite_star"),
		make_stone_prefab('lmoon_effect_stone_yingyu_xinghui', "Moon_YINGYU_XINGHUI")
