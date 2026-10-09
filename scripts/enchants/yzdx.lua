-- 小月亮 附魔：一枝独秀
-- 周围15码内没有队友时：+40%伤害、+20%移速，但受到的伤害+25%
-- 有队友时无任何效果（孤胆双刃：越独立越强，也越危险）

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_YZDX", {
        name = "一枝独秀",
        client_text = "一枝\n独秀",
        desc = "周围15码内无队友时：\n+60%伤害、+30%移速\n但受到的伤害+25%",
        check_desc = "一枝独秀，傲视群雄！\n孤身作战更强，但也更危险",
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
                        if v:IsValid() and v ~= owner and v:GetDistanceSqToPoint(x, y, z) < 225 then
                            is_solo = false
                            break
                        end
                    end
                    owner._yzdx_cache_solo = is_solo
                end

                -- 应用静态buff (伤害 + 移速)
                owner._yzdx_applyBuffs = function()
                    if owner._yzdx_effect_applied then return end
                    local hh = owner.components.hh_player
                    if not hh then return end
                    hh:AddEffectValueByKey("addComDamagePercent", 40)
                    hh:AddEffectValueByKey("addSpeedPercent", 20)
                    owner._yzdx_effect_applied = true
                end

                owner._yzdx_removeBuffs = function()
                    if not owner._yzdx_effect_applied then return end
                    local hh = owner.components.hh_player
                    if not hh then return end
                    hh:ReduceEffectValueByKey("addComDamagePercent", 40)
                    hh:ReduceEffectValueByKey("addSpeedPercent", 20)
                    owner._yzdx_effect_applied = false
                end

                -- 受到伤害+25%：包装本实例的 GetBlockDamage（HH 受击结算入口，
                -- hh_api.lua 的 combat GetAttacked 钩子调用其返回值直接进原版扣血），
                -- 仅在 solo 时对 owner 自己生效。乘法层写法参考 jieshen/ji 先例。
                local hh = owner.components.hh_player
                if hh and not hh._yzdx_gbd_wrapped then
                    hh._yzdx_gbd_wrapped = true
                    local old_gbd = hh.GetBlockDamage
                    hh._yzdx_orig_gbd = old_gbd
                    hh.GetBlockDamage = function(self, player, attacker, amount)
                        local dmg = old_gbd(self, player, attacker, amount)
                        if player == owner and owner._yzdx_cache_solo
                                and _G.Moon_HasEffect(owner, "yzdx") then
                            dmg = dmg * 1.25
                        end
                        return dmg
                    end
                end

                owner._yzdx_refreshBuffs = function()
                    if not _G.Moon_HasEffect(owner, "yzdx") then return end
                    _G.pcall(owner._yzdx_refreshCache, owner)
                    if owner._yzdx_cache_solo then
                        owner._yzdx_applyBuffs()
                    else
                        owner._yzdx_removeBuffs()
                    end
                end

                -- 初始应用
                owner._yzdx_refreshBuffs()

                -- 每3秒检测队友
                owner._yzdx_check_task = owner:DoPeriodicTask(3, owner._yzdx_refreshBuffs)
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "yzdx", "Legend_YZDX", 1)
            if not _G.Moon_HasEffect(owner, "yzdx") then
                if owner._yzdx_check_task then
                    owner._yzdx_check_task:Cancel()
                    owner._yzdx_check_task = nil
                end
                if owner._yzdx_removeBuffs then
                    owner._yzdx_removeBuffs()
                end
                -- 还原 GetBlockDamage 包装
                local hh = owner.components.hh_player
                if hh and hh._yzdx_gbd_wrapped and hh._yzdx_orig_gbd then
                    hh.GetBlockDamage = hh._yzdx_orig_gbd
                    hh._yzdx_orig_gbd = nil
                    hh._yzdx_gbd_wrapped = nil
                end
                owner._yzdx_effect_applied = nil
                owner._yzdx_cache_solo = nil
                owner._yzdx_inited = nil
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_YZDX", 0.01)
end)
