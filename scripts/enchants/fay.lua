-- 小月亮 附魔：妖精庇护（fay）
-- 攻击附带目标已损失生命值8%的真实伤害，击杀敌人时回复30点精神值
-- 夜间获得夜视效果，移动速度+20%，攻击有15%几率释放妖精之尘使目标减速40%持续3秒

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_FAY", {
        name = "妖精庇护",
        client_text = "妖精\n庇护",
        desc = "fay的祝福\n攻击附带8%已损失生命真伤，击杀回30精神\n夜间+20%移速+夜视，15%妖精之尘",
        check_desc = "妖精之力的庇护",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "fay", "Legend_FAY", 1)
            if not owner._fay_hooked then
                owner._fay_hooked = true

                -- 攻击时触发妖精之尘 + 真实伤害
                owner._fay_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "fay") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    -- 真实伤害：目标已损失生命值的8%
                    if target.components.health then
                        local max_hp = target.components.health.maxhealth or 100
                        local cur_hp = target.components.health.currenthealth or max_hp
                        local missing = max_hp - cur_hp
                        if missing > 0 then
                            local true_dmg = missing * 0.08
                            -- 使用 DoHHDelta 造成真实伤害（如果有的话）
                            if target.components.health.DoHHDelta then
                                target.components.health:DoHHDelta(-true_dmg, owner, nil)
                            else
                                target.components.health:DoDelta(-true_dmg, false, nil)
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._fay_attack_handler)

                -- 击杀回复30精神值
                owner._fay_kill_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "fay") then return end
                    if owner.components.sanity then
                        owner.components.sanity:DoDelta(30)
                    end
                end
                owner:ListenForEvent("killed", owner._fay_kill_handler)

                -- 夜间buff（事件驱动，不轮询）
                local function _fay_update_night()
                    if not _G.Moon_HasEffect(owner, "fay") then return end
                    local is_night = _G.TheWorld.state.isnight
                    local hh = owner.components.hh_player
                    if is_night and not owner._fay_night_active then
                        owner._fay_night_active = true
                        if hh then hh:AddEffectValueByKey("addSpeedPercent", 20) end
                        if owner.components.playervision then
                            owner.components.playervision:ForceNightVision(true)
                            owner._fay_nightvision = true
                        end
                    elseif not is_night and owner._fay_night_active then
                        owner._fay_night_active = false
                        if hh then hh:ReduceEffectValueByKey("addSpeedPercent", 20) end
                        if owner._fay_nightvision and owner.components.playervision then
                            owner.components.playervision:ForceNightVision(false)
                            owner._fay_nightvision = false
                        end
                    end
                end
                owner:WatchWorldState("isnight", _fay_update_night)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "fay", "Legend_FAY", 1)
            if not _G.Moon_HasEffect(owner, "fay") then
                if owner._fay_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._fay_attack_handler)
                    owner._fay_attack_handler = nil
                end
                if owner._fay_kill_handler then
                    owner:RemoveEventCallback("killed", owner._fay_kill_handler)
                    owner._fay_kill_handler = nil
                end
                -- 清理夜间效果
                if owner._fay_night_active then
                    local hh = owner.components.hh_player
                    if hh then
                        hh:ReduceEffectValueByKey("addSpeedPercent", 20)
                    end
                    if owner._fay_nightvision and owner.components.playervision then
                        owner.components.playervision:ForceNightVision(false)
                        owner._fay_nightvision = false
                    end
                end
                owner._fay_night_active = nil
                owner._fay_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_FAY", 0.01)
end)
