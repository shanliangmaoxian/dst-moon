-- 小月亮 附魔：空白
-- 攻击时60%几率清除目标身上所有增益效果
-- 每成功清除一个增益，获得+60%伤害加成，持续30秒（最多5层+300%）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_KONGBAI", {
        name = "空白",
        client_text = "空\n白",
        desc = "攻击60%几率清除目标所有增益\n每清除一个增益+60%伤害(最多5层+300%)\n持续30秒",
        check_desc = "归于虚无，万物皆空",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "kongbai", "Legend_KONGBAI", 1)
            if not owner._kongbai_hooked then
                owner._kongbai_hooked = true
                owner._kongbai_stacks = 0

                -- 攻击时清除目标增益
                owner._kongbai_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "kongbai") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end

                    if math.random() <= 0.6 then
                        local buffs_cleared = 0

                        -- 清除目标的伤害吸收buff
                        if target.components.health and target.components.health.externalabsorbmodifiers then
                            local mods = target.components.health.externalabsorbmodifiers
                            local keys = {}
                            for k, _ in pairs(mods) do
                                if type(k) == "string" then
                                    keys[#keys + 1] = k
                                end
                            end
                            for _, k in ipairs(keys) do
                                mods:RemoveModifier(k)
                                buffs_cleared = buffs_cleared + 1
                            end
                        end

                        -- 清除目标的伤害减免
                        if target.components.combat and target.components.combat.externaldamagetakenmultipliers then
                            local mods = target.components.combat.externaldamagetakenmultipliers
                            local keys = {}
                            for k, _ in pairs(mods) do
                                if type(k) == "string" then
                                    keys[#keys + 1] = k
                                end
                            end
                            for _, k in ipairs(keys) do
                                mods:RemoveModifier(k)
                                buffs_cleared = buffs_cleared + 1
                            end
                        end

                        -- 移除一些常见增益标签
                        local buff_tags = { "shielded", "armored", "enhanced", "buffed" }
                        for _, tag in ipairs(buff_tags) do
                            if target:HasTag(tag) then
                                target:RemoveTag(tag)
                                buffs_cleared = buffs_cleared + 1
                            end
                        end

                        if buffs_cleared > 0 then
                            -- 叠加伤害buff
                            local hh_player = owner.components.hh_player
                            if hh_player then
                                -- 移除旧层
                                hh_player:ReduceEffectValueByKey("addComDamagePercent", owner._kongbai_stacks * 60)
                                -- 增加新层
                                owner._kongbai_stacks = math.min(owner._kongbai_stacks + buffs_cleared, 5)
                                hh_player:AddEffectValueByKey("addComDamagePercent", owner._kongbai_stacks * 60)

                                -- 30秒后衰减
                                if owner._kongbai_decay_task then
                                    owner._kongbai_decay_task:Cancel()
                                end
                                owner._kongbai_decay_task = owner:DoTaskInTime(30, function()
                                    if owner:IsValid() then
                                        if owner.components.hh_player then
                                            owner.components.hh_player:ReduceEffectValueByKey("addComDamagePercent", owner._kongbai_stacks * 60)
                                        end
                                        owner._kongbai_stacks = 0
                                    end
                                end)
                            end
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._kongbai_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "kongbai", "Legend_KONGBAI", 1)
            if not _G.Moon_HasEffect(owner, "kongbai") then
                if owner._kongbai_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._kongbai_attack_handler)
                    owner._kongbai_attack_handler = nil
                end
                if owner._kongbai_decay_task then
                    owner._kongbai_decay_task:Cancel()
                    owner._kongbai_decay_task = nil
                end
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addComDamagePercent", (owner._kongbai_stacks or 0) * 60)
                end
                owner._kongbai_stacks = nil
                owner._kongbai_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_KONGBAI", 0.01)
end)
