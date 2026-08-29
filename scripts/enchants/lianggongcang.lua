-- Legend_LIANGGONG.lua
local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function()

    if not _G.Moon_IsHHEnabled() then
        return
    end

    GLOBAL.AddSpecialEquipEffect("Legend_LIANGGONG",{
        name="良弓藏",
        client_text="良弓\n藏",
        desc="自身伤害-1000%\n每30秒自动射箭攻击最近敌人(300%伤害)",
        check_desc="飞鸟尽，良弓藏。",
        can_add=false,
        only_one=true,
        is_special=false,
        client_color={0.8,0,0.8,1},

        check_equip_can_add=function()
            return true,"满足条件"
        end,

        on_equip_fn=function(inst,owner,value)

            _G.Moon_AddEffect(owner,"lianggongcang","Legend_LIANGGONG",1)

            if owner._lianggong_hooked then
                return
            end
            owner._lianggong_hooked=true

            if owner.components.hh_player then
                owner.components.hh_player:AddEffectValueByKey("addComDamagePercent",-1000)
            end

            owner._lianggong_task=owner:DoPeriodicTask(30,function()

                if not owner:IsValid() then return end
                if not _G.Moon_HasEffect(owner,"lianggongcang") then return end

                local x,y,z=owner.Transform:GetWorldPosition()

                local ents=_G.TheSim:FindEntities(
                    x,y,z,20,
                    {"_combat"},
                    {"INLIMBO","FX","NOCLICK","playerghost"}
                )

                local target=nil
                local d2=999999

                for _,v in ipairs(ents) do
                    if v~=owner
                    and v:IsValid()
                    and v.components.health
                    and not v.components.health:IsDead()
                    and v.components.combat
                    and not v:HasTag("player")
                    then

                        local inv=v.components.inventoryitem
                        if not (inv and (inv.owner or (inv.IsHeld and inv:IsHeld()))) then

                            local fol=v.components.follower
                            if not (fol and fol.leader==owner) then
                                local ex,ey,ez=v.Transform:GetWorldPosition()
                                local dx=x-ex
                                local dz=z-ez
                                local dist=dx*dx+dz*dz
                                if dist<d2 then
                                    d2=dist
                                    target=v
                                end
                            end
                        end
                    end
                end

                if target then
                    local dmg=34
                    local combat=owner.components.combat
                    if combat then
                        dmg=combat.defaultdamage or 34
                        if combat.externaldamagemultipliers then
                            dmg=dmg*combat.externaldamagemultipliers:Get()
                        end
                        if combat.weapon and combat.weapon.components.weapon then
                            dmg=combat.weapon.components.weapon.damage or dmg
                        end
                    end

                    target.components.combat:GetAttacked(owner,dmg*3)

                    local fx=_G.SpawnPrefab("impact")
                    if fx then
                        fx.Transform:SetPosition(target.Transform:GetWorldPosition())
                    end

                    if owner.components.talker and math.random()<0.3 then
                        owner.components.talker:Say("藏弓一发！")
                    end
                end
            end)
        end,

        un_equip_fn=function(inst,owner,value)

            _G.Moon_ReduceEffect(owner,"lianggongcang","Legend_LIANGGONG",1)

            if not _G.Moon_HasEffect(owner,"lianggongcang") then

                if owner.components.hh_player then
                    owner.components.hh_player:ReduceEffectValueByKey("addComDamagePercent",-1000)
                end

                if owner._lianggong_task then
                    owner._lianggong_task:Cancel()
                    owner._lianggong_task=nil
                end

                owner._lianggong_hooked=nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_LIANGGONG",0.008)
end)