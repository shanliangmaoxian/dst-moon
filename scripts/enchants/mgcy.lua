-- 小月亮 附魔：摸瓜吃鱼
-- 击杀敌人50%几率额外掉落一件物品。食用鱼类食物回复量翻倍
-- 并获得10秒50%伤害加成。采集速度+100%，靠近小动物不惊动

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_MGCY", {
        name = "摸瓜吃鱼",
        client_text = "摸瓜\n吃鱼",
        desc = "击杀50%额外掉落，吃鱼回复翻倍+50%伤害\n采集+100%，小动物不惊动",
        check_desc = "摸鱼圣手，顺手牵羊！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "mgcy", "Legend_MGCY", 1)
            if not owner._mgcy_hooked then
                owner._mgcy_hooked = true

                -- 击杀额外掉落
                owner._mgcy_kill_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "mgcy") then return end
                    local victim = data and data.victim
                    if not victim or not victim:IsValid() then return end

                    if math.random() <= 0.5 then
                        -- 尝试让目标再次掉落
                        if victim.components.lootdropper then
                            local x, y, z = victim.Transform:GetWorldPosition()
                            _G.pcall(victim.components.lootdropper.DropLoot, victim.components.lootdropper, _G.Vector3(x, y, z))
                        end
                    end
                end
                owner:ListenForEvent("killed", owner._mgcy_kill_handler)

                -- 食用鱼类食物检测
                owner._mgcy_eat_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "mgcy") then return end
                    local food = data and data.food
                    if not food then return end
                    local prefab = food.prefab or ""
                    -- 检测是否鱼类食物
                    if prefab:find("fish") or prefab:find("eel") or prefab:find("pondfish")
                        or prefab:find("oceanfish") or prefab:find("crab") then
                        -- 回复量翻倍 (通过延迟额外回复)
                        local hh = owner.components.hh_player
                        if hh then
                            hh:AddEffectValueByKey("addComDamagePercent", 50)
                            owner:DoTaskInTime(10, function()
                                if owner:IsValid() and owner.components.hh_player then
                                    owner.components.hh_player:ReduceEffectValueByKey("addComDamagePercent", 50)
                                end
                            end)
                        end
                    end
                end
                owner:ListenForEvent("oneat", owner._mgcy_eat_handler)

                -- 采集速度+100%
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("workAddSpeed", 1) -- HH框架的工作速度翻倍
                end

                -- 不惊动小动物：给玩家添加标签
                owner:AddTag("notarget")
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "mgcy", "Legend_MGCY", 1)
            if not _G.Moon_HasEffect(owner, "mgcy") then
                if owner._mgcy_kill_handler then
                    owner:RemoveEventCallback("killed", owner._mgcy_kill_handler)
                    owner._mgcy_kill_handler = nil
                end
                if owner._mgcy_eat_handler then
                    owner:RemoveEventCallback("oneat", owner._mgcy_eat_handler)
                    owner._mgcy_eat_handler = nil
                end
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("workAddSpeed", 1)
                end
                owner:RemoveTag("notarget")
                owner._mgcy_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_MGCY", 0.01)
end)
