-- 小月亮 附魔：兔兔生财
-- 吃东西 20% 拉粑粑，收获/采集几率多一份
-- 小动物不惊动，兔人浣猫中立，每5分钟产胡萝卜，幸运+3

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_TTSC", {
        name = "兔兔生财",
        client_text = "兔兔\n生财",
        desc = "吃东西 20% 拉一坨粑粑\n收获/采集 25% 几率多一份\n小动物不惊动, 兔人浣猫对你中立\n每5分钟自动产一个胡萝卜在背包\n幸运+3",
        check_desc = "兔兔生财，好运滚滚来！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "tutushengcai", "Legend_TTSC", 1)
            if not owner._ttsc_hooked then
                owner._ttsc_hooked = true

                -- 幸运+3
                if not owner.components.luckuser then
                    owner:AddComponent("luckuser")
                end
                owner.components.luckuser:SetLuckSource(3, "Legend_TTSC")

                -- 小动物不惊动，兔人浣猫中立
                owner:AddTag("notarget")

                -- 吃东西 20% 拉粑粑
                owner._ttsc_eat_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "tutushengcai") then return end
                    if math.random() > 0.2 then return end
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local poop = _G.SpawnPrefab("poop")
                    if poop then
                        poop.Transform:SetPosition(x + math.random() * 2 - 1, y, z + math.random() * 2 - 1)
                    end
                    if owner.components.talker then
                        owner.components.talker:Say("噗～")
                    end
                end
                owner:ListenForEvent("oneat", owner._ttsc_eat_handler)

                -- 收获/采集 25% 多一份 (picksomething: 采摘浆果/草/树枝等)
                owner._ttsc_pick_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "tutushengcai") then return end
                    if data and data.loot and math.random() <= 0.25 then
                        if data.loot.prefab and owner.components.inventory then
                            local extra = _G.SpawnPrefab(data.loot.prefab)
                            if extra then
                                owner.components.inventory:GiveItem(extra, nil, owner:GetPosition())
                            end
                        end
                    end
                end
                owner:ListenForEvent("picksomething", owner._ttsc_pick_handler)

                -- 砍树/挖矿 25% 多一份 (finishedwork)
                owner._ttsc_work_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "tutushengcai") then return end
                    local target = data and data.target
                    if target and target:IsValid() and target.components.lootdropper and math.random() <= 0.25 then
                        _G.pcall(target.components.lootdropper.DropLoot, target.components.lootdropper)
                    end
                end
                owner:ListenForEvent("finishedwork", owner._ttsc_work_handler)

                -- 每5分钟自动产一个胡萝卜在背包
                owner._ttsc_carrot_task = owner:DoPeriodicTask(300, function()
                    if not _G.Moon_HasEffect(owner, "tutushengcai") then return end
                    if owner.components.inventory then
                        local carrot = _G.SpawnPrefab("carrot")
                        if carrot then
                            owner.components.inventory:GiveItem(carrot, nil, owner:GetPosition())
                        end
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "tutushengcai", "Legend_TTSC", 1)
            if not _G.Moon_HasEffect(owner, "tutushengcai") then
                -- 移除幸运值
                if owner.components.luckuser then
                    owner.components.luckuser:RemoveLuckSource("Legend_TTSC")
                end

                owner:RemoveTag("notarget")

                -- 清理事件监听
                if owner._ttsc_eat_handler then
                    owner:RemoveEventCallback("oneat", owner._ttsc_eat_handler)
                    owner._ttsc_eat_handler = nil
                end
                if owner._ttsc_pick_handler then
                    owner:RemoveEventCallback("picksomething", owner._ttsc_pick_handler)
                    owner._ttsc_pick_handler = nil
                end
                if owner._ttsc_work_handler then
                    owner:RemoveEventCallback("finishedwork", owner._ttsc_work_handler)
                    owner._ttsc_work_handler = nil
                end

                -- 清理定时任务
                if owner._ttsc_carrot_task then
                    owner._ttsc_carrot_task:Cancel()
                    owner._ttsc_carrot_task = nil
                end

                owner._ttsc_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_TTSC", 0.01)
end)
