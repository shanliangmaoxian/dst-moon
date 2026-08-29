-- 小月亮 附魔：打工人
-- 采集、挖掘、砍伐效率 +100%，且有 25% 几率获得双倍产出。黄昏和夜晚伤害额外 +30%。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_DGR", {
        name = "打工人",
        client_text = "打工\n人",
        desc = "工作速度+100%，25%双倍产出\n黄昏/夜晚伤害+30%",
        check_desc = "早安，打工人！工作使我快乐！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "dagongren", "Legend_DGR", 1)
            if not owner._dgr_hooked then
                owner._dgr_hooked = true

                -- 工作效率+100%
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("workAddSpeed", 1)
                end

                -- 25%几率双倍采摘产出
                owner._dgr_pick_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "dagongren") then return end
                    if data and data.loot and math.random() <= 0.25 then
                        if data.loot.prefab and owner.components.inventory then
                            local extra = _G.SpawnPrefab(data.loot.prefab)
                            if extra then
                                owner.components.inventory:GiveItem(extra, nil, owner:GetPosition())
                                if owner.components.talker then
                                    owner.components.talker:Say("多打一份工，多一份产出！")
                                end
                            end
                        end
                    end
                end
                owner:ListenForEvent("picksomething", owner._dgr_pick_handler)

                -- 25%几率双倍砍伐/挖掘产出
                owner._dgr_work_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "dagongren") then return end
                    local target = data and data.target
                    if target and target:IsValid() and target.components.lootdropper and math.random() <= 0.25 then
                        _G.pcall(target.components.lootdropper.DropLoot, target.components.lootdropper)
                        if owner.components.talker then
                            owner.components.talker:Say("劳模暴击！双倍爆率！")
                        end
                    end
                end
                owner:ListenForEvent("finishedwork", owner._dgr_work_handler)

                -- 黄昏/夜晚伤害加成（事件驱动，不轮询）
                local function _dgr_update_dark()
                    if not _G.Moon_HasEffect(owner, "dagongren") then return end
                    local is_dark = _G.TheWorld.state.isdusk or _G.TheWorld.state.isnight
                    local hh = owner.components.hh_player
                    if is_dark and not owner._dgr_dark_active then
                        owner._dgr_dark_active = true
                        if hh then hh:AddEffectValueByKey("addComDamagePercent", 30) end
                    elseif not is_dark and owner._dgr_dark_active then
                        owner._dgr_dark_active = false
                        if hh then hh:ReduceEffectValueByKey("addComDamagePercent", 30) end
                    end
                end
                owner:WatchWorldState("isnight", _dgr_update_dark)
                owner:WatchWorldState("isdusk", _dgr_update_dark)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "dagongren", "Legend_DGR", 1)
            if not _G.Moon_HasEffect(owner, "dagongren") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("workAddSpeed", 1)
                    if owner._dgr_dark_active then
                        hh:ReduceEffectValueByKey("addComDamagePercent", 30)
                    end
                end

                if owner._dgr_pick_handler then
                    owner:RemoveEventCallback("picksomething", owner._dgr_pick_handler)
                    owner._dgr_pick_handler = nil
                end
                if owner._dgr_work_handler then
                    owner:RemoveEventCallback("finishedwork", owner._dgr_work_handler)
                    owner._dgr_work_handler = nil
                end
                owner._dgr_dark_active = nil
                owner._dgr_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_DGR", 0.01)
end)
