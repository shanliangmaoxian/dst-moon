-- 小月亮 附魔：我就跟着混
-- 周围15码内有队友：+20%伤害、+15%移速、减伤+30%
-- 队友击杀敌人时30%几率你也获得额外掉落

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_GENZHE", {
        name = "我就跟着混",
        client_text = "跟\n着",
        desc = "周围15码内有队友时：\n+20%伤害、+15%移速、减伤+30%\n队友击杀敌人时30%几率你也获得掉落",
        check_desc = "混子也是技术活！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "genzhe", "Legend_GENZHE", 1)
            if not owner._genzhe_hooked then
                owner._genzhe_hooked = true
                owner._genzhe_near_teammate = false
                owner._genzhe_applied = false

                -- 检测附近是否有队友（单次扫描，缓存结果）
                local function refreshTeammateStatus()
                    local x, y, z = owner.Transform:GetWorldPosition()
                    for _, v in ipairs(GLOBAL.AllPlayers) do
                        if v ~= owner and v:IsValid() and v:GetDistanceSqToPoint(x, y, z) < 225 then
                            return true
                        end
                    end
                    return false
                end

                -- 应用队友buff
                local function applyTeammateBuffs()
                    if owner._genzhe_applied then return end
                    owner._genzhe_applied = true
                    local hh = owner.components.hh_player
                    if hh then
                        hh:AddEffectValueByKey("addComDamagePercent", 20)
                        hh:AddEffectValueByKey("addSpeedPercent", 15)
                        hh:AddEffectValueByKey("absorbDamage", 30)
                    end
                end

                -- 移除队友buff
                owner._genzhe_removeBuffs = function()
                    if not owner._genzhe_applied then return end
                    owner._genzhe_applied = false
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("addComDamagePercent", 20)
                        hh:ReduceEffectValueByKey("addSpeedPercent", 15)
                        hh:ReduceEffectValueByKey("absorbDamage", 30)
                    end
                end

                -- 队友检测（5秒间隔 + 玩家加入/离开时立即刷新）
                owner._genzhe_check = function()
                    if not _G.Moon_HasEffect(owner, "genzhe") then return end
                    if refreshTeammateStatus() then
                        applyTeammateBuffs()
                    else
                        owner._genzhe_removeBuffs()
                    end
                end
                owner._genzhe_check_task = owner:DoPeriodicTask(5, owner._genzhe_check)

                -- 玩家加入/离开时立即刷新
                owner:ListenForEvent("ms_playerjoined", function() owner._genzhe_check() end)
                owner:ListenForEvent("ms_playerleft", function() owner._genzhe_check() end)

                -- 队友击杀掉落：监听死亡事件（事件驱动，不轮询）
                owner._genzhe_death_handler = function(_, data)
                    if not _G.Moon_HasEffect(owner, "genzhe") then return end
                    if not owner._genzhe_applied then return end
                    if math.random() > 0.3 then return end
                    local victim = data and data.inst
                    if not victim or not victim:IsValid() then return end
                    local x, y, z = owner.Transform:GetWorldPosition()
                    if victim:GetDistanceSqToPoint(x, y, z) > 400 then return end -- 20码

                    local killer = nil
                    if victim.components.combat and victim.components.combat.lastattacker then
                        killer = victim.components.combat.lastattacker
                    end
                    if killer and killer:IsValid() and killer:HasTag("player")
                        and killer ~= owner and killer:GetDistanceSqToPoint(x, y, z) < 225 then
                        if victim.components.lootdropper and not victim._genzhe_looted then
                            local ex, ey, ez = victim.Transform:GetWorldPosition()
                            _G.pcall(victim.components.lootdropper.DropLoot, victim.components.lootdropper, _G.Vector3(ex, ey, ez))
                            victim._genzhe_looted = true
                        end
                    end
                end
                owner:ListenForEvent("entity_death", owner._genzhe_death_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "genzhe", "Legend_GENZHE", 1)
            if not _G.Moon_HasEffect(owner, "genzhe") then
                if owner._genzhe_check_task then
                    owner._genzhe_check_task:Cancel()
                    owner._genzhe_check_task = nil
                end
                if owner._genzhe_death_handler then
                    owner:RemoveEventCallback("entity_death", owner._genzhe_death_handler)
                    owner._genzhe_death_handler = nil
                end
                if owner._genzhe_removeBuffs then
                    owner._genzhe_removeBuffs()
                end
                owner._genzhe_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_GENZHE", 0.01)
end)
