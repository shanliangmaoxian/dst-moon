-- 小月亮 附魔：蔷薇主教
-- 将血肉织成能抵御伤害的披风！
-- 血量≤50%时每损失1%血+0.6%移速(上限+30%)
-- 受击冰霜爆发：4格内敌人冻结1秒+50%攻击力伤害(CD4秒)

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local MAX_SPEED = 30        -- 低血移速上限
local FROST_RANGE = 4       -- 冰霜爆发范围
local FROST_CD = 4          -- 冰霜爆发冷却(秒)

-- 更新低血移速（血量≤50%时，每损失1%血 +0.6%移速，上限+30%）
local function update_speed(owner)
    local hh = owner.components.hh_player
    if not hh then return end
    local percent = owner.components.health and owner.components.health:GetPercent() or 1
    local target = 0
    if percent <= 0.5 then
        target = math.min(MAX_SPEED, math.floor((0.5 - percent) * 60))
    end
    local cur = owner._qiangwei_speed_bonus or 0
    if target > cur then
        hh:AddEffectValueByKey("addSpeedPercent", target - cur)
    elseif target < cur then
        hh:ReduceEffectValueByKey("addSpeedPercent", cur - target)
    end
    owner._qiangwei_speed_bonus = target
end

-- 受击冰霜爆发：4格内敌人冻结1秒+50%攻击力伤害（CD4秒，特效ice_splash）
local function frost_burst(owner)
    local now = _G.GetTime and _G.GetTime() or 0
    if owner._qiangwei_frost_cd and now - owner._qiangwei_frost_cd < FROST_CD then
        return
    end
    owner._qiangwei_frost_cd = now

    local x, y, z = owner.Transform:GetWorldPosition()
    local fx = _G.SpawnPrefab("ice_splash")
    if fx then fx.Transform:SetPosition(x, y + 1, z) end

    local dmg = (owner.components.combat and owner.components.combat.defaultdamage or 10) * 0.5
    -- 用 C 层 TheSim:FindEntities（严格模式下 GLOBAL.FindEntities 未声明不可用）
    local targets = _G.TheSim:FindEntities(x, y, z, FROST_RANGE, { "_combat" }, { "INLIMBO", "FX", "NOCLICK", "DECOR", "player", "playerghost", "friendly", "companion", "wall", "structure", "prey", "butterfly" })
    for _, t in ipairs(targets) do
        if t and t:IsValid() and t.components.health and not t.components.health:IsDead() then
            -- 目标侧受击（HH 框架下玩家 combat:DoDamage 不可用，与良弓藏/胖虎一致）
            if t.components.combat and t.components.combat.GetAttacked then
                t.components.combat:GetAttacked(owner, dmg)
            end
            if t.components.freezable then
                t.components.freezable:AddColdness(2, 1) -- 冻结1秒
            end
        end
    end
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_QIANGWEI", {
        name = "蔷薇主教",
        client_text = "蔷\n薇",
        desc = "血肉披风:血量≤50%时低血加移速(上限+30%)\n受击冰霜爆发:4格内敌人冻结1秒+50%伤害(CD4秒)",
        check_desc = "将血肉织成能抵御伤害的披风！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "qiangwei", "Legend_QIANGWEI", 1)
            if not owner._qiangwei_hooked then
                owner._qiangwei_hooked = true

                update_speed(owner)

                -- 勾住 health:DoDelta 监听受击（冰霜爆发）
                local health = owner.components.health
                if health and not health._qiangwei_hooked_dodelta then
                    health._qiangwei_hooked_dodelta = true
                    local oldDoDelta = health.DoDelta
                    health._qiangwei_old_dodelta = oldDoDelta
                    health.DoDelta = function(self, delta, overtime, cause, ...)
                        -- 仅战斗打击(非持续伤害)触发冰霜爆发，冷/火/中毒等持续掉血不触发
                        if delta < 0 and not overtime and _G.Moon_HasEffect(owner, "qiangwei") then
                            frost_burst(owner)
                        end
                        return oldDoDelta(self, delta, overtime, cause, ...)
                    end
                end

                -- 低血移速：每1秒刷新
                owner._qiangwei_speed_task = owner:DoPeriodicTask(1, function()
                    if not _G.Moon_HasEffect(owner, "qiangwei") then return end
                    update_speed(owner)
                end)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "qiangwei", "Legend_QIANGWEI", 1)
            if not _G.Moon_HasEffect(owner, "qiangwei") then
                -- 还原低血移速
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("addSpeedPercent", owner._qiangwei_speed_bonus or 0)
                end
                owner._qiangwei_speed_bonus = nil
                -- 还原 DoDelta
                local health = owner.components.health
                if health and health._qiangwei_old_dodelta then
                    health.DoDelta = health._qiangwei_old_dodelta
                    health._qiangwei_old_dodelta = nil
                    health._qiangwei_hooked_dodelta = nil
                end
                -- 停止任务
                if owner._qiangwei_speed_task then
                    owner._qiangwei_speed_task:Cancel()
                    owner._qiangwei_speed_task = nil
                end
                owner._qiangwei_frost_cd = nil
                owner._qiangwei_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_QIANGWEI", 0.01)
end)
