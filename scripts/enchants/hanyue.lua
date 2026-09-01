-- 小月亮 附魔：寒月公主
-- 攻击冻结目标(永冻)：每秒扣2%最大生命(有托托莉则2%噩梦真伤)
-- 每次攻击附带666真伤 | 暴击率+66% 爆伤+666% | 雪花特效
-- 托托莉检测参考一枝独秀(yzdx)

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local FROST_DURATION = 8    -- 永冻持续时间(秒)，攻击会刷新
local FROST_PERCENT = 0.02  -- 每秒扣血百分比(2%最大生命)
local TRUE_DMG = 666        -- 每次攻击附带的真伤
local CRIT_RATE = 66        -- 暴击率(暴击率+66%)
local CRIT_EFFECT = 666     -- 爆伤(额外+666%)

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_HANYUE", {
        name = "寒月公主",
        client_text = "寒月\n公主",
        desc = "攻击冻结目标(永冻)每秒扣2%最大生命\n有托托莉则2%噩梦伤害 | 暴击+66% 爆伤+666%\n每次攻击附带666真伤",
        check_desc = "寒月照，万物霜！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "hanyue", "Legend_HANYUE", 1)
            if not owner._hanyue_inited then
                owner._hanyue_inited = true
                owner._hanyue_marks = {}
                owner._hanyue_has_totori = false

                -- 确保 ttl_wanly_damage 组件存在（托托莉噩梦伤害组件，由托托莉mod提供）
                if not owner.components.ttl_wanly_damage then
                    _G.pcall(function() owner:AddComponent("ttl_wanly_damage") end)
                end

                -- 暴击爆伤(HH框架属性)
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("criticalHitRate", CRIT_RATE)
                    hh:AddEffectValueByKey("criticalHitEffect", CRIT_EFFECT)
                end

                -- 雪花特效：目标头顶飘雪(优先 snow_fx，不存在则用冰刺特效兜底)
                -- local function spawnSnowFx(target)
                --     if not target or not target.Transform then return end
                --     local fx = _G.SpawnPrefab("snow_fx")
                --     if not fx then
                --         fx = _G.SpawnPrefab("deerclops_icespike_fx")
                --     end
                --     if fx and fx.Transform then
                --         local x, y, z = target.Transform:GetWorldPosition()
                --         fx.Transform:SetPosition(x, y + 1.5, z)
                --         fx:DoTaskInTime(1.5, function()
                --             if fx:IsValid() then
                --                 fx:Remove()
                --             end
                --         end)
                --     end
                -- end

                -- 冻结目标
                local function freezeTarget(target)
                    local fz = target.components.freezable
                    if fz then
                        fz:AddColdness(1)
                        fz:Freeze(FROST_DURATION)
                    end
                end

                -- 攻击触发：666真伤 + 永冻标记 + 雪花特效
                owner._hanyue_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "hanyue") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target:HasTag("player") then return end -- 只对怪物生效
                    local health = target.components.health
                    if not health or health:IsDead() then return end

                    -- 托托莉检测(参考一枝独秀)：有托托莉则每秒2%伤害变为噩梦真伤
                    local has_totori = false
                    for _, v in ipairs(_G.AllPlayers) do
                        if v:IsValid() then
                            local prefab = (v.prefab or ""):lower()
                            if prefab:find("totooria") or prefab:find("tutuoli") or prefab:find("totori") or prefab:find("torori") then
                                has_totori = true
                                break
                            end
                        end
                    end
                    owner._hanyue_has_totori = has_totori

                    -- 每次攻击附带666真伤(无视护甲)
                    if health.DoHHDelta then
                        health:DoHHDelta(-TRUE_DMG, owner, nil)
                    else
                        health:DoDelta(-TRUE_DMG, false, "hanyue_true")
                    end

                    -- 永冻标记(攻击刷新持续时长)
                    owner._hanyue_marks[target] = _G.GetTime() + FROST_DURATION
                    freezeTarget(target)
                end
                owner:ListenForEvent("onattackother", owner._hanyue_attack_handler)

                -- 每秒一跳：保持冻结 + 2%最大生命伤害 + 雪花特效
                owner._hanyue_tick_task = owner:DoPeriodicTask(1, function()
                    if not _G.Moon_HasEffect(owner, "hanyue") then return end
                    local now = _G.GetTime()
                    local remove_list = {}
                    for target, till in pairs(owner._hanyue_marks) do
                        local valid = target and target:IsValid()
                        local health = valid and target.components.health
                        if not valid or not health or health:IsDead() or now >= till then
                            remove_list[#remove_list + 1] = target
                        else
                            freezeTarget(target)
                            local max_hp = health.maxhealth or 100
                            local dmg = max_hp * FROST_PERCENT
                            if owner._hanyue_has_totori then
                                -- 托托莉噩梦伤害（ttl_wanly_damage 伤害模式）
                                local ttl = owner.components.ttl_wanly_damage
                                if ttl then
                                    ttl:ApplyTTL_wanly_damage(target, dmg)
                                else
                                    health:DoDelta(-dmg, false, "hanyue_frost")
                                end
                            else
                                health:DoDelta(-dmg, false, "hanyue_frost")
                            end
                        end
                    end
                    for _, t in ipairs(remove_list) do
                        owner._hanyue_marks[t] = nil
                    end
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "hanyue", "Legend_HANYUE", 1)
            if not _G.Moon_HasEffect(owner, "hanyue") then
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("criticalHitRate", CRIT_RATE)
                    hh:ReduceEffectValueByKey("criticalHitEffect", CRIT_EFFECT)
                end

                if owner._hanyue_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._hanyue_attack_handler)
                    owner._hanyue_attack_handler = nil
                end
                if owner._hanyue_tick_task then
                    owner._hanyue_tick_task:Cancel()
                    owner._hanyue_tick_task = nil
                end

                owner._hanyue_marks = nil
                owner._hanyue_has_totori = nil
                owner._hanyue_inited = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_HANYUE", 0) -- 掉落率0
end)
