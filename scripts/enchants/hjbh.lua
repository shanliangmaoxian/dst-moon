-- 小月亮 附魔：厚积薄发
-- 当角色15秒内没有攻击时，每0.5秒存储一次"当前攻击伤害"（走 HH DoAttackDamage
-- 公式，吃附魔与倍率加成），最多存储15次；下次攻击时，把存储总量释放为范围伤害。
-- 范围伤害走 DoHHDelta 真伤通道（与一枝独秀一致，带击杀归属），不会二次吃 HH 百分比。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_HJBH"
local EFFECT_KEY = "hjbh"

local IDLE_GATE = 15          -- 需要多久没攻击才开始蓄力（秒）
local TICK_INTERVAL = 0.5     -- 存储间隔（秒）
local MAX_STACKS = 15         -- 最多存储次数
local AOE_RADIUS = 6          -- 范围伤害半径

-- 计算当前攻击伤害快照：基础 CalcDamage + HH 附魔/倍率加成
-- （HH 的百分比加成在 combat:GetAttacked 里注入，这里手动走同一公式）
local function snapshot_damage(owner)
    local combat = owner.components.combat
    if not combat or not combat.CalcDamage then return 0 end
    -- 原版 CalcDamage(target, weapon, multiplier) 的 target 是必传参数（combat.lua:847
    -- 无条件 target:HasTag），传自身当中性目标；pcall 兜底防第三方 hook 抛错
    local ok, dmg = pcall(combat.CalcDamage, combat, owner)
    if not ok or type(dmg) ~= "number" then return 0 end
    local hh = owner.components.hh_player
    if hh and hh.DoAttackDamage then
        -- 用自身当中性目标：目标标签类加成不误触发，百分比加成正常生效
        dmg = hh:DoAttackDamage(owner, owner, dmg) or dmg
    end
    return dmg
end

-- 释放：以攻击目标为中心的范围真伤
local function release_aoe(owner, target, total)
    if total <= 0 or not target or not target:IsValid() then return end
    local x, y, z = target.Transform:GetWorldPosition()
    for _, v in ipairs(_G.TheSim:FindEntities(x, y, z, AOE_RADIUS, { "_combat" })) do
        if v:IsValid()
                and not v:HasTag("player")
                and not v:HasTag("playerghost")
                and v.components.health
                and not v.components.health:IsDead()
        then
            if v.components.health.DoHHDelta then
                v.components.health:DoHHDelta(-total, owner, nil)
            else
                v.components.health:DoDelta(-total, false, nil)
            end
        end
    end
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "厚积薄发",
        client_text = "厚积\n薄发",
        desc = "15秒未攻击后，每0.5秒存储一次当前攻击伤害（吃附魔与倍率加成），最多15次\n下次攻击时释放为范围真伤",
        check_desc = "别急，我在蓄力呢。——by：清欢渡",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._hjbh_hooked then
                owner._hjbh_hooked = true
                owner._hjbh_stack_count = 0   -- 已存储次数
                owner._hjbh_total = 0         -- 存储的伤害总量
                owner._hjbh_last_attack = _G.GetTime()

                -- 攻击时：刷新计时 + 释放已蓄力的范围伤害
                owner._hjbh_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    owner._hjbh_last_attack = _G.GetTime()
                    if owner._hjbh_stack_count > 0 then
                        local total = owner._hjbh_total
                        release_aoe(owner, data and data.target, total)
                        owner._hjbh_stack_count = 0
                        owner._hjbh_total = 0
                    end
                end
                owner:ListenForEvent("onattackother", owner._hjbh_attack_handler)

                -- 蓄力：15秒无攻击后每0.5秒存一次
                owner._hjbh_tick = function()
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    if owner._hjbh_stack_count >= MAX_STACKS then return end
                    if _G.GetTime() - (owner._hjbh_last_attack or 0) < IDLE_GATE then return end
                    local dmg = snapshot_damage(owner)
                    if dmg > 0 then
                        owner._hjbh_stack_count = owner._hjbh_stack_count + 1
                        owner._hjbh_total = owner._hjbh_total + dmg
                        if owner._hjbh_stack_count == MAX_STACKS and owner.components.talker then
                            owner.components.talker:Say("蓄满了！该出手了！")
                        end
                    end
                end
                owner._hjbh_task = owner:DoPeriodicTask(TICK_INTERVAL, owner._hjbh_tick)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                if owner._hjbh_task then
                    owner._hjbh_task:Cancel()
                    owner._hjbh_task = nil
                end
                if owner._hjbh_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._hjbh_attack_handler)
                    owner._hjbh_attack_handler = nil
                end
                owner._hjbh_stack_count = nil
                owner._hjbh_total = nil
                owner._hjbh_last_attack = nil
                owner._hjbh_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
