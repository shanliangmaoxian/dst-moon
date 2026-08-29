-- 小月亮 附魔：七步之外
-- 增加攻击距离 2~4（生成附魔石时确定具体数值，4为满级）
-- 获取：受到100+伤害时1%概率获得附魔石

local _G = GLOBAL
local CFG = GLOBAL.MOON_CFG

-- =========================================================
-- 独立计数器：受到100+伤害时1%概率获得附魔石
-- 独立于 HH 框架，防止部署环境不生效
-- =========================================================
local _ldgory_hooked_world = false

AddPrefabPostInit("world", function(inst)
    if not _G.TheWorld.ismastersim then return end
    if _ldgory_hooked_world then return end
    _ldgory_hooked_world = true

    -- 监听所有玩家受伤事件（用 healthdelta 事件，不需要 hook DoDelta）
    AddPrefabPostInitAny(function(inst2)
        if not _G.TheWorld.ismastersim then return end
        if not inst2:HasTag("player") then return end
        if inst2._ldgory_hooked then return end
        inst2._ldgory_hooked = true

        inst2:ListenForEvent("healthdelta", function(_, data)
            if not data then return end
            local newhp = data.newhealth or 0
            local oldhp = data.oldhealth or 0
            local delta = newhp - oldhp
            -- 只拦截伤害（负值），且 >=100
            if delta < 0 and -delta >= 100 and math.random() <= 0.01 then
                local success, stone = _G.pcall(_G.HHSpawnStoneById, "Legend_CHANGPI")
                if success and stone and inst2.components.inventory then
                    inst2.components.inventory:GiveItem(stone, nil, inst2:GetPosition())
                    if inst2.components.talker then
                        inst2.components.talker:Say("七步之外附魔石到手！攻击距离增加啦～")
                    end
                end
            end
        end)
    end)
end)

-- =========================================================
-- 附魔注册（需要 HH 框架）
-- =========================================================
if not CFG.ENABLE_MORE_ENCHANTS then return end

AddPrefabPostInit("world", function(inst)
    if not _G.Moon_IsHHEnabled() then return end

    GLOBAL.AddSpecialEquipEffect("Legend_CHANGPI", {
        name = "七步之外",
        client_text = "七步\n之外",
        desc = "受到100+伤害时有1%%概率获得\n增加攻击距离%s",
        check_desc = "七步之外，摸得到！",
        can_add = false,
        only_one = true,
        is_special = false,
        client_color = { 0.8, 0, 0.8, 1 },
        value_range = { min = 2, max = 4 },
        check_equip_can_add = function(inst)
            return true, "满足条件"
        end,
        on_equip_fn = function(inst, owner, value)
            local range_bonus = value or 2
            _G.Moon_AddEffect(owner, "changpi", "Legend_CHANGPI", range_bonus)
            local combat = owner.components.combat
            if combat then
                if not owner._changpi_orig_range then
                    owner._changpi_orig_range = combat.attackrange or 3
                end
                local total_bonus = _G.Moon_GetTotalEffectValue(owner, "changpi")
                combat:SetRange(owner._changpi_orig_range + total_bonus)
            end
            if not owner._changpi_hooked then
                owner._changpi_hooked = true
            end
        end,
        un_equip_fn = function(inst, owner, value)
            _G.Moon_ReduceEffect(owner, "changpi", "Legend_CHANGPI", value or 2)
            if not _G.Moon_HasEffect(owner, "changpi") then
                local combat = owner.components.combat
                if combat and owner._changpi_orig_range then
                    combat:SetRange(owner._changpi_orig_range)
                end
                owner._changpi_orig_range = nil
                owner._changpi_hooked = nil
            else
                -- 还有剩余附魔（多件叠加），恢复总值
                local combat = owner.components.combat
                if combat and owner._changpi_orig_range then
                    local remaining = _G.Moon_GetTotalEffectValue(owner, "changpi")
                    combat:SetRange(owner._changpi_orig_range + remaining)
                end
            end
        end,
    })

    _G.Moon_RegisterEnchantDrop("Legend_CHANGPI", 0)
end)
