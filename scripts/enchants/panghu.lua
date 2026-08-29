-- 小月亮 附魔：胖虎
-- 攻击有15%几率释放「魔音贯耳」
-- 对周围敌人造成200点伤害
-- 周围小动物惊恐逃跑

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then
    return
end

AddPrefabPostInit("world", function(inst)

    if not _G.Moon_IsHHEnabled() then
        return
    end

    GLOBAL.AddSpecialEquipEffect("Legend_PANGHU", {

        name = "胖虎",
        client_text = "胖\n虎",
        desc = "攻击有15%几率释放「魔音贯耳」\n对周围敌人造成200点伤害\n震撼威压：释放时周围小动物惊恐逃跑",
        check_desc = "我是胖虎，我是孩子王！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = {0.8,0,0.8,1},

        check_equip_can_add = function(inst)
            return true,"满足条件"
        end,

        ------------------------------------------------------
        -- 装备
        ------------------------------------------------------
        on_equip_fn = function(inst, owner, value)

            _G.Moon_AddEffect(owner,"panghu","Legend_PANGHU",1)

            if owner._panghu_hooked then
                return
            end

            owner._panghu_hooked = true

            owner._panghu_attack_handler = function(attacker,data)

                if not _G.Moon_HasEffect(owner,"panghu") then
                    return
                end

                local target = data and data.target

                if not target or not target:IsValid() then
                    return
                end

                if math.random() > 0.15 then
                    return
                end

                local x,y,z = target.Transform:GetWorldPosition()

                --------------------------------------------------
                -- 范围伤害
                --------------------------------------------------

                local victims = _G.TheSim:FindEntities(
                    x,y,z,
                    8,
                    {"_combat"},
                    {
                        "INLIMBO",
                        "FX",
                        "NOCLICK",
                        "DECOR",
                        "playerghost"
                    }
                )

                for _,victim in ipairs(victims) do

                    if victim ~= owner
                    and not victim:HasTag("player")
                    and victim:IsValid()
                    and victim.components.health
                    and not victim.components.health:IsDead()
                    and victim.components.combat then

                        --------------------------------------------------
                        -- 不伤害容器、背包里的生物
                        --------------------------------------------------

                        local inv = victim.components.inventoryitem

                        if not (
                            inv and (
                                inv.owner
                                or (inv.IsHeld and inv:IsHeld())
                            )
                        ) then

                            victim.components.combat:GetAttacked(owner,200)

                            if victim.components.talker then
                                pcall(function()
                                    victim.components.talker:Say("好难听啊！")
                                end)
                            end
                        end
                    end
                end

                --------------------------------------------------
                -- 吓跑附近小动物
                --------------------------------------------------

                local animals = _G.TheSim:FindEntities(
                    x,y,z,
                    12,
                    nil,
                    {"INLIMBO"}
                )

                for _,animal in ipairs(animals) do

                    if animal:IsValid() then

                        local p = animal.prefab

                        if p=="rabbit"
                        or p=="rabbit2"
                        or p=="bird"
                        or p=="crow"
                        or p=="robin"
                        or p=="robin_winter"
                        or p=="canary"
                        or p=="mole"
                        or p=="perd"
                        or p=="penguin" then

                            animal:PushEvent("panic")

                        end
                    end
                end

                --------------------------------------------------
                -- 玩家喊话
                --------------------------------------------------

                if owner.components.talker then
                    owner.components.talker:Say("【魔音贯耳】我是胖虎，我是孩子王！🎵~")
                end
            end

            owner:ListenForEvent(
                "onattackother",
                owner._panghu_attack_handler
            )

        end,

        ------------------------------------------------------
        -- 卸下
        ------------------------------------------------------

        un_equip_fn = function(inst,owner,value)

            _G.Moon_ReduceEffect(owner,"panghu","Legend_PANGHU",1)

            if not _G.Moon_HasEffect(owner,"panghu") then

                if owner._panghu_attack_handler then

                    owner:RemoveEventCallback(
                        "onattackother",
                        owner._panghu_attack_handler
                    )

                    owner._panghu_attack_handler=nil
                end

                owner._panghu_hooked=nil

            end

        end,

    })

    _G.Moon_RegisterEnchantDrop("Legend_PANGHU",0.01)

end)