-- 小月亮 附魔：草莓奶昔
-- 每3秒回复5%最大生命值和3%精神值
-- 被攻击时100%使攻击者陷入「糖分过量」：攻速和移速-35%持续5秒
-- 食用甜食类食物额外回复20点生命

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_STRAWBERRY", {
        name = "草莓奶昔",
        client_text = "草莓\n奶昔",
        desc = "每3秒回复5%最大生命+3%精神\n被攻击时对攻击者施加「糖分过量」标记\n食用甜食额外回复20生命",
        check_desc = "甜蜜陷阱，欲罢不能～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            -- 仅在服务端执行，避免客/双端重复跑回血Task与生成特效（导致卡顿/数值抖动）
            if not _G.TheWorld or not _G.TheWorld.ismastersim then return end
            _G.Moon_AddEffect(owner, "strawberry", "Legend_STRAWBERRY", 1)
            if not owner._strawberry_hooked then
                owner._strawberry_hooked = true

                -- 每3秒回复5%最大生命 + 3%精神
                owner._strawberry_regen_task = owner:DoPeriodicTask(3, function()
                    if not owner:IsValid() then return end
                    if not _G.Moon_HasEffect(owner, "strawberry") then return end
                    if owner.components.health then
                        local max_hp = owner.components.health.maxhealth or 150
                        owner.components.health:DoDelta(max_hp * 0.05, false, "strawberry")
                    end
                    if owner.components.sanity then
                        local max_san = owner.components.sanity.max or 200
                        owner.components.sanity:DoDelta(max_san * 0.03)
                    end
                end)

                -- 被攻击时使攻击者「糖分过量」
                owner._strawberry_attacked_handler = function(victim, data)
                    if not _G.Moon_HasEffect(owner, "strawberry") then return end
                    local attacker = data and data.attacker
                    if not attacker or not attacker:IsValid() then return end
                    if attacker == owner then return end

                    -- 特效（3秒冷却，改用轻量特效减轻卡顿）
                    local now = _G.GetTime and _G.GetTime() or 0
                    if not owner._strawberry_fx_cd or now - owner._strawberry_fx_cd >= 3 then
                        owner._strawberry_fx_cd = now
                        if GLOBAL.SpawnPrefab then
                            local x, y, z = attacker.Transform:GetWorldPosition()
                            local fx = GLOBAL.SpawnPrefab("collapse_small")
                            if fx then
                                fx.Transform:SetPosition(x, y, z)
                            end
                        end
                    end

                    -- 糖分过量：攻速-35%、移速-35%，持续5秒（不叠加）
                    if attacker:HasTag("strawberry_sugar") then return end
                    if not attacker.components.locomotor then return end
                    attacker:AddTag("strawberry_sugar")

                    local mult = 0.65 -- 降为原来的65%
                    attacker.components.locomotor:SetExternalSpeedMultiplier(owner, "strawberry_sugar", mult)

                    local old_period = nil
                    if attacker.components.combat and type(attacker.components.combat.min_attack_period) == "number" then
                        old_period = attacker.components.combat.min_attack_period
                        attacker.components.combat.min_attack_period = old_period / mult
                    end

                    attacker:DoTaskInTime(5, function()
                        if not attacker:IsValid() then return end
                        attacker:RemoveTag("strawberry_sugar")
                        if attacker.components.locomotor then
                            attacker.components.locomotor:RemoveExternalSpeedMultiplier(owner, "strawberry_sugar")
                        end
                        if attacker.components.combat and old_period ~= nil then
                            attacker.components.combat.min_attack_period = old_period
                        end
                    end)
                end
                owner:ListenForEvent("attacked", owner._strawberry_attacked_handler)

                -- 甜食额外回复
                owner._strawberry_eat_handler = function(inst, data)
                    if not _G.Moon_HasEffect(owner, "strawberry") then return end
                    local food = data and data.food
                    if not food then return end
                    local foodtype = food.components.edible and food.components.edible.foodtype
                    -- DST中甜食通常用 foodtype == "GENERIC" 或 "VEGGIE" 中的特定prefab
                    -- 这里检测常见的甜食prefab
                    local prefab = food.prefab or ""
                    local sweet_foods = {
                        "taffy", "pumpkincookie", "waffles", "icecream",
                        "watermelonicle", "sweettea", "jellybean", "fruitmedley",
                        "berries", "cave_banana", "dragonfruit", "pomegranate",
                        "honey", "honeycomb", "royal_jelly"
                    }
                    for _, sweet in ipairs(sweet_foods) do
                        if prefab:find(sweet) then
                            if owner.components.health then
                                owner.components.health:DoDelta(20, false, "strawberry")
                            end
                            break
                        end
                    end
                end
                owner:ListenForEvent("oneat", owner._strawberry_eat_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "strawberry", "Legend_STRAWBERRY", 1)
            if not _G.Moon_HasEffect(owner, "strawberry") then
                if owner._strawberry_regen_task then
                    owner._strawberry_regen_task:Cancel()
                    owner._strawberry_regen_task = nil
                end
                if owner._strawberry_attacked_handler then
                    owner:RemoveEventCallback("attacked", owner._strawberry_attacked_handler)
                    owner._strawberry_attacked_handler = nil
                end
                if owner._strawberry_eat_handler then
                    owner:RemoveEventCallback("oneat", owner._strawberry_eat_handler)
                    owner._strawberry_eat_handler = nil
                end
                owner._strawberry_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_STRAWBERRY", 0.01)
end)
