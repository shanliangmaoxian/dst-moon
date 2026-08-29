-- 小月亮 附魔：九月
-- 娱乐属性：秋叶飘落，走路留花，秋夜萤火虫，树木互动

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_JIUYUE", {
        name = "九月",
        client_text = "九\n月",
        desc = "每15秒飘落秋叶特效\n走路时每15秒随机留下小花\n秋天夜晚环绕萤火虫\n靠近树木时自动飘落树叶～",
        check_desc = "秋日私语，九月浪漫～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "jiuyue", "Legend_JIUYUE", 1)
            if not owner._jiuyue_hooked then
                owner._jiuyue_hooked = true

                -- 持续飘落秋叶
                owner._jiuyue_leaf_task = owner:DoPeriodicTask(15, function()
                    if not _G.Moon_HasEffect(owner, "jiuyue") then return end
                    if GLOBAL.SpawnPrefab then
                        local x, y, z = owner.Transform:GetWorldPosition()
                        -- 用 foliage（蕨叶）模拟秋叶
                        local leaf = GLOBAL.SpawnPrefab("foliage")
                        if leaf then
                            leaf.Transform:SetPosition(
                                x + math.random() * 5 - 2.5,
                                y + 3 + math.random() * 3,
                                z + math.random() * 5 - 2.5
                            )
                            local s = 0.4 + math.random() * 0.6
                            leaf.Transform:SetScale(s, s, s)
                            if leaf.Physics then
                                leaf.Physics:SetVel(
                                    math.random() * 0.6 - 0.3,
                                    -0.2 - math.random() * 0.4,
                                    math.random() * 0.6 - 0.3
                                )
                            end
                            leaf:DoTaskInTime(6, function()
                                if leaf:IsValid() then leaf:Remove() end
                            end)
                        end
                    end
                end)

                -- 走路时身后留小花
                owner._jiuyue_flower_task = owner:DoPeriodicTask(15, function()
                    if not _G.Moon_HasEffect(owner, "jiuyue") then return end
                    -- 检测是否在移动
                    if owner.sg and owner.sg:HasStateTag("moving") then
                        if GLOBAL.SpawnPrefab then
                            local x, y, z = owner.Transform:GetWorldPosition()
                            local flower = GLOBAL.SpawnPrefab("petals")
                            if flower then
                                flower.Transform:SetPosition(x, y, z)
                                flower.Transform:SetScale(0.4, 0.4, 0.4)
                                flower:DoTaskInTime(3, function()
                                    if flower:IsValid() then flower:Remove() end
                                end)
                            end
                        end
                    end
                end)

                -- 秋天夜晚萤火虫
                owner._jiuyue_firefly_task = owner:DoPeriodicTask(4, function()
                    if not _G.Moon_HasEffect(owner, "jiuyue") then return end
                    local is_autumn = GLOBAL.TheWorld.state.season == "autumn"
                    local is_night = GLOBAL.TheWorld.state.isnight
                    if is_autumn and is_night and GLOBAL.SpawnPrefab then
                        local x, y, z = owner.Transform:GetWorldPosition()
                        local ff = GLOBAL.SpawnPrefab("fireflies")
                        if ff then
                            ff.Transform:SetPosition(
                                x + math.random() * 3 - 1.5,
                                y + math.random() * 2,
                                z + math.random() * 3 - 1.5
                            )
                            ff:DoTaskInTime(6, function()
                                if ff:IsValid() then ff:Remove() end
                            end)
                        end
                    end
                end)

                -- 靠近树木时飘落树叶（10秒间隔）
                owner._jiuyue_tree_task = owner:DoPeriodicTask(10, function()
                    if not _G.Moon_HasEffect(owner, "jiuyue") then return end
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local trees = GLOBAL.TheSim:FindEntities(x, y, z, 4, { "tree", "leif" })
                    if #trees > 0 and GLOBAL.SpawnPrefab then
                        for _ = 1, 3 do
                            local leaf = GLOBAL.SpawnPrefab("petals")
                            if leaf then
                                local tree = trees[math.random(#trees)]
                                local tx, ty, tz = tree.Transform:GetWorldPosition()
                                leaf.Transform:SetPosition(
                                    tx + math.random() * 2 - 1,
                                    ty + 3 + math.random() * 3,
                                    tz + math.random() * 2 - 1
                                )
                                if leaf.Physics then
                                    leaf.Physics:SetVel(
                                        math.random() * 1 - 0.5,
                                        -0.3 - math.random() * 0.6,
                                        math.random() * 1 - 0.5
                                    )
                                end
                                leaf:DoTaskInTime(3, function()
                                    if leaf:IsValid() then leaf:Remove() end
                                end)
                            end
                        end
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "jiuyue", "Legend_JIUYUE", 1)
            if not _G.Moon_HasEffect(owner, "jiuyue") then
                if owner._jiuyue_leaf_task then
                    owner._jiuyue_leaf_task:Cancel()
                    owner._jiuyue_leaf_task = nil
                end
                if owner._jiuyue_flower_task then
                    owner._jiuyue_flower_task:Cancel()
                    owner._jiuyue_flower_task = nil
                end
                if owner._jiuyue_firefly_task then
                    owner._jiuyue_firefly_task:Cancel()
                    owner._jiuyue_firefly_task = nil
                end
                if owner._jiuyue_tree_task then
                    owner._jiuyue_tree_task:Cancel()
                    owner._jiuyue_tree_task = nil
                end
                owner._jiuyue_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_JIUYUE", 0.01)
end)
