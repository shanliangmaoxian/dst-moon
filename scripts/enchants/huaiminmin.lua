-- 小月亮 附魔：怀民民
-- 平常：攻击+25%，攻击范围+25%
-- 镜华（mcw）装备：效果翻倍（攻击+50%，范围+50%），
--   且攻击伤害的 50% 转为真伤（走 HH 官方 DoHHDelta 通道，无视护甲），
--   夜晚攻击时概率催眠被攻击单位。

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

local ATK_PERCENT      = 25    -- 平常攻击加成（%）
local RANGE_PERCENT    = 0.25  -- 平常范围加成（基础攻击距离的百分比）
local TRUE_DMG_PERCENT = 0.5   -- 镜华：伤害转为真伤的比例
local SLEEP_CHANCE     = 0.30  -- 镜华：夜晚攻击催眠概率
local SLEEP_TIME       = 5     -- 催眠时长（秒）

-- =========================================================
-- Part 1: 伤害转换（编译期组件钩子，仅镜华佩戴时生效）
-- 原理：CalcDamage 时把本次攻击伤害减半并记下真伤部分，
--       onattackother 后由附魔注册段把真伤部分走 DoHHDelta 补刀。
-- =========================================================
AddComponentPostInit("combat", function(self)
    local _old_CalcDamage = self.CalcDamage
    self.CalcDamage = function(self, target, weapon, ...)
        local dmg = _old_CalcDamage(self, target, weapon, ...)
        local inst = self.inst
        if dmg
            and dmg > 0
            and target ~= nil
            and inst ~= nil
            and inst:HasTag("player")
            and inst.prefab == "mcw"
            and _G.Moon_HasEffect
            and _G.Moon_HasEffect(inst, "huaiminmin") then
            local true_part = dmg * TRUE_DMG_PERCENT
            dmg = dmg - true_part
            inst._hmm_pending_true = true_part
        end
        return dmg
    end
end)

-- =========================================================
-- Part 2: HH 附魔框架注册
-- =========================================================
if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_HUAIMINMIN", {
        name = "怀民民",
        client_text = "怀民\n民",
        desc = "攻击+25%，攻击范围+25%\n镜华装备：攻击+50%，范围+50%\n伤害50%转为真伤\n夜晚攻击30%概率催眠目标",
        check_desc = "你睡没睡？镜华：起来重睡！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, "huaiminmin", "Legend_HUAIMINMIN", 1)

            -- 镜华判定（角色不会中途变化，装备时算一次即可）
            local is_mcw = (owner.prefab == "mcw")
            local mult = is_mcw and 2 or 1

            if not owner._huaiminmin_hooked then
                owner._huaiminmin_hooked = true
                owner._huaiminmin_is_mcw = is_mcw
                owner._huaiminmin_buff_applied = false

                local hh = owner.components.hh_player

                -- 攻击加成（HH 效果键，走减伤/增伤体系）
                owner._huaiminmin_applyBuff = function()
                    if owner._huaiminmin_buff_applied then return end
                    local hh2 = owner.components.hh_player
                    if not hh2 then return end
                    hh2:AddEffectValueByKey("addComDamagePercent", ATK_PERCENT * mult)
                    owner._huaiminmin_buff_applied = true
                end
                owner._huaiminmin_removeBuff = function()
                    if not owner._huaiminmin_buff_applied then return end
                    local hh2 = owner.components.hh_player
                    if not hh2 then return end
                    hh2:ReduceEffectValueByKey("addComDamagePercent", ATK_PERCENT * mult)
                    owner._huaiminmin_buff_applied = false
                end
                owner._huaiminmin_applyBuff()

                -- 攻击范围加成（缓存原始攻击距离，防止绝对值写坏）
                local combat = owner.components.combat
                if combat then
                    if not owner._huaiminmin_orig_range then
                        owner._huaiminmin_orig_range = combat.attackrange or 3
                    end
                    local range_bonus = owner._huaiminmin_orig_range * RANGE_PERCENT * mult
                    combat:SetRange(owner._huaiminmin_orig_range + range_bonus)
                end

                -- 攻击后处理：真伤补刀（镜华）+ 夜晚催眠（镜华）
                owner._huaiminmin_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "huaiminmin") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if not owner._huaiminmin_is_mcw then return end

                    -- 1) 真伤补刀：CalcDamage 里减掉的 50% 伤害走 HH 官方真伤通道
                    local pending = owner._hmm_pending_true
                    owner._hmm_pending_true = nil
                    local health = target.components.health
                    if pending and pending > 0 and health and not health:IsDead() then
                        if health.DoHHDelta then
                            health:DoHHDelta(-pending, owner, nil)
                        else
                            health:DoDelta(-pending, false, "huaiminmin_true")
                        end
                    end

                    -- 2) 夜晚概率催眠（不对玩家/boss 生效）
                    if not health or health:IsDead() then return end
                    if target:HasTag("player") or target:HasTag("epic") then return end
                    if _G.TheWorld and _G.TheWorld.state.isnight
                        and target.components.sleeper
                        and math.random() <= SLEEP_CHANCE then
                        target.components.sleeper:AddSleepiness(10, SLEEP_TIME)
                        if owner.components.talker then
                            owner.components.talker:Say("怀民民：晚安～")
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._huaiminmin_attack_handler)
            else
                -- 多件同词条叠加时按当前判定刷新数值
                owner._huaiminmin_is_mcw = is_mcw
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "huaiminmin", "Legend_HUAIMINMIN", 1)
            if not _G.Moon_HasEffect(owner, "huaiminmin") then
                owner._huaiminmin_removeBuff()

                -- 还原攻击距离
                local combat = owner.components.combat
                if combat and owner._huaiminmin_orig_range then
                    combat:SetRange(owner._huaiminmin_orig_range)
                end

                if owner._huaiminmin_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._huaiminmin_attack_handler)
                    owner._huaiminmin_attack_handler = nil
                end

                owner._hmm_pending_true = nil
                owner._huaiminmin_orig_range = nil
                owner._huaiminmin_is_mcw = nil
                owner._huaiminmin_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_HUAIMINMIN", 0.005)
end)
