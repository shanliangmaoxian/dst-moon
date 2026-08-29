-- 小月亮 附魔：心平气和 (Legend_XPING)
-- 攻守兼备套装·防御位 — 单件：减伤+持续回复（普通）；与「千月野」齐穿触发套装：
-- 减伤/回复大幅强化 + 受击 30% 几率获得护盾（25% 最大生命，10 秒消散，内置冷却 8 秒）
-- 套装判定：Moon_HasEffect 双向检查（xping + qianyue），不依赖 HH 已废弃的套装机制

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- 数值常量
local ABSORB_SINGLE = 10      -- 单件减伤 %
local ABSORB_SUIT = 25        -- 套装减伤 %
local HEAL_PCT_SINGLE = 0.015 -- 单件回复：3 秒回最大生命 %
local HEAL_PCT_SUIT = 0.03    -- 套装回复 %
local SHIELD_PCT = 0.25       -- 护盾 = 最大生命 %
local SHIELD_CHANCE = 0.3     -- 受击触发护盾概率
local SHIELD_COOLDOWN = 8     -- 护盾内置冷却（秒）
local SHIELD_DURATION = 10    -- 护盾持续时间（秒）

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_XPING", {
        name = "心平气和",
        client_text = "心平\n气和",
        desc = "佛系护体 — 减伤10%，每3秒回复1.5%生命\n与「千月野」齐穿触发套装：\n减伤25%、回复翻倍\n受击30%几率护盾(25%生命,冷却8秒)",
        check_desc = "佛系护体～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "xping", "Legend_XPING", 1)
            if not owner._xping_hooked then
                owner._xping_hooked = true

                -- 套装判定：与千月野同时装备
                local function isSuitActive()
                    return _G.Moon_HasEffect(owner, "xping")
                        and _G.Moon_HasEffect(owner, "qianyue")
                end

                -- 应用减伤（先清自己的上限值再按状态加，防残留）
                local function applyDefense(suit)
                    local hh = owner.components.hh_player
                    if not hh then return end
                    hh:ReduceEffectValueByKey("absorbDamage", ABSORB_SUIT)
                    hh:AddEffectValueByKey("absorbDamage", suit and ABSORB_SUIT or ABSORB_SINGLE)
                end

                -- 持续回复（常驻任务，按套装状态取数值）
                owner._xping_heal_task = owner:DoPeriodicTask(3, function()
                    if not _G.Moon_HasEffect(owner, "xping") or not owner:IsValid() then return end
                    local health = owner.components.health
                    if not health or health:IsDead() then return end
                    local pct = isSuitActive() and HEAL_PCT_SUIT or HEAL_PCT_SINGLE
                    health:DoDelta(health.maxhealth * pct, false, nil)
                end)

                -- 套装状态轮询：减伤数值切换 + 提示（0.5 秒延迟无感知）
                owner._xping_suit_was = false
                owner._xping_suit_task = owner:DoPeriodicTask(0.5, function()
                    if not _G.Moon_HasEffect(owner, "xping") then return end
                    local suit = isSuitActive()
                    if suit ~= owner._xping_suit_was then
                        owner._xping_suit_was = suit
                        applyDefense(suit)
                        if owner.components.talker then
                            owner.components.talker:Say(suit and "心平气和·套装激活！" or "套装失效")
                        end
                    end
                end)
                -- 立即应用当前状态（单穿时也要有单件数值，不能等轮询
                -- 首次变化——suit==was 时轮询不会触发 applyDefense）
                applyDefense(isSuitActive())

                -- 套装联动·护盾：被攻击 30% 几率获得护盾（仅套装激活时）
                owner._xping_shield_active = false
                owner._xping_shield_hp = 0
                owner._xping_shield_last = 0
                owner._xping_attacked_handler = function(victim, data)
                    if not _G.Moon_HasEffect(owner, "xping") then return end
                    if not isSuitActive() then return end
                    if owner._xping_shield_active then return end
                    local now = _G.GetTime()
                    if now - (owner._xping_shield_last or 0) < SHIELD_COOLDOWN then return end
                    if _G.math.random() > SHIELD_CHANCE then return end
                    local health = owner.components.health
                    if not health then return end

                    owner._xping_shield_last = now
                    owner._xping_shield_active = true
                    owner._xping_shield_hp = health.maxhealth * SHIELD_PCT

                    if owner.components.talker then
                        owner.components.talker:Say("心平气和·护盾！")
                    end

                    -- 护盾 SHIELD_DURATION 秒后消散（存句柄，卸载时 Cancel）
                    owner._xping_shield_timer = owner:DoTaskInTime(SHIELD_DURATION, function()
                        if owner:IsValid() then
                            owner._xping_shield_active = false
                            owner._xping_shield_hp = 0
                            owner._xping_shield_timer = nil
                        end
                    end)
                end
                owner:ListenForEvent("attacked", owner._xping_attacked_handler)

                -- DoDelta 拦截：护盾吸收伤害（与山竹同款范式；还原时校验归属，
                -- 避免与其他附魔（山竹/君可知）同穿时先卸装者覆盖后者的包装）
                local health = owner.components.health
                if health and not health._xping_hooked_dodelta then
                    local oldDoDelta = health.DoDelta
                    local function xping_shield_wrapper(self, delta, overtime, cause, ...)
                        if delta < 0 and cause ~= "xping_shield" then
                            if _G.Moon_HasEffect(owner, "xping") and owner._xping_shield_active then
                                local damage = -delta
                                if damage >= owner._xping_shield_hp then
                                    local overflow = damage - owner._xping_shield_hp
                                    owner._xping_shield_active = false
                                    owner._xping_shield_hp = 0
                                    if overflow > 0 then
                                        return oldDoDelta(self, -overflow, overtime, cause, ...)
                                    end
                                    return oldDoDelta(self, 0, overtime, cause, ...)
                                else
                                    owner._xping_shield_hp = owner._xping_shield_hp - damage
                                    return oldDoDelta(self, 0, overtime, cause, ...)
                                end
                            end
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                    health._xping_old_dodelta = oldDoDelta
                    health._xping_wrapper = xping_shield_wrapper
                    health.DoDelta = xping_shield_wrapper
                    health._xping_hooked_dodelta = true
                end
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "xping", "Legend_XPING", 1)
            if not _G.Moon_HasEffect(owner, "xping") then
                -- 清除减伤（清上限值，防残留）
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("absorbDamage", ABSORB_SUIT)
                end

                if owner._xping_heal_task then
                    owner._xping_heal_task:Cancel()
                    owner._xping_heal_task = nil
                end
                if owner._xping_suit_task then
                    owner._xping_suit_task:Cancel()
                    owner._xping_suit_task = nil
                end
                if owner._xping_shield_timer then
                    owner._xping_shield_timer:Cancel()
                    owner._xping_shield_timer = nil
                end
                if owner._xping_attacked_handler then
                    owner:RemoveEventCallback("attacked", owner._xping_attacked_handler)
                    owner._xping_attacked_handler = nil
                end

                -- 还原 DoDelta（校验归属：仅当当前包装还是自己的才还原）
                local health = owner.components.health
                if health and health._xping_wrapper and health.DoDelta == health._xping_wrapper then
                    health.DoDelta = health._xping_old_dodelta
                end
                if health then
                    health._xping_old_dodelta = nil
                    health._xping_wrapper = nil
                    health._xping_hooked_dodelta = nil
                end

                owner._xping_hooked = nil
                owner._xping_suit_was = nil
                owner._xping_shield_active = nil
                owner._xping_shield_hp = nil
                owner._xping_shield_last = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_XPING", 0.01)
end)
