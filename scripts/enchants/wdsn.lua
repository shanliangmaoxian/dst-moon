-- 小月亮 附魔：我打宿傩？
-- 基础：固定增伤1点，爆率+2%，爆伤10%，命中的目标30秒内无法回血
-- 对 boss：每刀额外 26 点真伤

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

local EFFECT_ID = "Legend_WDSN"
local EFFECT_KEY = "wdsn"

local HEAL_BLOCK_TIME = 30        -- 封疗时长（秒）
local BOSS_EXTRA = 26             -- 对 boss 每刀额外真伤

-- 让目标无法回血：包一层 health.DoDelta，正回复在封疗期内归零
-- 到期后包装器自动放行（不解包，避免嵌套 hook 风险）
local function apply_heal_block(target)
    local now = _G.GetTime()
    local health = target.components.health
    if not health then return end
    if target._wdsn_block_until and target._wdsn_block_until > now then
        target._wdsn_block_until = now + HEAL_BLOCK_TIME
        return
    end
    target._wdsn_block_until = now + HEAL_BLOCK_TIME
    if not target._wdsn_heal_hooked then
        target._wdsn_heal_hooked = true
        local old = health.DoDelta
        health.DoDelta = function(self, delta, overtime, cause, ...)
            if delta > 0 and target._wdsn_block_until and _G.GetTime() < target._wdsn_block_until then
                delta = 0
            end
            return old(self, delta, overtime, cause, ...)
        end
    end
end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect(EFFECT_ID, {
        name = "我打宿傩？",
        client_text = "我打\n宿傩？",
        desc = "增伤+1，爆率+2%，爆伤+10%，命中目标30秒无法回血\n对boss每刀额外" .. BOSS_EXTRA .. "点真伤",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            _G.Moon_AddEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not owner._wdsn_hooked then
                owner._wdsn_hooked = true

                -- 静态数值 buff：装备即生效
                local hh = owner.components.hh_player
                if hh then
                    hh:AddEffectValueByKey("trueDamageNum", 1)
                    hh:AddEffectValueByKey("criticalHitRate", 2)
                    hh:AddEffectValueByKey("criticalHitEffect", 10)
                end

                -- 命中处理：封疗 + boss 额外真伤
                owner._wdsn_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, EFFECT_KEY) then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    local health = target.components.health
                    if not health or health:IsDead() then return end

                    -- 封疗
                    apply_heal_block(target)

                    if target:HasTag("boss") and BOSS_EXTRA > 0 then
                        if health.DoHHDelta then
                            health:DoHHDelta(-BOSS_EXTRA, owner, nil)
                        else
                            health:DoDelta(-BOSS_EXTRA, false, nil)
                        end
                    end
                end
                owner:ListenForEvent("onattackother", owner._wdsn_attack_handler)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, EFFECT_KEY, EFFECT_ID, 1)
            if not _G.Moon_HasEffect(owner, EFFECT_KEY) then
                if owner._wdsn_attack_handler then
                    owner:RemoveEventCallback("onattackother", owner._wdsn_attack_handler)
                    owner._wdsn_attack_handler = nil
                end
                local hh = owner.components.hh_player
                if hh then
                    hh:ReduceEffectValueByKey("trueDamageNum", 1)
                    hh:ReduceEffectValueByKey("criticalHitRate", 2)
                    hh:ReduceEffectValueByKey("criticalHitEffect", 10)
                end
                owner._wdsn_hooked = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_ID, 0.01)
end)
