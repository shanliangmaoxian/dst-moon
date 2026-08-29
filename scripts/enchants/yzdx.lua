-- 小月亮 附魔：一枝独秀
-- 有托托莉就1%的噩梦伤害，没有就1%血量伤害(类似撕裂)、8%吸血、50%增强
-- 周围15码内没有队友时，以上效果翻倍

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_YZDX", {
        name = "一枝独秀",
        client_text = "一枝\n独秀",
        desc = "有托托莉就1%的噩梦伤害，没有就1%血量伤害+8%吸血+50%增强\n周围无队友时效果翻倍",
        check_desc = "一枝独秀，傲视群雄！\n周围15码内无队友时效果翻倍",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "yzdx", "Legend_YZDX", 1)
            if not owner._yzdx_inited then
                owner._yzdx_inited = true
                owner._yzdx_effect_applied = false

                -- 缓存：一次遍历 AllPlayers，同时检测托托莉和周围队友
                owner._yzdx_refreshCache = function()
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local has_tutu = false
                    local is_solo = true
                    for _, v in ipairs(GLOBAL.AllPlayers) do
                        if v:IsValid() then
                            -- 检测托托莉
                            if not has_tutu then
                                local prefab = v.prefab or ""
                                if prefab:find("tutuoli") or prefab:find("totori") or prefab:find("torori") then
                                    has_tutu = true
                                end
                            end
                            -- 检测附近队友
                            if is_solo and v ~= owner and v:GetDistanceSqToPoint(x, y, z) < 225 then
                                is_solo = false
                            end
                        end
                    end
                    owner._yzdx_cache_tutu = has_tutu
                    owner._yzdx_cache_solo = is_solo
                    owner._yzdx_cache_mult = is_solo and 2 or 1
                end

                -- 应用静态buff (吸血 + 增强)
                owner._yzdx_applyBuffs = function()
                    if owner._yzdx_effect_applied then return end
                    local hh = owner.components.hh_player
                    if not hh then return end
                    _G.pcall(owner._yzdx_refreshCache, owner)
                    local mult = owner._yzdx_cache_mult or 1
                    hh:AddEffectValueByKey("bloodSuck", 8 * mult)
                    hh:AddEffectValueByKey("criticalHitEffect", 50 * mult)
                    owner._yzdx_effect_applied = true
                    owner._yzdx_applied_mult = mult
                end

                owner._yzdx_removeBuffs = function()
                    if not owner._yzdx_effect_applied then return end
                    local hh = owner.components.hh_player
                    if not hh then return end
                    local mult = owner._yzdx_applied_mult or 1
                    hh:ReduceEffectValueByKey("bloodSuck", 8 * mult)
                    hh:ReduceEffectValueByKey("criticalHitEffect", 50 * mult)
                    owner._yzdx_effect_applied = false
                    owner._yzdx_applied_mult = nil
                end

                owner._yzdx_refreshBuffs = function()
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    owner._yzdx_removeBuffs()
                    owner._yzdx_applyBuffs()
                end

                -- 攻击时触发撕裂/噩梦伤害（使用缓存，不遍历 AllPlayers）
                owner._yzdx_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if not target.components.health or target.components.health:IsDead() then return end

                    local mult = owner._yzdx_cache_mult or 1
                    local tutu = owner._yzdx_cache_tutu

                    if not tutu then
                        -- 没有托托莉：1%血量伤害（撕裂）
                        local max_hp = target.components.health.maxhealth or 100
                        local bleed_dmg = max_hp * 0.01 * mult
                        if target.components.health.DoHHDelta then
                            target.components.health:DoHHDelta(-bleed_dmg, owner, nil)
                        else
                            target.components.health:DoDelta(-bleed_dmg, false, nil)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._yzdx_attack_handler)

                -- 周期性更新缓存与buff（每3秒）
                owner._yzdx_periodicUpdate = function()
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    local hh = owner.components.hh_player
                    if not hh then return end

                    _G.pcall(owner._yzdx_refreshCache, owner)
                    local tutu = owner._yzdx_cache_tutu
                    local mult = owner._yzdx_cache_mult or 1

                    -- 更新 trueDamageNum (托托莉)
                    if tutu then
                        hh:ReduceEffectValueByKey("trueDamageNum", owner._yzdx_old_truedmg or 0)
                        local new_td = 1 * mult
                        hh:AddEffectValueByKey("trueDamageNum", new_td)
                        owner._yzdx_old_truedmg = new_td
                    else
                        if owner._yzdx_old_truedmg then
                            hh:ReduceEffectValueByKey("trueDamageNum", owner._yzdx_old_truedmg)
                            owner._yzdx_old_truedmg = nil
                        end
                    end

                    owner._yzdx_refreshBuffs()
                end

                -- 初始应用
                owner._yzdx_applyBuffs()
                owner._yzdx_periodicUpdate()

                -- 每3秒检测
                owner._yzdx_check_task = owner:DoPeriodicTask(3, owner._yzdx_periodicUpdate)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yzdx", "Legend_YZDX", 1)
            if not _G.Moon_HasEffect(owner, "yzdx") then
                if owner._yzdx_check_task then
                    owner._yzdx_check_task:Cancel()
                    owner._yzdx_check_task = nil
                end
                if owner._yzdx_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._yzdx_attack_handler)
                    owner._yzdx_attack_handler = nil
                end
                if owner._yzdx_removeBuffs then
                    owner._yzdx_removeBuffs()
                end
                local hh = owner.components.hh_player
                if hh and owner._yzdx_old_truedmg then
                    hh:ReduceEffectValueByKey("trueDamageNum", owner._yzdx_old_truedmg)
                    owner._yzdx_old_truedmg = nil
                end
                owner._yzdx_effect_applied = nil
                owner._yzdx_inited = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YZDX", 0.01)
end)
