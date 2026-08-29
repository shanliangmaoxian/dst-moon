-- 小月亮 附魔：老师怜悯
-- 每日额外获取两个锻体碎片 (elaina_dtsp)
-- 依赖魔女之旅 Mod (workshop-2578692071)，仅伊蕾娜(elaina)角色装备生效

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- 依赖 Mod 未开启时不注册（魔女之旅）
if not _G.Moon_IsModEnabled("workshop-2578692071") then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_LAOSHI", {
        name = "老师怜悯",
        client_text = "老师\n怜悯",
        desc = "每日额外获取两个锻体碎片\n仅可附魔胸针，唯一",
        check_desc = "倒霉孩子，老师怜悯你了！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        ui_from_desc = "击败精英/Boss概率掉落",
        check_equip_can_add = function(inst)
            if inst and inst.prefab and string.find(inst.prefab, "brooch") then
                return true, "满足条件"
            end
            return false, "只能附魔在胸针上"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "laoshi", "Legend_LAOSHI", 1)
            if not owner._laoshi_hooked then
                owner._laoshi_hooked = true

                -- 仅伊蕾娜(elaina)角色装备生效
                if owner.prefab == "elaina" or owner:HasTag("elaina") then
                    local function give_dtsp()
                        if not _G.Moon_HasEffect(owner, "laoshi") then return end
                        if not owner:IsValid() or not owner.components.inventory then return end

                        for i = 1, 2 do
                            local dtsp = _G.SpawnPrefab("elaina_dtsp")
                            if dtsp then
                                local ok = owner.components.inventory:GiveItem(dtsp, nil, owner:GetPosition())
                                if not ok and dtsp:IsValid() then
                                    dtsp.Transform:SetPosition(owner.Transform:GetWorldPosition())
                                end
                            end
                        end

                        if owner.components.talker then
                            local lines = {
                                "老师怜悯，锻体碎片到了～",
                                "这是老师给你的锻体碎片！",
                                "好好修炼，别辜负老师的期望～",
                            }
                            owner.components.talker:Say(lines[_G.math.random(#lines)])
                        end
                    end

                    -- 当天已给过（含刚装备/轮询）则不重复给
                    local function try_give_daily()
                        if not _G.Moon_HasEffect(owner, "laoshi") then return end
                        if not owner:IsValid() or not owner.components.inventory then return end
                        local current_day = _G.TheWorld.state.cycles
                        if owner._laoshi_last_day ~= nil and current_day <= owner._laoshi_last_day then
                            return -- 今天已经给过，脱下重穿不重复
                        end
                        owner._laoshi_last_day = current_day
                        give_dtsp()
                    end

                    -- 每天送两个锻体碎片（轮询天数变化，必触发）
                    owner._laoshi_daycheck_task = owner:DoPeriodicTask(60, function()
                        if not _G.Moon_HasEffect(owner, "laoshi") then return end
                        local current_day = _G.TheWorld.state.cycles
                        if owner._laoshi_last_day == nil or current_day > owner._laoshi_last_day then
                            owner._laoshi_last_day = current_day
                            owner:DoTaskInTime(0.5, function()
                                if owner:IsValid() then give_dtsp() end
                            end)
                        end
                    end)

                    -- 刚装备时首次给（延迟几秒等加载完成）；当天已给过则跳过
                    owner:DoTaskInTime(3, function()
                        if owner:IsValid() then try_give_daily() end
                    end)
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "laoshi", "Legend_LAOSHI", 1)
            if not _G.Moon_HasEffect(owner, "laoshi") then
                if owner._laoshi_daycheck_task then
                    owner._laoshi_daycheck_task:Cancel()
                    owner._laoshi_daycheck_task = nil
                end
                owner._laoshi_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_LAOSHI", 0.01)
end)
