-- 小月亮 附魔：篮球
-- 连续攻击同一目标时每击伤害+10%（最多10层+100%）
-- 叠满后下一击触发「灌篮！」造成500%暴击伤害并重置层数
-- 切换目标层数减半

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_LANQIU", {
        name = "篮球",
        client_text = "篮\n球",
        desc = "连续攻击同一目标每击+10%伤害(最多10层)\n叠满触发「灌篮!」500%暴击伤害\n切换目标层数减半",
        check_desc = "连击不断，灌篮终结！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "lanqiu", "Legend_LANQIU", 1)
            if not owner._lanqiu_hooked then
                owner._lanqiu_hooked = true
                owner._lanqiu_combo = 0
                owner._lanqiu_last_target = nil

                owner._lanqiu_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "lanqiu") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    local hh = owner.components.hh_player

                    -- 检查是否切换目标
                    if owner._lanqiu_last_target and owner._lanqiu_last_target ~= target then
                        -- 切换目标，层数减半(向下取整)
                        owner._lanqiu_combo = math.floor(owner._lanqiu_combo / 2)
                        -- 移除旧层数效果
                        if hh and owner._lanqiu_combo_old then
                            hh:ReduceEffectValueByKey("addComDamagePercent", owner._lanqiu_combo_old * 10)
                        end
                        -- 应用减半后的层数
                        if hh then
                            hh:AddEffectValueByKey("addComDamagePercent", owner._lanqiu_combo * 10)
                        end
                        owner._lanqiu_combo_old = owner._lanqiu_combo
                    end

                    owner._lanqiu_last_target = target

                    -- 检查是否触发灌篮 (叠满10层)
                    if owner._lanqiu_combo >= 10 then
                        -- 灌篮！500%暴击
                        if hh then
                            -- 移除连击加成
                            hh:ReduceEffectValueByKey("addComDamagePercent", owner._lanqiu_combo * 10)
                            -- 短暂增加暴击效果
                            hh:AddEffectValueByKey("criticalHitEffect", 400) -- 额外400% = 总共500%
                            hh:AddEffectValueByKey("criticalHitRate", 100) -- 必定暴击
                            owner:DoTaskInTime(0.2, function()
                                if owner:IsValid() and owner.components.hh_player then
                                    owner.components.hh_player:ReduceEffectValueByKey("criticalHitEffect", 400)
                                    owner.components.hh_player:ReduceEffectValueByKey("criticalHitRate", 100)
                                end
                            end)
                        end

                        -- 特效
                        if GLOBAL.SpawnPrefab then
                            local fx = GLOBAL.SpawnPrefab("collapse_small")
                            if fx then
                                local x, y, z = target.Transform:GetWorldPosition()
                                fx.Transform:SetPosition(x, y, z)
                            end
                        end

                        if owner.components.talker then
                            owner.components.talker:Say("灌篮！")
                        end

                        -- 重置层数
                        owner._lanqiu_combo = 0
                        owner._lanqiu_combo_old = 0
                    else
                        -- 正常叠层
                        -- 移除旧层
                        if hh and owner._lanqiu_combo_old then
                            hh:ReduceEffectValueByKey("addComDamagePercent", owner._lanqiu_combo_old * 10)
                        end
                        -- 增加新层
                        owner._lanqiu_combo = owner._lanqiu_combo + 1
                        owner._lanqiu_combo_old = owner._lanqiu_combo
                        -- 飘字提示
                        if owner.components.talker and owner._lanqiu_combo % 3 == 0 then
                            owner.components.talker:Say("连击 x" .. owner._lanqiu_combo .. "!")
                        end
                        if hh then
                            hh:AddEffectValueByKey("addComDamagePercent", owner._lanqiu_combo * 10)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._lanqiu_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "lanqiu", "Legend_LANQIU", 1)
            if not _G.Moon_HasEffect(owner, "lanqiu") then
                if owner._lanqiu_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._lanqiu_attack_handler)
                    owner._lanqiu_attack_handler = nil
                end
                local hh = owner.components.hh_player
                if hh and owner._lanqiu_combo_old then
                    hh:ReduceEffectValueByKey("addComDamagePercent", owner._lanqiu_combo_old * 10)
                end
                owner._lanqiu_combo = nil
                owner._lanqiu_combo_old = nil
                owner._lanqiu_last_target = nil
                owner._lanqiu_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_LANQIU", 0.01)
end)
