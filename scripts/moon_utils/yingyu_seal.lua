local M = {}

function M.Install()
    local action = ACTIONS.CCS_SEAL
    if not action or action._lmoon_yingyu_hooked then return end
    action._lmoon_yingyu_hooked = true
    local original = action.fn
    action.fn = function(act)
        local target, doer = act.target, act.doer
        local pity = doer and doer.components.lmoon_yingyu_pity
        local valid = pity and target and target:IsValid() and not target._lmoon_yingyu_rewarded
        local health = valid and target.components.health
        local alive = health and not health:IsDead()
        local result, reason = original(act)

        -- 本体失败时也会返回true，必须确认怪物确实被封印击杀，或物品被消耗。
        -- 不监听普通击杀/卡牌获得，避免其它来源的卡牌触发抽奖。
        if valid and result and ((alive and health:IsDead() and target:HasTag("ccs_no_droploot"))
            or (not health and not target:IsValid())) then
            target._lmoon_yingyu_rewarded = true
            pity:OnSealSuccess()
        end
        return result, reason
    end
end

return M
