-- 小月亮 附魔：千月野 (Legend_QIANYUE)
-- 攻守兼备套装·输出位 — 单件：伤害+攻速（普通）；与「心平气和」齐穿触发套装：
-- 伤害/攻速大幅强化 + 击杀触发月爆（250% 攻击力范围伤害，内置冷却 3 秒）
-- 套装判定：Moon_HasEffect 双向检查（qianyue + xping），不依赖 HH 已废弃的套装机制

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

-- 数值常量
local DMG_SINGLE = 12   -- 单件伤害加成 %
local DMG_SUIT = 30     -- 套装伤害加成 %
local ATK_SINGLE = 10   -- 单件攻速 %（HH atk_speed，上限 2 倍=100）
local ATK_SUIT = 30     -- 套装攻速 %
local BURST_RADIUS = 6  -- 月爆范围（码）
local BURST_MULT = 2.5  -- 月爆 = 攻击力倍数
local BURST_COOLDOWN = 3 -- 月爆内置冷却（秒）

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_QIANYUE", {
        name = "千月野",
        client_text = "千\n月",
        desc = "月野锋芒 — 伤害+12%，攻速+10%\n与「心平气和」齐穿触发套装：\n伤害+30%、攻速+30%\n击杀触发月爆(250%范围伤害,冷却3秒)",
        check_desc = "月野锋芒～",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "qianyue", "Legend_QIANYUE", 1)
            if not owner._qianyue_hooked then
                owner._qianyue_hooked = true

                -- 套装判定：与心平气和同时装备
                local function isSuitActive()
                    return _G.Moon_HasEffect(owner, "qianyue")
                        and _G.Moon_HasEffect(owner, "xping")
                end

                -- 应用输出数值（先清自己的上限值再按状态加，防残留）
                local function applyOffense(suit)
                    local hh = owner.components.hh_player
                    if not hh then return end
                    hh:ReduceEffectValueByKey("addComDamagePercent", DMG_SUIT)
                    hh:ReduceEffectValueByKey("atk_speed", ATK_SUIT)
                    hh:AddEffectValueByKey("addComDamagePercent", suit and DMG_SUIT or DMG_SINGLE)
                    hh:AddEffectValueByKey("atk_speed", suit and ATK_SUIT or ATK_SINGLE)
                end

                -- 套装状态轮询：输出数值切换 + 提示
                owner._qianyue_suit_was = false
                owner._qianyue_suit_task = owner:DoPeriodicTask(0.5, function()
                    if not _G.Moon_HasEffect(owner, "qianyue") then return end
                    local suit = isSuitActive()
                    if suit ~= owner._qianyue_suit_was then
                        owner._qianyue_suit_was = suit
                        applyOffense(suit)
                        if owner.components.talker then
                            owner.components.talker:Say(suit and "千月野·套装激活！" or "套装失效")
                        end
                    end
                end)
                -- 立即应用当前状态（单穿时也要有单件数值，不能等轮询
                -- 首次变化——suit==was 时轮询不会触发 applyOffense）
                applyOffense(isSuitActive())

                -- 套装联动·月爆：击杀敌人时对周围 6 码敌人造成 250% 攻击力范围伤害（仅套装激活时）
                owner._qianyue_kill_last = 0
                owner._qianyue_kill_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "qianyue") then return end
                    if not isSuitActive() then return end
                    -- 只响应玩家击杀他人（killed 事件，data.target=被击杀者；
                    -- 此时目标 IsDead() 已为 true，不能再拿 IsDead 过滤）
                    local target = data and data.victim
                    if not target or target == owner or not target:IsValid() then return end

                    local now = _G.GetTime()
                    if now - (owner._qianyue_kill_last or 0) < BURST_COOLDOWN then return end
                    owner._qianyue_kill_last = now

                    local x, y, z = owner.Transform:GetWorldPosition()
                    local damage = 50
                    if owner.components.combat then
                        damage = owner.components.combat.defaultdamage or 50
                    end
                    local burst = damage * BURST_MULT

                    local enemies = _G.TheSim:FindEntities(x, y, z, BURST_RADIUS, { "_combat" })
                    for _, enemy in _G.ipairs(enemies) do
                        if enemy ~= owner and enemy:IsValid() and not enemy:HasTag("player")
                            and not enemy:HasTag("follower") -- 不误伤友方随从（猪人/牛等）
                            and enemy.components.health and not enemy.components.health:IsDead() then
                            enemy.components.health:DoDelta(-burst, false, "qianyue_burst")
                        end
                    end

                    if owner.components.talker then
                        owner.components.talker:Say("月爆！")
                    end
                end
                owner:ListenForEvent("killed", owner._qianyue_kill_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "qianyue", "Legend_QIANYUE", 1)
            if not _G.Moon_HasEffect(owner, "qianyue") then
                -- 清除输出数值（清上限值，防残留）
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addComDamagePercent", DMG_SUIT)
                    hh:ReduceEffectValueByKey("atk_speed", ATK_SUIT)
                end

                if owner._qianyue_suit_task then
                    owner._qianyue_suit_task:Cancel()
                    owner._qianyue_suit_task = nil
                end
                if owner._qianyue_kill_handler then
                    owner:RemoveEventCallback("killed", owner._qianyue_kill_handler)
                    owner._qianyue_kill_handler = nil
                end

                owner._qianyue_hooked = nil
                owner._qianyue_suit_was = nil
                owner._qianyue_kill_last = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_QIANYUE", 0.01)
end)
