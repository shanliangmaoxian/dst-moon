-- 小月亮 附魔：一枝独秀
-- 1%最大生命真伤(穿透护甲与防御层减伤)、8%吸血、50%暴击效果、10%暴击率
-- 周围15码内没有队友时，以上效果翻倍

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_YZDX", {
        name = "一枝独秀",
        client_text = "一枝\n独秀",
        desc = "1%最大生命真伤+8%吸血+50%暴击效果+10%暴击率\n周围无队友时效果翻倍",
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

                -- 缓存：一次遍历 AllPlayers，检测周围是否有队友
                owner._yzdx_refreshCache = function()
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local is_solo = true
                    for _, v in ipairs(GLOBAL.AllPlayers) do
                        if v:IsValid() then
                            -- 检测附近队友
                            if is_solo and v ~= owner and v:GetDistanceSqToPoint(x, y, z) < 225 then
                                is_solo = false
                            end
                        end
                    end
                    owner._yzdx_cache_solo = is_solo
                    owner._yzdx_cache_mult = is_solo and 2 or 1
                end

                -- 应用静态buff (吸血 + 暴击效果 + 暴击率)
                owner._yzdx_applyBuffs = function()
                    if owner._yzdx_effect_applied then return end
                    local hh = owner.components.hh_player
                    if not hh then return end
                    _G.pcall(owner._yzdx_refreshCache, owner)
                    local mult = owner._yzdx_cache_mult or 1
                    hh:AddEffectValueByKey("bloodSuck", 8 * mult)
                    hh:AddEffectValueByKey("criticalHitEffect", 50 * mult)
                    -- 自带暴击率：否则 HH 的暴击效果(需 criticalHitRate > 0)永远不触发
                    hh:AddEffectValueByKey("criticalHitRate", 10 * mult)
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
                    hh:ReduceEffectValueByKey("criticalHitRate", 10 * mult)
                    owner._yzdx_effect_applied = false
                    owner._yzdx_applied_mult = nil
                end

                owner._yzdx_refreshBuffs = function()
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    owner._yzdx_removeBuffs()
                    owner._yzdx_applyBuffs()
                end

                -- 攻击时触发 1%最大生命真伤（使用缓存，不遍历 AllPlayers）
                owner._yzdx_attack_handler = function(attacker, data)
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    local health = target.components.health
                    if not health or health:IsDead() then return end

                    local mult = owner._yzdx_cache_mult or 1
                    local max_hp = health.maxhealth or 100
                    local dmg = max_hp * 0.01 * mult

                    -- 1%最大生命真伤：优先走 HH 官方真伤（SetVal 直写，穿透护甲与怪物强化
                    -- 防御层减伤，且带击杀归属/掉落兼容），无 DoHHDelta 时回退普通扣血。
                    -- 写法与 fay.lua / epsilon.lua 的真伤分支一致。
                    if health.DoHHDelta then
                        health:DoHHDelta(-dmg, owner, nil)
                    else
                        health:DoDelta(-dmg, false, nil)
                    end
                end
                owner:ListenForEvent("onattackother", owner._yzdx_attack_handler)

                -- 周期性更新缓存与buff（每3秒）
                owner._yzdx_periodicUpdate = function()
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    local hh = owner.components.hh_player
                    if not hh then return end

                    -- 刷新缓存（独狼判定）并同步吸血/增强buff
                    _G.pcall(owner._yzdx_refreshCache, owner)
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
                owner._yzdx_effect_applied = nil
                owner._yzdx_inited = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YZDX", 0.01)
end)
